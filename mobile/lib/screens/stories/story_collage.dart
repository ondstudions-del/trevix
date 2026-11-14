import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/media_gallery.dart';

/// Diseños del collage: rectángulos en fracciones del lienzo 9:16 (izquierda, arriba, ancho, alto).
const collageLayouts = <List<Rect>>[
  [Rect.fromLTWH(0, 0, 1, .5), Rect.fromLTWH(0, .5, 1, .5)],
  [Rect.fromLTWH(0, 0, .5, 1), Rect.fromLTWH(.5, 0, .5, 1)],
  [Rect.fromLTWH(0, 0, 1, 1 / 3), Rect.fromLTWH(0, 1 / 3, 1, 1 / 3), Rect.fromLTWH(0, 2 / 3, 1, 1 / 3)],
  [Rect.fromLTWH(0, 0, 1, .6), Rect.fromLTWH(0, .6, .5, .4), Rect.fromLTWH(.5, .6, .5, .4)],
  [Rect.fromLTWH(0, 0, .5, 1), Rect.fromLTWH(.5, 0, .5, .5), Rect.fromLTWH(.5, .5, .5, .5)],
  [Rect.fromLTWH(0, 0, .5, .5), Rect.fromLTWH(.5, 0, .5, .5), Rect.fromLTWH(0, .5, .5, .5), Rect.fromLTWH(.5, .5, .5, .5)],
  [Rect.fromLTWH(0, 0, 1, .5), Rect.fromLTWH(0, .5, 1 / 3, .5), Rect.fromLTWH(1 / 3, .5, 1 / 3, .5), Rect.fromLTWH(2 / 3, .5, 1 / 3, .5)],
  [
    Rect.fromLTWH(0, 0, .5, 1 / 3), Rect.fromLTWH(.5, 0, .5, 1 / 3), Rect.fromLTWH(0, 1 / 3, 1, 1 / 3),
    Rect.fromLTWH(0, 2 / 3, .5, 1 / 3), Rect.fromLTWH(.5, 2 / 3, .5, 1 / 3),
  ],
  [
    Rect.fromLTWH(0, 0, .5, 1 / 3), Rect.fromLTWH(.5, 0, .5, 1 / 3), Rect.fromLTWH(0, 1 / 3, .5, 1 / 3),
    Rect.fromLTWH(.5, 1 / 3, .5, 1 / 3), Rect.fromLTWH(0, 2 / 3, .5, 1 / 3), Rect.fromLTWH(.5, 2 / 3, .5, 1 / 3),
  ],
];

const _maxPhotos = 6;

/// Bordes: separación (en fracción del ancho) y color.
const _borders = <(double, Color)>[(0, Colors.black), (.008, Colors.white), (.02, Colors.white), (.012, Colors.black)];

/// Encuadre de una foto dentro de su casilla: acercamiento y desplazamiento (−1 a 1 de lo que sobra por lado).
class _Frame {
  double zoom = 1;
  Offset shift = Offset.zero;
}

/// Historia en collage: se eligen de 2 a 6 fotos de la galería, un diseño, bordes y esquinas; cada foto se cambia
/// o se quita tocándola y se encuadra arrastrando y pellizcando. «Siguiente» la convierte en una sola imagen
/// 1080×1920 que sigue en el editor de historias (textos, stickers, música y filtros) como cualquier foto.
class StoryCollageScreen extends StatefulWidget {
  const StoryCollageScreen({super.key});

  @override
  State<StoryCollageScreen> createState() => _StoryCollageScreenState();
}

class _StoryCollageScreenState extends State<StoryCollageScreen> {
  final List<String?> _photos = List.filled(_maxPhotos, null);
  final List<_Frame> _frames = List.generate(_maxPhotos, (_) => _Frame());
  final Map<String, Size> _sizes = {};
  final _canvas = GlobalKey();
  int _layout = 5;
  int _border = 1;
  bool _rounded = false;
  int? _active;
  bool _exporting = false;
  double _startZoom = 1;

  List<Rect> get _cells => collageLayouts[_layout];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _addPhotos(initial: true));
  }

  ImageProvider _provider(String path) => ResizeImage(FileImage(File(path)), width: 1440, height: 1440, policy: ResizeImagePolicy.fit);

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

  void _put(int index, String path) {
    _photos[index] = path;
    _frames[index] = _Frame();
    _measure(path);
  }

  /// Galería del teléfono (solo fotos) en una hoja; con [many] se eligen varias de una vez.
  Future<List<String>?> _openGallery({int? many}) {
    return showModalBottomSheet<List<String>>(
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
              Expanded(child: Text(many != null ? tr('Elige las fotos del collage') : tr('Elige una foto'), style: TxDark.display(18))),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(CupertinoIcons.xmark, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: PhoneGallery(
              photosOnly: true,
              maxSelect: many,
              onPickMany: many == null ? null : (picks) => Navigator.pop(ctx, [for (final p in picks) p.path]),
              onPick: (p) => Navigator.pop(ctx, [p.path]),
            ),
          ),
        ]),
      ),
    );
  }

  /// Llena los espacios vacíos; si es el comienzo, elige el diseño según cuántas fotos se tomaron.
  Future<void> _addPhotos({bool initial = false}) async {
    final empty = [for (var i = 0; i < _maxPhotos; i++) if (_photos[i] == null) i];
    final room = initial ? _maxPhotos : _cells.length - _photos.take(_cells.length).whereType<String>().length;
    if (room <= 0) {
      toast(context, tr('El collage está completo. Toca una foto para cambiarla o quitarla, o elige otro diseño.'));
      return;
    }
    final paths = await _openGallery(many: room);
    if (!mounted) return;
    if (paths == null || paths.isEmpty) {
      if (initial) Navigator.pop(context);
      return;
    }
    setState(() {
      if (initial) {
        final fit = collageLayouts.indexWhere((l) => l.length == math.max(2, paths.length));
        if (fit >= 0) _layout = fit;
      }
      final visible = empty.where((i) => i < _cells.length).toList();
      for (var k = 0; k < paths.length && k < visible.length; k++) {
        _put(visible[k], paths[k]);
      }
    });
  }

  Future<void> _replace(int index) async {
    final paths = await _openGallery();
    if (!mounted || paths == null || paths.isEmpty) return;
    setState(() {
      _put(index, paths.first);
      _active = null;
    });
  }

  void _removeAt(int index) => setState(() {
        _photos[index] = null;
        _frames[index] = _Frame();
        _active = null;
      });

  void _onCellTap(int index) {
    if (_photos[index] == null) {
      _replace(index);
      return;
    }
    if (_active != index) {
      setState(() => _active = index);
      return;
    }
    actionSheet(context, [
      SheetAction(tr('Cambiar foto'), CupertinoIcons.photo, () => _replace(index)),
      SheetAction(tr('Volver a encuadrar'), CupertinoIcons.arrow_counterclockwise, () => setState(() => _frames[index] = _Frame())),
      SheetAction(tr('Quitar foto'), CupertinoIcons.trash, () => _removeAt(index), destructive: true),
    ]);
  }

  /// Lo que sobra de la foto por cada lado de la casilla con su acercamiento (para limitar el arrastre).
  Offset _overflow(int index, Size cell) {
    final size = _sizes[_photos[index]];
    if (size == null) return Offset.zero;
    final scale = math.max(cell.width / size.width, cell.height / size.height) * _frames[index].zoom;
    return Offset((size.width * scale - cell.width) / 2, (size.height * scale - cell.height) / 2);
  }

  Future<void> _next() async {
    final visible = _photos.take(_cells.length).toList();
    if (visible.whereType<String>().length < 2) {
      toast(context, tr('Elige al menos 2 fotos para el collage.'), error: true);
      return;
    }
    if (visible.contains(null)) {
      toast(context, tr('Completa todos los espacios del collage o elige otro diseño.'), error: true);
      return;
    }
    setState(() {
      _active = null;
      _exporting = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _canvas.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw Exception('png');
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png');
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (mounted) Navigator.pop(context, out.path);
    } catch (_) {
      if (mounted) {
        setState(() => _exporting = false);
        toast(context, tr('No se pudo preparar el collage.'), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
            child: Row(children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 24)),
              const Spacer(),
              Text(tr('Collage'), style: TxDark.display(18)),
              const Spacer(),
              SizedBox(
                width: 120,
                child: GradientButton(label: tr('Siguiente'), loading: _exporting, onPressed: _next, height: 40),
              ),
            ]),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: AspectRatio(aspectRatio: 9 / 16, child: RepaintBoundary(key: _canvas, child: _collage())),
              ),
            ),
          ),
          _tools(),
        ]),
      ),
    );
  }

  Widget _collage() {
    final (gapFraction, gapColor) = _borders[_border];
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final gap = gapFraction * w;
      final radius = _rounded ? w * .04 : 0.0;
      return ColoredBox(
        color: gapColor,
        child: Stack(children: [
          for (var i = 0; i < _cells.length; i++)
            Builder(builder: (context) {
              final r = _cells[i];
              final left = r.left * w + (r.left == 0 ? gap : gap / 2);
              final top = r.top * h + (r.top == 0 ? gap : gap / 2);
              final right = r.right * w - (r.right >= .999 ? gap : gap / 2);
              final bottom = r.bottom * h - (r.bottom >= .999 ? gap : gap / 2);
              final cell = Size(math.max(0, right - left), math.max(0, bottom - top));
              return Positioned(left: left, top: top, width: cell.width, height: cell.height, child: _cell(i, cell, radius));
            }),
        ]),
      );
    });
  }

  Widget _cell(int index, Size cell, double radius) {
    final path = _photos[index];
    final frame = _frames[index];
    final size = path == null ? null : _sizes[path];
    Widget content;
    if (path == null) {
      content = _exporting
          ? const ColoredBox(color: Colors.black)
          : Container(
              color: TxDark.surface3,
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(CupertinoIcons.plus_circle, color: Colors.white70, size: 30),
                const SizedBox(height: 6),
                Text(tr('Añadir foto'), style: TxDark.body(12.5, weight: FontWeight.w600, color: Colors.white70)),
              ]),
            );
    } else if (size == null) {
      content = Image(image: _provider(path), fit: BoxFit.cover, width: cell.width, height: cell.height);
    } else {
      final scale = math.max(cell.width / size.width, cell.height / size.height) * frame.zoom;
      final dw = size.width * scale, dh = size.height * scale;
      final over = _overflow(index, cell);
      content = Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: (cell.width - dw) / 2 + frame.shift.dx * over.dx,
          top: (cell.height - dh) / 2 + frame.shift.dy * over.dy,
          width: dw,
          height: dh,
          child: Image(image: _provider(path), fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
        ),
      ]);
    }
    final active = _active == index && !_exporting;
    return GestureDetector(
      onTap: () => _onCellTap(index),
      onScaleStart: path == null
          ? null
          : (_) {
              _startZoom = frame.zoom;
              if (_active != index) setState(() => _active = index);
            },
      onScaleUpdate: path == null
          ? null
          : (d) => setState(() {
                frame.zoom = (_startZoom * d.scale).clamp(1.0, 4.0);
                final over = _overflow(index, cell);
                frame.shift = Offset(
                  over.dx <= 0 ? 0 : (frame.shift.dx + d.focalPointDelta.dx / over.dx).clamp(-1.0, 1.0),
                  over.dy <= 0 ? 0 : (frame.shift.dy + d.focalPointDelta.dy / over.dy).clamp(-1.0, 1.0),
                );
              }),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(fit: StackFit.expand, children: [
          content,
          if (active)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Tx.purple400, width: 3),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tools() {
    Widget tool(IconData icon, String label, VoidCallback onTap, {bool active = false}) => GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: active ? Tx.purple300 : Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(label, style: TxDark.body(11.5, weight: FontWeight.w600, color: active ? Tx.purple300 : Colors.white)),
            ]),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_active != null && _photos[_active!] != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(tr('Arrastra o pellizca para encuadrar. Toca otra vez para cambiarla o quitarla.'),
              textAlign: TextAlign.center, style: TxDark.body(12, color: Colors.white70)),
        ),
      SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (var i = 0; i < collageLayouts.length; i++)
              GestureDetector(
                onTap: () => setState(() {
                  _layout = i;
                  if (_active != null && _active! >= _cells.length) _active = null;
                }),
                child: Container(
                  width: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: i == _layout ? Tx.purple400 : Colors.white38, width: i == _layout ? 2.5 : 1.2),
                  ),
                  child: LayoutBuilder(builder: (context, box) {
                    return Stack(children: [
                      for (final r in collageLayouts[i])
                        Positioned(
                          left: r.left * box.maxWidth + 1.5,
                          top: r.top * box.maxHeight + 1.5,
                          width: r.width * box.maxWidth - 3,
                          height: r.height * box.maxHeight - 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: i == _layout ? Tx.purple400.withAlpha(150) : Colors.white24, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                    ]);
                  }),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          tool(CupertinoIcons.photo_on_rectangle, tr('Fotos'), () => _addPhotos()),
          tool(CupertinoIcons.square, tr('Bordes'), () => setState(() => _border = (_border + 1) % _borders.length), active: _border != 0),
          tool(CupertinoIcons.app, tr('Esquinas'), () => setState(() => _rounded = !_rounded), active: _rounded),
        ]),
      ),
    ]);
  }
}
