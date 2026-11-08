import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

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
    'candy': [Color(0xFFF472B6), Color(0xFFFB7185), Color(0xFFFBBF24)],
    'lavender': [Color(0xFFC4B5FD), Color(0xFFA78BFA), Color(0xFFF0ABFC)],
    'graphite': [Color(0xFF18181B), Color(0xFF3F3F46), Color(0xFF52525B)],
    'hearts': [Color(0xFFBE185D), Color(0xFFDB2777), Color(0xFFF472B6)],
    'stars': [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF4C1D95)],
    'bubbles': [Color(0xFF0E7490), Color(0xFF0284C7), Color(0xFF6366F1)],
  };

  static const _patterns = <String, IconData>{
    'hearts': CupertinoIcons.heart_fill,
    'stars': CupertinoIcons.star_fill,
    'bubbles': CupertinoIcons.circle_fill,
  };

  /// Muestra pequeña para el selector de fondos.
  static Widget swatch(String name, {double size = 64, bool selected = false}) {
    final colors = _gradients[name];
    return Container(
      width: size,
      height: size * 1.4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: colors == null ? Tx.bg : null,
        gradient: colors == null ? null : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: selected ? Tx.accent : Tx.border, width: selected ? 3 : 1),
      ),
      child: _patterns[name] == null
          ? (colors == null ? Icon(CupertinoIcons.nosign, color: Tx.subtle, size: 20) : null)
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(painter: _PatternPainter(_patterns[name]!, spacing: 22, iconSize: 9)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[name];
    if (colors == null) return child;
    final pattern = _patterns[name];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Stack(fit: StackFit.expand, children: [
        // Velo del color del tema para que las burbujas se lean bien sobre el fondo.
        ColoredBox(color: Tx.alpha(Tx.bg, Tx.isDark ? .45 : .3)),
        if (pattern != null) IgnorePointer(child: CustomPaint(painter: _PatternPainter(pattern))),
        child,
      ]),
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.icon, {this.spacing = 64, this.iconSize = 18});

  final IconData icon;
  final double spacing;
  final double iconSize;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (double y = spacing / 2; y < size.height + spacing; y += spacing) {
      final row = (y / spacing).floor();
      for (double x = (row.isOdd ? spacing / 2 : 0) + spacing / 4; x < size.width + spacing; x += spacing) {
        final scale = .7 + rnd.nextDouble() * .6;
        final painter = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              fontSize: iconSize * scale,
              color: Colors.white.withAlpha(38),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x, y));
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.icon != icon || old.spacing != spacing;
}
