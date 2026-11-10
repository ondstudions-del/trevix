import 'package:flutter/material.dart';

/// Secuencias de emoji: pictogramas, banderas, tonos de piel, selector de variante (FE0F), unión (200D) y etiquetas.
final emojiRun = RegExp(
  r'(?:[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2300}-\u{23FF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{3030}\u{303D}\u{3297}\u{3299}\u{00A9}\u{00AE}\u{2122}\u{2139}\u{24C2}\u{E0020}-\u{E007F}][\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}\u{20E3}]*|[#*0-9]\u{FE0F}?\u{20E3})+',
  unicode: true,
);

/// El texto es solo emojis (hasta [max] secuencias), para mostrarlo en grande como en Messenger.
bool isOnlyEmoji(String text, {int max = 3}) {
  final t = text.trim();
  if (t.isEmpty || t.length > 40) return false;
  if (t.replaceAll(emojiRun, '').trim().isNotEmpty) return false;
  final runs = t.characters.where((c) => c.trim().isNotEmpty).length;
  return runs <= max;
}

/// Parte [text] en tramos de texto y de emoji. Los emojis no llevan las sombras de [style]: en iOS una sombra
/// difuminada sobre un emoji de color lo deja manchado.
List<InlineSpan> emojiSpans(String text, {TextStyle? style}) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in emojiRun.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: style));
    spans.add(TextSpan(text: m.group(0), style: (style ?? const TextStyle()).copyWith(shadows: const [])));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: style));
  return spans;
}

/// Texto con sombra (sobre video o fotos) cuyos emojis se ven limpios.
class ShadowText extends StatelessWidget {
  const ShadowText(this.text, {super.key, required this.style, this.maxLines, this.overflow, this.textAlign});

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(style: style, children: emojiSpans(text)),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
