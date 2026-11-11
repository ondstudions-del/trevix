import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/chat_media.dart';
import '../../core/chat_sender.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/user_tile.dart';

/// Reenviar un mensaje a varias personas (sin búsqueda: los chats recientes). Devuelve true si se reenvió.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key, required this.message, this.max = 5});

  final Message message;
  final int max;

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<User>? _users;
  Object? _error;
  int _request = 0;
  final Map<String, User> _selected = {};
  bool _sending = false;

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
      final List<User> users;
      if (q.isEmpty) {
        final res = await api.get('conversations');
        users = res.list.map(Conversation.fromJson).where((c) => c.available && !c.blocked).map((c) => c.user).toList();
      } else {
        final res = await api.get('messages/recipients', {'q': q});
        users = res.list.map(User.fromJson).toList();
      }
      if (id == _request && mounted) {
        setState(() {
          _users = users;
          _error = null;
        });
      }
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  void _toggle(User u) {
    setState(() {
      if (_selected.containsKey(u.username)) {
        _selected.remove(u.username);
      } else if (_selected.length >= widget.max) {
        toast(context, tr('Puedes reenviarlo a {max} personas como máximo.', {'max': widget.max}), error: true);
      } else {
        _selected[u.username] = u;
      }
    });
  }

  /// Los mensajes cifrados no los puede leer el servidor: se descifran aquí y se vuelven a enviar (cifrados para cada
  /// chat que lo permita).
  Future<void> _sendEncrypted() async {
    final m = widget.message;
    final p = m.payload!;
    final myId = context.read<AppState>().me?.user.id ?? 0;
    String? path;
    if (p.type == 'image' || p.type == 'voice' || p.type == 'video') path = (await ChatMedia.load(m)).path;
    final g = p.gif;
    final size = p.file;
    final out = Outgoing(
      text: p.body,
      imagePath: p.type == 'image' ? path : null,
      videoPath: p.type == 'video' ? path : null,
      videoSeconds: p.type == 'video' ? p.duration : 0,
      videoWidth: (size?['w'] as num?)?.toInt() ?? 0,
      videoHeight: (size?['h'] as num?)?.toInt() ?? 0,
      voicePath: p.type == 'voice' ? path : null,
      voiceSeconds: p.duration,
      gif: g != null && p.type == 'gif'
          ? Gif(id: asStr(g['id']), kind: asStr(g['kind'], 'gif'), url: asStr(g['url']), width: asInt(g['w']), height: asInt(g['h']), title: asStr(g['title']))
          : null,
      location: p.type == 'location' ? p.location : null,
      forwarded: true,
    );
    final failed = <String, String>{};
    for (final username in _selected.keys) {
      try {
        await ChatSender.send(to: username, myId: myId, out: out);
      } on ApiException catch (e) {
        failed[username] = e.message;
      }
    }
    if (!mounted) return;
    final sent = _selected.length - failed.length;
    if (sent > 0) toast(context, sent == 1 ? tr('Mensaje reenviado.') : tr('Mensaje reenviado a {n} chats.', {'n': sent}));
    if (failed.isNotEmpty) {
      final first = failed.entries.first;
      toast(context, tr('No se envió a @{user}: {error}', {'user': first.key, 'error': first.value}), error: true);
    }
    if (sent > 0) Navigator.pop(context, true);
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    if (widget.message.encrypted) {
      try {
        await _sendEncrypted();
      } catch (e) {
        if (mounted) toastError(context, e);
      }
      if (mounted) setState(() => _sending = false);
      return;
    }
    try {
      final res = await api.post('messages/${widget.message.id}/forward', {'to': _selected.keys.toList()});
      if (!mounted) return;
      final failed = asMap(res.map['failed']);
      toast(context, '${res.map['message'] ?? tr('Mensaje reenviado.')}');
      if (failed.isNotEmpty) {
        final first = failed.entries.first;
        toast(context, tr('No se envió a @{user}: {error}', {'user': first.key, 'error': first.value}), error: true);
      }
      Navigator.pop(context, true);
      return;
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Reenviar a'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _sending ? null : _send,
            child: _sending
                ? const CupertinoActivityIndicator()
                : Text(_selected.isEmpty ? tr('Enviar') : tr('Enviar ({n})', {'n': _selected.length}),
                    style: Tx.body(16, weight: FontWeight.w700, color: _selected.isEmpty ? Tx.subtle : Tx.accent)),
          ),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
          child: Row(children: [
            Icon(CupertinoIcons.arrowshape_turn_up_right, size: 18, color: Tx.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.message.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.muted))),
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
            decoration: fieldDecoration(tr('Buscar personas'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final u in _selected.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      label: Text('@${u.username}', style: Tx.body(13)),
                      onDeleted: () => _toggle(u),
                      backgroundColor: Tx.surface3,
                      side: BorderSide(color: Tx.border),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : users == null
                  ? const Loading()
                  : users.isEmpty
                      ? EmptyState(icon: CupertinoIcons.person_crop_circle_badge_xmark, title: tr('Sin resultados'), message: tr('Busca por nombre o usuario.'))
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final u = users[i];
                            final on = _selected.containsKey(u.username);
                            return UserTile(
                              user: u,
                              onTap: () => _toggle(u),
                              trailing: Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                                  color: on ? Tx.accent : Tx.subtle, size: 24),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
