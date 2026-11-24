import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Emoji grande con entrada elástica (mensajes solo emoji).
class ChatBigEmoji extends StatefulWidget {
  const ChatBigEmoji({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<ChatBigEmoji> createState() => _ChatBigEmojiState();
}

class _ChatBigEmojiState extends State<ChatBigEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.72, end: 1.08).chain(CurveTween(curve: Curves.easeOutCubic)), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 45),
  ]).animate(_c);

  @override
  void initState() {
    super.initState();
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Text(widget.text, style: widget.style ?? const TextStyle(fontSize: 44, height: 1.1)),
    );
  }
}

/// Partículas breves al reaccionar (doble toque o barra de reacciones).
void showReactionBurst(BuildContext context, String emoji) {
  HapticFeedback.mediumImpact();
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  final rnd = math.Random();
  final specs = List.generate(6, (i) => (angle: rnd.nextDouble() * math.pi * 2, dist: 40.0 + rnd.nextDouble() * 36, spin: rnd.nextDouble() * .4 - .2));
  entry = OverlayEntry(
    builder: (ctx) => _ReactionBurstLayer(emoji: emoji, specs: specs, onDone: () {
      entry.remove();
    }),
  );
  overlay.insert(entry);
}

class _ReactionBurstLayer extends StatefulWidget {
  const _ReactionBurstLayer({required this.emoji, required this.specs, required this.onDone});

  final String emoji;
  final List<({double angle, double dist, double spin})> specs;
  final VoidCallback onDone;

  @override
  State<_ReactionBurstLayer> createState() => _ReactionBurstLayerState();
}

class _ReactionBurstLayerState extends State<_ReactionBurstLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 720));

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = Offset(MediaQuery.sizeOf(context).width / 2, MediaQuery.sizeOf(context).height * .42);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeOutCubic.transform(_c.value);
          final fade = (1 - _c.value).clamp(0.0, 1.0);
          return Stack(children: [
            Positioned(
              left: center.dx - 26,
              top: center.dy - 26,
              child: Opacity(
                opacity: fade,
                child: Transform.scale(
                  scale: 0.6 + t * 0.55,
                  child: Text(widget.emoji, style: const TextStyle(fontSize: 52)),
                ),
              ),
            ),
            for (final s in widget.specs)
              Positioned(
                left: center.dx + math.cos(s.angle) * s.dist * t - 12,
                top: center.dy + math.sin(s.angle) * s.dist * t - 28 * t - 12,
                child: Opacity(
                  opacity: fade,
                  child: Transform.rotate(
                    angle: s.spin * t,
                    child: Transform.scale(
                      scale: 0.35 + (1 - t) * 0.25,
                      child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}