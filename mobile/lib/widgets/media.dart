import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/audio.dart';
import '../core/device.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'story_layers.dart' show filtered;

/// Libera un reproductor cuando su VideoPlayer ya no se dibuja: liberarlo antes cierra la app en iOS.
void releaseVideo(VideoPlayerController? v) {
  if (v == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      if (v.value.isInitialized) await v.pause();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    try {
      await v.dispose();
    } catch (_) {}
  });
  WidgetsBinding.instance.scheduleFrame();
}

/// «1:05» a partir de segundos.
String clockText(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// Primer fotograma de un video remoto, para los videos publicados antes de que existieran las miniaturas.
class VideoFrame extends StatefulWidget {
  const VideoFrame({super.key, required this.url, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  State<VideoFrame> createState() => _VideoFrameState();
}

class _VideoFrameState extends State<VideoFrame> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await c.initialize();
      await c.setVolume(0);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _c = c);
    } catch (_) {
      await c.dispose();
    }
  }

  @override
  void dispose() {
    releaseVideo(_c);
    _c = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return const ColoredBox(color: Color(0xFF0B0B12));
    final size = c.value.size;
    return ClipRect(
      child: FittedBox(
        fit: widget.fit,
        child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c)),
      ),
    );
  }
}

/// Miniatura de un video: su póster o, si no tiene, su primer fotograma.
class VideoPoster extends StatelessWidget {
  const VideoPoster({super.key, required this.media, this.fit = BoxFit.cover});

  final Media media;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final poster = media.posterUrl;
    return filtered(media.filter, poster != null ? NetImage(poster, fit: fit) : VideoFrame(url: media.url, fit: fit));
  }
}

/// Video dentro de una tarjeta: miniatura con botón de reproducir, duración y la etiqueta «Reel».
class ReelThumb extends StatelessWidget {
  const ReelThumb({super.key, required this.media, required this.onTap, this.onDoubleTap});

  final Media media;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final duration = media.duration;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        VideoPoster(media: media),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x59000000), Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
              stops: [0, .28, .62, 1],
            ),
          ),
        ),
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withAlpha(90),
              border: Border.all(color: Colors.white.withAlpha(150), width: 1.5),
            ),
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 30),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
            decoration: BoxDecoration(color: Colors.black.withAlpha(120), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const TxIcon(TxGlyph.reels, size: 14, color: Colors.white, stroke: 2.2),
              const SizedBox(width: 5),
              Text('Reel', style: TxDark.body(12, weight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
        if (duration != null && duration > 0)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(8)),
              child: Text(clockText(duration), style: TxDark.body(12, weight: FontWeight.w600, color: Colors.white)),
            ),
          ),
      ]),
    );
  }
}

/// Galería de una publicación: una imagen, un video o un carrusel con indicadores.
/// Con [onVideoTap], el video se muestra como miniatura de Reel y al tocarlo se abre Reels.
class MediaGallery extends StatefulWidget {
  const MediaGallery({super.key, required this.media, this.onDoubleTap, this.onVideoTap, this.radius = 18});

  final List<Media> media;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onVideoTap;
  final double radius;

  @override
  State<MediaGallery> createState() => _MediaGalleryState();
}

class _MediaGalleryState extends State<MediaGallery> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media.isEmpty) return const SizedBox.shrink();
    final aspect = media.first.aspect.clamp(.8, 1.9).toDouble();
    final onVideoTap = widget.onVideoTap;
    Widget item(Media m, int i) => m.isVideo
        ? (onVideoTap != null ? ReelThumb(media: m, onTap: onVideoTap, onDoubleTap: widget.onDoubleTap) : InlineVideo(url: m.url, aspect: m.aspect))
        : GestureDetector(
            onTap: () => pushFade(context, MediaViewer(media: media.where((x) => !x.isVideo).toList(), initial: _imageIndex(i))),
            onDoubleTap: widget.onDoubleTap,
            child: filtered(m.filter, NetImage(m.url, fit: BoxFit.cover)),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        decoration: BoxDecoration(color: Tx.surface3, border: Border.all(color: Tx.border)),
        child: media.length == 1
            ? AspectRatio(
                aspectRatio: media.first.isVideo ? (onVideoTap != null ? media.first.aspect.clamp(.8, 1.9).toDouble() : media.first.aspect) : aspect,
                child: item(media.first, 0),
              )
            : AspectRatio(
                aspectRatio: aspect,
                child: Stack(children: [
                  PageView.builder(
                    itemCount: media.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => item(media[i], i),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withAlpha(140), borderRadius: BorderRadius.circular(12)),
                      child: Text('${_index + 1}/${media.length}', style: Tx.body(12, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(media.length, (i) {
                        final active = i == _index;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 18 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white.withAlpha(120),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }

  int _imageIndex(int i) {
    var n = 0;
    for (var k = 0; k < i; k++) {
      if (!widget.media[k].isVideo) n++;
    }
    return n;
  }
}

/// Video que se carga al tocarlo y se reproduce dentro de la tarjeta.
class InlineVideo extends StatefulWidget {
  const InlineVideo({super.key, required this.url, this.aspect = 16 / 9, this.autoplay = false, this.loop = true});

  final String url;
  final double aspect;
  final bool autoplay;
  final bool loop;

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  VideoPlayerController? _c;
  bool _loading = false;
  bool _failed = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) _start();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    try {
      await c.initialize();
      await c.setLooping(widget.loop);
      if (!mounted) {
        c.dispose();
        return;
      }
      songPlayer.pause();
      c.addListener(_tick);
      await c.play();
      setState(() {
        _c = c;
        _loading = false;
      });
    } catch (_) {
      c.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return GestureDetector(
        onTap: _failed ? null : _start,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: _failed
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(CupertinoIcons.exclamationmark_triangle, color: Tx.muted),
                  const SizedBox(height: 6),
                  Text(tr('No se pudo reproducir el video'), style: Tx.body(13, color: Tx.muted)),
                ])
              : _loading
                  ? const CupertinoActivityIndicator(color: Colors.white, radius: 14)
                  : Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha(36),
                        border: Border.all(color: Colors.white.withAlpha(90)),
                      ),
                      child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 28),
                    ),
        ),
      );
    }
    final value = c.value;
    final total = value.duration.inMilliseconds;
    final progress = total > 0 ? value.position.inMilliseconds / total : 0.0;
    return GestureDetector(
      onTap: () => value.isPlaying ? c.pause() : c.play(),
      child: Container(
        color: Colors.black,
        child: Stack(alignment: Alignment.center, children: [
          AspectRatio(aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : widget.aspect, child: VideoPlayer(c)),
          if (!value.isPlaying)
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(110)),
              child: const Icon(CupertinoIcons.play_fill, color: Colors.white, size: 28),
            ),
          Positioned(
            right: 10,
            bottom: 12,
            child: GestureDetector(
              onTap: () {
                setState(() => _muted = !_muted);
                c.setVolume(_muted ? 0 : 1);
              },
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(140)),
                child: Icon(_muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill, color: Colors.white, size: 16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0).toDouble(),
              minHeight: 3,
              backgroundColor: Colors.white.withAlpha(40),
              valueColor: AlwaysStoppedAnimation(Tx.accentSoft),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Relleno de las zonas seguras que no cambia al abrir el teclado (SafeArea pierde el inferior y mueve el contenido).
class StableSafeArea extends StatelessWidget {
  const StableSafeArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(padding: MediaQuery.viewPaddingOf(context), child: child);
}

/// Sube [child] (la barra con el comentario) por encima del teclado sin cambiar el tamaño de lo que hay detrás: la
/// foto o el video de la vista previa no se encogen ni se desplazan. Usar con `resizeToAvoidBottomInset: false`.
class KeyboardLift extends StatelessWidget {
  const KeyboardLift({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lift = (MediaQuery.viewInsetsOf(context).bottom - MediaQuery.viewPaddingOf(context).bottom).clamp(0.0, double.infinity).toDouble();
    return Transform.translate(
      offset: Offset(0, -lift),
      child: ColoredBox(color: lift > 0 ? const Color(0xE6000000) : Colors.transparent, child: child),
    );
  }
}

/// Video ajustado al espacio disponible conservando su proporción (el tamaño ya viene girado en los videos verticales).
class FittedVideo extends StatelessWidget {
  const FittedVideo({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    final w = size.width > 0 ? size.width : 9.0;
    final h = size.height > 0 ? size.height : 16.0;
    return SizedBox.expand(
      child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: w, height: h, child: VideoPlayer(controller))),
    );
  }
}

/// Foto ajustada al espacio disponible que se acerca con pellizco (hasta 5×) o doble toque. Sin ampliar, arrastrarla
/// en vertical con un dedo avisa a [onDrag]/[onDragEnd] (para cerrar el visor deslizando); un segundo dedo o un gesto
/// horizontal lo cancela ([onDragCancel]). [onZoom] avisa al ampliarse o volver. Sin ampliar, la foto no se puede mover.
class ZoomImage extends StatefulWidget {
  const ZoomImage({super.key, required this.image, this.onZoom, this.onDrag, this.onDragEnd, this.onDragCancel});

  final ImageProvider image;
  final ValueChanged<bool>? onZoom;
  final ValueChanged<double>? onDrag;
  final ValueChanged<double>? onDragEnd;
  final VoidCallback? onDragCancel;

  @override
  State<ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<ZoomImage> with SingleTickerProviderStateMixin {
  final _t = TransformationController();
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 240))
    ..addListener(() {
      final a = _zoomTo;
      if (a != null) _t.value = a.value;
    });
  Animation<Matrix4>? _zoomTo;
  Offset _tapAt = Offset.zero;
  bool _zoomed = false;
  // Gesto de cerrar: se decide tras 12 px; solo vale vertical, con un dedo y sin ampliar.
  Offset _moved = Offset.zero;
  bool _dragging = false;
  bool _ignore = false;

  @override
  void initState() {
    super.initState();
    _t.addListener(_changed);
  }

  @override
  void dispose() {
    _anim.dispose();
    _t.dispose();
    super.dispose();
  }

  void _changed() {
    final zoomed = _t.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed == _zoomed) return;
    setState(() => _zoomed = zoomed);
    widget.onZoom?.call(zoomed);
  }

  void _start(ScaleStartDetails d) {
    _moved = Offset.zero;
    _dragging = false;
    _ignore = _zoomed || d.pointerCount > 1;
  }

  void _update(ScaleUpdateDetails d) {
    if (d.pointerCount > 1 || _zoomed) {
      if (_dragging) widget.onDragCancel?.call();
      _dragging = false;
      _ignore = true;
      return;
    }
    if (_ignore) return;
    if (!_dragging) {
      _moved += d.focalPointDelta;
      if (_moved.distance < 12) return;
      if (_moved.dy.abs() <= _moved.dx.abs()) {
        _ignore = true;
        return;
      }
      _dragging = true;
      widget.onDrag?.call(_moved.dy);
      return;
    }
    widget.onDrag?.call(d.focalPointDelta.dy);
  }

  void _end(ScaleEndDetails d) {
    if (_dragging) widget.onDragEnd?.call(d.velocity.pixelsPerSecond.dy);
    _dragging = false;
    // Un pellizco que no llega a ampliar deja la foto exactamente centrada y a su tamaño.
    if (_t.value.getMaxScaleOnAxis() <= 1.01 && _t.value != Matrix4.identity()) _t.value = Matrix4.identity();
  }

  void _toggle() {
    const scale = 2.5;
    final end =
        _zoomed ? Matrix4.identity() : (Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(-_tapAt.dx * (scale - 1), -_tapAt.dy * (scale - 1), 0));
    _zoomTo = Matrix4Tween(begin: _t.value, end: end).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onDoubleTapDown: (d) => _tapAt = d.localPosition,
        onDoubleTap: _toggle,
        child: InteractiveViewer(
          transformationController: _t,
          minScale: 1,
          maxScale: 5,
          panEnabled: _zoomed,
          onInteractionStart: _start,
          onInteractionUpdate: _update,
          onInteractionEnd: _end,
          child: SizedBox(
            width: box.maxWidth,
            height: box.maxHeight,
            child: Image(
              image: widget.image,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) => Stack(alignment: Alignment.center, fit: StackFit.expand, children: [
                child,
                if (frame == null && !sync) const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
              ]),
              errorBuilder: (_, __, ___) => const Center(child: Icon(CupertinoIcons.photo, color: Colors.white54, size: 44)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Visor de fotos a pantalla completa: cada foto se ajusta a la pantalla (sin moverse con el teclado), se acerca con
/// pellizco o doble toque y, sin ampliar, se cierra deslizando hacia arriba o abajo.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.initial = 0}) : file = null;

  /// Foto guardada en el teléfono (por ejemplo, una foto cifrada del chat ya descifrada).
  const MediaViewer.file(File this.file, {super.key})
      : media = const [],
        initial = 0;

  final List<Media> media;
  final int initial;
  final File? file;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  double _drag = 0;
  bool _zoomed = false;
  int _pointers = 0;
  bool _saving = false;

  int get _count => widget.file != null ? 1 : widget.media.length;

  bool get _canSave => widget.file == null && !widget.media[_index].isVideo;

  ImageProvider _image(int i) {
    final file = widget.file;
    return file != null ? FileImage(file) : CachedNetworkImageProvider(widget.media[i].url);
  }

  void _pointer(int delta) {
    final before = _pointers > 1;
    _pointers = (_pointers + delta).clamp(0, 10);
    if (before != _pointers > 1) setState(() {});
  }

  void _dragEnd(double velocity) {
    if (_drag.abs() > 120 || velocity.abs() > 900) {
      Navigator.pop(context);
    } else if (_drag != 0) {
      setState(() => _drag = 0);
    }
  }

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    final media = widget.media[_index];
    setState(() => _saving = true);
    try {
      await DeviceAccess.saveImage(media.url);
      if (mounted) toast(context, tr('Imagen guardada en Fotos.'));
    } on DeviceException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo guardar la imagen.'), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_drag.abs() / 400)).clamp(0.3, 1.0).toDouble();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black.withAlpha((opacity * 255).round()),
        // El cuerpo del Scaffold llega con restricciones flexibles: sin SizedBox.expand el Stack mediría lo que la barra
        // superior y la foto quedaría encogida dentro de esa franja.
        body: SizedBox.expand(child: Stack(children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: (_) => _pointer(1),
              onPointerUp: (_) => _pointer(-1),
              onPointerCancel: (_) => _pointer(-1),
              child: Transform.translate(
                offset: Offset(0, _drag),
                child: PageView.builder(
                  controller: _page,
                  physics: _zoomed || _pointers > 1 ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                  itemCount: _count,
                  onPageChanged: (i) => setState(() {
                    _index = i;
                    _zoomed = false;
                  }),
                  itemBuilder: (_, i) => filtered(
                    i < widget.media.length ? widget.media[i].filter : null,
                    ZoomImage(
                      image: _image(i),
                      onZoom: (zoomed) => setState(() {
                        _zoomed = zoomed;
                        _drag = 0;
                      }),
                      onDrag: (dy) => setState(() => _drag += dy),
                      onDragEnd: _dragEnd,
                      onDragCancel: () => setState(() => _drag = 0),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(36)),
                    child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 20),
                  ),
                ),
                const Spacer(),
                if (_count > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(tr('{index} de {count}', {'index': _index + 1, 'count': _count}), style: TxDark.body(14, weight: FontWeight.w600, color: Colors.white)),
                  ),
                if (_canSave)
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(36)),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20, child: CupertinoActivityIndicator(color: Colors.white))
                          : const Icon(CupertinoIcons.arrow_down_to_line, color: Colors.white, size: 20),
                    ),
                  ),
              ]),
            ),
          ),
        ])),
      ),
      ),
    );
  }
}
