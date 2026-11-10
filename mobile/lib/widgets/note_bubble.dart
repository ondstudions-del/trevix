import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import 'gif_picker.dart';

/// Nube de una nota (como un globo de pensamiento): el texto en un globo redondeado con dos burbujas pequeñas
/// debajo, hacia el avatar. Con [placeholder] se muestra en gris (p. ej. «Publicar una nota»).
class NoteCloud extends StatelessWidget {
  const NoteCloud({
    super.key,
    required this.text,
    this.placeholder = false,
    this.maxWidth = 120,
    this.fontSize = 11.5,
    this.maxLines = 2,
    this.onTap,
    this.dark = false,
    this.tailUp = false,
    this.sticker,
  });

  final String text;

  /// Sticker de la nota, encima del texto (o solo, si la nota no tiene texto).
  final Gif? sticker;
  final bool placeholder;
  final double maxWidth;
  final double fontSize;
  final int maxLines;
  final VoidCallback? onTap;

  /// Sobre fondos oscuros fijos (visor de historias).
  final bool dark;

  /// Burbujas arriba del globo (cuando la nube va debajo del avatar).
  final bool tailUp;

  @override
  Widget build(BuildContext context) {
    final fill = dark ? const Color(0xF0FFFFFF) : (Tx.isDark ? Tx.surface4 : Colors.white);
    final ink = dark ? const Color(0xFF18181B) : Tx.text;
    final shadow = [BoxShadow(color: Colors.black.withAlpha(Tx.isDark || dark ? 70 : 28), blurRadius: 10, offset: const Offset(0, 3))];
    final bubble = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 34),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: fontSize * .85, vertical: fontSize * .55),
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(fontSize * 1.6), boxShadow: shadow),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (sticker != null) GifView(gif: sticker!, maxWidth: fontSize * 3.6, maxHeight: fontSize * 3.6),
            if (text.isNotEmpty || sticker == null)
              Text(
                text,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Tx.body(fontSize,
                    weight: placeholder ? FontWeight.w500 : FontWeight.w600,
                    color: placeholder ? (dark ? const Color(0xFF71717A) : Tx.subtle) : ink,
                    height: 1.25),
              ),
          ]),
        ),
      );
    final big = Padding(
      padding: EdgeInsets.only(left: fontSize * 1.3, top: tailUp ? 1 : 2, bottom: tailUp ? 2 : 0),
      child: _Dot(size: fontSize * .62, color: fill, shadow: shadow),
    );
    final small = Padding(
      padding: EdgeInsets.only(left: fontSize * .9, top: tailUp ? 0 : 1, bottom: tailUp ? 1 : 0),
      child: _Dot(size: fontSize * .36, color: fill, shadow: shadow),
    );
    final cloud = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tailUp ? [small, big, bubble] : [bubble, big, small],
    );
    return onTap == null ? cloud : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: cloud);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color, required this.shadow});

  final double size;
  final Color color;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: shadow));
}
