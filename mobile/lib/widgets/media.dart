import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/audio.dart';
import '../core/device.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Galería de una publicación: una imagen, un video o un carrusel con indicadores.
class MediaGallery extends StatefulWidget {
  const MediaGallery({super.key, required this.media, this.onDoubleTap, this.radius = 18});

  final List<Media> media;
  final VoidCallback? onDoubleTap;
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
    Widget item(Media m, int i) => m.isVideo
        ? InlineVideo(url: m.url, aspect: m.aspect)
        : GestureDetector(
            onTap: () => pushFade(context, MediaViewer(media: media.where((x) => !x.isVideo).toList(), initial: _imageIndex(i))),
            onDoubleTap: widget.onDoubleTap,
            child: NetImage(m.url, fit: BoxFit.cover),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Container(
        decoration: BoxDecoration(color: Tx.surface3, border: Border.all(color: Tx.border)),
        child: media.length == 1
            ? AspectRatio(aspectRatio: media.first.isVideo ? media.first.aspect : aspect, child: item(media.first, 0))
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
                  Text('No se pudo reproducir el video', style: Tx.body(13, color: Tx.muted)),
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

/// Visor de imágenes a pantalla completa con zoom y deslizar hacia abajo para cerrar.
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.media, this.initial = 0});

  final List<Media> media;
  final int initial;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  double _drag = 0;
  bool _saving = false;

  Future<void> _save() async {
    final media = widget.media[_index];
    if (_saving || media.isVideo) return;
    setState(() => _saving = true);
    try {
      await DeviceAccess.saveImage(media.url);
      if (mounted) toast(context, 'Imagen guardada en Fotos.');
    } on DeviceException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo guardar la imagen.', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_drag.abs() / 400)).clamp(0.3, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black.withAlpha((opacity * 255).round()),
      body: Stack(children: [
        GestureDetector(
          onVerticalDragUpdate: (d) => setState(() => _drag += d.delta.dy),
          onVerticalDragEnd: (d) {
            if (_drag.abs() > 120 || d.velocity.pixelsPerSecond.dy.abs() > 900) {
              Navigator.pop(context);
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: PageView.builder(
              controller: _page,
              itemCount: widget.media.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(child: NetImage(widget.media[i].url, fit: BoxFit.contain)),
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
              if (widget.media.length > 1)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text('${_index + 1} de ${widget.media.length}', style: TxDark.body(14, weight: FontWeight.w600, color: Colors.white)),
                ),
              if (!widget.media[_index].isVideo)
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
      ]),
    );
  }
}
