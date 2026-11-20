import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import 'common.dart';

/// Banner encima del medio: exclusivas (Suscríbete) o contenido +18 (Mirar).
class ContentGate extends StatelessWidget {
  const ContentGate({
    super.key,
    required this.child,
    this.exclusive = false,
    this.adult = false,
    this.onSubscribe,
    this.onRevealAdult,
    this.minHeight = 220,
  });

  final Widget child;
  final bool exclusive;
  final bool adult;
  final VoidCallback? onSubscribe;
  final VoidCallback? onRevealAdult;
  final double minHeight;

  bool get _active => exclusive || adult;

  @override
  Widget build(BuildContext context) {
    if (!_active) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(minHeight <= 0 ? 0 : 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight <= 0 ? 0 : minHeight),
        child: Stack(alignment: Alignment.center, fit: StackFit.passthrough, children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withAlpha(exclusive ? 90 : 70), BlendMode.darken),
              child: child,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(40),
                    Colors.black.withAlpha(110),
                    Colors.black.withAlpha(150),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                exclusive ? CupertinoIcons.lock_fill : CupertinoIcons.exclamationmark_triangle_fill,
                color: Colors.white,
                size: exclusive ? 52 : 48,
              ),
              const SizedBox(height: 14),
              Text(
                exclusive ? tr('Contenido exclusivo') : tr('Contenido para adulto'),
                textAlign: TextAlign.center,
                style: Tx.display(22, color: Colors.white, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                exclusive ? tr('Suscríbete para desbloquear este contenido') : tr('¿Quieres seguir viendo?'),
                textAlign: TextAlign.center,
                style: Tx.body(14.5, color: Colors.white.withAlpha(230), height: 1.35),
              ),
              const SizedBox(height: 18),
              if (exclusive)
                _GateButton(
                  label: tr('Suscríbete'),
                  icon: CupertinoIcons.star_circle_fill,
                  gradient: true,
                  onPressed: onSubscribe,
                )
              else
                _GateButton(
                  label: tr('Mirar'),
                  icon: CupertinoIcons.eye_fill,
                  gradient: false,
                  onPressed: onRevealAdult,
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({required this.label, required this.icon, required this.gradient, this.onPressed});

  final String label;
  final IconData icon;
  final bool gradient;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: gradient ? Colors.white : Colors.black, size: 20),
      const SizedBox(width: 8),
      Text(label, style: Tx.body(16, weight: FontWeight.w800, color: gradient ? Colors.white : Colors.black)),
    ]);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: gradient ? Tx.brand : null,
            color: gradient ? null : Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(60), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Animación corta de bienvenida al suscribirse a un colaborador.
Future<void> showSubscribeWelcome(BuildContext context, {required String name}) async {
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'welcome',
    barrierColor: Colors.black.withAlpha(160),
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (ctx, a1, a2) {
      return Center(
        child: ScaleTransition(
          scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
          child: FadeTransition(
            opacity: a1,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 300,
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: Tx.brandSoft,
                  border: Border.all(color: Tx.alpha(Tx.purple500, .4)),
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(80), blurRadius: 28, offset: const Offset(0, 12))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
                    child: const Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 16),
                  Text(tr('¡Bienvenido!'), textAlign: TextAlign.center, style: Tx.display(24, weight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    tr('Gracias por suscribirte al plan de {name}. Ya puedes ver su contenido exclusivo.', {'name': name}),
                    textAlign: TextAlign.center,
                    style: Tx.body(14.5, color: Tx.muted, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      label: tr('Empezar'),
                      height: 46,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
}
