import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'i18n.dart';

/// Efectos del editor de reels: se dibujan encima de todo el video. Los mismos trazos sirven para la vista previa
/// ([ReelEffectPainter]) y para los fotogramas PNG que se graban en el video ([reelEffectFrames]), así el reel
/// publicado queda igual que en el editor. Los animados se repiten en bucle desde el inicio del video.
Map<String, String> get reelEffectNames => {
      'vignette': tr('Viñeta'),
      'cinema': tr('Cine'),
      'vhs': tr('VHS'),
      'grain': tr('Grano'),
      'sparkle': tr('Destellos'),
      'hearts': tr('Corazones'),
      'leak': tr('Luz cálida'),
      'frame': tr('Marco'),
    };

/// Número de fotogramas del efecto (1 = estático) y duración de cada uno en ms.
int reelEffectFrameCount(String key) => switch (key) { 'grain' => 4, 'vhs' => 2, 'sparkle' => 8, 'hearts' => 12, _ => 1 };

int reelEffectFrameMs(String key) => switch (key) { 'grain' => 90, 'vhs' => 600, 'sparkle' => 150, 'hearts' => 140, _ => 1000 };

class ReelEffectPainter extends CustomPainter {
  const ReelEffectPainter(this.effect, this.frame);

  final String effect;
  final int frame;

  @override
  void paint(Canvas canvas, Size size) => paintReelEffect(canvas, size, effect, frame);

  @override
  bool shouldRepaint(ReelEffectPainter old) => old.effect != effect || old.frame != frame;
}

/// Vista previa animada del efecto sobre el video (el fotograma avanza con el tiempo, como en el video final).
class ReelEffectLayer extends StatefulWidget {
  const ReelEffectLayer({super.key, required this.effect});

  final String effect;

  @override
  State<ReelEffectLayer> createState() => _ReelEffectLayerState();
}

class _ReelEffectLayerState extends State<ReelEffectLayer> with SingleTickerProviderStateMixin {
  late final _ticker = createTicker((elapsed) {
    final count = reelEffectFrameCount(widget.effect);
    final frame = count < 2 ? 0 : (elapsed.inMilliseconds ~/ reelEffectFrameMs(widget.effect)) % count;
    if (frame != _frame) setState(() => _frame = frame);
  });
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: ReelEffectPainter(widget.effect, _frame), size: Size.infinite)));
  }
}

/// Fotogramas del efecto como PNG transparentes de [size] en [dir]. Devuelve las rutas y la duración de cada uno.
Future<(List<String>, List<int>)> reelEffectFrames(String effect, Size size, String dir) async {
  final count = reelEffectFrameCount(effect);
  final paths = <String>[];
  for (var i = 0; i < count; i++) {
    final recorder = ui.PictureRecorder();
    paintReelEffect(Canvas(recorder), size, effect, i);
    final image = await recorder.endRecording().toImage(size.width.round(), size.height.round());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final path = '$dir/effect_$i.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    paths.add(path);
  }
  return (paths, List<int>.filled(count, reelEffectFrameMs(effect)));
}

void paintReelEffect(Canvas c, Size s, String effect, int frame) {
  final u = s.shortestSide;
  final full = Offset.zero & s;
  switch (effect) {
    case 'vignette':
      c.drawRect(
        full,
        Paint()
          ..shader = const RadialGradient(radius: 1.05, colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)], stops: [0, .5, 1])
              .createShader(full),
      );
    case 'cinema':
      final bar = s.height * .11;
      final paint = Paint()..color = Colors.black;
      c.drawRect(Rect.fromLTWH(0, 0, s.width, bar), paint);
      c.drawRect(Rect.fromLTWH(0, s.height - bar, s.width, bar), paint);
    case 'vhs':
      _vhs(c, s, u, frame);
    case 'grain':
      _grain(c, s, u, frame);
    case 'sparkle':
      _sparkles(c, s, u, frame);
    case 'hearts':
      _hearts(c, s, u, frame);
    case 'leak':
      c.drawRect(
        full,
        Paint()
          ..shader = const RadialGradient(center: Alignment(-1, -1), radius: 1.3, colors: [Color(0x80FF8A3D), Color(0x33FFB86B), Color(0x00FFB86B)], stops: [0, .45, 1])
              .createShader(full),
      );
      c.drawRect(
        full,
        Paint()
          ..shader = const RadialGradient(center: Alignment(1, 1), radius: 1.1, colors: [Color(0x55F43F5E), Color(0x00F43F5E)]).createShader(full),
      );
    case 'frame':
      final inset = u * .035;
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(full)
        ..addRRect(RRect.fromRectAndRadius(full.deflate(inset), Radius.circular(u * .05)));
      c.drawPath(path, Paint()..color = Colors.white);
  }
}

void _vhs(Canvas c, Size s, double u, int frame) {
  final line = Paint()..color = const Color(0x22000000);
  final step = max(3.0, u / 160);
  for (var y = 0.0; y < s.height; y += step * 2) {
    c.drawRect(Rect.fromLTWH(0, y, s.width, step), line);
  }
  c.drawRect(Offset.zero & s, Paint()..color = const Color(0x0DFF00AA));
  final mono = TextStyle(
    color: Colors.white,
    fontSize: u * .055,
    fontWeight: FontWeight.w700,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier', 'Courier New'],
    letterSpacing: u * .004,
    shadows: [Shadow(color: const Color(0xCC22D3EE), offset: Offset(-u * .004, 0)), Shadow(color: const Color(0xCCF43F5E), offset: Offset(u * .004, 0))],
  );
  final pad = u * .06;
  _label(c, 'PLAY ▶', mono, Offset(pad, pad));
  if (frame == 0) c.drawCircle(Offset(s.width - pad - u * .17, pad + u * .033), u * .022, Paint()..color = const Color(0xFFEF4444));
  _label(c, 'REC', mono, Offset(s.width - pad - u * .13, pad));
  final now = DateTime.now();
  const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  final date = '${months[now.month - 1]}. ${now.day.toString().padLeft(2, '0')} ${now.year}';
  _label(c, date, mono, Offset(pad, s.height - pad - u * .07));
}

void _label(Canvas c, String text, TextStyle style, Offset at) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
  tp.paint(c, at);
}

void _grain(Canvas c, Size s, double u, int frame) {
  final r = Random(frame * 7919 + 13);
  final n = (s.width * s.height / 840).clamp(200, 7000).round() * 2;
  final light = Float32List(n);
  final dark = Float32List(n);
  for (var i = 0; i < n; i += 2) {
    light[i] = r.nextDouble() * s.width;
    light[i + 1] = r.nextDouble() * s.height;
    dark[i] = r.nextDouble() * s.width;
    dark[i + 1] = r.nextDouble() * s.height;
  }
  final w = max(1.0, u / 300);
  c.drawRawPoints(ui.PointMode.points, light, Paint()..color = const Color(0x40FFFFFF)..strokeWidth = w);
  c.drawRawPoints(ui.PointMode.points, dark, Paint()..color = const Color(0x40000000)..strokeWidth = w);
  c.drawRect(Offset.zero & s, Paint()..color = const Color(0x0A6B4F2A));
}

void _sparkles(Canvas c, Size s, double u, int frame) {
  final r = Random(42);
  const count = 16;
  for (var i = 0; i < count; i++) {
    final at = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height);
    final phase = r.nextDouble();
    final size = u * (.025 + r.nextDouble() * .03);
    final t = (sin((frame / reelEffectFrameCount('sparkle') + phase) * 2 * pi) + 1) / 2;
    if (t < .08) continue;
    final k = size * (.4 + .6 * t);
    final star = Path()
      ..moveTo(at.dx, at.dy - k)
      ..quadraticBezierTo(at.dx, at.dy, at.dx + k, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + k)
      ..quadraticBezierTo(at.dx, at.dy, at.dx - k, at.dy)
      ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - k)
      ..close();
    final alpha = (t * 255).round();
    c.drawCircle(at, k * .9, Paint()..color = Color.fromARGB((alpha * .35).round(), 255, 255, 255)..maskFilter = MaskFilter.blur(BlurStyle.normal, k * .6));
    c.drawPath(star, Paint()..color = Color.fromARGB(alpha, 255, 255, 255));
  }
}

void _hearts(Canvas c, Size s, double u, int frame) {
  final r = Random(7);
  const count = 11;
  const colors = [Color(0xFFF43F5E), Color(0xFFEC4899), Color(0xFFF9A8D4), Color(0xFFFB7185)];
  final frames = reelEffectFrameCount('hearts');
  for (var i = 0; i < count; i++) {
    final phase = r.nextDouble();
    final x0 = r.nextDouble();
    final size = u * (.05 + r.nextDouble() * .05);
    final color = colors[i % colors.length];
    final p = (frame / frames + phase) % 1;
    final y = s.height * (1.04 - p * .62);
    final x = s.width * x0 + sin(p * 2 * pi + i) * u * .04;
    final fade = p < .15 ? p / .15 : (p > .7 ? (1 - p) / .3 : 1.0);
    final paint = Paint()..color = color.withAlpha((fade.clamp(0.0, 1.0) * 230).round());
    final h = Path()
      ..moveTo(x, y + size * .35)
      ..cubicTo(x - size * .9, y - size * .25, x - size * .45, y - size * .85, x, y - size * .4)
      ..cubicTo(x + size * .45, y - size * .85, x + size * .9, y - size * .25, x, y + size * .35)
      ..close();
    c.drawPath(h, paint);
  }
}
