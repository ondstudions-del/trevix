import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import 'chat_screen.dart';
import 'new_message_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _list = Paged<Conversation>('conversations', Conversation.fromJson);
  final _search = TextEditingController();
  Timer? _poll;
  Timer? _debounce;

  String get _term => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    if (!mounted || _list.loading) return;
    await _list.refresh();
    if (mounted) context.read<AppState>().refreshCounts();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final term = value.trim();
      _list.query = term.isEmpty ? {} : {'q': term};
      _list.refresh();
      if (mounted) setState(() {});
    });
  }

  Future<void> _open(Conversation c) async {
    await push(context, ChatScreen(conversationId: c.id, user: c.user));
    _silentRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: 'Mensajes',
        actions: [
          IconButton(
            onPressed: () async {
              await push(context, const NewMessageScreen());
              _silentRefresh();
            },
            icon: Icon(CupertinoIcons.square_pencil, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<Conversation>(
        paged: _list,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: TextField(
                controller: _search,
                onChanged: _onSearch,
                textInputAction: TextInputAction.search,
                style: Tx.body(15),
                decoration: fieldDecoration(
                  'Buscar chats o mensajes',
                  prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20),
                  suffix: _term.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _search.clear();
                            _onSearch('');
                          },
                          icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                        ),
                ),
              ),
            ),
          ),
        ],
        empty: _term.isNotEmpty
            ? EmptyState(icon: CupertinoIcons.search, title: 'Sin resultados', message: 'Ningún chat ni mensaje coincide con «$_term».')
            : EmptyState(
                icon: CupertinoIcons.chat_bubble_2,
                title: 'Tu bandeja está vacía',
                message: 'Escribe a alguien para empezar una conversación.',
                action: GradientButton(
                  label: 'Nuevo mensaje',
                  icon: CupertinoIcons.square_pencil,
                  expand: false,
                  onPressed: () => push(context, const NewMessageScreen()),
                ),
              ),
        itemBuilder: (context, c, _) => _ConversationTile(conversation: c, term: _term, onTap: () => _open(c)),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.term, required this.onTap});

  final Conversation conversation;
  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    final match = term.isNotEmpty ? c.searchMatch : null;
    final weight = unread ? FontWeight.w700 : FontWeight.w600;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(user: c.user, size: 54, online: c.online && c.available),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if ((c.nickname ?? '').isNotEmpty)
                  Flexible(child: Text(c.nickname!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: weight)))
                else
                  Flexible(child: NameLine(user: c.user, weight: weight)),
                if (c.disappearSeconds > 0) ...[const SizedBox(width: 6), Icon(CupertinoIcons.timer, size: 13, color: Tx.subtle)],
                if (c.muted) ...[const SizedBox(width: 6), Icon(CupertinoIcons.bell_slash_fill, size: 13, color: Tx.subtle)],
              ]),
              const SizedBox(height: 3),
              if (match != null)
                Row(children: [
                  Icon(CupertinoIcons.search, size: 13, color: Tx.accent),
                  const SizedBox(width: 4),
                  Expanded(child: Text(match, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.text))),
                ])
              else
                Text(
                  c.blocked ? 'No disponible' : (c.preview.isEmpty ? 'Empieza la conversación' : c.preview),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tx.body(14, color: unread ? Tx.text : Tx.muted, weight: unread ? FontWeight.w600 : FontWeight.w400),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(timeAgo(c.lastMessageAt), style: Tx.body(12, color: unread ? Tx.accent : Tx.subtle)),
            const SizedBox(height: 6),
            if (unread) CountBadge(c.unread) else const SizedBox(height: 18),
          ]),
        ]),
      ),
    );
  }
}
