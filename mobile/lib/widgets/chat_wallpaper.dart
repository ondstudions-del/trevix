import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

enum _ChatPattern { hearts, stars, bubbles, pride }

/// Fondos del chat (las claves y nombres los define el servidor en app.chat.wallpapers).
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  static const _gradients = <String, List<Color>>{
    'aurora': [Color(0xFF0EA5E9), Color(0xFF8B5CF6), Color(0xFF10B981)],
    'sunset': [Color(0xFFF97316), Color(0xFFEC4899), Color(0xFF8B5CF6)],
    'ocean': [Color(0xFF0369A1), Color(0xFF0891B2), Color(0xFF22D3EE)],
    'forest': [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF84CC16)],
    'midnight': [Color(0xFF020617), Color(0xFF1E1B4B), Color(0xFF312E81)],
    'lavender': [Color(0xFFC4B5FD), Color(0xFFA78BFA), Color(0xFFF0ABFC)],
    'graphite': [Color(0xFF18181B), Color(0xFF3F3F46), Color(0xFF52525B)],
    'hearts': [Color(0xFF500724), Color(0xFF9F1239), Color(0xFFE11D48), Color(0xFFFDA4AF)],
    'stars': [Color(0xFF020617), Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF818CF8)],
    'bubbles': [Color(0xFF042F2E), Color(0xFF0D9488), Color(0xFF2DD4BF), Color(0xFFA5F3FC)],
    'pride': [Color(0xFF1E1B2E), Color(0xFF312E81), Color(0xFF4C1D95)],
    'champagne': [Color(0xFF0C0A09), Color(0xFF44403C), Color(0xFFB08D3E), Color(0xFFE8D5A3)],
    'velvet': [Color(0xFF0F0610), Color(0xFF3B1428), Color(0xFF7A2E4D), Color(0xFFC97B9A)],
    'pearl': [Color(0xFFDDE4EA), Color(0xFFB0BEC8), Color(0xFF78909C), Color(0xFF546E7A)],
    'dune': [Color(0xFF292018), Color(0xFF5C4A3A), Color(0xFF9A7B5C), Color(0xFFDBC4A8)],
    'candy': [Color(0xFFF472B6), Color(0xFFFB7185), Color(0xFFFBBF24)],
  };

  static const _pattern = <String, _ChatPattern>{
    'hearts': _ChatPattern.hearts,
    'stars': _ChatPattern.stars,
    'bubbles': _ChatPattern.bubbles,
    'pride': _ChatPattern.pride,
  };

  static const _lightWallpapers = {'pearl', 'lavender'};

  static bool usesLightForeground(String name) => name != 'default' && !_lightWallpapers.contains(name);

  /// Muestra pequeña para el selector de fondos.
  static Widget swatch(String name, {double size = 64, bool selected = false}) {
    final colors = _gradients[name];
    final kind = _pattern[name];
    return Container(
      width: size,
      height: size * 1.4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colors == null ? Tx.bg : null,
        gradient: colors == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: selected ? Tx.accent : Tx.border, width: selected ? 3 : 1),
        boxShadow: selected ? [BoxShadow(color: Tx.alpha(Tx.accent, .25), blurRadius: 10, offset: const Offset(0, 3))] : null,
      ),
      child: colors == null
          ? Icon(CupertinoIcons.nosign, color: Tx.subtle, size: 20)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                if (kind == _ChatPattern.pride)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE40303), Color(0xFFFF8C00), Color(0xFFFFED00), Color(0xFF008026), Color(0xFF24408E), Color(0xFF732982)],
                      ),
                    ),
                  ),
                if (kind != null) CustomPaint(painter: _FancyPatternPainter(kind, spacing: 20, compact: true)),
              ]),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[name];
    if (colors == null) return child;
    final kind = _pattern[name];
    final veil = Tx.isDark ? .42 : .28;
    final light = _lightWallpapers.contains(name);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (name == 'pride')
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.2, -1),
                end: Alignment(1.2, 1),
                colors: [Color(0x99E40303), Color(0x99FF8C00), Color(0x99FFED00), Color(0x99008026), Color(0x9924408E), Color(0x99732982)],
              ),
            ),
          ),
        ColoredBox(color: Tx.alpha(light ? Colors.white : Tx.bg, light ? .15 : veil)),
        if (kind != null) IgnorePointer(child: CustomPaint(painter: _FancyPatternPainter(kind))),
        child,
      ]),
    );
  }
}

class _FancyPatternPainter extends CustomPainter {
  _FancyPatternPainter(this.kind, {this.spacing = 56, this.compact = false});

  final _ChatPattern kind;
  final double spacing;
  final bool compact;

  static const _prideColors = [Color(0xFFE40303), Color(0xFFFF8C00), Color(0xFFFFED00), Color(0xFF008026), Color(0xFF24408E), Color(0xFF732982)];

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(kind.index + 11);
    final gap = compact ? spacing : spacing;
    for (double y = gap * .35; y < size.height + gap; y += gap) {
      final row = (y / gap).floor();
      final xStart = row.isOdd ? gap * .55 : gap * .2;
      for (double x = xStart; x < size.width + gap; x += gap) {
        final jitter = compact ? 0.0 : (rnd.nextDouble() - .5) * gap * .18;
        final scale = compact ? .55 + rnd.nextDouble() * .35 : .65 + rnd.nextDouble() * .55;
        final rot = (rnd.nextDouble() - .5) * (compact ? .35 : .55);
        final alpha = compact ? 42 + rnd.nextInt(28) : 32 + rnd.nextInt(38);
        canvas.save();
        canvas.translate(x + jitter, y + jitter * .5);
        canvas.rotate(rot);
        switch (kind) {
          case _ChatPattern.hearts:
            _paintHeart(canvas, 9 * scale, Colors.white.withAlpha(alpha));
          case _ChatPattern.stars:
            _paintStar(canvas, 10 * scale, Colors.white.withAlpha(alpha + 8));
          case _ChatPattern.bubbles:
            _paintBubble(canvas, 11 * scale, Colors.white.withAlpha(alpha));
          case _ChatPattern.pride:
            final c = _prideColors[rnd.nextInt(_prideColors.length)];
            _paintHeart(canvas, 8 * scale, c.withAlpha(alpha + 20));
        }
        canvas.restore();
      }
    }
    if (kind == _ChatPattern.stars && !compact) {
      final spark = Paint()..color = Colors.white.withAlpha(55);
      for (var i = 0; i < 12; i++) {
        final px = rnd.nextDouble() * size.width;
        final py = rnd.nextDouble() * size.height;
        canvas.drawCircle(Offset(px, py), .8 + rnd.nextDouble() * 1.2, spark);
      }
    }
  }

  static void _paintHeart(Canvas canvas, double size, Color color) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, size * .28)
      ..cubicTo(-size * .55, -size * .35, -size * .55, size * .45, 0, size * .92)
      ..cubicTo(size * .55, size * .45, size * .55, -size * .35, 0, size * .28)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _paintStar(Canvas canvas, double r, Color color) {
    final paint = Paint()..color = color;
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final a = i * math.pi / 2;
      final tip = Offset(math.cos(a) * r, math.sin(a) * r);
      final inner = Offset(math.cos(a + math.pi / 4) * r * .38, math.sin(a + math.pi / 4) * r * .38);
      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      } else {
        path.lineTo(tip.dx, tip.dy);
      }
      path.lineTo(inner.dx, inner.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  static void _paintBubble(Canvas canvas, double r, Color color) {
    final outer = Paint()..color = color.withAlpha((color.a * 255 * .45).round().clamp(0, 255));
    final inner = Paint()..color = color.withAlpha((color.a * 255 * .85).round().clamp(0, 255));
    canvas.drawCircle(Offset.zero, r, outer);
    canvas.drawCircle(Offset(-r * .22, -r * .22), r * .28, inner);
  }

  @override
  bool shouldRepaint(_FancyPatternPainter old) => old.kind != kind || old.spacing != spacing;
}