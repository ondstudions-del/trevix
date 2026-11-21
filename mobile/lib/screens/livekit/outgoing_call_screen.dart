import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'call_presentation.dart';
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
  static const _ringTimeout = Duration(seconds: 62);
  static const _serverGrace = Duration(seconds: 8);

  bool _busy = false;
  bool _opening = false;
  bool _micOn = true;
  bool _speakerOn = true;
  bool _videoOn = true;
  Timer? _poll;
  Timer? _ringDeadline;
  AudioPlayer? _ringback;
  late final AnimationController _pulse;
  late final DateTime _startedAt;

  bool get _video => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _videoOn = _video;
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _startRingback();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _ringDeadline = Timer(_ringTimeout, () => _tick(forceTimeout: true));
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

  bool get _trustServerTerminal {
    return DateTime.now().difference(_startedAt) >= _serverGrace;
  }

  Future<void> _failRing(String message) async {
    await _stopRingback();
    _ringDeadline?.cancel();
    if (!mounted) return;
    toast(context, message, error: true);
    Navigator.pop(context);
  }

  Future<void> _tick({bool forceTimeout = false}) async {
    if (_opening || !mounted) return;
    try {
      final s = await liveKitShow(widget.session.id);
      if (!mounted) return;
      if (s.status == 'active') {
        await _enterRoom();
        return;
      }
      if (s.status == 'declined') {
        await _failRing(tr('Rechazó la llamada.'));
        return;
      }
      if (forceTimeout || DateTime.now().difference(_startedAt) >= _ringTimeout) {
        if (s.status == 'ringing') {
          try {
            await liveKitEnd(widget.session.id);
          } catch (_) {}
          await _failRing(tr('No contestó la llamada.'));
        }
        return;
      }
      if ((s.status == 'missed' || s.status == 'ended') && _trustServerTerminal) {
        await _failRing(tr('No contestó la llamada.'));
      }
    } catch (_) {}
  }

  Future<void> _enterRoom() async {
    if (_opening) return;
    _opening = true;
    _ringDeadline?.cancel();
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
          video: _video && _videoOn,
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
    _ringDeadline?.cancel();
    await _stopRingback();
    try {
      await liveKitEnd(widget.session.id);
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ringDeadline?.cancel();
    _pulse.dispose();
    // ignore: discarded_futures
    _stopRingback();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.peer.displayName;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CallBlurBackdrop(user: widget.peer),
          SafeArea(
            child: Column(
              children: [
                CallTopBar(title: name, onMinimize: _busy ? null : _cancel, onMore: () {}),
                const Spacer(flex: 2),
                CallCallerBlock(
                  user: widget.peer,
                  subtitle: tr('Llamando…'),
                  pulse: _pulse,
                ),
                const Spacer(flex: 3),
                if (_busy) const Padding(padding: EdgeInsets.only(bottom: 20), child: CupertinoActivityIndicator(color: Colors.white)),
                CallOutgoingDock(
                  video: _video,
                  videoOn: _video && _videoOn,
                  micOn: _micOn,
                  speakerOn: _speakerOn,
                  onToggleVideo: _video ? () => setState(() => _videoOn = !_videoOn) : null,
                  onToggleMic: () => setState(() => _micOn = !_micOn),
                  onToggleSpeaker: () => setState(() => _speakerOn = !_speakerOn),
                  onEnd: _busy ? () {} : _cancel,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}