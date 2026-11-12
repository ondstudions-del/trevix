import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:trevix_video/trevix_video.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio.dart';
import '../../core/device.dart';
import '../../core/face_effects.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../core/video_render.dart';
import '../../core/video_tools.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart';
import '../../widgets/media_gallery.dart';
import '../../widgets/story_layers.dart';
import '../music/music_picker.dart';
import '../post/composer_screen.dart';
import 'reel_draft.dart';

const _songKey = 'reel-camera';
const _durations = [15, 30, 60];

/// Filtros de la cámara de reels: primero los de belleza (Rejuvenecer), luego los de color.
List<String?> get _cameraFilters => [null, 'smooth', ...storyFilterNames.keys.where((k) => k != 'smooth')];

String _filterName(String? key) => key == null ? tr('Original') : (storyFilterNames[key] ?? key);

/// Cámara para grabar un reel (como la de TikTok): 15 s, 30 s o 1 min, con música sincronizada (con canción no se
/// graba el micrófono, solo la imagen; la canción se une al publicar), cambio de cámara, flash, cuenta regresiva de
/// 3 a 10 s, formato pantalla completa (9:16) o 4:5, filtros (Rejuvenecer y efectos de color), efectos de cara que
/// siguen el rostro y, a la izquierda del botón de grabar, la galería. El formato 4:5 y el efecto de cara se graban
/// en el video al terminar. Devuelve la publicación creada.
class ReelCameraScreen extends StatefulWidget {
  const ReelCameraScreen({super.key, this.song});

  /// Canción o sonido ya elegido («Usar este sonido» en su ficha): el reel se graba a su compás.
  final Song? song;

  @override
  State<ReelCameraScreen> createState() => _ReelCameraScreenState();
}

enum _Phase { idle, recording, paused, finishing }

class _ReelCameraScreenState extends State<ReelCameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  int _camIndex = 0;
  CameraController? _cam;
  bool _starting = false;
  String? _error;
  bool _permissionError = false;
  bool _micDenied = false;

  int _maxSeconds = 15;
  late PickedSong? _song = widget.song != null && widget.song!.available ? PickedSong(widget.song!, widget.song!.clipStart ?? 0) : null;
  String? _filter;
  bool _showFilters = false;
  bool _fourFive = false;
  FaceEffect? _effect;
  bool _showEffects = false;
  bool _detecting = false;
  List<PartPlacement?> _placements = const [];
  DateTime _lastFace = DateTime.fromMillisecondsSinceEpoch(0);
  bool _flash = false;
  int _timerSeconds = 0;
  int? _countdown;
  Timer? _countdownTimer;

  _Phase _phase = _Phase.idle;
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  final List<int> _marks = [];
  bool _busy = false;

  bool get _hasTake => _phase == _Phase.recording || _phase == _Phase.paused;
  bool get _front => _cameras.isNotEmpty && _cameras[_camIndex].lensDirection == CameraLensDirection.front;

  /// Con canción, el reel dura como mucho lo que queda de ella desde el inicio elegido.
  int get _limitMs {
    var ms = _maxSeconds * 1000;
    final song = _song;
    if (song != null && song.song.duration > 0) ms = min(ms, (song.song.duration - song.start) * 1000);
    return max(ms, 1000);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    songPlayer.stop();
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _ticker?.cancel();
    songPlayer.stop(_songKey);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _cancelCountdown();
      if (_phase == _Phase.recording) {
        _pause();
      } else if (!_hasTake && _phase == _Phase.idle && _cam != null) {
        final c = _cam;
        setState(() => _cam = null);
        c?.dispose();
      }
    } else if (state == AppLifecycleState.resumed && _cam == null && !_starting && mounted) {
      _initCamera();
    }
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = [];
    }
    if (!mounted) return;
    if (_cameras.isEmpty) {
      setState(() => _error = tr('No encontramos ninguna cámara en este teléfono.'));
      return;
    }
    final front = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _camIndex = front >= 0 ? front : 0;
    await _initCamera();
  }

  /// (Re)crea la cámara. Con canción se crea sin micrófono: el video no lleva el sonido de fuera.
  Future<void> _initCamera() async {
    if (_cameras.isEmpty || _starting) return;
    _starting = true;
    final old = _cam;
    setState(() {
      _cam = null;
      _error = null;
      _permissionError = false;
    });
    await old?.dispose();
    final withMic = _song == null && !_micDenied;
    final c = CameraController(
      _cameras[_camIndex],
      ResolutionPreset.high,
      enableAudio: withMic,
      videoBitrate: 6000000,
      // Fotogramas que se pasan al detector de caras del teléfono (efectos).
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    try {
      await c.initialize();
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      if (_flash && !_front) {
        try {
          await c.setFlashMode(FlashMode.torch);
        } catch (_) {}
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _cam = c);
      unawaited(_startStream());
    } on CameraException catch (e) {
      await c.dispose();
      if (!mounted) return;
      if (e.code.startsWith('AudioAccess') && withMic) {
        _micDenied = true;
        _starting = false;
        toast(context, tr('Sin permiso del micrófono los videos se graban sin sonido. Puedes activarlo en Ajustes.'), error: true);
        return _initCamera();
      }
      setState(() {
        _permissionError = e.code.startsWith('CameraAccess');
        _error = _permissionError
            ? tr('TREVIX necesita permiso para usar la cámara. Actívalo en Ajustes.')
            : tr('No se pudo abrir la cámara. Inténtalo de nuevo.');
      });
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _error = tr('No se pudo abrir la cámara. Inténtalo de nuevo.'));
    } finally {
      _starting = false;
    }
  }

  // ---------- Efectos de cara (vista previa) ----------

  /// Con un efecto elegido, los fotogramas de la cámara pasan por el detector de caras del teléfono (Vision en iOS,
  /// FaceDetector en Android) para seguir la cara en la vista previa.
  Future<void> _startStream() async {
    final c = _cam;
    if (c == null || _effect == null || !c.value.isInitialized || c.value.isStreamingImages || c.value.isRecordingVideo) return;
    try {
      await c.startImageStream(_onFrame);
    } catch (_) {}
  }

  Future<void> _stopStream() async {
    final c = _cam;
    if (c == null || !c.value.isStreamingImages || c.value.isRecordingVideo) return;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage image) {
    final effect = _effect;
    if (effect == null || _detecting || !mounted || _cameras.isEmpty) return;
    final camera = _cameras[_camIndex];
    final frame = grayFrame(image, camera);
    if (frame == null) return;
    final (gray, w, h) = frame;
    final size = Size(w.toDouble(), h.toDouble());
    final mirror = previewMirrored(camera);
    _detecting = true;
    TrevixVideo.faces(gray: gray, width: w, height: h).then((faces) {
      if (!mounted || _effect != effect) return;
      final face = largestFace(faces);
      final now = DateTime.now();
      if (face == null) {
        if (_placements.isNotEmpty && now.difference(_lastFace).inMilliseconds > 500) setState(() => _placements = const []);
        return;
      }
      _lastFace = now;
      final box = FaceBox.from(face, size);
      final next = [
        for (final part in effect.parts)
          if (mirror) placePart(part, box, size).mirrored() else placePart(part, box, size),
      ];
      final prev = _placements;
      setState(() {
        _placements = [
          for (var i = 0; i < next.length; i++) i < prev.length && prev[i] != null ? prev[i]!.blend(next[i], .55) : next[i],
        ];
      });
    }).catchError((_) {}).whenComplete(() => _detecting = false);
  }

  void _setEffect(FaceEffect? effect) {
    setState(() {
      _effect = effect;
      _placements = const [];
    });
    if (effect != null) {
      _startStream();
    } else {
      _stopStream();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _hasTake || _countdown != null) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    setState(() => _flash = !_flash);
    final c = _cam;
    if (c == null || _front) return;
    try {
      await c.setFlashMode(_flash ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      if (mounted) toast(context, tr('Esta cámara no tiene flash.'), error: true);
    }
  }

  Future<void> _chooseSong() async {
    if (_hasTake) {
      toast(context, tr('Termina o descarta la grabación para cambiar la canción.'));
      return;
    }
    final picked = await pickSong(context, clipSeconds: max(30, _maxSeconds), current: _song);
    if (picked == null || !mounted) return;
    final hadSong = _song != null;
    setState(() => _song = picked);
    if (!hadSong) await _initCamera();
  }

  Future<void> _removeSong() async {
    if (_hasTake) return;
    setState(() => _song = null);
    await _initCamera();
  }

  Future<void> _chooseTimer() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimerSheet(current: _timerSeconds),
    );
    if (picked != null && mounted) setState(() => _timerSeconds = picked);
  }

  void _onRecordTap() {
    if (_busy || _cam == null || _phase == _Phase.finishing) return;
    if (_countdown != null) {
      _cancelCountdown();
      return;
    }
    if (_phase == _Phase.recording) {
      _pause();
      return;
    }
    if (_timerSeconds > 0) {
      _startCountdown();
    } else {
      _record();
    }
  }

  void _startCountdown() {
    setState(() {
      _countdown = _timerSeconds;
      _showFilters = false;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_countdown ?? 1) - 1;
      if (left <= 0) {
        t.cancel();
        setState(() => _countdown = null);
        _record();
      } else {
        setState(() => _countdown = left);
      }
    });
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != null && mounted) setState(() => _countdown = null);
  }

  /// Empieza o continúa la grabación; la canción arranca (o sigue) en el mismo punto del video.
  Future<void> _record() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy) return;
    _busy = true;
    try {
      final song = _song;
      if (song != null) {
        final at = Duration(milliseconds: _clock.elapsedMilliseconds);
        if (songPlayer.currentKey != _songKey) {
          final clip = song.song.withClip(song.start, max(30, _maxSeconds));
          final ok = await songPlayer.prepare(_songKey, clip, clip: true, at: at);
          if (!ok) {
            if (mounted) toast(context, tr('No se pudo cargar la canción. Revisa tu conexión.'), error: true);
            return;
          }
        } else {
          await songPlayer.seek(at);
        }
      }
      if (_phase == _Phase.idle) {
        final streaming = _effect != null;
        if (c.value.isStreamingImages) await c.stopImageStream();
        try {
          // El efecto sigue la cara también mientras se graba.
          await c.startVideoRecording(onAvailable: streaming ? _onFrame : null);
        } on CameraException {
          if (!streaming || c.value.isRecordingVideo) rethrow;
          await c.startVideoRecording();
        }
      } else {
        await c.resumeVideoRecording();
      }
      if (song != null) unawaited(songPlayer.resume(_songKey));
      _clock.start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _onTick());
      if (mounted) {
        setState(() {
          _phase = _Phase.recording;
          _showFilters = false;
        });
      }
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo grabar el video. Inténtalo de nuevo.'), error: true);
    } finally {
      _busy = false;
    }
  }

  void _onTick() {
    if (!mounted) return;
    if (_clock.elapsedMilliseconds >= _limitMs) {
      _finish();
    } else {
      setState(() {});
    }
  }

  Future<void> _pause() async {
    final c = _cam;
    if (c == null || _phase != _Phase.recording || _busy) return;
    _busy = true;
    _ticker?.cancel();
    _clock.stop();
    try {
      await c.pauseVideoRecording();
      if (_song != null) {
        await songPlayer.pause();
        await songPlayer.seek(Duration(milliseconds: _clock.elapsedMilliseconds));
      }
      _marks.add(_clock.elapsedMilliseconds);
      if (mounted) setState(() => _phase = _Phase.paused);
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo pausar. Toca ✓ para terminar el video.'), error: true);
      _clock.start();
      _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => _onTick());
    } finally {
      _busy = false;
    }
  }

  /// Termina la grabación y abre la vista previa.
  Future<void> _finish() async {
    final c = _cam;
    if (c == null || !_hasTake || _phase == _Phase.finishing) return;
    _ticker?.cancel();
    _clock.stop();
    setState(() => _phase = _Phase.finishing);
    unawaited(songPlayer.pause());
    final ms = _clock.elapsedMilliseconds;
    XFile? file;
    try {
      file = await c.stopVideoRecording();
    } catch (_) {
      file = null;
    }
    _resetTake();
    if (!mounted) return;
    if (file == null) {
      toast(context, tr('No se pudo guardar el video. Inténtalo de nuevo.'), error: true);
      unawaited(_startStream());
      return;
    }
    if (ms < 1000) {
      _deleteQuietly(file.path);
      toast(context, tr('Graba al menos 1 segundo.'), error: true);
      unawaited(_startStream());
      return;
    }
    var path = file.path;
    if (_fourFive || _effect != null) {
      final baked = await _bake(path, ms, _effect);
      if (!mounted) return;
      if (baked == null) {
        unawaited(_startStream());
        return;
      }
      path = baked;
    }
    final song = _song;
    await _openPreview(ReelDraft(path: path, seconds: ms / 1000, filter: _filter, song: song, songSync: song != null));
  }

  /// Graba en el video el formato elegido (recorte al centro) y el efecto de cara, que sigue la cara fotograma a
  /// fotograma. Devuelve la ruta del video nuevo, la del original si falla o null si se cancela.
  Future<String?> _bake(String input, int ms, FaceEffect? effect) async {
    final label = effect != null ? tr('Aplicando el efecto…') : tr('Preparando el video…');
    final status = ValueNotifier<(String, double?)>((label, null));
    var cancelled = false;
    final close = showRenderProgress(context, status, () {
      cancelled = true;
      TrevixVideo.cancel().ignore();
    });
    final dir = await renderDir('reel_bake');
    try {
      final aspect = _fourFive ? 4 / 5 : 9 / 16;
      var overlays = <VideoOverlay>[];
      if (effect != null) {
        overlays = await faceOverlays(
          effect,
          input,
          dir.path,
          durationMs: ms,
          aspect: aspect,
          onProgress: (p) => status.value = (label, p * .5),
          cancelled: () => cancelled,
        );
      }
      if (cancelled) throw const _BakeCancelled();
      final base = effect != null ? .5 : 0.0;
      status.value = (tr('Preparando el video…'), base);
      final output = '${(await getTemporaryDirectory()).path}/reel_${DateTime.now().microsecondsSinceEpoch}.mp4';
      await renderWithProgress(
        VideoRenderJob(input: input, output: output, aspect: aspect, overlays: overlays),
        (p) => status.value = (tr('Preparando el video…'), base + p * (1 - base)),
      );
      if (cancelled) throw const _BakeCancelled();
      _deleteQuietly(input);
      return output;
    } catch (_) {
      if (cancelled) {
        _deleteQuietly(input);
        if (mounted) toast(context, tr('Se descartó el video.'));
        return null;
      }
      if (mounted) toast(context, tr('No se pudo aplicar el formato o el efecto: se usará el video tal como se grabó.'), error: true);
      return input;
    } finally {
      close();
      dir.delete(recursive: true).ignore();
    }
  }

  Future<void> _discard() async {
    if (!_hasTake) return;
    final ok = await confirm(context, tr('¿Descartar el video?'), tr('Se borrará lo que has grabado.'), action: tr('Descartar'), destructive: true);
    if (!ok || !mounted) return;
    final c = _cam;
    _ticker?.cancel();
    _clock.stop();
    setState(() => _phase = _Phase.finishing);
    try {
      final file = await c?.stopVideoRecording();
      if (file != null) _deleteQuietly(file.path);
    } catch (_) {}
    _resetTake();
    unawaited(_startStream());
  }

  void _resetTake() {
    songPlayer.stop(_songKey);
    _clock
      ..stop()
      ..reset();
    _marks.clear();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  void _deleteQuietly(String path) {
    File(path).delete().catchError((_) => File(path));
  }

  Future<void> _close() async {
    if (_hasTake) {
      final ok = await confirm(context, tr('¿Descartar el video?'), tr('Se borrará lo que has grabado.'), action: tr('Descartar'), destructive: true);
      if (!ok || !mounted) return;
      _ticker?.cancel();
      try {
        final file = await _cam?.stopVideoRecording();
        if (file != null) _deleteQuietly(file.path);
      } catch (_) {}
      _resetTake();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openGallery() async {
    if (_hasTake || _countdown != null) return;
    final maxSeconds = context.read<AppState>().limit('video_max_seconds', 300);
    final pick = await push<GalleryPick>(context, _VideoGalleryPage(maxSeconds: maxSeconds), fullscreen: true);
    if (pick == null || !mounted) return;
    await _openPreview(ReelDraft(path: pick.path, seconds: pick.seconds, filter: _filter, song: _song));
  }

  Future<void> _openPreview(ReelDraft draft) async {
    final c = _cam;
    await _stopStream();
    try {
      await c?.pausePreview();
    } catch (_) {}
    if (!mounted) return;
    final post = await push<Post>(context, ReelPreviewScreen(draft: draft));
    if (!mounted) return;
    if (post != null) {
      Navigator.of(context).pop(post);
      return;
    }
    songPlayer.stop(_songKey);
    if (draft.filter != _filter) setState(() => _filter = draft.filter);
    try {
      await _cam?.resumePreview();
    } catch (_) {}
    await _startStream();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final c = _cam;
    final ringLight = _flash && _front && (_hasTake || _countdown != null);
    return PopScope(
      canPop: !_hasTake,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(fit: StackFit.expand, children: [
            if (c != null && c.value.isInitialized)
              _CameraView(controller: c, filter: _filter, fourFive: _fourFive, effect: _effect, placements: _placements)
            else
              _placeholder(),
            if (ringLight) IgnorePointer(child: Container(decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 46)))),
            if (_countdown != null)
              IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, a) => ScaleTransition(scale: Tween(begin: 1.6, end: 1.0).animate(a), child: FadeTransition(opacity: a, child: child)),
                    child: Text('$_countdown', key: ValueKey(_countdown), style: TxDark.display(140, color: Colors.white)),
                  ),
                ),
              ),
            Positioned(left: 12, right: 12, top: pad.top + 8, child: _progressBar()),
            Positioned(left: 4, right: 4, top: pad.top + 20, child: _topBar()),
            if (!_hasTake && _countdown == null) Positioned(right: 8, top: pad.top + 84, child: _sideTools()),
            Positioned(left: 0, right: 0, bottom: pad.bottom + 12, child: _bottom()),
          ]),
        ),
      ),
    );
  }

  Widget _placeholder() {
    final error = _error;
    if (error == null) return const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.camera, color: Colors.white70, size: 44),
          const SizedBox(height: 14),
          Text(error, textAlign: TextAlign.center, style: TxDark.body(15, color: Colors.white)),
          const SizedBox(height: 18),
          if (_permissionError)
            GradientButton(label: tr('Abrir ajustes'), expand: false, height: 44, onPressed: DeviceAccess.openSettings)
          else
            GradientButton(label: tr('Reintentar'), expand: false, height: 44, onPressed: _cameras.isEmpty ? _setup : _initCamera),
          const SizedBox(height: 10),
          TextButton(onPressed: _openGallery, child: Text(tr('Elegir un video de la galería'), style: TxDark.body(14, weight: FontWeight.w600, color: Colors.white))),
        ]),
      ),
    );
  }

  Widget _progressBar() {
    if (_phase == _Phase.idle && _countdown == null) return const SizedBox(height: 5);
    final limit = _limitMs;
    final done = (_clock.elapsedMilliseconds / limit).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (context, box) {
      return SizedBox(
        height: 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(children: [
            Container(color: Colors.white.withAlpha(60)),
            FractionallySizedBox(widthFactor: done, child: Container(color: Tx.purple300)),
            for (final m in _marks)
              Positioned(left: box.maxWidth * (m / limit).clamp(0.0, 1.0) - 1, top: 0, bottom: 0, child: Container(width: 2, color: Colors.white)),
          ]),
        ),
      );
    });
  }

  Widget _topBar() {
    final song = _song;
    return Row(children: [
      _RoundIcon(icon: CupertinoIcons.xmark, onTap: _close, label: tr('Cerrar')),
      Expanded(
        child: Center(
          child: _hasTake || _phase == _Phase.finishing
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${clockText(_clock.elapsed.inSeconds)} / ${clockText((_limitMs / 1000).round())}',
                    style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white),
                  ),
                )
              : GestureDetector(
                  onTap: _chooseSong,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 240),
                    padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
                    decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(CupertinoIcons.music_note_2, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          song == null ? tr('Añadir música') : song.song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TxDark.body(13.5, weight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                      if (song != null)
                        GestureDetector(
                          onTap: _removeSong,
                          child: const Padding(padding: EdgeInsets.only(left: 6), child: Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white70, size: 18)),
                        )
                      else
                        const SizedBox(width: 4),
                    ]),
                  ),
                ),
        ),
      ),
      const SizedBox(width: 44),
    ]);
  }

  Widget _sideTools() {
    return Column(children: [
      if (_cameras.length > 1) _SideTool(icon: CupertinoIcons.camera_rotate, label: tr('Girar'), onTap: _switchCamera),
      _SideTool(icon: _flash ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt_slash, label: tr('Flash'), onTap: _toggleFlash, active: _flash),
      _SideTool(
        icon: CupertinoIcons.timer,
        label: _timerSeconds > 0 ? '${_timerSeconds}s' : tr('Temporizador'),
        onTap: _chooseTimer,
        active: _timerSeconds > 0,
      ),
      _SideTool(
        icon: _fourFive ? CupertinoIcons.rectangle : CupertinoIcons.device_phone_portrait,
        label: _fourFive ? '4:5' : '9:16',
        onTap: () => setState(() => _fourFive = !_fourFive),
        active: _fourFive,
      ),
      _SideTool(
        icon: CupertinoIcons.sparkles,
        label: tr('Filtros'),
        onTap: () => setState(() {
          _showFilters = !_showFilters;
          _showEffects = false;
        }),
        active: _filter != null,
      ),
      _SideTool(
        icon: CupertinoIcons.smiley,
        label: tr('Efectos'),
        onTap: () => setState(() {
          _showEffects = !_showEffects;
          _showFilters = false;
        }),
        active: _effect != null,
      ),
      _SideTool(icon: CupertinoIcons.music_note_2, label: tr('Música'), onTap: _chooseSong, active: _song != null),
    ]);
  }

  Widget _bottom() {
    final idle = _phase == _Phase.idle && _countdown == null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_showFilters && idle) ...[
        FilterStrip(value: _filter, onChanged: (f) => setState(() => _filter = f)),
        const SizedBox(height: 14),
      ],
      if (_showEffects && idle) ...[
        _EffectStrip(value: _effect, onChanged: _setEffect),
        const SizedBox(height: 14),
      ],
      if (_effect != null && idle && _placements.isEmpty && _cam != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            tr('Pon tu cara frente a la cámara'),
            style: TxDark.body(13, weight: FontWeight.w600, color: Colors.white).copyWith(shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
          ),
        ),
      Row(children: [
        Expanded(
          child: Center(
            child: idle
                ? _GalleryButton(onTap: _openGallery)
                : _phase == _Phase.paused
                    ? _RoundIcon(icon: CupertinoIcons.delete_left, onTap: _discard, label: tr('Descartar'), size: 48)
                    : const SizedBox.shrink(),
          ),
        ),
        _RecordButton(
          recording: _phase == _Phase.recording,
          counting: _countdown != null,
          busy: _phase == _Phase.finishing,
          onTap: _onRecordTap,
        ),
        Expanded(
          child: Center(
            child: _phase == _Phase.paused || (_phase == _Phase.recording && _clock.elapsedMilliseconds >= 1000)
                ? GestureDetector(
                    onTap: _finish,
                    child: Semantics(
                      button: true,
                      label: tr('Terminar'),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
                        child: const Icon(CupertinoIcons.checkmark_alt, color: Colors.white, size: 26),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      AnimatedOpacity(
        opacity: idle ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          ignoring: !idle,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (final s in _durations)
              GestureDetector(
                onTap: () => setState(() => _maxSeconds = s),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _maxSeconds == s ? Colors.white : Colors.black.withAlpha(90),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    s == 60 ? tr('1 min') : '$s s',
                    style: TxDark.body(13, weight: FontWeight.w700, color: _maxSeconds == s ? Colors.black : Colors.white),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ]);
  }
}

/// Vista de la cámara con el filtro y el efecto de cara en vivo. En 9:16 ocupa la pantalla (recortada como «cover»);
/// en 4:5 se ve a lo ancho y se oscurece lo que queda fuera del recuadro que se grabará.
class _CameraView extends StatelessWidget {
  const _CameraView({required this.controller, this.filter, this.fourFive = false, this.effect, this.placements = const []});

  final CameraController controller;
  final String? filter;
  final bool fourFive;
  final FaceEffect? effect;
  final List<PartPlacement?> placements;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ratio = controller.value.aspectRatio;
    // El sensor entrega la imagen apaisada: en vertical se invierte la proporción.
    final previewAspect = 1 / ratio;
    final preview = AspectRatio(
      aspectRatio: previewAspect,
      child: Stack(fit: StackFit.expand, children: [
        filtered(filter, CameraPreview(controller)),
        if (effect != null) IgnorePointer(child: CustomPaint(painter: FaceEffectPainter(effect!, placements))),
      ]),
    );
    if (fourFive) {
      final window = Rect.fromCenter(center: size.center(Offset.zero), width: size.width, height: size.width * 5 / 4);
      return Stack(fit: StackFit.expand, children: [
        ClipRect(child: Center(child: SizedBox(width: size.width, child: preview))),
        IgnorePointer(child: CustomPaint(painter: _FrameMask(window))),
      ]);
    }
    var scale = size.aspectRatio / previewAspect;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(child: Transform.scale(scale: scale, child: Center(child: preview)));
  }
}

/// Oscurece todo menos [window] (formato 4:5).
class _FrameMask extends CustomPainter {
  _FrameMask(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(window);
    canvas.drawPath(outside, Paint()..color = const Color(0xD9000000));
    canvas.drawRect(
      window,
      Paint()
        ..color = Colors.white54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_FrameMask old) => old.window != window;
}

class _BakeCancelled implements Exception {
  const _BakeCancelled();
}

/// Tira de efectos de cara (como la de filtros).
class _EffectStrip extends StatelessWidget {
  const _EffectStrip({required this.value, required this.onChanged});

  final FaceEffect? value;
  final ValueChanged<FaceEffect?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = <FaceEffect?>[null, ...faceEffects];
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final e = items[i];
          final selected = e?.id == value?.id;
          return GestureDetector(
            onTap: () => onChanged(e),
            child: SizedBox(
              width: 60,
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withAlpha(110),
                    border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1.5),
                  ),
                  child: e == null
                      ? const Icon(CupertinoIcons.nosign, color: Colors.white, size: 24)
                      : Text(e.emoji, style: const TextStyle(fontSize: 26)),
                ),
                const SizedBox(height: 5),
                Text(
                  e == null ? tr('Ninguno') : e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TxDark.body(11.5, weight: selected ? FontWeight.w800 : FontWeight.w600, color: Colors.white),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.recording, required this.counting, required this.busy, required this.onTap});

  final bool recording;
  final bool counting;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recording ? tr('Pausar la grabación') : (counting ? tr('Cancelar la cuenta regresiva') : tr('Grabar')),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)),
          alignment: Alignment.center,
          child: busy
              ? const CupertinoActivityIndicator(color: Colors.white, radius: 13)
              : AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: recording || counting ? 30 : 64,
                  height: recording || counting ? 30 : 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E),
                    borderRadius: BorderRadius.circular(recording || counting ? 8 : 32),
                  ),
                ),
        ),
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tr('Elegir de la galería'),
      child: GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(36),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(CupertinoIcons.photo_on_rectangle, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(tr('Galería'), style: TxDark.body(11.5, weight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.label, this.size = 40});

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(110)),
          child: Icon(icon, color: Colors.white, size: size * .5),
        ),
      ),
    );
  }
}

class _SideTool extends StatelessWidget {
  const _SideTool({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: SizedBox(
          width: 64,
          child: Column(children: [
            Icon(icon, color: active ? Tx.purple300 : Colors.white, size: 27, shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TxDark.body(11, weight: FontWeight.w700, color: Colors.white).copyWith(shadows: const [Shadow(color: Colors.black54, blurRadius: 6)]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TimerSheet extends StatefulWidget {
  const _TimerSheet({required this.current});

  final int current;

  @override
  State<_TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<_TimerSheet> {
  late double _value = (widget.current == 0 ? 3 : widget.current).toDouble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.paddingOf(context).bottom + 16),
      decoration: BoxDecoration(color: TxDark.surface2, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Cuenta regresiva'), style: TxDark.display(18, color: Colors.white)),
        const SizedBox(height: 4),
        Text(tr('La grabación empieza cuando termina la cuenta.'), style: TxDark.body(13.5, color: Colors.white70)),
        const SizedBox(height: 18),
        Row(children: [
          Text('3s', style: TxDark.body(13, color: Colors.white70)),
          Expanded(
            child: CupertinoSlider(
              value: _value,
              min: 3,
              max: 10,
              divisions: 7,
              activeColor: Tx.purple300,
              onChanged: (v) => setState(() => _value = v),
            ),
          ),
          Text('10s', style: TxDark.body(13, color: Colors.white70)),
        ]),
        Center(child: Text('${_value.round()} s', style: TxDark.display(28, color: Colors.white))),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, 0),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: TxDark.border),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(tr('Sin cuenta regresiva')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: GradientButton(label: tr('Usar'), height: 48, onPressed: () => Navigator.pop(context, _value.round()))),
        ]),
      ]),
    );
  }
}

/// Tira de filtros (cámara y vista previa). Con [thumb], cada filtro muestra esa imagen con el filtro aplicado.
class FilterStrip extends StatelessWidget {
  const FilterStrip({super.key, required this.value, required this.onChanged, this.thumb});

  final String? value;
  final ValueChanged<String?> onChanged;
  final ImageProvider? thumb;

  @override
  Widget build(BuildContext context) {
    final filters = _cameraFilters;
    final image = thumb;
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = filters[i];
          final selected = f == value;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: SizedBox(
              width: 60,
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1.5),
                  ),
                  child: ClipOval(
                    child: image != null
                        ? filtered(f, Image(image: image, fit: BoxFit.cover, width: 56, height: 56))
                        : filtered(
                            f,
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [Color(0xFFF9A8D4), Color(0xFFA78BFA), Color(0xFF38BDF8)]),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _filterName(f),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TxDark.body(11.5, weight: selected ? FontWeight.w800 : FontWeight.w600, color: Colors.white),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Galería de videos del teléfono a pantalla completa (botón a la izquierda del de grabar).
class _VideoGalleryPage extends StatelessWidget {
  const _VideoGalleryPage({required this.maxSeconds});

  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TxDark.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                tooltip: tr('Cerrar'),
              ),
              const SizedBox(width: 4),
              Text(tr('Elige un video'), style: TxDark.display(18, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: PhoneGallery(
              videosOnly: true,
              maxVideoSeconds: maxSeconds,
              onPick: (p) => Navigator.pop(context, p),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Vista previa del reel: el video en bucle con su filtro (se puede cambiar) y, si se grabó con canción, la canción
/// a su compás. «Siguiente» abre el compositor con el reel listo.
class ReelPreviewScreen extends StatefulWidget {
  const ReelPreviewScreen({super.key, required this.draft});

  final ReelDraft draft;

  @override
  State<ReelPreviewScreen> createState() => _ReelPreviewScreenState();
}

class _ReelPreviewScreenState extends State<ReelPreviewScreen> {
  VideoPlayerController? _v;
  bool _failed = false;
  late String? _filter = widget.draft.filter;
  String? _poster;
  bool _next = false;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  ReelDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _load();
    VideoTools.poster(_draft.path, _draft.seconds).then((p) {
      if (mounted && p != null) setState(() => _poster = p);
    });
  }

  @override
  void dispose() {
    final v = _v;
    _v = null;
    v?.removeListener(_tick);
    releaseVideo(v);
    songPlayer.stop(_songKey);
    super.dispose();
  }

  Future<void> _load() async {
    final v = VideoPlayerController.file(File(_draft.path), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await v.initialize();
      await v.setLooping(true);
      if (_draft.songSync) await v.setVolume(0);
      if (!mounted) {
        releaseVideo(v);
        return;
      }
      setState(() => _v = v);
      v.addListener(_tick);
      await _play();
    } catch (_) {
      releaseVideo(v);
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _play() async {
    final v = _v;
    if (v == null) return;
    final song = _draft.song;
    if (_draft.songSync && song != null) {
      final at = v.value.position;
      if (songPlayer.currentKey != _songKey) {
        await songPlayer.prepare(_songKey, song.song.withClip(song.start, max(30, (_draft.seconds ?? 30).ceil())), clip: true, at: at);
      } else {
        await songPlayer.seek(at);
      }
      unawaited(songPlayer.resume(_songKey));
    }
    await v.play();
  }

  Future<void> _pause() async {
    await _v?.pause();
    if (_draft.songSync) await songPlayer.pause();
  }

  void _tick() {
    final v = _v;
    if (v == null || !_draft.songSync || !v.value.isPlaying || songPlayer.currentKey != _songKey) return;
    final now = DateTime.now();
    if (now.difference(_lastSync).inMilliseconds < 900) return;
    final drift = (songPlayer.positionNow - v.value.position).inMilliseconds.abs();
    if (drift > 300) {
      _lastSync = now;
      songPlayer.seek(v.value.position);
      if (!songPlayer.playing) songPlayer.resume(_songKey);
    }
  }

  Future<void> _continue() async {
    if (_next) return;
    setState(() => _next = true);
    await _pause();
    final poster = _poster ?? await VideoTools.poster(_draft.path, _draft.seconds);
    if (!mounted) return;
    _draft
      ..filter = _filter
      ..poster = poster;
    setState(() => _next = false);
    final post = await push<Post>(context, ComposerScreen(reel: _draft), fullscreen: true);
    if (!mounted) return;
    if (post != null) {
      Navigator.of(context).pop(post);
    } else {
      await _play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final v = _v;
    final poster = _poster;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(fit: StackFit.expand, children: [
          if (v != null)
            GestureDetector(
              onTap: () => v.value.isPlaying ? _pause() : _play(),
              child: filtered(
                _filter,
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
                ),
              ),
            )
          else if (_failed)
            Center(child: Text(tr('No se pudo reproducir el video'), style: TxDark.body(14, color: Colors.white70)))
          else
            const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
          Positioned(
            left: 8,
            top: pad.top + 8,
            child: _RoundIcon(icon: CupertinoIcons.chevron_back, onTap: () => Navigator.of(context).pop(), label: tr('Volver')),
          ),
          if (_draft.songSync && _draft.song != null)
            Positioned(
              left: 60,
              right: 60,
              top: pad.top + 14,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.music_note_2, color: Colors.white, size: 15),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _draft.song!.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: pad.bottom + 12,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FilterStrip(
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
                thumb: poster != null ? FileImage(File(poster)) : null,
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GradientButton(label: tr('Siguiente'), loading: _next, onPressed: v == null ? null : _continue),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
