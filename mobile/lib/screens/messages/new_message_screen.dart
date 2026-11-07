import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/user_tile.dart';
import 'chat_screen.dart';

/// Elegir a quién escribir (sin búsqueda: las cuentas que sigues).
class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<User>? _users;
  Object? _error;
  int _request = 0;
  int? _opening;

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
      final res = await api.get('messages/recipients', {'q': q});
      if (id == _request && mounted) {
        setState(() {
          _users = res.list.map(User.fromJson).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(User user) async {
    setState(() => _opening = user.id);
    try {
      final res = await api.get('users/${Uri.encodeComponent(user.username)}');
      final profile = Profile.fromJson(res.map);
      if (!mounted) return;
      if (profile.conversationId == null && profile.messageBlockedReason != null) {
        toast(context, profile.messageBlockedReason!, error: true);
      } else {
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(builder: (_) => ChatScreen(conversationId: profile.conversationId, user: profile.user)),
        );
        return;
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _opening = null);
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: const GlassBar(title: 'Nuevo mensaje'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _load(v.trim()));
            },
            style: Tx.body(15),
            decoration: fieldDecoration('Buscar personas', prefix: const Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : users == null
                  ? const Loading()
                  : users.isEmpty
                      ? const EmptyState(icon: CupertinoIcons.person_crop_circle_badge_xmark, title: 'Sin resultados', message: 'Busca por nombre o usuario.')
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (_, i) => UserTile(
                            user: users[i],
                            onTap: () => _open(users[i]),
                            trailing: _opening == users[i].id
                                ? const CupertinoActivityIndicator()
                                : const Icon(CupertinoIcons.chat_bubble_text, color: Tx.purple300),
                          ),
                        ),
        ),
      ]),
    );
  }
}
