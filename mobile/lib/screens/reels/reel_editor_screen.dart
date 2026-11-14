import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:trevix_video/trevix_video.dart';
import 'package:video_player/video_player.dart';

import '../../core/audio.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/reel_effects.dart';
import '../../core/theme.dart';
import '../../core/video_render.dart';
import '../../core/video_tools.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/story_layers.dart';
import '../post/composer_screen.dart';
import '../stories/story_editor_tools.dart';
import 'reel_camera_screen.dart' show FilterStrip;
import 'reel_draft.dart';

const _songKey = 'reel-camera';
const _limits = {'text': 5, 'sticker': 5, 'emoji': 8};
const _maxLayers = 12;

const _emojis = [
  '😀', '😂', '🤣', '😍', '🥰', '😘', '😎', '🤩', '🥳', '😇', '🙂', '😉', '😜', '🤪', '🤔', '🤫', //
  '😴', '😱', '😭', '😡', '🥺', '😅', '🙈', '🙌', '👏', '👍', '👎', '✌️', '🤞', '🤟', '👌', '💪', //
  '🙏', '👀', '💯', '🔥', '✨', '⭐', '🌟', '⚡', '💥', '💫', '🎉', '🎊', '🎁', '🎈', '🎂', '🍕', //
  '🍔', '🍟', '🍦', '🍩', '🍓', '🍉', '☕', '🍻', '⚽', '🏀', '🎮', '🎧', '🎵', '🎶', '🎤', '📸', //
  '🎬', '🚀', '✈️', '🌈', '☀️', '🌙', '🌊', '🌸', '🌹', '🌴', '🍀', '🐶', '🐱', '🦋', '🦄', '❤️', //
  '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💖', '💔', '💋', '👑', '💎', '💸', '📍', '✅', '❌', //
];

/// Texto, emoji o sticker del reel y el tramo del video en el que se ve ([endMs] null: hasta el final).
class _ReelLayer {
  _ReelLayer(this.s);

  final StoryLayer s;
  int startMs = 0;
  int? endMs;
  final key = GlobalKey();
}

/// Editor de video del reel (como el de TikTok), al terminar de grabar o al elegir un video: filtros, efectos,
/// textos con fuentes y efectos, emojis y stickers animados que se mueven, giran y agrandan con los dedos, cada uno
/// con su tramo del video. «Siguiente» graba todo en el video y abre el compositor para la descripción.
class ReelEditorScreen extends StatefulWidget {
  const ReelEditorScreen({super.key, required this.draft});

  final ReelDraft draft;

  @override
  State<ReelEditorScreen> createState() => _ReelEditorScreenState();
}

class _ReelEditorScreenState extends State<ReelEditorScreen> {
  VideoPlayerController? _v;
  bool _failed = false;
  late String? _filter = widget.draft.filter;
  String? _effect;
  String? _poster;
  bool _next = false;

  /// Tira abierta abajo: '' (línea de tiempo), 'filters' o 'effects'.
  String _panel = '';
  final List<_ReelLayer> _layers = [];
  _ReelLayer? _selected;
  _ReelLayer? _target;
  _ReelLayer? _dragging;
  bool _overTrash = false;
  double _startScale = 1;
  double _startRotation = 0;

  /// Mientras se capturan los textos para grabarlos: todos visibles y sin el marco de elegido.
  bool _capturing = false;
  int _positionMs = 0;
  bool _playing = false;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  final _canvasKey = GlobalKey();
  final _trashKey = GlobalKey();

  /// Último video editado y la edición de la que salió (para no repetirlo al volver del compositor sin cambios).
  ReelDraft? _rendered;
  String? _renderedSig;

  ReelDraft get _draft => widget.draft;
  bool get _edited => _layers.isNotEmpty || _effect != null;
  int get _durationMs {
    final d = _v?.value.duration.inMilliseconds ?? 0;
    return d > 0 ? d : ((_draft.seconds ?? 0) * 1000).round();
  }

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
        await songPlayer.prepare(_songKey, song.song.withClip(song.start, math.max(30, (_draft.seconds ?? 30).ceil())), clip: true, at: at);
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

  Future<void> _seek(int ms) async {
    final v = _v;
    if (v == null) return;
    setState(() => _positionMs = ms);
    await v.seekTo(Duration(milliseconds: ms));
    if (_draft.songSync && songPlayer.currentKey == _songKey) await songPlayer.seek(Duration(milliseconds: ms));
  }

  void _tick() {
    final v = _v;
    if (v == null || !mounted) return;
    final pos = v.value.position.inMilliseconds;
    if ((pos - _positionMs).abs() >= 40 || v.value.isPlaying != _playing) {
      setState(() {
        _positionMs = pos;
        _playing = v.value.isPlaying;
      });
    }
    if (!_draft.songSync || !v.value.isPlaying || songPlayer.currentKey != _songKey) return;
    final now = DateTime.now();
    if (now.difference(_lastSync).inMilliseconds < 900) return;
    final drift = (songPlayer.positionNow - v.value.position).inMilliseconds.abs();
    if (drift > 300) {
      _lastSync = now;
      songPlayer.seek(v.value.position);
      if (!songPlayer.playing) songPlayer.resume(_songKey);
    }
  }

  void _togglePlay() => (_v?.value.isPlaying ?? false) ? _pause() : _play();

  // ---- Elementos ----

  bool _canAdd(String type) {
    if (_layers.length >= _maxLayers) {
      toast(context, tr('Puedes añadir como mucho {max} elementos a un reel.', {'max': _maxLayers}), error: true);
      return false;
    }
    final limit = _limits[type] ?? 1;
    if (_layers.where((l) => l.s.type == type).length >= limit) {
      toast(context, tr('Puedes añadir como mucho {max} de este tipo.', {'max': limit}), error: true);
      return false;
    }
    return true;
  }

  void _add(StoryLayer s) {
    s
      ..x = .5
      ..y = .4 + (_layers.length % 4) * .05;
    final layer = _ReelLayer(s);
    setState(() {
      _layers.add(layer);
      _selected = layer;
      _panel = '';
    });
  }

  void _remove(_ReelLayer layer) {
    setState(() {
      _layers.remove(layer);
      if (_selected == layer) _selected = null;
    });
  }

  Future<void> _addText() async {
    if (!_canAdd('text')) return;
    await _pause();
    if (!mounted) return;
    final r = await editStoryText(context);
    if (r == null || r.text.isEmpty || !mounted) return;
    _add(StoryLayer(type: 'text', text: r.text, color: r.color, style: r.style, font: r.font));
  }

  Future<void> _editText(_ReelLayer layer) async {
    final s = layer.s;
    final r = await editStoryText(context, text: s.text, color: s.color, style: s.style, font: s.font);
    if (r == null || !mounted) return;
    if (r.text.isEmpty) {
      _remove(layer);
      return;
    }
    setState(() {
      s
        ..text = r.text
        ..color = r.color
        ..style = r.style
        ..font = r.font;
    });
  }

  Future<void> _addSticker() async {
    if (!_canAdd('sticker')) return;
    final picked = await pickStorySticker(context, header: (_) => const SizedBox.shrink());
    if (picked is! Gif || !mounted || !_canAdd('sticker')) return;
    _add(StoryLayer(type: 'sticker', gifId: picked.id, url: picked.url, width: picked.width, height: picked.height));
  }

  Future<void> _addEmoji() async {
    if (!_canAdd('emoji')) return;
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EmojiSheet(),
    );
    if (emoji == null || !mounted || !_canAdd('emoji')) return;
    _add(StoryLayer(type: 'emoji', text: emoji));
  }

  void _layerMenu(_ReelLayer layer) {
    actionSheet(context, [
      if (layer.s.type == 'text') SheetAction(tr('Editar texto'), CupertinoIcons.textformat, () => _editText(layer)),
      SheetAction(tr('Duración en el video'), CupertinoIcons.timer, () => _editDuration(layer)),
      SheetAction(tr('Eliminar'), CupertinoIcons.trash, () => _remove(layer), destructive: true),
    ]);
  }

  /// Tramo del video en el que se ve el elemento (al mover un extremo, el video va a ese instante).
  Future<void> _editDuration(_ReelLayer layer) async {
    final total = _durationMs;
    if (total <= 0) return;
    await _pause();
    if (!mounted) return;
    setState(() => _selected = layer);
    final initial = RangeValues(layer.startMs.clamp(0, total).toDouble(), (layer.endMs ?? total).clamp(0, total).toDouble());
    final range = await showModalBottomSheet<RangeValues>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DurationSheet(total: total, initial: initial, onScrub: (ms) => _seek(ms)),
    );
    if (range == null || !mounted) return;
    var start = range.start.round();
    var end = range.end.round();
    if (end - start < 300) {
      end = math.min(total, start + 300);
      start = math.max(0, end - 300);
    }
    setState(() {
      layer
        ..startMs = start
        ..endMs = end >= total - 50 ? null : end;
    });
  }

  bool _visible(_ReelLayer layer) {
    if (_capturing || layer == _selected || layer == _target) return true;
    return _positionMs >= layer.startMs && _positionMs <= (layer.endMs ?? 1 << 31);
  }

  // ---- Gestos (como en el editor de historias) ----

  RenderBox? _boxOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize && box.attached ? box : null;
  }

  _ReelLayer? _hitLayer(Offset global) {
    for (final layer in _layers.reversed) {
      if (!_visible(layer)) continue;
      final box = _boxOf(layer.key);
      if (box == null) continue;
      if ((Offset.zero & box.size).inflate(14 / layer.s.scale).contains(box.globalToLocal(global))) return layer;
    }
    return null;
  }

  static double _snapRotation(double r) {
    final n = math.atan2(math.sin(r), math.cos(r));
    return n.abs() < .06 ? 0 : n;
  }

  bool _nearTrash(Offset global) {
    final box = _boxOf(_trashKey);
    if (box == null) return false;
    return (global - box.localToGlobal(box.size.center(Offset.zero))).distance < 52;
  }

  void _onTap(Offset global) {
    final hit = _hitLayer(global);
    if (hit == null) {
      if (_selected != null || _panel.isNotEmpty) {
        setState(() {
          _selected = null;
          _panel = '';
        });
      } else {
        _togglePlay();
      }
    } else if (hit == _selected) {
      _layerMenu(hit);
    } else {
      setState(() => _selected = hit);
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    final current = _target;
    if (current != null && _layers.contains(current)) {
      _startScale = current.s.scale;
      _startRotation = current.s.rotation;
      return;
    }
    final layer = _hitLayer(d.focalPoint) ?? (d.pointerCount >= 2 ? _selected : null);
    if (layer == null) return;
    _startScale = layer.s.scale;
    _startRotation = layer.s.rotation;
    setState(() {
      _target = layer;
      _selected = layer;
      _layers
        ..remove(layer)
        ..add(layer);
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size size) {
    final layer = _target;
    if (layer == null) return;
    setState(() {
      layer.s
        ..x = (layer.s.x + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0)
        ..y = (layer.s.y + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0);
      if (d.pointerCount >= 2) {
        layer.s
          ..scale = (_startScale * d.scale).clamp(StoryLayer.minScale, StoryLayer.maxScale)
          ..rotation = _snapRotation(_startRotation + d.rotation);
      }
      if (d.pointerCount == 1 && d.focalPointDelta.distance > 0) _dragging = layer;
      _overTrash = _dragging == layer && d.pointerCount == 1 && _nearTrash(d.focalPoint);
    });
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (d.pointerCount > 0) return;
    final layer = _target;
    final trash = _overTrash;
    setState(() {
      _target = null;
      _dragging = null;
      _overTrash = false;
    });
    if (layer != null && trash) _remove(layer);
  }

  // ---- Siguiente ----

  String _signature() => [
        _filter,
        _effect,
        for (final l in _layers)
          '${l.s.type}|${l.s.text}|${l.s.color}|${l.s.style}|${l.s.font}|${l.s.url}|${l.s.x}|${l.s.y}|${l.s.scale}|${l.s.rotation}|${l.startMs}|${l.endMs}',
      ].join('§');

  Future<void> _back() async {
    if (_edited) {
      final ok = await confirm(context, tr('¿Descartar la edición?'), tr('Se quitarán los textos, stickers y efectos que añadiste.'),
          action: tr('Descartar'), destructive: true);
      if (!ok || !mounted) return;
    }
    _draft.filter = _filter;
    Navigator.of(context).pop();
  }

  Future<void> _continue() async {
    if (_next) return;
    setState(() {
      _next = true;
      _selected = null;
      _panel = '';
    });
    await _pause();
    ReelDraft? out;
    if (!_edited) {
      final poster = _poster ?? await VideoTools.poster(_draft.path, _draft.seconds);
      _draft
        ..filter = _filter
        ..poster = poster;
      out = _draft;
    } else {
      out = await _render();
    }
    if (!mounted) return;
    setState(() => _next = false);
    if (out == null) return;
    final post = await push<Post>(context, ComposerScreen(reel: out), fullscreen: true);
    if (!mounted) return;
    if (post != null) {
      Navigator.of(context).pop(post);
    } else {
      await _play();
    }
  }

  /// Graba en el video los textos, emojis, stickers (animados), el efecto y el filtro. «Rejuvenecer» no se graba:
  /// su enfoque suave no es una matriz de color, así que sigue aplicándose al reproducir, como sin edición.
  Future<ReelDraft?> _render() async {
    final v = _v;
    if (v == null) return null;
    final sig = _signature();
    if (_rendered != null && _renderedSig == sig) return _rendered;

    setState(() => _capturing = true);
    await WidgetsBinding.instance.endOfFrame;
    final canvas = _boxOf(_canvasKey)?.size;
    if (canvas == null || canvas.width <= 0 || !mounted) {
      if (mounted) setState(() => _capturing = false);
      return null;
    }
    final outW = math.min(1080.0, v.value.size.width);
    final dir = await renderDir('reel_edit');
    final captured = <_ReelLayer, (String, double)>{};
    try {
      for (final l in _layers) {
        if (l.s.type == 'sticker') continue;
        final ro = l.key.currentContext?.findRenderObject();
        if (ro is! RenderRepaintBoundary || !ro.hasSize) continue;
        final image = await ro.toImage(pixelRatio: (outW / canvas.width * l.s.scale).clamp(1.0, 6.0));
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final path = '${dir.path}/layer_${captured.length}.png';
        await File(path).writeAsBytes(data!.buffer.asUint8List());
        captured[l] = (path, ro.size.width * l.s.scale / canvas.width);
      }
    } catch (_) {
      captured.clear();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
    if (!mounted) {
      dir.delete(recursive: true).ignore();
      return null;
    }

    final label = tr('Aplicando la edición…');
    final status = ValueNotifier<(String, double?)>((label, null));
    final client = http.Client();
    var cancelled = false;
    final close = showRenderProgress(context, status, () {
      cancelled = true;
      client.close();
      TrevixVideo.cancel().ignore();
    });
    try {
      final total = _durationMs;
      final overlays = <VideoOverlay>[];
      for (final l in _layers) {
        if (cancelled) throw const _Cancelled();
        if (l.s.type == 'sticker') {
          status.value = (tr('Preparando los stickers…'), null);
          final (frames, ms) = await _stickerFrames(client, l, dir.path, overlays.length);
          overlays.add(VideoOverlay(frames.first, _keys(l, .35 * l.s.scale, total), frames: frames, frameMs: ms));
        } else {
          final c = captured[l];
          if (c == null) throw const _Failed();
          overlays.add(VideoOverlay(c.$1, _keys(l, c.$2, total)));
        }
      }
      final effect = _effect;
      if (effect != null) {
        final aspect = v.value.aspectRatio > 0 ? v.value.aspectRatio : 9 / 16;
        final (frames, ms) = await reelEffectFrames(effect, Size(540, (540 / aspect).roundToDouble()), dir.path);
        overlays.add(VideoOverlay(frames.first, const [OverlayKey(0, x: .5, y: .5, width: 1)], frames: frames, frameMs: ms));
      }
      if (cancelled) throw const _Cancelled();
      final bake = _filter != null && _filter != 'smooth';
      final output = '${(await getTemporaryDirectory()).path}/reel_edit_${DateTime.now().microsecondsSinceEpoch}.mp4';
      status.value = (label, 0);
      await renderWithProgress(
        VideoRenderJob(
          input: _draft.path,
          output: output,
          colorMatrix: bake ? storyFilterMatrix(_filter) : null,
          overlays: overlays,
          keepAudio: !_draft.songSync,
        ),
        (p) => status.value = (label, p),
      );
      if (cancelled) throw const _Cancelled();
      final poster = await VideoTools.poster(output, _draft.seconds);
      final out = ReelDraft(
        path: output,
        seconds: _draft.seconds,
        poster: poster,
        filter: bake ? null : _filter,
        song: _draft.song,
        songSync: _draft.songSync,
      );
      _rendered = out;
      _renderedSig = sig;
      return out;
    } catch (e) {
      if (!cancelled && e is! _Cancelled && mounted) {
        toast(context, tr('No se pudo aplicar la edición. Revisa tu conexión e inténtalo de nuevo.'), error: true);
      }
      return null;
    } finally {
      close();
      client.close();
      dir.delete(recursive: true).ignore();
    }
  }

  /// Claves de una superposición: fija en su sitio y visible solo en su tramo del video.
  List<OverlayKey> _keys(_ReelLayer l, double width, int total) {
    final rotation = -l.s.rotation * 180 / math.pi;
    OverlayKey at(int ms, double alpha) => OverlayKey(ms, x: l.s.x, y: l.s.y, width: width, rotation: rotation, alpha: alpha);
    final start = l.startMs.clamp(0, total);
    final end = (l.endMs ?? total).clamp(start, total);
    return [
      if (start > 0) ...[at(0, 0), at(start - 1, 0)],
      at(start, 1),
      if (end < total) ...[at(end, 1), at(end + 1, 0)] else at(total, 1),
    ];
  }

  /// Fotogramas del sticker de GIPHY (como mucho 24, de 256 px de ancho) con la duración de cada uno.
  Future<(List<String>, List<int>)> _stickerFrames(http.Client client, _ReelLayer l, String dir, int index) async {
    final res = await client.get(Uri.parse(l.s.url ?? '')).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw const _Failed();
    final codec = await ui.instantiateImageCodec(res.bodyBytes, targetWidth: 256);
    try {
      final count = math.max(1, codec.frameCount);
      final step = (count / 24).ceil();
      final paths = <String>[];
      final ms = <int>[];
      for (var i = 0; i < count; i++) {
        final frame = await codec.getNextFrame();
        final duration = frame.duration.inMilliseconds > 10 ? frame.duration.inMilliseconds : 100;
        if (i % step == 0) {
          final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          final path = '$dir/sticker_${index}_$i.png';
          await File(path).writeAsBytes(data!.buffer.asUint8List());
          paths.add(path);
          ms.add(duration);
        } else {
          ms[ms.length - 1] += duration;
        }
        frame.image.dispose();
      }
      return (paths, ms);
    } finally {
      codec.dispose();
    }
  }

  // ---- Vista ----

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Column(children: [
            SizedBox(height: pad.top + 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                _CircleButton(icon: CupertinoIcons.chevron_back, label: tr('Volver'), onTap: _back),
                const SizedBox(width: 8),
                Expanded(child: _songChip()),
                const SizedBox(width: 48),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Stack(children: [
                Positioned.fill(
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Center(child: _stage())),
                ),
                Positioned(right: 12, top: 4, child: _tools()),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: IgnorePointer(
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _dragging != null ? 1 : 0,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 120),
                          scale: _overTrash ? 1.25 : 1,
                          child: Container(
                            key: _trashKey,
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _overTrash ? Tx.danger : Colors.black.withAlpha(150),
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(CupertinoIcons.trash, color: Colors.white, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: switch (_panel) {
                'filters' => FilterStrip(
                    key: const ValueKey('filters'),
                    value: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    thumb: _poster != null ? FileImage(File(_poster!)) : null,
                  ),
                'effects' => _EffectStrip(
                    key: const ValueKey('effects'),
                    value: _effect,
                    thumb: _poster != null ? FileImage(File(_poster!)) : null,
                    onChanged: (e) => setState(() => _effect = e),
                  ),
                _ => _timeline(),
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GradientButton(label: tr('Siguiente'), loading: _next, onPressed: _v == null ? null : _continue),
            ),
            SizedBox(height: pad.bottom + 10),
          ]),
        ),
      ),
    );
  }

  Widget _songChip() {
    final song = _draft.song;
    if (!_draft.songSync || song == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.music_note_2, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(song.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white)),
          ),
        ]),
      ),
    );
  }

  Widget _stage() {
    final v = _v;
    if (v == null) {
      return _failed
          ? Text(tr('No se pudo reproducir el video'), style: TxDark.body(14, color: Colors.white70))
          : const CupertinoActivityIndicator(color: Colors.white, radius: 14);
    }
    return AspectRatio(
      aspectRatio: v.value.aspectRatio > 0 ? v.value.aspectRatio : 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTap(d.globalPosition),
            onLongPressStart: (d) {
              final layer = _hitLayer(d.globalPosition);
              if (layer != null) _layerMenu(layer);
            },
            onScaleStart: _onScaleStart,
            onScaleUpdate: (d) => _onScaleUpdate(d, size),
            onScaleEnd: _onScaleEnd,
            child: Stack(key: _canvasKey, fit: StackFit.expand, children: [
              filtered(_filter, VideoPlayer(v)),
              if (_effect != null) ReelEffectLayer(key: ValueKey(_effect), effect: _effect!),
              for (final layer in _layers)
                if (_visible(layer))
                  PlacedLayer(
                    key: ObjectKey(layer),
                    layer: layer.s,
                    size: size,
                    child: IgnorePointer(child: _layerView(layer, size.width)),
                  ),
              if (!_playing && _target == null && !_capturing)
                const IgnorePointer(child: Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white70, size: 54))),
            ]),
          );
        }),
      ),
    );
  }

  Widget _layerView(_ReelLayer layer, double w) {
    final s = layer.s;
    final Widget body = s.type == 'emoji'
        ? Text(s.text, style: TextStyle(fontSize: w * .16, height: 1.1))
        : LayerContent(layer: s, w: w);
    Widget content = RepaintBoundary(key: layer.key, child: body);
    if (layer == _selected && !_capturing && _dragging != layer) {
      final inv = 1 / s.scale;
      content = Container(
        padding: EdgeInsets.all(8 * inv),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10 * inv),
          border: Border.all(color: Colors.white.withAlpha(230), width: 1.5 * inv),
        ),
        child: content,
      );
    }
    return Opacity(opacity: _dragging == layer && _overTrash ? .5 : 1, child: content);
  }

  Widget _tools() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _Tool(icon: CupertinoIcons.textformat, label: tr('Texto'), onTap: _addText),
      _Tool(icon: CupertinoIcons.smiley, label: tr('Stickers'), onTap: _addSticker),
      _Tool(icon: CupertinoIcons.heart, label: tr('Emojis'), onTap: _addEmoji),
      _Tool(
        icon: CupertinoIcons.sparkles,
        label: tr('Efectos'),
        active: _panel == 'effects' || _effect != null,
        onTap: () => setState(() => _panel = _panel == 'effects' ? '' : 'effects'),
      ),
      _Tool(
        icon: CupertinoIcons.wand_stars,
        label: tr('Filtros'),
        active: _panel == 'filters' || _filter != null,
        onTap: () => setState(() => _panel = _panel == 'filters' ? '' : 'filters'),
      ),
    ]);
  }

  Widget _timeline() {
    final total = _durationMs;
    final pos = _positionMs.clamp(0, math.max(1, total)).toInt();
    final selected = _selected;
    return SizedBox(
      key: const ValueKey('timeline'),
      height: 86,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (selected != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: GestureDetector(
              onTap: () => _editDuration(selected),
              child: Text(
                tr('Se ve de {from} a {to} · Toca para cambiarlo', {'from': _fmt(selected.startMs), 'to': _fmt(selected.endMs ?? total)}),
                style: TxDark.body(12.5, weight: FontWeight.w600, color: Tx.purple300),
              ),
            ),
          ),
        Row(children: [
          IconButton(
            onPressed: _v == null ? null : _togglePlay,
            icon: Icon(_playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: Colors.white),
            tooltip: _playing ? tr('Pausar') : tr('Reproducir'),
          ),
          Text(_fmt(pos), style: TxDark.body(12.5, color: Colors.white70)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: Tx.purple300,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: pos.toDouble(),
                max: math.max(1, total).toDouble(),
                onChangeStart: (_) => _pause(),
                onChanged: total <= 0 ? null : (value) => _seek(value.round()),
              ),
            ),
          ),
          Text(_fmt(total), style: TxDark.body(12.5, color: Colors.white70)),
          const SizedBox(width: 14),
        ]),
      ]),
    );
  }
}

String _fmt(int ms) {
  final s = (ms / 1000).floor();
  final tenths = ((ms % 1000) / 100).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}.$tenths';
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class _Failed implements Exception {
  const _Failed();
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(30)),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap, this.active = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black54, blurRadius: 6)];
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: SizedBox(
          width: 60,
          child: Column(children: [
            Icon(icon, color: active ? Tx.purple300 : Colors.white, size: 26, shadows: shadow),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TxDark.body(11, weight: FontWeight.w700, color: Colors.white).copyWith(shadows: shadow),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tira de efectos: cada uno sobre la miniatura del video.
class _EffectStrip extends StatelessWidget {
  const _EffectStrip({super.key, required this.value, required this.onChanged, this.thumb});

  final String? value;
  final ValueChanged<String?> onChanged;
  final ImageProvider? thumb;

  @override
  Widget build(BuildContext context) {
    final effects = <String?>[null, ...reelEffectNames.keys];
    final image = thumb;
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: effects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final e = effects[i];
          final selected = e == value;
          return GestureDetector(
            onTap: () => onChanged(e),
            child: SizedBox(
              width: 60,
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(fit: StackFit.expand, children: [
                      if (image != null)
                        Image(image: image, fit: BoxFit.cover)
                      else
                        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF2563EB)]))),
                      if (e != null) CustomPaint(painter: ReelEffectPainter(e, 0)),
                      if (e == null) const Icon(CupertinoIcons.nosign, color: Colors.white, size: 22),
                    ]),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  e == null ? tr('Ninguno') : reelEffectNames[e]!,
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

class _EmojiSheet extends StatelessWidget {
  const _EmojiSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 360 + MediaQuery.paddingOf(context).bottom,
      padding: EdgeInsets.fromLTRB(12, 14, 12, MediaQuery.paddingOf(context).bottom + 8),
      decoration: BoxDecoration(color: TxDark.surface2, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(tr('Emojis'), style: TxDark.display(18, color: Colors.white)),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 8,
            children: [
              for (final e in _emojis)
                GestureDetector(
                  onTap: () => Navigator.pop(context, e),
                  child: Center(child: Text(e, style: const TextStyle(fontSize: 28))),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _DurationSheet extends StatefulWidget {
  const _DurationSheet({required this.total, required this.initial, required this.onScrub});

  final int total;
  final RangeValues initial;
  final ValueChanged<int> onScrub;

  @override
  State<_DurationSheet> createState() => _DurationSheetState();
}

class _DurationSheetState extends State<_DurationSheet> {
  late RangeValues _range = widget.initial;

  @override
  Widget build(BuildContext context) {
    final total = widget.total.toDouble();
    return Container(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.paddingOf(context).bottom + 16),
      decoration: BoxDecoration(color: TxDark.surface2, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Duración en el video'), style: TxDark.display(18, color: Colors.white)),
        const SizedBox(height: 4),
        Text(tr('Elige cuándo aparece y cuándo desaparece.'), style: TxDark.body(13.5, color: Colors.white70)),
        const SizedBox(height: 14),
        RangeSlider(
          values: _range,
          max: total,
          divisions: math.max(1, widget.total ~/ 100),
          activeColor: Tx.purple300,
          inactiveColor: Colors.white24,
          onChanged: (r) {
            final moved = r.start != _range.start ? r.start : r.end;
            setState(() => _range = r);
            widget.onScrub(moved.round());
          },
        ),
        Row(children: [
          Text(_fmt(_range.start.round()), style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white)),
          const Spacer(),
          Text(_fmt(_range.end.round()), style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, RangeValues(0, total)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: TxDark.border),
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(tr('Todo el video')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: GradientButton(label: tr('Listo'), height: 48, onPressed: () => Navigator.pop(context, _range))),
        ]),
      ]),
    );
  }
}
