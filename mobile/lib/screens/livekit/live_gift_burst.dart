import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Regalo en live: entrada desde abajo, pulso de marca y chispas (sin pantalla completa).
class LiveGiftBurstOverlay extends StatefulWidget {
  const LiveGiftBurstOverlay({super.key, required this.url, required this.label});

  final String url;
  final String label;

  @override
  State<LiveGiftBurstOverlay> createState() => _LiveGiftBurstOverlayState();
}

class _LiveGiftBurstOverlayState extends State<LiveGiftBurstOverlay> with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 3000);

  late final AnimationController _main = AnimationController(vsync: this, duration: _duration)..forward();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  return IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([_main, _pulse]),
      builder: (_, __) {
        final t = _main.value;
        final opacity = t < 0.78 ? 1.0 : (1 - ((t - 0.78) / 0.22)).clamp(0.0, 1.0);
        final entry = Curves.easeOutCubic.transform((t / 0.34).clamp(0.0, 1.0));
        final bounce = Curves.elasticOut.transform(((t - 0.08) / 0.42).clamp(0.0, 1.0));
        final scale = (0.35 + bounce * 0.65) * (1 + _pulse.value * 0.04);
        final slideY = (1 - entry) * 72.0;
        final wobble = math.sin(t * math.pi * 5) * 0.09 * (1 - t).clamp(0.0, 1.0);
        final labelIn = Curves.easeOut.transform(((t - 0.22) / 0.35).clamp(0.0, 1.0));
        final halo = 0.55 + _pulse.value * 0.45;

        return Opacity(
          opacity: opacity,
          child: Center(
            child: Transform.translate(
              offset: Offset(0, slideY),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ..._sparkles(t, halo),
                        Transform.scale(
                          scale: 0.92 + halo * 0.14,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Tx.accent.withAlpha((28 * halo).round().clamp(0, 255)),
                                  Tx.cyan.withAlpha((12 * halo).round().clamp(0, 255)),
                                  Colors.transparent,
                                ],
                                stops: const [0.2, 0.55, 1],
                              ),
                            ),
                            child: const SizedBox(width: 116, height: 116),
                          ),
                        ),
                        Transform.rotate(
                          angle: wobble,
                          child: Transform.scale(
                            scale: scale,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withAlpha(55), width: 1.2),
                                boxShadow: [
                                  BoxShadow(color: Tx.accent.withAlpha(45), blurRadius: 16, spreadRadius: 0),
                                  BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 12, offset: const Offset(0, 6)),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: ColoredBox(
                                  color: Colors.black.withAlpha(40),
                                  child: SizedBox(
                                    width: 76,
                                    height: 76,
                                    child: NetImage(widget.url, fit: BoxFit.contain),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Opacity(
                    opacity: labelIn,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - labelIn)),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 260),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(185),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Tx.accent.withAlpha(110)),
                          boxShadow: [BoxShadow(color: Colors.black.withAlpha(90), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.sparkles, size: 14, color: Tx.cyan.withAlpha(220)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                widget.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Tx.body(12, weight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  }

  List<Widget> _sparkles(double t, double halo) {
    const n = 7;
    final burst = Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0));
    final fade = (1 - ((t - 0.55) / 0.4).clamp(0.0, 1.0));
    final rot = t * math.pi * 0.65;
    final out = <Widget>[];
    for (var i = 0; i < n; i++) {
      final a = rot + (i / n) * math.pi * 2;
      final r = 38 + burst * 22;
      final dx = math.cos(a) * r;
      final dy = math.sin(a) * r;
      final s = 0.65 + halo * 0.35;
      out.add(
        Transform.translate(
          offset: Offset(dx, dy),
          child: Opacity(
            opacity: (burst * fade * 0.85).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: s,
              child: Icon(
                CupertinoIcons.sparkles,
                size: 11 + (i.isEven ? 2.0 : 0.0),
                color: i.isEven ? Tx.accent.withAlpha(200) : Tx.cyan.withAlpha(200),
              ),
            ),
          ),
        ),
      );
    }
    return out;
  }
}