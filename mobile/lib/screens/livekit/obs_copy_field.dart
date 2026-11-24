import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';

/// Campo copiable (servidor RTMP, clave, URLs). Clave: mostrar/ocultar + copiar explícito.
class ObsCopyField extends StatefulWidget {
  const ObsCopyField({
    super.key,
    required this.label,
    required this.value,
    this.secret = false,
  });

  final String label;
  final String value;
  final bool secret;

  @override
  State<ObsCopyField> createState() => _ObsCopyFieldState();
}

class _ObsCopyFieldState extends State<ObsCopyField> {
  bool _revealed = false;

  Future<void> _copy() async {
  if (widget.value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (mounted) toast(context, tr('Copiado al portapapeles.'));
  }

  @override
  Widget build(BuildContext context) {
    final showPlain = !widget.secret || _revealed;
    final display = showPlain
        ? widget.value
        : ('•' * widget.value.length.clamp(12, 28));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: Tx.body(12, color: Colors.white54)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(color: Colors.white.withAlpha(14), borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  display,
                  style: Tx.body(12.5, color: Colors.white, height: 1.3),
                ),
              ),
              if (widget.secret)
                TextButton(
                  onPressed: () => setState(() => _revealed = !_revealed),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(_revealed ? tr('Ocultar') : tr('Mostrar'), style: Tx.body(12, color: Tx.accent)),
                ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
                icon: const Icon(CupertinoIcons.doc_on_doc, color: Colors.white70, size: 20),
                tooltip: tr('Copiar'),
                onPressed: _copy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}