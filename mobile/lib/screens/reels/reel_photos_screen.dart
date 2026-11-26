import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trevix_video/trevix_video.dart';
import 'package:video_player/video_player.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/reel_effects.dart';
import '../../core/reel_photo_item.dart';
import '../../core/reel_photo_motion.dart';
import '../../core/theme.dart';
import '../../core/video_render.dart';
import '../../core/video_tools.dart';
import '../../widgets/common.dart';
import '../../widgets/media_gallery.dart';
import 'reel_draft.dart';

const reelMaxPhotos = 8;
const _aspect = 9 / 16;
const _fadeMs = 300;

Map<String, (IconData, String)> get _modes => {
      'live': (CupertinoIcons.circle_grid_hex_fill, tr('Foto animada')),
      'loop': (CupertinoIcons.repeat, tr('Bucle')),
      'static': (CupertinoIcons.photo, tr('Estática')),
    };

/// Reel con fotos de la galería (como historias): fotos en movimiento LIVE, bucle del clip o imagen fija.
class ReelPhotosScreen extends StatefulWidget {
  ReelPhotosScreen({super.key, List<String>? photos, List<ReelPhotoItem>? items})
      : items = items ?? [for (final p in photos ?? const <String>[]) ReelPhotoItem(path: p)];

  final List<ReelPhotoItem> items;

  @override
  State<ReelPhotosScreen> createState() => _ReelPhotosScreenState();
}

class _ReelPhotosScreenState extends State<ReelPhotosScreen> with SingleTickerProviderStateMixin {
  late final List<ReelPhotoItem> _items = [...widget.items.take(reelMaxPhotos)];
  final Map<String, Size> _sizes = {};
  String _mode = 'live';
  String? _effect;
  int _seconds = 3;
  bool _busy = false;
  late final _ticker = createTicker((elapsed) {
    setState(() => _elapsed = elapsed.inMilliseconds);
    _syncLivePreview();
  });
  int _elapsed = 0;
  VideoPlayerController? _live;
  int _liveSlot = -1;

  int get _per => _seconds * 1000;
  int get _total => _items.length * _per;
  int get _slot => _items.isEmpty ? 0 : (_elapsed ~/ _per) % _items.length;

  @override
  void initState() {
    super.initState();
    if (_items.length == 1) _seconds = 5;
    if (!_items.any((e) => e.hasLive)) _mode = 'static';
    for (final e in _items) {
      _measure(e.path);
    }
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLivePreview());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _live?.dispose();
    super.dispose();
  }

  bool _useLive(ReelPhotoItem item) => item.hasLive && _mode != 'static';

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

  double _fitWidth(String path) {
    final s = _sizes[path];
    if (s == null || s.height <= 0) return 1;
    return math.min(1, (s.width / s.height) / _aspect);
  }

  void _restart() {
    _ticker.stop();
    _elapsed = 0;
    _liveSlot = -1;
    _ticker.start();
    _syncLivePreview();
  }

  Future<void> _syncLivePreview() async {
    if (!mounted || _items.isEmpty) return;
    final item = _items[_slot];
    if (!_useLive(item)) {
      if (_live != null) {
        await _live!.pause();
        _live!.dispose();
        _live = null;
        _liveSlot = -1;
        if (mounted) setState(() {});
      }
      return;
    }
    if (_liveSlot == _slot && _live != null && _live!.value.isInitialized) return;
    _live?.dispose();
    final c = VideoPlayerController.file(File(item.livePath!));
    _live = c;
    _liveSlot = _slot;
    try {
      await c.initialize();
      await c.setLooping(_mode == 'loop');
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      c.dispose();
      _live = null;
      _liveSlot = -1;
    }
    if (mounted) setState(() {});
  }

  Future<void> _addPhotos() async {
    final room = reelMaxPhotos - _items.length;
    if (room <= 0) {
      toast(context, tr('Puedes usar como mucho {max} fotos.', {'max': reelMaxPhotos}));
      return;
    }
    final picked = await showModalBottomSheet<List<ReelPhotoItem>>(
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
              onPickMany: (picks) => Navigator.pop(ctx, [for (final p in picks) ReelPhotoItem.fromPick(p)]),
              onPick: (p) => Navigator.pop(ctx, [ReelPhotoItem.fromPick(p)]),
            ),
          ),
        ]),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final e in picked.take(reelMaxPhotos - _items.length)) {
        _items.add(e);
        _measure(e.path);
      }
    });
    _restart();
  }

  void _removePhoto(int index) {
    if (_items.length == 1) {
      Navigator.pop(context);
      return;
    }
    setState(() => _items.removeAt(index));
    _restart();
  }

  Future<String> _renderLivePart(ReelPhotoItem item, int index, String dirPath) async {
    try {
      final livePath = item.livePath;
      if (livePath == null || !await File(livePath).exists()) {
        return await _renderStillPart(item, index, dirPath);
      }
      final clip = '$dirPath/live_$index.mp4';
      await renderWithProgress(
        VideoRenderJob(input: livePath, output: clip, aspect: _aspect, contain: true, keepAudio: false),
        (_) {},
      );
      if (_mode != 'loop') return clip;
      final info = await VideoTools.info(livePath);
      final liveMs = math.max(400, ((info.seconds ?? 2) * 1000).round());
      if (liveMs >= _per) return clip;
      final reps = (_per / liveMs).ceil().clamp(1, 24);
      if (reps <= 1) return clip;
      final looped = '$dirPath/live_loop_$index.mp4';
      await TrevixVideo.concat(List<String>.filled(reps, clip), looped, aspect: _aspect);
      return looped;
    } catch (_) {
      return await _renderStillPart(item, index, dirPath);
    }
  }

  Future<String> _renderStillPart(ReelPhotoItem item, int index, String dirPath) async {
    final (photo, bg, width) = await _preparePhoto(item.path, dirPath, index);
    final overlays = <VideoOverlay>[
      VideoOverlay(bg, [const OverlayKey(0, x: 0.5, y: 0.5, width: 1), OverlayKey(_per, x: 0.5, y: 0.5, width: 1)]),
      VideoOverlay(photo, [
        OverlayKey(0, x: 0.5, y: 0.5, width: width),
        OverlayKey(_per, x: 0.5, y: 0.5, width: width),
      ]),
    ];
    final base = await _blackFrame(dirPath);
    final out = '$dirPath/still_$index.mp4';
    await renderWithProgress(
      VideoRenderJob(input: base, output: out, imageMs: _per, aspect: _aspect, overlays: overlays, keepAudio: false),
      (_) {},
    );
    return out;
  }

  Future<void> _continue() async {
    if (_busy || _items.isEmpty) return;
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
      final n = _items.length;
      final parts = <String>[];
      for (var i = 0; i < n; i++) {
        if (cancelled) throw const _Cancelled();
        status.value = (tr('Preparando las fotos…'), i / n * .85);
        final item = _items[i];
        if (_useLive(item)) {
          parts.add(await _renderLivePart(item, i, dir.path));
        } else {
          parts.add(await _renderStillPart(item, i, dir.path));
        }
      }
      var merged = '$dir/merged.mp4';
      if (parts.length == 1) {
        merged = parts.first;
      } else {
        status.value = (tr('Creando el video…'), .86);
        merged = '${(await getTemporaryDirectory()).path}/reel_photos_${DateTime.now().microsecondsSinceEpoch}.mp4';
        await TrevixVideo.concat(parts, merged, aspect: _aspect);
      }
      if (cancelled) throw const _Cancelled();
      String output = merged;
      final effect = _effect;
      if (effect != null) {
        final effectDir = await renderDir('reel_photos_fx');
        final (frames, ms) = await reelEffectFrames(effect, const Size(540, 960), effectDir.path);
        final withFx = '${(await getTemporaryDirectory()).path}/reel_photos_fx_${DateTime.now().microsecondsSinceEpoch}.mp4';
        await renderWithProgress(
          VideoRenderJob(
            input: merged,
            output: withFx,
            overlays: [
              VideoOverlay(frames.first, const [OverlayKey(0, x: .5, y: .5, width: 1)], frames: frames, frameMs: ms),
            ],
            keepAudio: false,
          ),
          (p) => status.value = (tr('Creando el video…'), .86 + p * .14),
        );
        output = withFx;
        effectDir.delete(recursive: true).ignore();
      }
      if (cancelled) throw const _Cancelled();
      close();
      if (!mounted) return;
      final dur = (await VideoTools.info(output)).seconds ?? (n * _seconds).toDouble();
      Navigator.pop(context, ReelDraft(path: output, seconds: dur));
    } catch (e) {
      close();
      if (!cancelled && e is! _Cancelled && mounted) {
        toast(context, tr('No se pudo crear el video con las fotos. Inténtalo de nuevo.'), error: true);
      }
      if (mounted) {
        setState(() => _busy = false);
        _restart();
      }
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  Future<(String, String, double)> _preparePhoto(String path, String dir, int index) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 960,
      targetHeight: 1600,
    );
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    final w = image.width;
    final h = image.height;
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
    final anyLive = _items.any((e) => e.hasLive);
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
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Fotos en movimiento'), textAlign: TextAlign.center, style: TxDark.display(17, color: Colors.white)),
                  Text(
                    tr('Elige fotos en movimiento (LIVE) de tu galería, como en las historias.'),
                    textAlign: TextAlign.center,
                    style: TxDark.body(11.5, color: Colors.white60),
                  ),
                ]),
              ),
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
                  enabled: m.key == 'static' || anyLive,
                  onTap: () {
                    if (m.key != 'static' && !anyLive) {
                      toast(context, tr('Elige una foto en movimiento (LIVE) de tu galería.'), error: true);
                      return;
                    }
                    setState(() => _mode = m.key);
                    _restart();
                  },
                ),
              const SizedBox(width: 10),
              for (final s in const [2, 3, 5, 8])
                _Chip(
                  label: tr('{n} s', {'n': s}),
                  selected: _seconds == s,
                  enabled: _mode == 'static' || _mode == 'loop',
                  onTap: () {
                    setState(() => _seconds = s);
                    _restart();
                  },
                ),
            ]),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _Chip(
                  icon: CupertinoIcons.sparkles,
                  label: tr('Sin efecto'),
                  selected: _effect == null,
                  onTap: () => setState(() => _effect = null),
                ),
                for (final e in reelEffectNames.entries)
                  _Chip(
                    label: e.value,
                    selected: _effect == e.key,
                    onTap: () => setState(() => _effect = e.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 74,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(clipBehavior: Clip.none, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image(image: ResizeImage(FileImage(File(_items[i].path)), width: 160), width: 56, height: 70, fit: BoxFit.cover),
                    ),
                    if (_items[i].hasLive)
                      const Positioned(left: 4, top: 4, child: LiveBadge(small: true)),
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
              if (_items.length < reelMaxPhotos)
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
            child: GradientButton(label: tr('Siguiente'), loading: _busy, onPressed: _items.isEmpty ? null : _continue),
          ),
          SizedBox(height: pad.bottom + 10),
        ]),
      ),
    );
  }

  Widget _preview() {
    final n = _items.length;
    if (n == 0) return const ColoredBox(color: Colors.black);
    final t = _total <= 0 ? 0 : _elapsed % _total;
    final slot = _slot;
    final item = _items[slot];
    final showLive = _useLive(item) && _live != null && _live!.value.isInitialized;

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        if (showLive)
          FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _live!.value.size.width,
              height: _live!.value.size.height,
              child: VideoPlayer(_live!),
            ),
          )
        else
          for (var i = 0; i < n; i++)
            if (reelPhotoSlideAt(i, n, _per, t, fadeMs: _fadeMs) case final s when s.alpha > 0)
              Opacity(
                opacity: s.alpha.clamp(0.0, 1.0),
                child: Stack(fit: StackFit.expand, children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18, tileMode: TileMode.clamp),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.mode(Color(0x59000000), BlendMode.srcOver),
                      child: Image(image: ResizeImage(FileImage(File(_items[i].path)), width: 200), fit: BoxFit.cover),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: w * _fitWidth(_items[i].path),
                      child: Image(image: _provider(_items[i].path), fit: BoxFit.fitWidth),
                    ),
                  ),
                ]),
              ),
        if (_effect != null) ReelEffectLayer(effect: _effect!),
      ]);
    });
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, required this.label, required this.selected, required this.onTap, this.enabled = true});

  final IconData? icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final on = enabled && selected;
    final fg = enabled ? (on ? Colors.black : Colors.white) : Colors.white38;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.white.withAlpha(26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(on ? 255 : 70)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
            Text(label, style: TxDark.body(13, weight: FontWeight.w700, color: fg)),
          ]),
        ),
      ),
    );
  }
}