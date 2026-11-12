import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/emoji_picker.dart';

/// Reacciones rápidas del chat (las mismas en todas las conversaciones, en la web y en la app).
/// La primera es la del doble toque. Devuelve la lista guardada o null si no hubo cambios.
Future<List<String>?> editQuickReactions(BuildContext context, ChatOptions options) {
  return showModalBottomSheet<List<String>>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _QuickReactionsSheet(options: options),
  );
}

class _QuickReactionsSheet extends StatefulWidget {
  const _QuickReactionsSheet({required this.options});

  final ChatOptions options;

  @override
  State<_QuickReactionsSheet> createState() => _QuickReactionsSheetState();
}

class _QuickReactionsSheetState extends State<_QuickReactionsSheet> {
  late final List<String> _list = [...widget.options.reactions];
  int _selected = 0;
  bool _saving = false;

  int get _max => widget.options.maxQuickReactions;

  Future<void> _pick(int index) async {
    setState(() => _selected = index);
    final emoji = await pickEmoji(context);
    if (emoji == null || !mounted) return;
    setState(() {
      final existing = _list.indexOf(emoji);
      if (index < _list.length) {
        if (existing >= 0 && existing != index) _list[existing] = _list[index];
        _list[index] = emoji;
      } else if (existing < 0) {
        _list.add(emoji);
      }
    });
  }

  void _remove(int index) {
    if (_list.length <= 1) return;
    setState(() {
      _list.removeAt(index);
      if (_selected >= _list.length) _selected = _list.length - 1;
    });
  }

  Future<void> _save([List<String>? list]) async {
    final reactions = list ?? _list;
    setState(() => _saving = true);
    try {
      final res = await api.put('me/chat-reactions', {'reactions': reactions});
      final saved = res.map['reactions'] is List ? (res.map['reactions'] as List).map((e) => asStr(e)).where((e) => e.isNotEmpty).toList() : reactions;
      if (!mounted) return;
      toast(context, tr('Reacciones rápidas guardadas.'));
      Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toastError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = _list.length < _max ? _list.length + 1 : _list.length;
    return SheetFrame(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Reacciones rápidas'), style: Tx.display(18)),
          const SizedBox(height: 4),
          Text(
            tr('Toca una para cambiarla. La primera es la del doble toque. Mantén presionada para quitarla.'),
            style: Tx.body(13, color: Tx.muted),
          ),
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < slots; i++)
              GestureDetector(
                onTap: _saving ? null : () => _pick(i),
                onLongPress: _saving || i >= _list.length ? null : () => _remove(i),
                child: Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Tx.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: i == _selected ? Tx.purple500 : Tx.border, width: i == _selected ? 2 : 1),
                  ),
                  child: i < _list.length
                      ? Text(_list[i], style: const TextStyle(fontSize: 26))
                      : Icon(CupertinoIcons.add, color: Tx.muted, size: 22),
                ),
              ),
          ]),
          const SizedBox(height: 20),
          GradientButton(label: tr('Guardar'), loading: _saving, onPressed: _saving ? null : () => _save()),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _saving ? null : () => _save(const []),
            child: Text(tr('Restablecer ({emoji} primero)', {'emoji': widget.options.defaultReactions.first}), style: Tx.body(14, color: Tx.muted)),
          ),
        ]),
      ),
    );
  }
}
