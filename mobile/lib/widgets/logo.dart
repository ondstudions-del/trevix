import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Logo de TREVIX: cuadro redondeado con el degradado de la marca y el «#» blanco (mismo trazo que la web).
class TrevixLogo extends StatelessWidget {
  const TrevixLogo({super.key, this.size = 36, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: glow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(size * 18 / 64),
              boxShadow: [
                BoxShadow(color: Tx.alpha(Tx.purple, .55), blurRadius: size * .6, spreadRadius: size * .02),
                BoxShadow(color: Tx.alpha(Tx.blue, .35), blurRadius: size * 1.1, offset: Offset(size * .1, size * .2)),
              ],
            )
          : null,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(18 * s));
    canvas.drawRRect(rrect, Paint()..shader = Tx.brand.createShader(rect));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.6, -.7),
          radius: .9,
          colors: [Colors.white.withAlpha(46), Colors.white.withAlpha(0)],
        ).createShader(rect),
    );
    final pen = Paint()
      ..color = Colors.white
      ..strokeWidth = 5.5 * s
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void line(double x1, double y1, double x2, double y2) => canvas.drawLine(Offset(x1 * s, y1 * s), Offset(x2 * s, y2 * s), pen);
    line(27.5, 14.5, 23, 49.5);
    line(41, 14.5, 36.5, 49.5);
    line(16.5, 26, 48.5, 26);
    line(15.5, 38, 47.5, 38);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Texto con el degradado de la marca.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, required this.style, this.gradient = Tx.brandText, this.align});

  final String text;
  final TextStyle style;
  final Gradient gradient;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(Offset.zero & bounds.size),
      child: Text(text, style: style, textAlign: align),
    );
  }
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 30, this.gradientText = false});

  final double size;
  final bool gradientText;

  @override
  Widget build(BuildContext context) {
    final style = Tx.display(size * .68, weight: FontWeight.w700).copyWith(letterSpacing: 1.6);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      TrevixLogo(size: size),
      SizedBox(width: size * .32),
      if (gradientText)
        GradientText('TREVIX', style: style, gradient: const LinearGradient(colors: [Colors.white, Tx.purple300, Tx.blue400]))
      else
        Text('TREVIX', style: style),
    ]);
  }
}
