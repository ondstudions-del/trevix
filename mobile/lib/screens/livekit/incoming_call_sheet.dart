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
import 'call_presentation.dart';
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
          title: tr('Llamada'),
          video: false,
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
    final host = widget.session.hostUser ??
        User(id: 0, username: widget.session.hostUsername ?? 'user', displayName: name, avatarUrl: widget.session.hostAvatar);
    final subtitle = tr('Llamada de audio de TREVIX');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CallBlurBackdrop(user: host, avatarUrl: widget.session.hostAvatar),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 36),
                CallCallerBlock(
                  user: host,
                  nameOverride: name,
                  subtitle: subtitle,
                  avatarSize: 132,
                  pulse: _pulse,
                ),
                const Spacer(),
                if (_busy) const CupertinoActivityIndicator(color: Colors.white),
                CallAnswerRow(video: false, busy: _busy, onDecline: _decline, onAccept: _accept),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
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
