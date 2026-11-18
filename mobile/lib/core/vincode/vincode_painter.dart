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

  Color _hsl(double h, double s, double l, double a) {
    final c = HSLColor.fromAHSL(a.clamp(0, 1), h % 360, s.clamp(0, 1), l.clamp(0, 1));
    return c.toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final R = s * 0.435;
    final dataR = s * 0.455;

    final plate = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        R * 0.92,
        const [Color(0xCC0B0A12), Color(0x9909080F), Color(0x00000000)],
        const [0.0, 0.78, 1.0],
      );
    canvas.drawCircle(Offset(cx, cy), R * 0.92, plate);

    final halo = Paint()
      ..shader = ui.Gradient.radial(
        Offset(cx, cy),
        R * 1.28,
        const [Color(0x226B38BE), Color(0x1826C0E1), Color(0x00000000)],
        const [0.0, 0.62, 1.0],
      );
    canvas.drawRect(Offset.zero & size, halo);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.2, s * 0.02)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < vincodeModules && i < modules.length; i++) {
      final a0 = i / vincodeModules * math.pi * 2 - math.pi / 2;
      final a1 = (i + 0.78) / vincodeModules * math.pi * 2 - math.pi / 2;
      final on = modules[i] == 1;
      ringPaint.color = on ? const Color(0xF037E6FF) : const Color(0xE89B6CFF);
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: dataR), a0, a1 - a0, false, ringPaint);
      if (on) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: dataR),
          a0,
          a1 - a0,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(5, s * 0.028)
            ..strokeCap = StrokeCap.round
            ..color = const Color(0x4037E6FF)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.012),
        );
      }
    }

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, s * 0.0018)
      ..color = const Color(0x3869DCFF);
    canvas.drawCircle(Offset(cx, cy), R, dash);

    for (final p in _ring) {
      final a = p.a + (reduceMotion ? 0 : t * p.speed * 0.19);
      final pulse = reduceMotion ? 1.0 : 0.7 + 0.3 * math.sin(t * 5 + p.phase);
      final x = cx + math.cos(a) * R;
      final y = cy + math.sin(a) * R;
      canvas.drawCircle(
        Offset(x, y),
        s * p.radius * (0.8 + pulse * 0.5),
        Paint()
          ..color = _hsl(p.hue, 1, 0.7, 0.48 + pulse * 0.45)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.006),
      );
    }

    final coords = <({double x, double y, _Particle p})>[];
    for (final p in _particles) {
      final wobble = reduceMotion ? 0.0 : math.sin(t * p.speed + p.phase) * p.drift;
      final wobble2 = reduceMotion ? 0.0 : math.cos(t * (p.speed * 0.83) + p.phase) * p.drift;
      coords.add((x: cx + (p.x + wobble) * s * 0.88, y: cy + (p.y + wobble2) * s * 0.88, p: p));
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.7, s * 0.0017);
    for (var i = 0; i < coords.length - 1; i++) {
      final a = coords[i];
      final b = coords[i + 1];
      if (a.p.kind != b.p.kind) continue;
      line.color = _hsl(a.p.hue, 1, 0.68, a.p.kind == 'hash' ? 0.32 : 0.1);
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), line);
    }

    for (final c in coords) {
      final p = c.p;
      final pulse = reduceMotion ? 1.0 : 0.55 + 0.45 * math.sin(t * (p.speed * 2.1) + p.phase);
      final hue = (p.hue + math.sin(t * 2.7 + p.phase) * 24 + 360) % 360;
      final radius = s * p.radius * (p.kind == 'hash' ? 1.0 : 0.75) * (0.78 + pulse * 0.55);
      canvas.drawCircle(
        Offset(c.x, c.y),
        radius,
        Paint()
          ..color = _hsl(hue, 1, p.kind == 'hash' ? 0.7 : 0.65, p.kind == 'hash' ? 0.72 + pulse * 0.25 : 0.25 + pulse * 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.kind == 'hash' ? s * 0.008 : s * 0.004),
      );
      if (p.kind == 'hash' && pulse > 0.88) {
        canvas.drawCircle(Offset(c.x, c.y), radius * 0.34, Paint()..color = const Color(0xE6FFFFFF));
      }
    }

    if (!reduceMotion) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(t * 1.35);
      final beam = Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, -R),
          Offset(0, R),
          const [Color(0x0037E6FF), Color(0x2637E6FF), Color(0x0037E6FF)],
          const [0.0, 0.5, 1.0],
        );
      canvas.drawRect(Rect.fromLTWH(-R * 0.025, -R, R * 0.05, R * 2), beam);
      canvas.restore();
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
