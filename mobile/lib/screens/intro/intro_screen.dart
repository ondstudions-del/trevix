import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/logo.dart';

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
  late final AnimationController _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  late final AnimationController _text = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  double _offset = 0;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page.addListener(() => setState(() => _offset = _page.page ?? 0));
  }

  @override
  void dispose() {
    _page.dispose();
    _ambient.dispose();
    _entry.dispose();
    _text.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_index < _slides.length - 1) {
      _page.nextPage(duration: const Duration(milliseconds: 520), curve: Curves.easeOutCubic);
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
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Tx.bg,
        body: Stack(children: [
          Positioned.fill(child: _Ambient(animation: _ambient, c1: c1, c2: c2)),
          Positioned.fill(child: _Sparkles(animation: _ambient)),
          SafeArea(
            child: Column(children: [
              SizedBox(
                height: 52,
                child: Row(children: [
                  const SizedBox(width: 20),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _index == 0 ? 0 : 1,
                    child: const Wordmark(size: 26),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: last ? 0 : 1,
                    child: CupertinoButton(
                      onPressed: last ? null : _finish,
                      child: Text('Omitir', style: Tx.body(15, weight: FontWeight.w600, color: Tx.muted)),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
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
                      text: i == _index ? _text : null,
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (i) {
                      final dist = (i - _offset).abs().clamp(0.0, 1.0);
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8 + 22 * (1 - dist),
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: dist < .5 ? LinearGradient(colors: [c1, c2]) : null,
                          color: dist < .5 ? null : Colors.white.withAlpha(50),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 26),
                  _GlowButton(label: last ? 'Comenzar' : 'Siguiente', icon: last ? CupertinoIcons.sparkles : CupertinoIcons.arrow_right, c1: c1, c2: c2, onTap: _next),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.index, required this.delta, required this.ambient, required this.entry, this.text});

  final _Slide slide;
  final int index;
  final double delta;
  final Animation<double> ambient;
  final Animation<double> entry;
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
      return Column(children: [
        Expanded(
          flex: 11,
          child: Transform.translate(
            offset: Offset(delta * box.maxWidth * .35, 0),
            child: Opacity(opacity: (1 - delta.abs() * .8).clamp(0.0, 1.0).toDouble(), child: Center(child: art)),
          ),
        ),
        Expanded(
          flex: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: _Texts(slide: slide, animation: text, first: index == 0),
          ),
        ),
      ]);
    });
  }
}

class _Texts extends StatelessWidget {
  const _Texts({required this.slide, required this.animation, required this.first});

  final _Slide slide;
  final Animation<double>? animation;
  final bool first;

  Widget _stagger(Widget child, double start) {
    final a = animation;
    if (a == null) return child;
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (_, c) {
        final v = Curves.easeOutCubic.transform(((a.value - start) / (1 - start)).clamp(0.0, 1.0));
        return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: c));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final gradient = LinearGradient(colors: [Colors.white, Color.lerp(slide.colors[0], Colors.white, .35)!, slide.colors[1]]);
    return Column(children: [
      _stagger(
        Text(slide.kicker, style: Tx.body(12.5, weight: FontWeight.w700, color: Tx.alpha(Colors.white, .6)).copyWith(letterSpacing: 4)),
        0,
      ),
      const SizedBox(height: 12),
      _stagger(
        GradientText(
          slide.title,
          align: TextAlign.center,
          gradient: gradient,
          style: first ? Tx.display(54, weight: FontWeight.w700).copyWith(letterSpacing: 6) : Tx.display(32, height: 1.12),
        ),
        .12,
      ),
      const SizedBox(height: 16),
      _stagger(
        Text(slide.text, textAlign: TextAlign.center, style: Tx.body(16, color: Tx.alpha(Colors.white, .72), height: 1.55)),
        .26,
      ),
    ]);
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
        Widget orb(Color color, double d, double x, double y) => Positioned(
              left: x - d / 2,
              top: y - d / 2,
              child: Container(
                width: d,
                height: d,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [color.withAlpha(150), color.withAlpha(0)]),
                ),
              ),
            );
        return Stack(children: [
          orb(c1, size.width * 1.3, size.width * (.2 + .12 * math.sin(a)), size.height * (.18 + .05 * math.cos(a))),
          orb(c2, size.width * 1.2, size.width * (.9 + .1 * math.cos(a * 1.3)), size.height * (.5 + .06 * math.sin(a))),
          orb(Tx.purple700, size.width, size.width * (.3 + .1 * math.sin(a * .7)), size.height * (.92 + .03 * math.cos(a))),
          Positioned.fill(child: Container(color: Tx.bg.withAlpha(70))),
        ]);
      },
    );
  }
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
  static final _seeds = List.generate(34, (_) => [_rand.nextDouble(), _rand.nextDouble(), _rand.nextDouble(), _rand.nextDouble()]);

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

/// Logo que entra girando con un halo que respira.
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
        final breathe = (math.sin(ambient.value * 2 * math.pi * 3) + 1) / 2;
        final spin = ambient.value * 2 * math.pi;
        return Opacity(
          opacity: fade,
          child: SizedBox(
            width: 280,
            height: 280,
            child: Stack(alignment: Alignment.center, children: [
              Transform.rotate(
                angle: spin,
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(colors: [
                      Tx.purple500.withAlpha(0),
                      Tx.purple500.withAlpha(150),
                      Tx.cyan.withAlpha(150),
                      Tx.blue.withAlpha(0),
                    ]),
                  ),
                ),
              ),
              Container(width: 238, height: 238, decoration: const BoxDecoration(shape: BoxShape.circle, color: Tx.bg)),
              Transform.rotate(
                angle: -spin * 1.5,
                child: CustomPaint(size: const Size(200, 200), painter: _OrbitPainter()),
              ),
              Container(
                width: 150 + 20 * breathe,
                height: 150 + 20 * breathe,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Tx.purple.withAlpha((90 + 60 * breathe).round()), blurRadius: 60, spreadRadius: 6)],
                ),
              ),
              Transform.scale(
                scale: .4 + .6 * e,
                child: Transform.rotate(angle: (1 - e) * -.6, child: const TrevixLogo(size: 128, glow: true)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withAlpha(30);
    canvas.drawCircle(c, r, ring);
    final dots = [(0.0, Tx.cyan), (2.1, Tx.purple300), (4.2, const Color(0xFFEC4899))];
    for (final d in dots) {
      final p = c + Offset(math.cos(d.$1) * r, math.sin(d.$1) * r);
      canvas.drawCircle(p, 9, Paint()..color = d.$2.withAlpha(60));
      canvas.drawCircle(p, 4.5, Paint()..color = d.$2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
              child: _bubble(CupertinoIcons.heart_fill, const [Color(0xFFF43F5E), Color(0xFFEC4899)], 54),
            ),
            Positioned(
              left: 10,
              bottom: 22 + f(2.2, 7),
              child: _bubble(CupertinoIcons.music_note_2, const [Tx.purple500, Tx.blue], 48),
            ),
            Positioned(
              right: 40,
              bottom: 30 + f(4, 9),
              child: _bubble(CupertinoIcons.chat_bubble_fill, const [Tx.blue, Tx.cyan], 44),
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
            child: const Center(child: Icon(CupertinoIcons.photo, color: Colors.white, size: 34)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(CupertinoIcons.heart_fill, size: 14, color: Tx.like),
          const SizedBox(width: 6),
          _line(30, 6),
          const Spacer(),
          const Icon(CupertinoIcons.bookmark_fill, size: 13, color: Tx.purple400),
        ]),
      ]);

  Widget _threadContent() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.text_quote, size: 14, color: Tx.purple300),
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
        Text('#trevix', style: Tx.body(12, weight: FontWeight.w600, color: Tx.purple300)),
      ]);
}

Widget _line(double w, double h, [Color? color]) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: color?.withAlpha(150) ?? Colors.white.withAlpha(60), borderRadius: BorderRadius.circular(h)),
    );

Widget _glassCard(double w, double h, Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: w,
          height: h,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withAlpha(40)),
          ),
          child: child,
        ),
      ),
    );

Widget _bubble(IconData icon, List<Color> colors, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors),
        boxShadow: [BoxShadow(color: colors.first.withAlpha(120), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Icon(icon, color: Colors.white, size: size * .45),
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
        Widget ring(double size, double angle, List<Color> fill, IconData icon) => Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: SweepGradient(transform: GradientRotation(angle), colors: const [Tx.purple500, Tx.blue, Tx.cyan, Color(0xFFA855F7), Tx.purple500])),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Tx.bg),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fill)),
                  child: Icon(icon, color: Colors.white, size: size * .36),
                ),
              ),
            );
        return SizedBox(
          width: 300,
          height: 300,
          child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
            Positioned(left: 8, top: 60 + math.sin(a * 2) * 8, child: ring(78, a * 3, const [Color(0xFFDB2777), Tx.purple], CupertinoIcons.camera_fill)),
            Positioned(right: 8, top: 40 + math.cos(a * 2) * 8, child: ring(70, -a * 3, const [Color(0xFF0EA5E9), Color(0xFF0F766E)], CupertinoIcons.textformat)),
            Transform.translate(offset: Offset(0, math.sin(a * 2 + 1) * 6), child: ring(130, a * 4, const [Tx.purple700, Tx.blue], CupertinoIcons.play_fill)),
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
                    child: const Icon(CupertinoIcons.music_note_2, color: Colors.white, size: 20),
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
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: palette[i]),
                    border: Border.all(color: Tx.bg, width: 3),
                    boxShadow: [BoxShadow(color: palette[i][0].withAlpha(110), blurRadius: 16)],
                  ),
                  child: const Icon(CupertinoIcons.person_fill, color: Colors.white, size: 22),
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
        ),
        child: Text(text, style: Tx.body(13.5, weight: FontWeight.w500, color: Colors.white)),
      );
}

class _GlowButton extends StatelessWidget {
  const _GlowButton({required this.label, required this.icon, required this.c1, required this.c2, required this.onTap});

  final String label;
  final IconData icon;
  final Color c1;
  final Color c2;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 58,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(colors: [c1, c2]),
          boxShadow: [
            BoxShadow(color: c1.withAlpha(110), blurRadius: 26, offset: const Offset(0, 10)),
            BoxShadow(color: c2.withAlpha(70), blurRadius: 40, offset: const Offset(0, 14)),
          ],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(label, key: ValueKey(label), style: Tx.body(17, weight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(icon, key: ValueKey(icon), color: Colors.white, size: 20),
          ),
        ]),
      ),
    );
  }
}