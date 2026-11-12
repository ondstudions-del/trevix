import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';

/// Negrita, cursiva y viñetas para el texto de [controller]: escribe «**texto**», «*texto*» y «• » (lo que
/// muestran RichBody y la web). En una línea con viñeta, Enter abre otra; en una viñeta vacía, la quita.
class FormatBar extends StatefulWidget {
  const FormatBar({super.key, required this.controller, this.color});

  final TextEditingController controller;
  final Color? color;

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  static const _bullet = '• ';
  late String _last = widget.controller.text;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant FormatBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      _last = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final c = widget.controller;
    final text = c.text;
    final before = _last;
    _last = text;
    final caret = c.selection.baseOffset;
    if (!c.selection.isCollapsed || caret < 1 || text.length != before.length + 1 || text[caret - 1] != '\n') return;
    if (text.substring(0, caret - 1) + text.substring(caret) != before) return;
    final from = text.lastIndexOf('\n', caret - 2) + 1;
    final line = text.substring(from, caret - 1);
    if (!line.startsWith(_bullet)) return;
    if (line == _bullet) {
      _set(text.replaceRange(from, caret, ''), from);
    } else {
      _set(text.replaceRange(caret, caret, _bullet), caret + _bullet.length);
    }
  }

  void _set(String text, int start, [int? end]) {
    _last = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
    );
  }

  (int, int) _range() {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid) return (c.text.length, c.text.length);
    return (sel.start, sel.end);
  }

  void _wrap(String mark) {
    final text = widget.controller.text;
    final (start, end) = _range();
    final n = mark.length;
    final wrapped = start >= n &&
        end + n <= text.length &&
        text.substring(start - n, start) == mark &&
        text.substring(end, end + n) == mark &&
        (n == 2 || start < 2 || text.substring(start - 2, start) != '**');
    if (wrapped) {
      _set(text.replaceRange(end, end + n, '').replaceRange(start - n, start, ''), start - n, end - n);
    } else {
      _set(text.replaceRange(start, end, '$mark${text.substring(start, end)}$mark'), start + n, end + n);
    }
  }

  void _bullets() {
    final text = widget.controller.text;
    final (start, end) = _range();
    final from = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
    final lineEnd = text.indexOf('\n', end);
    final to = lineEnd == -1 ? text.length : lineEnd;
    final lines = text.substring(from, to).split('\n');
    final all = lines.every((l) => l.startsWith(_bullet));
    final next = lines.map((l) => all ? l.substring(_bullet.length) : (l.startsWith(_bullet) ? l : '$_bullet$l')).join('\n');
    _set(text.replaceRange(from, to, next), from + next.length);
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Tx.muted;
    Widget button(String label, Widget child, VoidCallback onTap) => Tooltip(
          message: label,
          child: Semantics(
            button: true,
            label: label,
            child: InkResponse(
              onTap: onTap,
              radius: 22,
              child: SizedBox(width: 40, height: 36, child: Center(child: child)),
            ),
          ),
        );
    return Row(children: [
      button(tr('Negrita'), Text('B', style: Tx.body(17, weight: FontWeight.w800, color: color)), () => _wrap('**')),
      button(
        tr('Cursiva'),
        Text('I', style: Tx.body(17, weight: FontWeight.w600, color: color).copyWith(fontStyle: FontStyle.italic, fontFamily: 'serif')),
        () => _wrap('*'),
      ),
      button(tr('Viñetas'), Icon(CupertinoIcons.list_bullet, size: 20, color: color), _bullets),
    ]);
  }
}
