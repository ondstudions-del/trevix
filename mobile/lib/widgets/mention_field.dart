import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Sugerencias de @menciones para un campo de texto (GET mentions): con solo «@» muestra tus amistades, a quienes
/// sigues y tus seguidores; al seguir escribiendo («@ana») filtra y completa con el resto de TREVIX.
class MentionSuggestions extends StatefulWidget {
  const MentionSuggestions({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<MentionSuggestions> createState() => _MentionSuggestionsState();
}

class _MentionSuggestionsState extends State<MentionSuggestions> {
  static final _token = RegExp(r'(^|\s)@([\p{L}\p{N}._]{0,30})$', unicode: true);
  Timer? _timer;
  String? _query;
  List<(User, String?)> _users = const [];
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _timer?.cancel();
    super.dispose();
  }

  String? _currentQuery() {
    final value = widget.controller.value;
    final caret = value.selection.baseOffset;
    if (caret < 0 || caret > value.text.length) return null;
    return _token.firstMatch(value.text.substring(0, caret))?.group(2);
  }

  void _onChanged() {
    final query = _currentQuery();
    if (query == _query) return;
    _query = query;
    _timer?.cancel();
    if (query == null) {
      if (_users.isNotEmpty) setState(() => _users = const []);
      return;
    }
    _timer = Timer(Duration(milliseconds: query.isEmpty ? 0 : 220), () => _search(query));
  }

  Future<void> _search(String query) async {
    final id = ++_request;
    try {
      final res = await api.get('mentions', {'q': query});
      if (!mounted || id != _request || _currentQuery() != query) return;
      setState(() => _users = res.list.take(8).map((j) => (User.fromJson(j), asStrOrNull(j['relation_label']))).toList());
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    }
  }

  void _pick(User user) {
    final value = widget.controller.value;
    final caret = value.selection.baseOffset;
    final before = value.text.substring(0, caret).replaceFirst(RegExp(r'@([\p{L}\p{N}._]{0,30})$', unicode: true), '@${user.username} ');
    widget.controller.value = TextEditingValue(
      text: before + value.text.substring(caret),
      selection: TextSelection.collapsed(offset: before.length),
    );
    setState(() {
      _users = const [];
      _query = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_users.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.borderStrong)),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
        for (final (u, relation) in _users)
          ListTile(
            dense: true,
            leading: Avatar(user: u, size: 34),
            title: NameLine(user: u, size: 14),
            subtitle: Text('@${u.username}', style: Tx.body(12.5, color: Tx.muted)),
            trailing: relation == null
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Tx.alpha(Tx.accent, .14), borderRadius: BorderRadius.circular(20)),
                    child: Text(relation, style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.accent)),
                  ),
            onTap: () => _pick(u),
          ),
      ]),
    );
  }
}
