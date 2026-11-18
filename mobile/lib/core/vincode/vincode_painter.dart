import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'vincode_codec.dart';

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.phase,
    required this.speed,
    required this.drift,
    required this.radius,
    required this.hue,
    required this.kind,
  });

  final double x, y, phase, speed, drift, radius, hue;
  final String kind;
}

class _RingDot {
  _RingDot({required this.a, required this.phase, required this.radius, required this.hue, required this.speed});
  final double a, phase, radius, hue, speed;
}

/// VINCODE animado: anillo de datos estable (codec) + # / corona decorativos.
class VincodePainter extends CustomPainter {
  VincodePainter({
    required this.code,
    required this.t,
    this.reduceMotion = false,
    int? seed,
  })  : modules = codeToBits(code) ?? List<int>.filled(vincodeModules, 0),
        _seed = seed ?? seedForVincode(code) {
    _buildDecor();
  }

  final String code;
  final double t;
  final bool reduceMotion;
  final List<int> modules;
  final int _seed;
  final List<_Particle> _particles = [];
  final List<_RingDot> _ring = [];

  int _rand = 0;
  double _next() {
    _rand = (_rand * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _rand / 4294967296;
  }

  void _buildDecor() {
    _rand = _seed & 0xFFFFFFFF;
    void stroke(double x1, double y1, double x2, double y2, int count, double spread, String kind) {
      for (var i = 0; i < count; i++) {
        final u = count == 1 ? 0.5 : i / (count - 1);
        final jitter = (_next() - 0.5) * spread;
        final dx = (y2 - y1).abs() > (x2 - x1).abs();
        _particles.add(_Particle(
          x: x1 + (x2 - x1) * u + (dx ? jitter : 0),
          y: y1 + (y2 - y1) * u + (!dx ? jitter : 0),
          phase: _next() * math.pi * 2,
          speed: 2.2 + _next() * 3.8,
          drift: 0.012 + _next() * 0.026,
          radius: 0.0018 + _next() * 0.0015,
          hue: 180 + _next() * 115,
          kind: kind,
        ));
      }
    }

    stroke(-0.31, -0.37, -0.17, 0.37, 33, 0.075, 'hash');
    stroke(0.17, -0.37, 0.31, 0.37, 33, 0.075, 'hash');
    stroke(-0.39, -0.13, 0.39, -0.13, 39, 0.075, 'hash');
    stroke(-0.39, 0.13, 0.39, 0.13, 39, 0.075, 'hash');
    for (var i = 0; i < 132; i++) {
      _ring.add(_RingDot(
        a: i / 132 * math.pi * 2,
        phase: _next() * math.pi * 2,
        radius: 0.004 + _next() * 0.002,
        hue: 185 + _next() * 115,
        speed: 1.2 + _next() * 2.2,
      ));
    }
    for (var i = 0; i < 48; i++) {
      final a = _next() * math.pi * 2;
      final r = 0.12 + _next() * 0.3;
      _particles.add(_Particle(
        x: math.cos(a) * r,
        y: math.sin(a) * r,
        phase: _next() * math.pi * 2,
        speed: 2 + _next() * 4,
        drift: 0.025 + _next() * 0.045,
        radius: 0.0012 + _next() * 0.0015,
        hue: 185 + _next() * 120,
        kind: 'ambient',
      ));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = s * 0.435;
    final dataR = s * 0.455;
    final breath = reduceMotion ? 1.0 : 0.94 + 0.06 * math.sin(t * 2.2);

    canvas.drawCircle(
      Offset(cx, cy),
      R * 0.9,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          R * 0.9,
          const [Color(0xF00C0B12), Color(0xE60A0910), Color(0x00000000)],
          const [0.0, 0.82, 1.0],
        ),
    );

    canvas.drawCircle(
      Offset(cx, cy),
      dataR + s * 0.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, s * 0.004)
        ..color = const Color(0x2869DCFF),
    );

    final ringRect = Rect.fromCircle(center: Offset(cx, cy), radius: dataR);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < vincodeModules && i < modules.length; i++) {
      final a0 = i / vincodeModules * math.pi * 2 - math.pi / 2;
      final a1 = (i + 0.9) / vincodeModules * math.pi * 2 - math.pi / 2;
      final on = modules[i] == 1;
      ringPaint
        ..strokeWidth = math.max(5.0, s * 0.028) * breath
        ..color = on ? const Color(0xFF3CEBFF) : const Color(0xFF8B5CF6);
      canvas.drawArc(ringRect, a0, a1 - a0, false, ringPaint);
    }

    canvas.drawCircle(
      Offset(cx, cy),
      s * 0.14,
      Paint()..color = const Color(0xFF15141D),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      s * 0.14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, s * 0.004)
        ..color = const Color(0x5537E6FF),
    );

    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.5, s * 0.012)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF37E6FF);
    final lr = s * 0.055;
    canvas.drawArc(Rect.fromCircle(center: Offset(cx - lr * 0.35, cy), radius: lr), -math.pi * 0.85, math.pi * 1.15, false, linkPaint);
    canvas.drawArc(Rect.fromCircle(center: Offset(cx + lr * 0.35, cy), radius: lr), math.pi * 0.15, math.pi * 1.15, false, linkPaint);

    if (!reduceMotion) {
      final pulse = 0.08 + 0.04 * math.sin(t * 3);
      canvas.drawCircle(
        Offset(cx, cy),
        dataR * (1 + pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, s * 0.003)
          ..color = Color.fromARGB((32 + 24 * breath).round().clamp(0, 255), 55, 230, 255),
      );
    }
  }

  @override
  bool shouldRepaint(covariant VincodePainter old) =>
      old.t != t || old.code != code || old.reduceMotion != reduceMotion;
}

/// Widget que anima el VINCODE.
class VincodeView extends StatefulWidget {
  const VincodeView({super.key, required this.code, this.size = 280});

  final String code;
  final double size;

  @override
  State<VincodeView> createState() => _VincodeViewState();
}

class _VincodeViewState extends State<VincodeView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: VincodePainter(
            code: widget.code,
            t: _c.value * 12,
            reduceMotion: reduce,
          ),
        ),
      ),
    );
  }
}
