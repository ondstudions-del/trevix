import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/emoji_picker.dart';
import '../../widgets/gif_picker.dart';

/// Foto lista para enviar: [viewSeconds] null = normal, 0 = una vez, 3/5/10 = segundos.
class EditedPhoto {
  EditedPhoto(this.path, this.viewSeconds, this.caption);

  final String path;
  final int? viewSeconds;
  final String caption;
}

/// Abre el editor antes de enviar una foto al chat.
Future<EditedPhoto?> editPhoto(BuildContext context, String path, {List<int> viewSeconds = const [0, 3, 5, 10], bool stickers = true}) =>
    push<EditedPhoto>(context, PhotoEditorScreen(path: path, viewSeconds: viewSeconds, stickers: stickers), fullscreen: true);

const _fonts = <(String, String)>[
  ('Inter', 'Clásica'),
  ('Bebas Neue', 'Fuerte'),
  ('Pacifico', 'Script'),
  ('Playfair Display', 'Elegante'),
  ('Permanent Marker', 'Marcador'),
  ('Caveat', 'A mano'),
  ('Lobster', 'Retro'),
  ('Courier Prime', 'Máquina'),
];

const _colors = <Color>[
  Colors.white,
  Colors.black,
  Color(0xFFF43F5E),
  Color(0xFFF97316),
  Color(0xFFFACC15),
  Color(0xFF22C55E),
  Color(0xFF22D3EE),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

TextStyle _font(String family, double size, Color color) {
  try {
    return GoogleFonts.getFont(family, fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1.15);
  } catch (_) {
    return TextStyle(fontSize: size, color: color, fontWeight: FontWeight.w700, height: 1.15);
  }
}

class _Layer {
  _Layer.text(this.text, this.font, this.color, this.box) : kind = 'text', gif = null;
  _Layer.emoji(this.text) : kind = 'emoji', font = '', color = Colors.white, box = false, gif = null;
  _Layer.sticker(Gif this.gif) : kind = 'sticker', text = '', font = '', color = Colors.white, box = false;

  final String kind;
  String text;
  String font;
  Color color;
  bool box;
  final Gif? gif;
  Offset pos = const Offset(.5, .45);
  double scale = 1;
  double rotation = 0;
}

class _Stroke {
  _Stroke(this.color, this.width);

  final Color color;
  final double width;
  final List<Offset> points = [];
}

enum _Mode { idle, draw, text }

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.path, this.viewSeconds = const [0, 3, 5, 10], this.stickers = true});

  final String path;
  final List<int> viewSeconds;
  final bool stickers;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _boundary = GlobalKey();
  final _caption = TextEditingController();
  final List<_Layer> _layers = [];
  final List<_Stroke> _strokes = [];
  Size? _imageSize;
  _Mode _mode = _Mode.idle;
  Color _brush = const Color(0xFFF43F5E);
  double _brushWidth = .012;
  int? _view;
  bool _exporting = false;

  _Layer? _dragging;
  bool _overTrash = false;
  double _baseScale = 1;
  double _baseRotation = 0;

  final _textInput = TextEditingController();
  _Layer? _editing;
  String _textFont = _fonts.first.$1;
  Color _textColor = Colors.white;
  bool _textBox = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  @override
  void dispose() {
    _caption.dispose();
    _textInput.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    try {
      final image = await decodeImageFromList(await File(widget.path).readAsBytes());
      if (mounted) setState(() => _imageSize = Size(image.width.toDouble(), image.height.toDouble()));
      image.dispose();
    } catch (_) {
      if (mounted) setState(() => _imageSize = const Size(1, 1));
    }
  }

  bool get _edited => _layers.isNotEmpty || _strokes.isNotEmpty;

  // ---- Texto ----

  void _openText([_Layer? layer]) {
    setState(() {
      _editing = layer;
      _textInput.text = layer?.text ?? '';
      _textFont = layer?.font ?? _textFont;
      _textColor = layer?.color ?? _textColor;
      _textBox = layer?.box ?? _textBox;
      _mode = _Mode.text;
    });
  }

  void _closeText() {
    final text = _textInput.text.trim();
    setState(() {
      final layer = _editing;
      if (layer != null) {
        if (text.isEmpty) {
          _layers.remove(layer);
        } else {
          layer
            ..text = text
            ..font = _textFont
            ..color = _textColor
            ..box = _textBox;
        }
      } else if (text.isNotEmpty) {
        _layers.add(_Layer.text(text, _textFont, _textColor, _textBox));
      }
      _editing = null;
      _mode = _Mode.idle;
    });
  }

  // ---- Emoji y stickers ----

  Future<void> _addEmoji() async {
    final emoji = await pickEmoji(context, dark: true);
    if (emoji != null && mounted) setState(() => _layers.add(_Layer.emoji(emoji)));
  }

  Future<void> _addSticker() async {
    final gif = await pickGif(context, kind: 'sticker');
    if (gif != null && mounted) setState(() => _layers.add(_Layer.sticker(gif)));
  }

  // ---- Exportar ----

  Future<void> _send() async {
    if (_exporting) return;
    var path = widget.path;
    if (_edited) {
      setState(() => _exporting = true);
      try {
        final boundary = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final natural = _imageSize ?? boundary.size;
        final longSide = math.min(1600.0, math.max(natural.width, natural.height));
        final ratio = longSide / math.max(boundary.size.width, boundary.size.height);
        final image = await boundary.toImage(pixelRatio: ratio);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw Exception('png');
        final dir = await getTemporaryDirectory();
        final out = File('${dir.path}/foto_${DateTime.now().millisecondsSinceEpoch}.png');
        await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
        path = out.path;
      } catch (_) {
        if (mounted) {
          setState(() => _exporting = false);
          toast(context, 'No se pudo preparar la foto editada.', error: true);
        }
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(EditedPhoto(path, _view, _caption.text.trim()));
  }

  // ---- Interfaz ----

  Widget _layerView(_Layer l) {
    switch (l.kind) {
      case 'emoji':
        return Text(l.text, style: const TextStyle(fontSize: 64));
      case 'sticker':
        final g = l.gif!;
        return SizedBox(width: 140, height: 140 / g.aspect, child: Image.network(g.url, fit: BoxFit.contain, gaplessPlayback: true));
      default:
        final style = _font(l.font, 30, l.box ? (l.color == Colors.white ? Colors.black : Colors.white) : l.color);
        final text = Text(l.text, textAlign: TextAlign.center, style: l.box ? style : style.copyWith(shadows: const [Shadow(blurRadius: 6, color: Colors.black45)]));
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: l.box
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(10)),
                  child: text,
                )
              : text,
        );
    }
  }

  Widget _canvas(Size size) {
    return RepaintBoundary(
      key: _boundary,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned.fill(child: Image.file(File(widget.path), fit: BoxFit.cover)),
          Positioned.fill(child: CustomPaint(painter: _StrokesPainter(_strokes))),
          for (final l in _layers)
            Positioned(
              left: l.pos.dx * size.width,
              top: l.pos.dy * size.height,
              child: FractionalTranslation(
                translation: const Offset(-.5, -.5),
                child: IgnorePointer(
                  ignoring: _mode != _Mode.idle,
                  child: GestureDetector(
                    onTap: l.kind == 'text' ? () => _openText(l) : null,
                    onScaleStart: (_) {
                      _baseScale = l.scale;
                      _baseRotation = l.rotation;
                      setState(() => _dragging = l);
                    },
                    onScaleUpdate: (d) {
                      setState(() {
                        l.pos = Offset(
                          (l.pos.dx + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0),
                          (l.pos.dy + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0),
                        );
                        l.scale = (_baseScale * d.scale).clamp(.3, 6.0);
                        l.rotation = _baseRotation + d.rotation;
                        _overTrash = l.pos.dy > .86 && (l.pos.dx - .5).abs() < .18;
                      });
                    },
                    onScaleEnd: (_) {
                      setState(() {
                        if (_overTrash) {
                          _layers.remove(l);
                          HapticFeedback.mediumImpact();
                        }
                        _dragging = null;
                        _overTrash = false;
                      });
                    },
                    child: Transform.rotate(
                      angle: l.rotation,
                      child: Transform.scale(scale: l.scale, child: _layerView(l)),
                    ),
                  ),
                ),
              ),
            ),
          if (_mode == _Mode.draw)
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (d) => setState(() {
                  _strokes.add(_Stroke(_brush, _brushWidth)..points.add(Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height)));
                }),
                onPanUpdate: (d) => setState(() {
                  _strokes.last.points.add(Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height));
                }),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _tool(IconData icon, String tooltip, VoidCallback onTap, {bool active = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: active ? Colors.white : Colors.black.withAlpha(110),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: tooltip,
              child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 21, color: active ? Colors.black : Colors.white)),
            ),
          ),
        ),
      );

  Widget _colorRow(Color selected, ValueChanged<Color> onPick) => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          children: [
            for (final c in _colors)
              GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: c == selected ? 3 : 1.5),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _topBar() {
    if (_mode == _Mode.draw) {
      return Row(children: [
        _tool(CupertinoIcons.arrow_uturn_left, 'Deshacer', () {
          if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
        }),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _mode = _Mode.idle),
          child: Text('Listo', style: Tx.body(16, weight: FontWeight.w700, color: Colors.white)),
        ),
      ]);
    }
    return Row(children: [
      _tool(CupertinoIcons.xmark, 'Cerrar', () => Navigator.of(context).pop()),
      const Spacer(),
      _tool(CupertinoIcons.textformat, 'Texto', () => _openText()),
      _tool(CupertinoIcons.scribble, 'Dibujar', () => setState(() => _mode = _Mode.draw)),
      _tool(CupertinoIcons.smiley, 'Emoji', _addEmoji),
      if (widget.stickers) _tool(CupertinoIcons.sparkles, 'Stickers', _addSticker),
    ]);
  }

  Widget _bottomBar() {
    if (_mode == _Mode.draw) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const SizedBox(width: 16),
          const Icon(CupertinoIcons.circle_fill, size: 8, color: Colors.white70),
          Expanded(
            child: Slider(
              value: _brushWidth,
              min: .004,
              max: .04,
              activeColor: Colors.white,
              inactiveColor: Colors.white24,
              onChanged: (v) => setState(() => _brushWidth = v),
            ),
          ),
          const Icon(CupertinoIcons.circle_fill, size: 20, color: Colors.white70),
          const SizedBox(width: 16),
        ]),
        _colorRow(_brush, (c) => setState(() => _brush = c)),
        const SizedBox(height: 8),
      ]);
    }
    final options = <int?>[null, ...widget.viewSeconds];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (final o in options)
              ViewChip(
                label: o == null ? 'Normal' : (o == 0 ? '1 vez' : '$o s'),
                icon: o == null ? null : (o == 0 ? CupertinoIcons.eye : CupertinoIcons.timer),
                selected: _view == o,
                onTap: () => setState(() => _view = o),
              ),
          ],
        ),
      ),
      if (_view != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Text(
            _view == 0 ? 'Se podrá abrir una sola vez.' : 'Se podrá abrir una vez durante $_view segundos.',
            style: Tx.body(12.5, color: Colors.white70),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _caption,
              enabled: _view == null,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              style: Tx.body(15, color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                counterText: '',
                hintText: _view == null ? 'Añade un comentario…' : 'Sin comentario en fotos de una vez',
                hintStyle: Tx.body(15, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withAlpha(30),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              child: _exporting
                  ? const Center(child: CupertinoActivityIndicator(color: Colors.white))
                  : const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 22),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _textEditor() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withAlpha(170),
        child: SafeArea(
          child: Column(children: [
            Row(children: [
              const SizedBox(width: 8),
              _tool(_textBox ? CupertinoIcons.textbox : CupertinoIcons.text_cursor, 'Fondo del texto', () => setState(() => _textBox = !_textBox),
                  active: _textBox),
              const Spacer(),
              TextButton(
                onPressed: _closeText,
                child: Text('Listo', style: Tx.body(16, weight: FontWeight.w700, color: Colors.white)),
              ),
            ]),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: _textBox ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6) : EdgeInsets.zero,
                    decoration: _textBox ? BoxDecoration(color: _textColor, borderRadius: BorderRadius.circular(10)) : null,
                    child: IntrinsicWidth(
                      child: TextField(
                        controller: _textInput,
                        autofocus: true,
                        maxLines: null,
                        maxLength: 200,
                        textAlign: TextAlign.center,
                        cursorColor: Colors.white,
                        style: _font(_textFont, 30, _textBox ? (_textColor == Colors.white ? Colors.black : Colors.white) : _textColor),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          isCollapsed: true,
                          hintText: 'Escribe…',
                          hintStyle: _font(_textFont, 30, Colors.white54),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in _fonts)
                    GestureDetector(
                      onTap: () => setState(() => _textFont = f.$1),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _textFont == f.$1 ? Colors.white : Colors.white.withAlpha(30),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(f.$2, style: _font(f.$1, 15, _textFont == f.$1 ? Colors.black : Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            _colorRow(_textColor, (c) => setState(() => _textColor = c)),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final natural = _imageSize;
    return TxDark.scope(
      context,
      AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: _mode != _Mode.text,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: _topBar()),
              Expanded(
                child: natural == null
                    ? const Center(child: CupertinoActivityIndicator(color: Colors.white))
                    : LayoutBuilder(builder: (context, box) {
                        final aspect = natural.width / natural.height;
                        var w = box.maxWidth;
                        var h = w / aspect;
                        if (h > box.maxHeight) {
                          h = box.maxHeight;
                          w = h * aspect;
                        }
                        return Center(
                          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: _canvas(Size(w, h))),
                        );
                      }),
              ),
              if (_dragging != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: _overTrash ? 60 : 48,
                    height: _overTrash ? 60 : 48,
                    decoration: BoxDecoration(color: _overTrash ? Tx.danger : Colors.black54, shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.trash, color: Colors.white),
                  ),
                )
              else
                _bottomBar(),
            ]),
          ),
          if (_mode == _Mode.text) _textEditor(),
        ]),
      ),
      ),
    );
  }
}

/// Opción de visualización (Normal, 1 vez, 3/5/10 s) sobre fondo oscuro. Colores fijos: el tema claro de la app no
/// debe pintarla de blanco.
class ViewChip extends StatelessWidget {
  const ViewChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.black : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Colors.white : const Color(0xFF4A4A50)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 6)],
            Text(label, style: TxDark.body(13.5, weight: FontWeight.w600, color: fg)),
          ]),
        ),
      ),
    );
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.strokes);

  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        final p = Offset(s.points.first.dx * size.width, s.points.first.dy * size.height);
        canvas.drawCircle(p, paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path();
      for (var i = 0; i < s.points.length; i++) {
        final p = Offset(s.points[i].dx * size.width, s.points[i].dy * size.height);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => true;
}
