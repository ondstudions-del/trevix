import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/chat_sender.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Abre «Enviar por mensaje» para una publicación o un reel (si es un compartido, se envía la original).
Future<void> openSendPost(BuildContext context, Post post) =>
    push<void>(context, SendPostScreen(card: SharedPostRef.ofPost(post)), fullscreen: true);

/// Un destino: un chat existente (directo o grupo) o una persona con la que todavía no hay chat.
class _Target {
  _Target.chat(Conversation c)
      : key = 'c:${c.id}',
        conversation = c,
        user = c.user,
        name = c.title,
        subtitle = c.isGroup ? tr('Grupo') : '@${c.user.username}';

  _Target.person(User u)
      : key = 'u:${u.username}',
        conversation = null,
        user = u,
        name = u.displayName,
        subtitle = '@${u.username}';

  final String key;
  final Conversation? conversation;
  final User user;
  final String name;
  final String subtitle;
}

/// Enviar una publicación o un reel a varios chats: los recientes arriba y, al buscar, chats y personas. En los
/// chats cifrados la tarjeta viaja dentro del mensaje cifrado.
class SendPostScreen extends StatefulWidget {
  const SendPostScreen({super.key, required this.card, this.max = 10});

  final SharedPostRef card;
  final int max;

  @override
  State<SendPostScreen> createState() => _SendPostScreenState();
}

class _SendPostScreenState extends State<SendPostScreen> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  Timer? _debounce;
  List<_Target>? _items;
  Object? _error;
  int _request = 0;
  final Map<String, _Target> _selected = {};
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
    _note.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    try {
      final results = await Future.wait([
        api.get('conversations', q.isEmpty ? null : {'q': q}),
        api.get('messages/recipients', {if (q.isNotEmpty) 'q': q}),
      ]);
      final chats = results[0].list.map(Conversation.fromJson).where((c) => c.available && !c.blocked).toList();
      final known = {for (final c in chats) if (!c.isGroup) c.user.id};
      final me = mounted ? context.read<AppState>().me?.user.id : null;
      final items = <_Target>[
        for (final c in chats.take(20)) _Target.chat(c),
        for (final u in results[1].list.map(User.fromJson))
          if (!known.contains(u.id) && u.id != me) _Target.person(u),
      ];
      if (id == _request && mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  void _toggle(_Target t) {
    setState(() {
      if (_selected.containsKey(t.key)) {
        _selected.remove(t.key);
      } else if (_selected.length >= widget.max) {
        toast(context, tr('Puedes enviarlo a {max} chats a la vez como máximo.', {'max': widget.max}), error: true);
      } else {
        _selected[t.key] = t;
      }
    });
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final myId = context.read<AppState>().me?.user.id ?? 0;
    final out = Outgoing(text: _note.text.trim(), sharedPost: widget.card);
    final failed = <String, String>{};
    for (final t in _selected.values.toList()) {
      try {
        final c = t.conversation;
        await ChatSender.send(
          conversationId: c?.id,
          to: c == null ? t.user.username : null,
          chatEncrypted: c?.e2ee ?? false,
          myId: myId,
          out: out,
        );
        _selected.remove(t.key);
      } on ApiException catch (e) {
        failed[t.name] = e.message;
      } catch (_) {
        failed[t.name] = tr('No se pudo enviar.');
      }
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (failed.isEmpty) {
      toast(context, tr('Enviado.'));
      Navigator.pop(context);
      return;
    }
    final first = failed.entries.first;
    toast(context, tr('No se envió a {name}: {error}', {'name': first.key, 'error': first.value}), error: true);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final card = widget.card;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Enviar por mensaje'),
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tx.border)),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 56,
                child: card.thumbUrl != null && !card.isAdult
                    ? NetImage(card.thumbUrl, fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(gradient: Tx.storyBackground(card.background)),
                        child: Icon(card.isReel ? CupertinoIcons.play_fill : CupertinoIcons.text_alignleft, color: Colors.white, size: 18),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(card.isReel ? tr('Reel de {name}', {'name': card.user?.displayName ?? ''}) : (card.user?.displayName ?? ''),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, weight: FontWeight.w600)),
                if (card.body.isNotEmpty)
                  Text(card.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
              ]),
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
            decoration: fieldDecoration(tr('Buscar chats o personas'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : items == null
                  ? const Loading()
                  : items.isEmpty
                      ? EmptyState(icon: CupertinoIcons.person_crop_circle_badge_xmark, title: tr('Sin resultados'), message: tr('Busca por nombre o usuario.'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final t = items[i];
                            final on = _selected.containsKey(t.key);
                            return ListTile(
                              onTap: () => _toggle(t),
                              leading: Avatar(user: t.user, size: 44),
                              title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w600)),
                              subtitle: Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
                              trailing: Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: on ? Tx.accent : Tx.subtle, size: 24),
                            );
                          },
                        ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: TextField(
              controller: _note,
              maxLength: 500,
              minLines: 1,
              maxLines: 3,
              style: Tx.body(15),
              decoration: fieldDecoration(tr('Escribe un mensaje (opcional)')).copyWith(counterText: ''),
            ),
          ),
        ),
      ]),
    );
  }
}
