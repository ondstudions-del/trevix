import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

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

Future<void> _playWelcomeSound() async {
  AudioPlayer? player;
  try {
    player = AudioPlayer();
    await player.setAsset('assets/sounds/trevix_welcome.wav');
    await player.setVolume(0.85);
    await player.play();
    await player.playerStateStream.firstWhere((s) => s.processingState == ProcessingState.completed).timeout(const Duration(seconds: 3));
  } catch (_) {
  } finally {
    try {
      await player?.dispose();
    } catch (_) {}
  }
}

/// Bienvenida al suscribirse: tarjeta opaca, animación y sonido corto.
Future<void> showSubscribeWelcome(BuildContext context, {required String name}) async {
  if (!context.mounted) return;
  HapticFeedback.mediumImpact();
  // ignore: unawaited_futures
  _playWelcomeSound();
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'welcome',
    barrierColor: Colors.black.withAlpha(210),
    transitionDuration: const Duration(milliseconds: 520),
    transitionBuilder: (ctx, a1, a2, child) {
      final curved = CurvedAnimation(parent: a1, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: a1,
        child: ScaleTransition(scale: Tween(begin: 0.82, end: 1.0).animate(curved), child: child),
      );
    },
    pageBuilder: (ctx, a1, a2) => _WelcomeCard(name: name),
  );
}

class _WelcomeCard extends StatefulWidget {
  const _WelcomeCard({required this.name});

  final String name;

  @override
  State<_WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends State<_WelcomeCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween(begin: 0.94, end: 1.08).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          decoration: BoxDecoration(
            color: Tx.isDark ? const Color(0xFF16161C) : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Tx.alpha(Tx.purple500, .55), width: 1.4),
            boxShadow: [
              BoxShadow(color: Tx.purple500.withAlpha(70), blurRadius: 36, spreadRadius: 2, offset: const Offset(0, 14)),
              BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 28, offset: const Offset(0, 16)),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: scale,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: Tx.brand,
                  boxShadow: [BoxShadow(color: Tx.purple500.withAlpha(90), blurRadius: 22, offset: const Offset(0, 8))],
                ),
                child: const Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 40),
              ),
            ),
            const SizedBox(height: 18),
            Text(tr('¡Bienvenido!'), textAlign: TextAlign.center, style: Tx.display(26, weight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              tr('Gracias por unirte al club de {name}.', {'name': widget.name}),
              textAlign: TextAlign.center,
              style: Tx.body(16, weight: FontWeight.w700, height: 1.35),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Ya puedes ver su contenido exclusivo. Disfruta del plan y gracias por apoyar a este creador.'),
              textAlign: TextAlign.center,
              style: Tx.body(14.5, color: Tx.muted, height: 1.45),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: tr('Empezar'),
                height: 48,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
