import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/chat_media.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/screen_guard.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/media.dart' show FittedVideo;

/// Nota de voz de una sola vez: se descarga, suena una vez y el archivo temporal se borra al cerrar.
/// Devuelve true si llegó a abrirse (el servidor ya la marcó como escuchada).
Future<bool> playVoiceOnce(BuildContext context, Message message) async {
  final ok = await confirm(
    context,
    tr('Nota de voz de una sola vez'),
    tr('Solo podrás escucharla ahora. Después no se puede volver a abrir.'),
    action: tr('Escuchar'),
  );
  if (!ok || !context.mounted) return false;
  final opened = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Tx.bg,
    builder: (_) => _VoiceOnceSheet(message: message),
  );
  return opened ?? false;
}

class _VoiceOnceSheet extends StatefulWidget {
  const _VoiceOnceSheet({required this.message});

  final Message message;

  @override
  State<_VoiceOnceSheet> createState() => _VoiceOnceSheetState();
}

class _VoiceOnceSheetState extends State<_VoiceOnceSheet> {
  File? _temp;
  String? _error;
  bool _opened = false;
  bool _started = false;
  bool _closing = false;

  String get _key => 'voice-once:${widget.message.id}';

  @override
  void initState() {
    super.initState();
    songPlayer.addListener(_onPlayer);
    _load();
  }

  @override
  void dispose() {
    songPlayer.removeListener(_onPlayer);
    songPlayer.stop(_key);
    final temp = _temp;
    if (temp != null) {
      () async {
        try {
          await temp.delete();
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await ChatMedia.once(widget.message);
      _opened = true;
      final dir = await getTemporaryDirectory();
      final temp = File('${dir.path}/once_${widget.message.id}_${DateTime.now().microsecondsSinceEpoch}.${ChatMedia.extFor(ChatMedia.mimeOf(widget.message) ?? 'audio/mp4')}');
      await temp.writeAsBytes(bytes, flush: true);
      _temp = temp;
      if (!mounted) return;
      final duration = widget.message.file?.duration ?? widget.message.payload?.duration ?? 0;
      await songPlayer.play(_key, Song(id: 0, title: tr('Nota de voz'), duration: duration, audioUrl: Uri.file(temp.path).toString()));
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 410 ? tr('Ya escuchaste esta nota de voz.') : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = tr('No se pudo abrir la nota de voz.'));
    }
  }

  void _onPlayer() {
    if (!mounted || _closing) return;
    if (songPlayer.isPlaying(_key)) {
      _started = true;
    } else if (_started && (songPlayer.currentKey != _key || !songPlayer.buffering)) {
      _close();
      return;
    }
    if (songPlayer.currentKey == _key && songPlayer.error != null) setState(() => _error = songPlayer.error);
    setState(() {});
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(_opened);
  }

  @override
  Widget build(BuildContext context) {
    final total = Duration(seconds: widget.message.file?.duration ?? widget.message.payload?.duration ?? 0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(CupertinoIcons.mic_fill, color: Tx.purple500, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('Nota de voz de una sola vez'), style: Tx.body(16, weight: FontWeight.w700))),
            CupertinoButton(padding: const EdgeInsets.all(4), onPressed: _close, child: Icon(CupertinoIcons.xmark, color: Tx.muted, size: 22)),
          ]),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, textAlign: TextAlign.center, style: Tx.body(14.5, color: Tx.muted))
          else if (!_started)
            const Padding(padding: EdgeInsets.all(8), child: CupertinoActivityIndicator(radius: 13))
          else
            StreamBuilder<Duration>(
              stream: songPlayer.position,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final length = songPlayer.duration ?? total;
                final value = length.inMilliseconds > 0 ? (pos.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0) : 0.0;
                final left = length - pos;
                return Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: value, minHeight: 6, color: Tx.purple500, backgroundColor: Tx.surface2),
                  ),
                  const SizedBox(height: 8),
                  Text('${left.inSeconds < 0 ? 0 : left.inSeconds} s', style: Tx.body(13, color: Tx.muted)),
                ]);
              },
            ),
          const SizedBox(height: 10),
          Text(tr('Al cerrar, la nota de voz desaparece.'), style: Tx.body(12.5, color: Tx.subtle)),
        ]),
      ),
    );
  }
}

/// Foto o video de visualización única: se descarga una sola vez, se muestra centrado y ajustado a la pantalla y se
/// cierra al terminar el tiempo (o el video). La pantalla queda protegida contra capturas y grabaciones.
class ViewOnceViewer extends StatefulWidget {
  const ViewOnceViewer({super.key, required this.message});

  final Message message;

  @override
  State<ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends State<ViewOnceViewer> with SingleTickerProviderStateMixin {
  Uint8List? _bytes;
  File? _temp;
  VideoPlayerController? _video;
  String? _error;
  AnimationController? _timer;
  bool _closing = false;

  int get _seconds => widget.message.viewOnce?.seconds ?? 0;
  bool get _isVideo => widget.message.fileIsVideo;
  bool get _ready => _bytes != null || _video != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.dispose();
    _video?.removeListener(_onVideo);
    _video?.dispose();
    final temp = _temp;
    if (temp != null) {
      () async {
        try {
          await temp.delete();
        } catch (_) {}
      }();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await ChatMedia.once(widget.message);
      if (!mounted) return;
      if (_isVideo) {
        await _openVideo(bytes);
      } else {
        setState(() => _bytes = bytes);
        _startTimer();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.status == 410 ? (_isVideo ? tr('Ya abriste este video.') : tr('Ya abriste esta foto.')) : e.message);
    } catch (_) {
      if (mounted) setState(() => _error = _isVideo ? tr('No se pudo abrir el video.') : tr('No se pudo abrir la foto.'));
    }
  }

  Future<void> _openVideo(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final ext = ChatMedia.extFor(ChatMedia.mimeOf(widget.message) ?? 'video/mp4');
    final temp = File('${dir.path}/once_${widget.message.id}_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await temp.writeAsBytes(bytes, flush: true);
    _temp = temp;
    final c = VideoPlayerController.file(temp, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    c.addListener(_onVideo);
    setState(() => _video = c);
    await c.play();
    _startTimer();
  }

  void _onVideo() {
    final c = _video;
    if (c == null || _closing) return;
    final v = c.value;
    if (v.isInitialized && v.duration > Duration.zero && !v.isPlaying && v.position >= v.duration - const Duration(milliseconds: 250)) {
      _close();
    }
  }

  void _startTimer() {
    if (_seconds <= 0) return;
    _timer = AnimationController(vsync: this, duration: Duration(seconds: _seconds))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _close();
      })
      ..forward();
    setState(() {});
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(_ready);
  }

  @override
  Widget build(BuildContext context) {
    return TxDark.scope(
      context,
      AnnotatedRegion<SystemUiOverlayStyle>(
        value: Tx.immersive,
        child: ScreenGuard(
          onScreenshot: () {
            if (mounted) toast(context, tr('Las capturas de visualización única salen en negro.'));
          },
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              resizeToAvoidBottomInset: false,
              body: SizedBox.expand(
                child: Stack(children: [
                  Positioned.fill(child: _content()),
                  SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: _topBar())),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final bytes = _bytes;
    final video = _video;
    if (bytes != null) {
      return LayoutBuilder(
        builder: (context, box) => InteractiveViewer(
          maxScale: 4,
          child: SizedBox(
            width: box.maxWidth,
            height: box.maxHeight,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain, width: box.maxWidth, height: box.maxHeight, gaplessPlayback: true)),
          ),
        ),
      );
    }
    if (video != null) {
      return GestureDetector(
        onTap: () => video.value.isPlaying ? video.pause() : video.play(),
        child: FittedVideo(controller: video),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.eye_slash, color: Colors.white70, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: TxDark.body(16)),
          ]),
        ),
      );
    }
    return const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
  }

  Widget _topBar() {
    final timer = _timer;
    final video = _video;
    return Row(children: [
      CupertinoButton(
        padding: const EdgeInsets.all(6),
        onPressed: () => Navigator.of(context).pop(_ready),
        child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 26),
      ),
      const Spacer(),
      if (_ready)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (timer != null)
              AnimatedBuilder(
                animation: timer,
                builder: (_, __) => SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(value: 1 - timer.value, strokeWidth: 2.4, color: Colors.white, backgroundColor: Colors.white24),
                ),
              )
            else
              const Icon(CupertinoIcons.eye, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            if (timer != null)
              AnimatedBuilder(
                animation: timer,
                builder: (_, __) => Text('${(_seconds * (1 - timer.value)).ceil()} s', style: TxDark.body(13.5, weight: FontWeight.w600)),
              )
            else if (video != null)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: video,
                builder: (_, v, __) {
                  final left = v.duration - v.position;
                  return Text('${left.inSeconds < 0 ? 0 : left.inSeconds} s', style: TxDark.body(13.5, weight: FontWeight.w600));
                },
              )
            else
              Text(tr('Ver una vez'), style: TxDark.body(13.5, weight: FontWeight.w600)),
          ]),
        ),
    ]);
  }
}
