import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../../app.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/livekit_incoming.dart';
import '../../core/nav.dart';
import '../../core/push.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'livekit_room_screen.dart';

/// Pantalla completa de llamada entrante (estilo Messenger).
Future<void> showIncomingLiveKitCall(BuildContext context, LiveKitSession session) async {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  await nav.push(
    PageRouteBuilder(
      opaque: true,
      barrierDismissible: false,
      pageBuilder: (_, __, ___) => IncomingCallScreen(session: session),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ),
  );
}

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({super.key, required this.session});

  final LiveKitSession session;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  bool _busy = false;
  late final AnimationController _pulse;
  AudioPlayer? _ringtone;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    HapticFeedback.heavyImpact();
    _startRingtone();
  }

  Future<void> _startRingtone() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.notificationRingtone,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
      await session.setActive(true);
      final player = AudioPlayer();
      _ringtone = player;
      await player.setAsset('assets/sounds/trevix_llamada.wav');
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(1);
      await player.play();
    } catch (_) {}
  }

  Future<void> _stopRingtone() async {
    final player = _ringtone;
    _ringtone = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> _cancelSystemNotif() async {
    await AndroidPush.cancelIncomingCall('${widget.session.id}');
  }

  @override
  void dispose() {
    _pulse.dispose();
    // ignore: discarded_futures
    _stopRingtone();
    super.dispose();
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopRingtone();
    await _cancelSystemNotif();
    try {
      await liveKitDecline(widget.session.id);
    } catch (_) {}
    await LiveKitIncoming.instance.dismissed(widget.session.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopRingtone();
    await _cancelSystemNotif();
    try {
      LiveKitSession snapshot;
      try {
        snapshot = await liveKitShow(widget.session.id);
      } catch (_) {
        snapshot = widget.session;
      }
      if (snapshot.status == 'ended' || snapshot.status == 'declined' || snapshot.status == 'missed') {
        throw StateError(tr('Esta llamada ya no está disponible.'));
      }
      final join = snapshot.status == 'active'
          ? await liveKitJoinToken(widget.session.id)
          : await liveKitAcceptCall(widget.session.id);
      await LiveKitIncoming.instance.dismissed(widget.session.id);
      if (!mounted) return;
      Navigator.pop(context);
      await push(
        context,
        LiveKitRoomScreen(
          join: join,
          title: widget.session.isVideoCall ? tr('Videollamada') : tr('Llamada'),
          video: widget.session.isVideoCall,
          mode: LiveKitRoomMode.call,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toastError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.session.hostName ?? tr('Alguien');
    final video = widget.session.isVideoCall;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            children: [
              Text(
                video ? tr('Videollamada de TREVIX') : tr('Llamada de audio de TREVIX'),
                style: Tx.body(15, weight: FontWeight.w600, color: Colors.white70),
              ),
              const Spacer(),
              ScaleTransition(
                scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Tx.accent.withAlpha(180), width: 3),
                    boxShadow: [BoxShadow(color: Tx.accent.withAlpha(60), blurRadius: 28, spreadRadius: 8)],
                  ),
                  child: Avatar(
                    user: widget.session.hostUser ??
                        User(id: 0, username: 'user', displayName: name, avatarUrl: widget.session.hostAvatar),
                    size: 120,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(name, style: Tx.display(28, color: Colors.white), textAlign: TextAlign.center),
              if ((widget.session.hostUsername ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('@${widget.session.hostUsername}', style: Tx.body(15, color: Colors.white54)),
              ],
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(
                    color: const Color(0xFFE11D48),
                    icon: CupertinoIcons.xmark,
                    label: tr('Rechazar'),
                    onTap: _busy ? null : _decline,
                  ),
                  _RoundAction(
                    color: const Color(0xFF16A34A),
                    icon: video ? CupertinoIcons.videocam_fill : CupertinoIcons.phone_fill,
                    label: tr('Contestar'),
                    onTap: _busy ? null : _accept,
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 18),
                const CupertinoActivityIndicator(color: Colors.white),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.color, required this.icon, required this.label, this.onTap});

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 72, height: 72, child: Icon(icon, color: Colors.white, size: 32)),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: Tx.body(13, color: Colors.white70)),
      ],
    );
  }
}

/// Escucha llamadas entrantes y abre la pantalla completa.
class LiveKitCallListener extends StatefulWidget {
  const LiveKitCallListener({super.key, required this.child});

  final Widget child;

  @override
  State<LiveKitCallListener> createState() => _LiveKitCallListenerState();
}

class _LiveKitCallListenerState extends State<LiveKitCallListener> {
  LiveKitSession? _shown;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    LiveKitIncoming.instance.addListener(_onRing);
  }

  @override
  void dispose() {
    LiveKitIncoming.instance.removeListener(_onRing);
    super.dispose();
  }

  void _onRing() {
    final s = LiveKitIncoming.instance.ringing;
    if (s == null || s.id == _shown?.id || _opening) return;
    _shown = s;
    _opening = true;
    void open() {
      final nav = navigatorKey.currentContext;
      if (nav == null || !nav.mounted) {
        Future.delayed(const Duration(milliseconds: 320), () {
          if (!mounted || LiveKitIncoming.instance.ringing?.id != s.id) {
            _opening = false;
            return;
          }
          open();
        });
        return;
      }
      showIncomingLiveKitCall(nav, s).whenComplete(() {
        _opening = false;
        if (LiveKitIncoming.instance.ringing?.id != s.id) _shown = null;
      });
    }
    open();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
