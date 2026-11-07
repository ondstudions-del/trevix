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
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _list.dispose();
    super.dispose();
  }

  Future<void> _silentRefresh() async {
    if (!mounted || _list.loading) return;
    await _list.refresh();
    if (mounted) context.read<AppState>().refreshCounts();
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
            icon: const Icon(CupertinoIcons.square_pencil, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<Conversation>(
        paged: _list,
        header: const [SliverToBoxAdapter(child: SizedBox(height: 6))],
        empty: EmptyState(
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
        itemBuilder: (context, c, _) => _ConversationTile(conversation: c, onTap: () => _open(c)),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
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
                Flexible(child: NameLine(user: c.user, weight: unread ? FontWeight.w700 : FontWeight.w600)),
                if (c.muted) ...[const SizedBox(width: 6), const Icon(CupertinoIcons.bell_slash_fill, size: 13, color: Tx.subtle)],
              ]),
              const SizedBox(height: 3),
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
            Text(timeAgo(c.lastMessageAt), style: Tx.body(12, color: unread ? Tx.purple300 : Tx.subtle)),
            const SizedBox(height: 6),
            if (unread) CountBadge(c.unread) else const SizedBox(height: 18),
          ]),
        ]),
      ),
    );
  }
}