import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/appearance.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/logo.dart';
import '../../widgets/tx_icon.dart';

/// Bienvenida animada que se muestra una sola vez, la primera vez que se abre la app.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _Slide {
  const _Slide(this.kicker, this.title, this.text, this.colors);

  final String kicker;
  final String title;
  final String text;
  final List<Color> colors;
}

const _slides = [
  _Slide('BIENVENIDO A', 'TREVIX', 'Conecta. Comparte. Descubre.\nLa red social donde tu voz brilla.', [Tx.purple500, Tx.blue]),
  _Slide('TU MUNDO', 'Comparte lo que te inspira', 'Fotos, videos, hilos y momentos con la música que los acompaña.', [Color(0xFFA855F7), Color(0xFFEC4899)]),
  _Slide('EN EL MOMENTO', 'Historias y música', 'Historias de 24 horas con canciones de artistas reales de la comunidad.', [Tx.blue, Tx.cyan]),
  _Slide('JUNTOS', 'Comunidades y mensajes', 'Encuentra a tu gente, únete a comunidades y conversa en privado.', [Tx.purple, Color(0xFF22D3EE)]),
];

class _IntroScreenState extends State<IntroScreen> with TickerProviderStateMixin {
  final _page = PageController();
  late final AnimationController _ambient = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  late final AnimationController _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  late final AnimationController _text = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  double _offset = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page.addListener(() => setState(() => _offset = _page.page ?? 0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Appearance.motionReduced(context)) {
      _ambient.stop();
      _shine.stop();
      _entry.value = 1;
      _text.value = 1;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
      _shine.repeat();
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _ambient.dispose();
    _entry.dispose();
    _text.dispose();
    _shine.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_index < _slides.length - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 620), curve: Curves.easeOutQuart);
    } else {
      _finish();
    }
  }

  void _finish() {
    HapticFeedback.mediumImpact();
    context.read<AppState>().finishIntro();
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    final from = _slides[_offset.floor().clamp(0, _slides.length - 1)].colors;
    final to = _slides[_offset.ceil().clamp(0, _slides.length - 1)].colors;
    final t = _offset - _offset.floor();
    final c1 = Color.lerp(from[0], to[0], t)!;
    final c2 = Color.lerp(from[1], to[1], t)!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: Scaffold(
        backgroundColor: TxDark.bg,
        body: Stack(children: [
          Positioned.fill(child: _Ambient(animation: _ambient, c1: c1, c2: c2)),
          Positioned.fill(child: _Grid(animation: _ambient)),
          Positioned.fill(child: _Sparkles(animation: _ambient)),
          SafeArea(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _entry, curve: const Interval(0, .4, curve: Curves.easeOut)),
              child: Column(children: [
                SizedBox(
                  height: 54,
                  child: Row(children: [
                    const SizedBox(width: 22),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _index == 0 ? 0 : 1,
                      child: const Wordmark(size: 26),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: last ? 0 : 1,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _GlassPill(
                          onTap: last ? null : _finish,
                          child: Text('Omitir', style: TxDark.body(14, weight: FontWeight.w600, color: Tx.alpha(Colors.white, .85))),
                        ),
                      ),
                    ),
                  ]),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _page,
                    itemCount: _slides.length,
                    physics: const BouncingScrollPhysics(),
                    onPageChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _index = i);
                      _text.forward(from: 0);
                    },
                    itemBuilder: (_, i) {
                      final delta = (i - _offset).clamp(-1.0, 1.0).toDouble();
                      return _SlideView(
                        slide: _slides[i],
                        index: i,
                        delta: delta,
                        ambient: _ambient,
                        entry: _entry,
                        shine: _shine,
                        text: i == _index ? _text : null,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(children: [
                    Row(children: [
                      Text(
                        '0${_index + 1}',
                        style: TxDark.display(15, weight: FontWeight.w700, color: Colors.white),
                      ),
                      Text(' / 0${_slides.length}', style: TxDark.display(15, weight: FontWeight.w500, color: Tx.alpha(Colors.white, .4))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Row(
                          children: List.generate(_slides.length, (i) {
                            final fill = (_offset - i + 1).clamp(0.0, 1.0);
                            return Expanded(
                              child: Container(
                                margin: EdgeInsets.only(right: i == _slides.length - 1 ? 0 : 6),
                                height: 4,
                                decoration: BoxDecoration(color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(2)),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: fill.toDouble(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [c1, c2]),
                                      borderRadius: BorderRadius.circular(2),
                                      boxShadow: [BoxShadow(color: c1.withAlpha(140), blurRadius: 8)],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _GlowButton(
                      label: last ? 'Comenzar' : 'Siguiente',
                      glyph: last ? TxGlyph.sparkles : TxGlyph.arrowRight,
                      c1: c1,
                      c2: c2,
                      shine: _shine,
                      onTap: _next,
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({
    required this.slide,
    required this.index,
    required this.delta,
    required this.ambient,
    required this.entry,
    required this.shine,
    this.text,
  });

  final _Slide slide;
  final int index;
  final double delta;
  final Animation<double> ambient;
  final Animation<double> entry;
  final Animation<double> shine;
  final Animation<double>? text;

  @override
  Widget build(BuildContext context) {
    final art = switch (index) {
      0 => _LogoArt(ambient: ambient, entry: entry),
      1 => _ShareArt(ambient: ambient),
      2 => _StoryArt(ambient: ambient),
      _ => _CommunityArt(ambient: ambient),
    };
    return LayoutBuilder(builder: (context, box) {
      final scale = (box.maxHeight / 560).clamp(.72, 1.0).toDouble();
      return Column(children: [
        Expanded(
          flex: 11,
          child: Transform.translate(
            offset: Offset(delta * box.maxWidth * .4, 0),
            child: Transform.scale(
              scale: scale * (1 - delta.abs() * .15),
              child: Opacity(opacity: (1 - delta.abs() * .9).clamp(0.0, 1.0).toDouble(), child: Center(child: art)),
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Transform.translate(
            offset: Offset(delta * box.maxWidth * .15, 0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: _Texts(slide: slide, animation: text, first: index == 0, shine: shine),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Texts extends StatelessWidget {
  const _Texts({required this.slide, required this.animation, required this.first, required this.shine});

  final _Slide slide;
  final Animation<double>? animation;
  final bool first;
  final Animation<double> shine;

  Widget _stagger(Widget child, double start) {
    final a = animation;
    if (a == null) return child;
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (_, c) {
        final v = Curves.easeOutCubic.transform(((a.value - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - v)),
            child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6 * (1 - v), sigmaY: 6 * (1 - v)), child: c),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = [Colors.white, Color.lerp(slide.colors[0], Colors.white, .35)!, slide.colors[1]];
    final titleStyle = first ? TxDark.display(52, weight: FontWeight.w700).copyWith(letterSpacing: 8) : TxDark.display(31, height: 1.12);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _stagger(
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 18, height: 1.5, color: Tx.alpha(Colors.white, .35)),
              const SizedBox(width: 10),
              Text(slide.kicker, style: TxDark.body(12, weight: FontWeight.w700, color: Tx.alpha(Colors.white, .65)).copyWith(letterSpacing: 4)),
              const SizedBox(width: 10),
              Container(width: 18, height: 1.5, color: Tx.alpha(Colors.white, .35)),
            ]),
            0,
          ),
          const SizedBox(height: 14),
          _stagger(
            Stack(alignment: Alignment.center, children: [
              GradientText(slide.title, align: TextAlign.center, gradient: LinearGradient(colors: base), style: titleStyle),
              AnimatedBuilder(
                animation: shine,
                builder: (_, __) {
                  final p = -.3 + shine.value * 1.6;
                  final List<double> stops = [
                    (p - .14).clamp(0.0, 1.0).toDouble(),
                    p.clamp(0.0, 1.0).toDouble(),
                    (p + .14).clamp(0.0, 1.0).toDouble(),
                  ];
                  return ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (b) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white.withAlpha(0), Colors.white.withAlpha(210), Colors.white.withAlpha(0)],
                      stops: stops,
                    ).createShader(Offset.zero & b.size),
                    child: Text(slide.title, textAlign: TextAlign.center, style: titleStyle),
                  );
                },
              ),
            ]),
            .12,
          ),
          const SizedBox(height: 16),
          _stagger(
            Text(slide.text, textAlign: TextAlign.center, style: TxDark.body(16, color: Tx.alpha(Colors.white, .74), height: 1.55)),
            .26,
          ),
          if (first) ...[
            const SizedBox(height: 22),
            _stagger(
              const Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                _FeatureChip(glyph: TxGlyph.image, label: 'Publicaciones'),
                _FeatureChip(glyph: TxGlyph.camera, label: 'Historias'),
                _FeatureChip(glyph: TxGlyph.music, label: 'Música'),
              ]),
              .4,
            ),
          ],
        ]),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.glyph, required this.label});

  final TxGlyph glyph;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withAlpha(38)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            TxIcon(glyph, size: 16, gradient: Tx.brandText, stroke: 2),
            const SizedBox(width: 7),
            Text(label, style: TxDark.body(13, weight: FontWeight.w600, color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withAlpha(36)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Orbes de luz que flotan lentamente detrás de todo.
class _Ambient extends StatelessWidget {
  const _Ambient({required this.animation, required this.c1, required this.c2});

  final Animation<double> animation;
  final Color c1;
  final Color c2;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final a = animation.value * 2 * math.pi;
        final size = MediaQuery.of(context).size;
        Widget orb(Color color, double d, double x, double y, int alpha) => Positioned(
              left: x - d / 2,
              top: y - d / 2,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [color.withAlpha(alpha), color.withAlpha(0)]),
                ),
              ),
            );
        return Stack(children: [
          orb(c1, size.width * 1.4, size.width * (.15 + .14 * math.sin(a)), size.height * (.2 + .06 * math.cos(a)), 160),
          orb(c2, size.width * 1.25, size.width * (.92 + .1 * math.cos(a * 1.3)), size.height * (.48 + .07 * math.sin(a)), 140),
          orb(Tx.purple700, size.width * 1.1, size.width * (.3 + .12 * math.sin(a * .7)), size.height * (.95 + .03 * math.cos(a)), 150),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [TxDark.bg.withAlpha(40), TxDark.bg.withAlpha(90), TxDark.bg.withAlpha(200)],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// Retícula en perspectiva que se desplaza muy despacio, como un horizonte.
class _Grid extends StatelessWidget {
  const _Grid({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(animation: animation, builder: (_, __) => CustomPaint(painter: _GridPainter(animation.value))),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * .62;
    final rect = Rect.fromLTWH(0, horizon, size.width, size.height - horizon);
    final paint = Paint()
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withAlpha(0), Colors.white.withAlpha(22)],
      ).createShader(rect);
    final cx = size.width / 2;
    for (var i = -10; i <= 10; i++) {
      canvas.drawLine(Offset(cx + i * 18, horizon), Offset(cx + i * 120, size.height), paint);
    }
    final depth = size.height - horizon;
    for (var i = 0; i < 9; i++) {
      final f = ((i + (t * 9 % 1)) / 9);
      final y = horizon + depth * f * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.t != t;
}

/// Destellos que suben y titilan.
class _Sparkles extends StatelessWidget {
  const _Sparkles({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(animation: animation, builder: (_, __) => CustomPaint(painter: _SparklePainter(animation.value))),
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.t);

  final double t;
  static final _rand = math.Random(7);
  static final _seeds = List.generate(40, (_) => [_rand.nextDouble(), _rand.nextDouble(), _rand.nextDouble(), _rand.nextDouble()]);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _seeds) {
      final y = ((s[1] - t * (0.25 + s[2] * .35)) % 1) * size.height;
      final x = s[0] * size.width + math.sin((t * 6 + s[3] * 10)) * 8;
      final twinkle = (math.sin(t * 2 * math.pi * 4 + s[3] * 12) + 1) / 2;
      final r = .8 + s[2] * 1.8;
      final paint = Paint()
        ..color = Colors.white.withAlpha((40 + 150 * twinkle * s[2]).round().clamp(0, 255))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter old) => old.t != t;
}

/// Logo que entra girando, con anillos que orbitan y un halo que respira.
class _LogoArt extends StatelessWidget {
  const _LogoArt({required this.ambient, required this.entry});

  final Animation<double> ambient;
  final Animation<double> entry;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ambient, entry]),
      builder: (_, __) {
        final e = Curves.elasticOut.transform(entry.value.clamp(0.0, 1.0));
        final fade = Curves.easeOut.transform((entry.value * 2).clamp(0.0, 1.0));
        final ringIn = Curves.easeOutCubic.transform(((entry.value - .2) / .8).clamp(0.0, 1.0));
        final breathe = (math.sin(ambient.value * 2 * math.pi * 3) + 1) / 2;
        final spin = ambient.value * 2 * math.pi;
        return Opacity(
          opacity: fade,
          child: SizedBox(
            width: 300,
            height: 300,
            child: Stack(alignment: Alignment.center, children: [
              Transform.scale(
                scale: .6 + .4 * ringIn,
                child: Transform.rotate(
                  angle: spin,
                  child: Container(
                    width: 262,
                    height: 262,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: SweepGradient(colors: [
                        Tx.purple500.withAlpha(0),
                        Tx.purple500.withAlpha(170),
                        Tx.cyan.withAlpha(170),
                        Tx.blue.withAlpha(0),
                      ]),
                    ),
                  ),
                ),
              ),
              Container(width: 256, height: 256, decoration: BoxDecoration(shape: BoxShape.circle, color: TxDark.bg.withAlpha(235))),
              Opacity(
                opacity: ringIn,
                child: Transform.rotate(angle: -spin * 1.5, child: CustomPaint(size: const Size(214, 214), painter: _OrbitPainter())),
              ),
              Opacity(
                opacity: ringIn * .7,
                child: Transform.rotate(angle: spin * 2, child: CustomPaint(size: const Size(170, 170), painter: _OrbitPainter(dashed: true))),
              ),
              Container(
                width: 140 + 24 * breathe,
                height: 140 + 24 * breathe,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Tx.purple.withAlpha((90 + 70 * breathe).round()), blurRadius: 64, spreadRadius: 8)],
                ),
              ),
              Transform.scale(
                scale: .4 + .6 * e,
                child: Transform.rotate(angle: (1 - e) * -.6, child: const TrevixLogo(size: 124, glow: true)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({this.dashed = false});

  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withAlpha(dashed ? 45 : 30);
    if (dashed) {
      const n = 48;
      for (var i = 0; i < n; i += 2) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * 2 * math.pi / n, math.pi / n, false, ring);
      }
      return;
    }
    canvas.drawCircle(c, r, ring);
    final dots = [(0.0, Tx.cyan), (2.1, Tx.purple300), (4.2, const Color(0xFFEC4899))];
    for (final d in dots) {
      final p = c + Offset(math.cos(d.$1) * r, math.sin(d.$1) * r);
      canvas.drawCircle(p, 10, Paint()..color = d.$2.withAlpha(55));
      canvas.drawCircle(p, 4.5, Paint()..color = d.$2);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => oldDelegate.dashed != dashed;
}

/// Tarjetas flotantes: foto, hilo y me gusta.
class _ShareArt extends StatelessWidget {
  const _ShareArt({required this.ambient});

  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ambient,
      builder: (_, __) {
        final a = ambient.value * 2 * math.pi;
        double f(double phase, double amp) => math.sin(a * 2 + phase) * amp;
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 30,
              top: 40 + f(0, 8),
              child: Transform.rotate(angle: -.12, child: _glassCard(170, 210, _photoContent())),
            ),
            Positioned(
              right: 14,
              top: 92 + f(1.5, 10),
              child: Transform.rotate(angle: .08, child: _glassCard(150, 120, _threadContent())),
            ),
            Positioned(
              left: 150,
              top: 20 + f(3, 6),
              child: _bubble(TxGlyph.heart, const [Color(0xFFF43F5E), Color(0xFFEC4899)], 56, filled: true),
            ),
            Positioned(
              left: 10,
              bottom: 22 + f(2.2, 7),
              child: _bubble(TxGlyph.music, const [Tx.purple500, Tx.blue], 50),
            ),
            Positioned(
              right: 40,
              bottom: 30 + f(4, 9),
              child: _bubble(TxGlyph.comment, const [Tx.blue, Tx.cyan], 46),
            ),
          ]),
        );
      },
    );
  }

  Widget _photoContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 22, height: 22, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand)),
          const SizedBox(width: 6),
          _line(60, 7),
        ]),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA855F7), Color(0xFFEC4899), Color(0xFFF59E0B)],
              ),
            ),
            child: const Center(child: TxIcon(TxGlyph.image, color: Colors.white, size: 34, stroke: 1.8)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const TxIcon(TxGlyph.heart, size: 14, color: Tx.like, filled: true),
          const SizedBox(width: 6),
          _line(30, 6),
          const Spacer(),
          const TxIcon(TxGlyph.bookmark, size: 13, color: Tx.purple400, filled: true),
        ]),
      ]);

  Widget _threadContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const TxIcon(TxGlyph.thread, size: 14, color: Tx.purple300, stroke: 2.2),
          const SizedBox(width: 6),
          _line(50, 7, Tx.purple300),
        ]),
        const SizedBox(height: 12),
        _line(118, 6),
        const SizedBox(height: 7),
        _line(100, 6),
        const SizedBox(height: 7),
        _line(70, 6),
        const Spacer(),
        Text('#trevix', style: TxDark.body(12, weight: FontWeight.w600, color: Tx.purple300)),
      ]);
}

Widget _line(double w, double h, [Color? color]) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color?.withAlpha(150) ?? Colors.white.withAlpha(60), borderRadius: BorderRadius.circular(h)),
    );

Widget _glassCard(double w, double h, Widget child) => Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: w,
            height: h,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withAlpha(34), Colors.white.withAlpha(12)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withAlpha(46)),
            ),
            child: child,
          ),
        ),
      ),
    );

Widget _bubble(TxGlyph glyph, List<Color> colors, double size, {bool filled = false}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: Colors.white.withAlpha(60)),
        boxShadow: [BoxShadow(color: colors.first.withAlpha(130), blurRadius: 22, offset: const Offset(0, 8))],
      ),
      alignment: Alignment.center,
      child: TxIcon(glyph, color: Colors.white, size: size * .46, filled: filled, stroke: 2.1),
    );

/// Anillos de historias y una canción sonando.
class _StoryArt extends StatelessWidget {
  const _StoryArt({required this.ambient});

  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ambient,
      builder: (_, __) {
        final a = ambient.value * 2 * math.pi;
        Widget ring(double size, double angle, List<Color> fill, TxGlyph glyph) => Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(transform: GradientRotation(angle), colors: const [Tx.purple500, Tx.blue, Tx.cyan, Color(0xFFA855F7), Tx.purple500]),
                boxShadow: [BoxShadow(color: fill.first.withAlpha(90), blurRadius: 24)],
              ),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: TxDark.bg),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fill)),
                  alignment: Alignment.center,
                  child: TxIcon(glyph, color: Colors.white, size: size * .34, filled: glyph == TxGlyph.play, stroke: 2),
                ),
              ),
            );
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned(left: 8, top: 60 + math.sin(a * 2) * 8, child: ring(78, a * 3, const [Color(0xFFDB2777), Tx.purple], TxGlyph.camera)),
            Positioned(right: 8, top: 40 + math.cos(a * 2) * 8, child: ring(70, -a * 3, const [Color(0xFF0EA5E9), Color(0xFF0F766E)], TxGlyph.text)),
            Transform.translate(offset: Offset(0, math.sin(a * 2 + 1) * 6), child: ring(130, a * 4, const [Tx.purple700, Tx.blue], TxGlyph.play)),
            Positioned(
              bottom: 18 + math.sin(a * 2 + 2) * 5,
              child: _glassCard(
                230,
                66,
                Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(11)),
                    alignment: Alignment.center,
                    child: const TxIcon(TxGlyph.note, color: Colors.white, size: 20, stroke: 2.2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _line(90, 7, Colors.white),
                      const SizedBox(height: 7),
                      _line(56, 6),
                    ]),
                  ),
                  _Bars(t: ambient.value),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final v = (math.sin(t * 2 * math.pi * 14 + i * 1.7) + 1) / 2;
          return Container(
            width: 4,
            height: 6 + 18 * v,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Tx.purple400, Tx.cyan]),
            ),
          );
        }),
      ),
    );
  }
}

/// Avatares de una comunidad y burbujas de chat.
class _CommunityArt extends StatelessWidget {
  const _CommunityArt({required this.ambient});

  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ambient,
      builder: (_, __) {
        final a = ambient.value * 2 * math.pi;
        const palette = [
          [Color(0xFFA855F7), Color(0xFFEC4899)],
          [Tx.blue, Tx.cyan],
          [Color(0xFFF59E0B), Color(0xFFDB2777)],
          [Tx.success, Tx.blue],
          [Tx.purple, Tx.blue],
        ];
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            CustomPaint(size: const Size(230, 230), painter: _OrbitPainter()),
            for (var i = 0; i < 5; i++)
              Transform.translate(
                offset: Offset(math.cos(a + i * 2 * math.pi / 5) * 115, math.sin(a + i * 2 * math.pi / 5) * 115),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: palette[i]),
                    border: Border.all(color: TxDark.bg, width: 3),
                    boxShadow: [BoxShadow(color: palette[i][0].withAlpha(120), blurRadius: 18)],
                  ),
                  alignment: Alignment.center,
                  child: const TxIcon(TxGlyph.user, color: Colors.white, size: 21, filled: true, stroke: 1.6),
                ),
              ),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Transform.translate(
                offset: Offset(-20, math.sin(a * 2) * 4),
                child: _chat('¡Hola! 👋', false),
              ),
              const SizedBox(height: 8),
              Transform.translate(
                offset: Offset(18, math.cos(a * 2) * 4),
                child: _chat('¿Te unes a la comunidad?', true),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _chat(String text, bool mine) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          gradient: mine ? Tx.brand : null,
          color: mine ? null : Colors.white.withAlpha(30),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
          border: mine ? null : Border.all(color: Colors.white.withAlpha(40)),
          boxShadow: mine ? [BoxShadow(color: Tx.purple.withAlpha(110), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: Text(text, style: TxDark.body(13.5, weight: FontWeight.w500, color: Colors.white)),
      );
}

class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.glyph, required this.c1, required this.c2, required this.shine, required this.onTap});

  final String label;
  final TxGlyph glyph;
  final Color c1;
  final Color c2;
  final Animation<double> shine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      pressedOpacity: .85,
      onPressed: onTap,
      child: Container(
        height: 60,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: [c1, c2]),
          border: Border.all(color: Colors.white.withAlpha(46)),
          boxShadow: [
            BoxShadow(color: c1.withAlpha(120), blurRadius: 28, offset: const Offset(0, 10)),
            BoxShadow(color: c2.withAlpha(80), blurRadius: 44, offset: const Offset(0, 16)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(21),
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: shine,
                builder: (_, __) => FractionalTranslation(
                  translation: Offset(-1.2 + shine.value * 2.6, 0),
                  child: Transform.rotate(
                    angle: .35,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white.withAlpha(0), Colors.white.withAlpha(60), Colors.white.withAlpha(0)],
                          stops: const [.35, .5, .65],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(label, key: ValueKey(label), style: TxDark.body(17, weight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: TxIcon(glyph, key: ValueKey(glyph), color: Colors.white, size: 20, stroke: 2.4),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
