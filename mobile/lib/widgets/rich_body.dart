import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/nav.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import 'emoji_text.dart';

/// Enlaces escritos como «https://…», «www.…» o «dominio.com/…» (sin tomar correos ni palabras con punto).
const linkPattern = r'(?:https?://|www\.)[^\s<]+'
    r'|(?<![@\w.\-])(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+'
    r'(?:com|net|org|co|io|app|dev|me|es|edu|gov|info|tv|ly|gg|xyz|store|shop|site|online|ai|us|uk|mx|ar|cl|pe|ve|ec|bo|uy|py|br|tk|link|page|blog|news)'
    r'(?![\w\-])(?:[/?#][^\s<]*)?';

/// Dirección completa de un enlace del texto («www.x.com» → «https://www.x.com»).
String linkUrl(String token) => RegExp(r'^https?://', caseSensitive: false).hasMatch(token) ? token : 'https://$token';

/// Texto con #hashtags, @menciones y enlaces tocables (el servidor envía texto plano). Con [onlyLinks] solo se
/// marcan los enlaces (mensajes del chat). Los enlaces se abren en el navegador de la app.
class RichBody extends StatefulWidget {
  const RichBody(this.text, {super.key, this.style, this.maxLines, Color? linkColor, this.textAlign, this.onlyLinks = false})
      : _linkColor = linkColor;

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final Color? _linkColor;
  Color get linkColor => _linkColor ?? Tx.accent;
  final TextAlign? textAlign;
  final bool onlyLinks;

  @override
  State<RichBody> createState() => _RichBodyState();
}

class _RichBodyState extends State<RichBody> {
  static final _pattern = RegExp('($linkPattern)|(#[\\p{L}\\p{N}_]{1,50})|(@[A-Za-z0-9_.]{2,30})', unicode: true, caseSensitive: false);
  static final _links = RegExp('($linkPattern)', unicode: true, caseSensitive: false);
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = widget.style ?? Tx.body(15.5, height: 1.45);
    final link = base.copyWith(color: widget.linkColor, fontWeight: FontWeight.w500);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in (widget.onlyLinks ? _links : _pattern).allMatches(widget.text)) {
      if (m.start > last) spans.addAll(emojiSpans(widget.text.substring(last, m.start)));
      final token = m.group(0)!;
      if (m.group(1) != null) {
        var url = token;
        var trailing = '';
        while (url.isNotEmpty && '.,;:!?)»”'.contains(url[url.length - 1])) {
          trailing = url[url.length - 1] + trailing;
          url = url.substring(0, url.length - 1);
        }
        final shown = url.replaceFirst(RegExp(r'^https?://(www\.)?', caseSensitive: false), '');
        spans.add(TextSpan(
          text: shown.length > 42 ? '${shown.substring(0, 40)}…' : shown,
          style: link.copyWith(decoration: TextDecoration.underline, decorationColor: Tx.alpha(widget.linkColor, .5)),
          recognizer: _tap(() => openUrl(context, linkUrl(url))),
        ));
        if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      } else if (m.group(2) != null) {
        final tag = token.substring(1);
        spans.add(TextSpan(text: token, style: link, recognizer: _tap(() => openHashtag(context, tag))));
      } else {
        var name = token.substring(1);
        var trailing = '';
        while (name.endsWith('.')) {
          name = name.substring(0, name.length - 1);
          trailing += '.';
        }
        spans.add(TextSpan(text: '@$name', style: link, recognizer: _tap(() => openProfile(context, name))));
        if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      }
      last = m.end;
    }
    if (last < widget.text.length) spans.addAll(emojiSpans(widget.text.substring(last)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}
