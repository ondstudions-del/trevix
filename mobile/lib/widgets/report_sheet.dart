import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/catalog.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import 'common.dart';

/// Reportar contenido: type = post, comment, user, community, message o story.
Future<void> showReportSheet(BuildContext context, String type, int id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReportSheet(type: type, id: id, parent: context),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.type, required this.id, required this.parent});

  final String type;
  final int id;
  final BuildContext parent;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  static const _what = {
    'post': 'esta publicación',
    'comment': 'este comentario',
    'user': 'esta cuenta',
    'community': 'esta comunidad',
    'message': 'este mensaje',
    'story': 'esta historia',
  };

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    if (reason == 'other' && _details.text.trim().length < 5) {
      setState(() => _error = 'Cuéntanos el motivo (al menos 5 caracteres).');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await api.post('reports', {
        'type': widget.type,
        'id': widget.id,
        'reason': reason,
        'details': _details.text.trim(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      if (widget.parent.mounted) toast(widget.parent, asMessage(res.map, 'Gracias. Revisaremos tu reporte.'));
    } on ApiException catch (e) {
      setState(() {
        _sending = false;
        _error = e.fields['details'] ?? e.fields['reason'] ?? e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Reportar ${_what[widget.type] ?? 'contenido'}', style: Tx.display(19)),
          const SizedBox(height: 6),
          Text('Tu reporte es anónimo. El equipo lo revisará según las normas de la comunidad.', style: Tx.body(13.5, color: Tx.muted)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in reportReasons.entries)
              PillChip(label: e.value, selected: _reason == e.key, onTap: () => setState(() => _reason = e.key)),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: _details,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            style: Tx.body(15),
            decoration: fieldDecoration(_reason == 'other' ? 'Describe el motivo (obligatorio)' : 'Detalles (opcional)'),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: Tx.body(13, color: Tx.danger))),
          GradientButton(label: 'Enviar reporte', loading: _sending, onPressed: _reason == null ? null : _send),
        ]),
      ),
    );
  }
}

String asMessage(Map<String, dynamic> data, String fallback) {
  final m = data['message'];
  return m is String && m.isNotEmpty ? m : fallback;
}
