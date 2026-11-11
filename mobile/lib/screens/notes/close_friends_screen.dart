import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/user_tile.dart';

/// Lista de mejores amigos (público de las notas): tus seguidores y las cuentas que sigues; solo tú la ves.
class CloseFriendsScreen extends StatefulWidget {
  const CloseFriendsScreen({super.key});

  @override
  State<CloseFriendsScreen> createState() => _CloseFriendsScreenState();
}

class _CloseFriendsScreenState extends State<CloseFriendsScreen> {
  static const _green = Color(0xFF22C55E);

  final _search = TextEditingController();
  Timer? _debounce;
  List<User>? _users;
  final Set<int> _selected = {};
  final Set<int> _busy = {};
  int? _count;
  Object? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    try {
      final res = await api.get('me/close-friends/candidates', {if (q.isNotEmpty) 'q': q});
      final count = _count ?? asInt((await api.get('me/close-friends')).meta['count']);
      if (id != _request || !mounted) return;
      setState(() {
        _users = res.list.map(User.fromJson).toList();
        for (final j in res.list) {
          final uid = asInt(j['id']);
          if (asBool(j['selected'])) {
            _selected.add(uid);
          } else {
            _selected.remove(uid);
          }
        }
        _count = count;
        _error = null;
      });
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(User u) async {
    if (_busy.contains(u.id)) return;
    final adding = !_selected.contains(u.id);
    setState(() {
      _busy.add(u.id);
      adding ? _selected.add(u.id) : _selected.remove(u.id);
    });
    try {
      final res = adding ? await api.post('me/close-friends/${u.id}') : await api.delete('me/close-friends/${u.id}');
      if (mounted) setState(() => _count = asInt(res.map['count'], _count ?? 0));
    } catch (e) {
      if (mounted) {
        setState(() => adding ? _selected.remove(u.id) : _selected.add(u.id));
        toastError(context, e);
      }
    }
    if (mounted) setState(() => _busy.remove(u.id));
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: GlassBar(title: tr('Mejores amigos')),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
          child: Row(children: [
            const Icon(CupertinoIcons.star_fill, size: 18, color: _green),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${_count == null ? '' : '${plural(_count!, 'persona', 'personas')} · '}${tr('Solo tú ves esta lista: nadie recibe un aviso si lo agregas o lo quitas.')}',
                style: Tx.body(13.5, color: Tx.muted, height: 1.35),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _load(v.trim()));
            },
            style: Tx.body(15),
            decoration: fieldDecoration(tr('Buscar entre tus seguidores y seguidos'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : users == null
                  ? const Loading()
                  : users.isEmpty
                      ? EmptyState(
                          icon: CupertinoIcons.person_2,
                          title: _search.text.trim().isEmpty ? tr('Aún no hay a quién agregar') : tr('Sin resultados'),
                          message: tr('Puedes agregar a las personas que sigues o que te siguen.'),
                        )
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final u = users[i];
                            final on = _selected.contains(u.id);
                            return UserTile(
                              user: u,
                              subtitle: '@${u.username}',
                              onTap: () => _toggle(u),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: on ? _green : Colors.transparent,
                                  border: Border.all(color: on ? _green : Tx.subtle, width: 1.6),
                                ),
                                child: on ? const Icon(CupertinoIcons.star_fill, size: 14, color: Colors.white) : null,
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
