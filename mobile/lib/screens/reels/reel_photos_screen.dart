import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trevix_video/trevix_video.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../core/video_render.dart';
import '../../widgets/common.dart';
import '../../widgets/media_gallery.dart';
import 'reel_draft.dart';

const reelMaxPhotos = 8;
const _aspect = 9 / 16;
const _fadeMs = 300;

/// Movimiento de las fotos: 'motion' (acercamiento lento con desplazamiento), 'loop' (se acerca y vuelve, para que
/// el reel se repita sin cortes) o 'static' (quieta).
Map<String, (IconData, String)> get _modes => {
      'motion': (CupertinoIcons.arrow_up_left_arrow_down_right, tr('En movimiento')),
      'loop': (CupertinoIcons.repeat, tr('Bucle')),
      'static': (CupertinoIcons.photo, tr('Estática')),
    };

/// Estado de una foto en el instante [t]: centro x, acercamiento y opacidad. Lo usan la vista previa y las claves
/// del video final; entre los puntos de quiebre es lineal, así que el video queda igual que la vista previa.
({double x, double zoom, double alpha}) _photoAt(String mode, int i, int n, int per, int t) {
  final start = i * per;
  final end = (i + 1) * per;
  final last = i == n - 1;
  double alpha;
  if (t < start || (!last && t > end + _fadeMs)) {
    alpha = 0;
  } else if (i > 0 && t < start + _fadeMs) {
    alpha = (t - start) / _fadeMs;
  } else {
    alpha = 1;
  }
  final p = ((t - start) / per).clamp(0.0, 1.0);
  final dir = i.isEven ? 1 : -1;
  return switch (mode) {
    'motion' => (x: .5 + dir * .03 * (p * 2 - 1), zoom: 1 + .18 * p, alpha: alpha),
    'loop' => (x: .5, zoom: 1 + .15 * (1 - (2 * p - 1).abs()), alpha: alpha),
    _ => (x: .5, zoom: 1.0, alpha: alpha),
  };
}

/// Reel con fotos animadas (como el modo foto de TikTok): de 1 a [reelMaxPhotos] fotos, una tras otra con un
/// fundido, en movimiento, en bucle o estáticas, sobre su propia foto desenfocada. Se quitan con la ✕ y se añaden
/// más con «+». «Siguiente» crea el video en el teléfono y lo devuelve como [ReelDraft] para el editor.
class ReelPhotosScreen extends StatefulWidget {
  const ReelPhotosScreen({super.key, required this.photos});

  final List<String> photos;

  @override
  State<ReelPhotosScreen> createState() => _ReelPhotosScreenState();
}

class _ReelPhotosScreenState extends State<ReelPhotosScreen> with SingleTickerProviderStateMixin {
  late final List<String> _photos = [...widget.photos.take(reelMaxPhotos)];
  final Map<String, Size> _sizes = {};
  String _mode = 'motion';
  int _seconds = 3;
  bool _busy = false;
  late final _ticker = createTicker((elapsed) => setState(() => _elapsed = elapsed.inMilliseconds));
  int _elapsed = 0;

  int get _per => _seconds * 1000;
  int get _total => _photos.length * _per;

  @override
  void initState() {
    super.initState();
    if (_photos.length == 1) _seconds = 5;
    for (final p in _photos) {
      _measure(p);
    }
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  ImageProvider _provider(String path) => ResizeImage(FileImage(File(path)), width: 1280, height: 1280, policy: ResizeImagePolicy.fit);

  void _measure(String path) {
    if (_sizes.containsKey(path)) return;
    final stream = _provider(path).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      if (mounted) setState(() => _sizes[path] = Size(info.image.width.toDouble(), info.image.height.toDouble()));
    }, onError: (_, __) => stream.removeListener(listener));
    stream.addListener(listener);
  }

  /// Ancho de la foto (fracción del ancho del reel) para verse entera en el marco 9:16.
  double _fitWidth(String path) {
    final s = _sizes[path];
    if (s == null || s.height <= 0) return 1;
    return math.min(1, (s.width / s.height) / _aspect);
  }

  void _restart() {
    _ticker.stop();
    _elapsed = 0;
    _ticker.start();
  }

  Future<void> _addPhotos() async {
    final room = reelMaxPhotos - _photos.length;
    if (room <= 0) {
      toast(context, tr('Puedes usar como mucho {max} fotos.', {'max': reelMaxPhotos}));
      return;
    }
    final paths = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .88,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Expanded(child: Text(tr('Elige más fotos'), style: TxDark.display(18))),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(CupertinoIcons.xmark, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: PhoneGallery(
              photosOnly: true,
              maxSelect: room,
              onPickMany: (picks) => Navigator.pop(ctx, [for (final p in picks) p.path]),
              onPick: (p) => Navigator.pop(ctx, [p.path]),
            ),
          ),
        ]),
      ),
    );
    if (paths == null || paths.isEmpty || !mounted) return;
    setState(() {
      for (final p in paths.take(reelMaxPhotos - _photos.length)) {
        _photos.add(p);
        _measure(p);
      }
    });
    _restart();
  }

  void _removePhoto(int index) {
    if (_photos.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _photos.removeAt(index));
    _restart();
  }

  /// Crea el video: un fondo negro de toda la duración y, encima, cada foto (con su copia desenfocada detrás)
  /// visible en su tramo y con su movimiento.
  Future<void> _continue() async {
    if (_busy || _photos.isEmpty) return;
    setState(() => _busy = true);
    _ticker.stop();
    final status = ValueNotifier<(String, double?)>((tr('Preparando las fotos…'), 0));
    var cancelled = false;
    final close = showRenderProgress(context, status, () {
      cancelled = true;
      TrevixVideo.cancel().ignore();
    });
    final dir = await renderDir('reel_photos');
    try {
      final n = _photos.length;
      final per = _per;
      final total = _total;
      final overlays = <VideoOverlay>[];
      for (var i = 0; i < n; i++) {
        if (cancelled) throw const _Cancelled();
        status.value = (tr('Preparando las fotos…'), i / n * .3);
        final (photo, bg, width) = await _preparePhoto(_photos[i], dir.path, i);
        final times = <int>{0, start(i, per) - 1, start(i, per), start(i, per) + _fadeMs, start(i, per) + per ~/ 2, start(i, per) + per,
          start(i, per) + per + _fadeMs, start(i, per) + per + _fadeMs + 1, total}
            .where((t) => t >= 0 && t <= total)
            .toList()
          ..sort();
        final photoKeys = <OverlayKey>[];
        final bgKeys = <OverlayKey>[];
        for (final t in times) {
          final s = _photoAt(_mode, i, n, per, t);
          photoKeys.add(OverlayKey(t, x: s.x, y: .5, width: width * s.zoom, alpha: s.alpha));
          bgKeys.add(OverlayKey(t, x: .5, y: .5, width: 1, alpha: s.alpha));
        }
        overlays
          ..add(VideoOverlay(bg, bgKeys))
          ..add(VideoOverlay(photo, photoKeys));
      }
      final base = await _blackFrame(dir.path);
      if (cancelled) throw const _Cancelled();
      final output = '${(await getTemporaryDirectory()).path}/reel_photos_${DateTime.now().microsecondsSinceEpoch}.mp4';
      final label = tr('Creando el video…');
      status.value = (label, .3);
      await renderWithProgress(
        VideoRenderJob(input: base, output: output, imageMs: total, aspect: _aspect, overlays: overlays, keepAudio: false),
        (p) => status.value = (label, .3 + p * .7),
      );
      if (cancelled) throw const _Cancelled();
      close();
      if (!mounted) return;
      Navigator.pop(context, ReelDraft(path: output, seconds: total / 1000));
    } catch (e) {
      close();
      if (!cancelled && e is! _Cancelled && mounted) toast(context, tr('No se pudo crear el video con las fotos. Inténtalo de nuevo.'), error: true);
      if (mounted) {
        setState(() => _busy = false);
        _restart();
      }
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  static int start(int i, int per) => i * per;

  /// La foto ya girada como se ve (ancho ≤ 960 px), su fondo desenfocado y oscurecido, y su ancho en el marco.
  Future<(String, String, double)> _preparePhoto(String path, String dir, int index) async {
    final bytes = await File(path).readAsBytes();
    final probe = await ui.instantiateImageCodec(bytes);
    final first = (await probe.getNextFrame()).image;
    final w = first.width, h = first.height;
    first.dispose();
    probe.dispose();
    final scale = math.min(1.0, math.min(960 / w, 1600 / h));
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: math.max(1, (w * scale).round()), targetHeight: math.max(1, (h * scale).round()));
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final photoPath = '$dir/photo_$index.png';
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(photoPath).writeAsBytes(data!.buffer.asUint8List());

      const bgSize = Size(180, 320);
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder);
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final fitted = applyBoxFit(BoxFit.cover, src.size, bgSize);
      final from = Alignment.center.inscribe(fitted.source, src);
      c.saveLayer(Offset.zero & bgSize, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.clamp));
      c.drawImageRect(image, from, Offset.zero & bgSize, Paint()..filterQuality = FilterQuality.medium);
      c.restore();
      c.drawRect(Offset.zero & bgSize, Paint()..color = const Color(0x59000000));
      final bgImage = await recorder.endRecording().toImage(bgSize.width.toInt(), bgSize.height.toInt());
      final bgData = await bgImage.toByteData(format: ui.ImageByteFormat.png);
      bgImage.dispose();
      final bgPath = '$dir/bg_$index.png';
      await File(bgPath).writeAsBytes(bgData!.buffer.asUint8List());
      return (photoPath, bgPath, math.min(1.0, (w / h) / _aspect));
    } finally {
      image.dispose();
    }
  }

  Future<String> _blackFrame(String dir) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 1080, 1920), Paint()..color = Colors.black);
    final image = await recorder.endRecording().toImage(1080, 1920);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final path = '$dir/base.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(children: [
          SizedBox(height: pad.top + 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.chevron_back, color: Colors.white),
                tooltip: tr('Volver'),
              ),
              Expanded(child: Text(tr('Fotos animadas'), textAlign: TextAlign.center, style: TxDark.display(17, color: Colors.white))),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Center(child: AspectRatio(aspectRatio: _aspect, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _preview()))),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final m in _modes.entries)
                _Chip(
                  icon: m.value.$1,
                  label: m.value.$2,
                  selected: _mode == m.key,
                  onTap: () {
                    setState(() => _mode = m.key);
                    _restart();
                  },
                ),
              const SizedBox(width: 10),
              for (final s in const [2, 3, 5, 8])
                _Chip(
                  label: tr('{n} s', {'n': s}),
                  selected: _seconds == s,
                  onTap: () {
                    setState(() => _seconds = s);
                    _restart();
                  },
                ),
            ]),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (var i = 0; i < _photos.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image(image: ResizeImage(FileImage(File(_photos[i])), width: 160), width: 56, height: 70, fit: BoxFit.cover),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: _busy ? null : () => _removePhoto(i),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                          child: Icon(CupertinoIcons.xmark, size: 12, color: Colors.white, semanticLabel: tr('Quitar')),
                        ),
                      ),
                    ),
                  ]),
                ),
              if (_photos.length < reelMaxPhotos)
                GestureDetector(
                  onTap: _busy ? null : _addPhotos,
                  child: Container(
                    width: 56,
                    height: 70,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white38)),
                    child: Icon(CupertinoIcons.add, color: Colors.white, semanticLabel: tr('Añadir fotos')),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GradientButton(label: tr('Siguiente'), loading: _busy, onPressed: _photos.isEmpty ? null : _continue),
          ),
          SizedBox(height: pad.bottom + 10),
        ]),
      ),
    );
  }

  Widget _preview() {
    final n = _photos.length;
    if (n == 0) return const ColoredBox(color: Colors.black);
    final t = _total <= 0 ? 0 : _elapsed % _total;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        for (var i = 0; i < n; i++)
          if (_photoAt(_mode, i, n, _per, t) case final s when s.alpha > 0)
            Opacity(
              opacity: s.alpha.clamp(0.0, 1.0),
              child: Stack(fit: StackFit.expand, children: [
                ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(Color(0x59000000), BlendMode.srcOver),
                    child: Image(image: ResizeImage(FileImage(File(_photos[i])), width: 200), fit: BoxFit.cover),
                  ),
                ),
                Center(
                  child: Transform.translate(
                    offset: Offset((s.x - .5) * w, 0),
                    child: Transform.scale(
                      scale: s.zoom,
                      child: SizedBox(width: w * _fitWidth(_photos[i]), child: Image(image: _provider(_photos[i]), fit: BoxFit.fitWidth)),
                    ),
                  ),
                ),
              ]),
            ),
      ]);
    });
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, required this.label, required this.selected, required this.onTap});

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withAlpha(26),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(selected ? 255 : 70)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: selected ? Colors.black : Colors.white), const SizedBox(width: 6)],
          Text(label, style: TxDark.body(13, weight: FontWeight.w700, color: selected ? Colors.black : Colors.white)),
        ]),
      ),
    );
  }
}
