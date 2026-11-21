import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'livekit_room_screen.dart';

/// Pantalla de llamada saliente (estilo Messenger) antes de conectar la sala.
Future<void> showOutgoingLiveKitCall(
  BuildContext context, {
  required User peer,
  required LiveKitSession session,
  required String kind,
}) async {
  await push(
    context,
    OutgoingCallScreen(peer: peer, session: session, kind: kind),
  );
}

class OutgoingCallScreen extends StatefulWidget {
  const OutgoingCallScreen({super.key, required this.peer, required this.session, required this.kind});

  final User peer;
  final LiveKitSession session;
  final String kind;

  @override
  State<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends State<OutgoingCallScreen> with SingleTickerProviderStateMixin {
  bool _busy = false;
  bool _opening = false;
  Timer? _poll;
  AudioPlayer? _ringback;
  late final AnimationController _pulse;

  bool get _video => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _startRingback();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick();
  }

  Future<void> _startRingback() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.sonification,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
      await session.setActive(true);
      final player = AudioPlayer();
      _ringback = player;
      await player.setAsset('assets/sounds/trevix_llamada.wav');
      await player.setLoopMode(LoopMode.one);
      await player.setVolume(0.55);
      await player.play();
    } catch (_) {}
  }

  Future<void> _stopRingback() async {
    final player = _ringback;
    _ringback = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }

  Future<void> _tick() async {
    if (_opening || !mounted) return;
    try {
      final s = await liveKitShow(widget.session.id);
      if (!mounted) return;
      if (s.status == 'active') {
        await _enterRoom();
        return;
      }
      if (s.status == 'declined' || s.status == 'missed' || s.status == 'ended') {
        await _stopRingback();
        if (mounted) {
          toast(context, tr('No contestó la llamada.'), error: true);
          Navigator.pop(context);
        }
      }
    } catch (_) {}
  }

  Future<void> _enterRoom() async {
    if (_opening) return;
    _opening = true;
    await _stopRingback();
    try {
      final join = await liveKitJoinToken(widget.session.id);
      if (!mounted) return;
      Navigator.pop(context);
      await push(
        context,
        LiveKitRoomScreen(
          join: join,
          title: _video ? tr('Videollamada') : tr('Llamada'),
          video: _video,
          mode: LiveKitRoomMode.call,
        ),
      );
    } catch (e) {
      _opening = false;
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _stopRingback();
    try {
      await liveKitEnd(widget.session.id);
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pulse.dispose();
    // ignore: discarded_futures
    _stopRingback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.peer.displayName;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            children: [
              Text(
                _video ? tr('Videollamada saliente') : tr('Llamada saliente'),
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
                  ),
                  child: Avatar(user: widget.peer, size: 120),
                ),
              ),
              const SizedBox(height: 22),
              Text(name, style: Tx.display(28, color: Colors.white), textAlign: TextAlign.center),
              Text('@${widget.peer.username}', style: Tx.body(15, color: Colors.white54)),
              const SizedBox(height: 16),
              Text(tr('Llamando…'), style: Tx.body(16, color: Colors.white70)),
              const Spacer(),
              _RoundAction(
                color: const Color(0xFFE11D48),
                icon: CupertinoIcons.xmark,
                label: tr('Cancelar'),
                onTap: _busy ? null : _cancel,
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