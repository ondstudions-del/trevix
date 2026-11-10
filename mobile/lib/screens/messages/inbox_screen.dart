import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';
import 'chat_style.dart';
import 'e2ee_screens.dart';
import 'group_screens.dart';
import 'new_message_screen.dart';

/// Bandeja de chats al estilo Messenger: título grande, personas activas, filtros y grupos.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

enum _Filter { all, unread, groups }

class _InboxScreenState extends State<InboxScreen> {
  final _search = TextEditingController();
  List<Conversation> _items = [];
  bool _loaded = false;
  bool _loading = false;
  Object? _error;
  _Filter _filter = _Filter.all;
  Timer? _poll;
  Timer? _debounce;
  int _request = 0;

  String get _term => _search.text.trim();

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh(silent: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerE2ee(context);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (silent && _loading) return;
    final id = ++_request;
    _loading = true;
    if (!silent) setState(() => _error = null);
    try {
      final res = await api.get('conversations', _term.isEmpty ? null : {'q': _term});
      if (id != _request || !mounted) return;
      setState(() {
        _items = res.list.map(Conversation.fromJson).toList();
        _loaded = true;
        _error = null;
      });
      if (silent) context.read<AppState>().refreshCounts();
    } catch (e) {
      if (id == _request && mounted && !silent) setState(() => _error = e);
    }
    _loading = false;
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _refresh();
      if (mounted) setState(() {});
    });
  }

  Future<void> _open(Conversation c) async {
    await push(context, ChatScreen(conversationId: c.id, user: c.user, conversation: c));
    _refresh(silent: true);
  }

  Future<void> _newGroup() async {
    await push(context, const CreateGroupScreen());
    _refresh(silent: true);
  }

  void _composeMenu() {
    actionSheet(context, [
      SheetAction('Nuevo mensaje', CupertinoIcons.square_pencil, () async {
        await push(context, const NewMessageScreen());
        _refresh(silent: true);
      }),
      SheetAction('Nuevo grupo', CupertinoIcons.person_3, _newGroup),
      SheetAction('Buscar grupos públicos', CupertinoIcons.globe, () => push(context, const PublicGroupsScreen())),
      SheetAction('Cifrado de los chats', CupertinoIcons.lock_shield, () => push(context, const E2eeSettingsScreen())),
    ]);
  }

  Future<void> _tileMenu(Conversation c) async {
    await actionSheet(context, [
      SheetAction(c.muted ? 'Activar avisos' : 'Silenciar', c.muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, () async {
        try {
          await api.patch('conversations/${c.id}', {'muted': !c.muted});
          if (!mounted) return;
          setState(() => c.muted = !c.muted);
          context.read<AppState>().refreshCounts();
        } catch (e) {
          if (mounted) toastError(context, e);
        }
      }),
      if (c.unread > 0)
        SheetAction('Marcar como leído', CupertinoIcons.checkmark_circle, () async {
          try {
            await api.post('conversations/${c.id}/read');
            if (!mounted) return;
            setState(() => c.unread = 0);
            context.read<AppState>().refreshCounts();
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }),
    ], title: c.title);
  }

  List<Conversation> get _visible => switch (_filter) {
        _Filter.all => _items,
        _Filter.unread => _items.where((c) => c.unread > 0).toList(),
        _Filter.groups => _items.where((c) => c.isGroup).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final active = _items.where((c) => !c.isGroup && c.online && c.available && !c.blocked).toList();
    final unread = _items.where((c) => c.unread > 0).length;
    final visible = _visible;
    return Scaffold(
      appBar: GlassBar(
        titleWidget: Text('Chats', style: Tx.display(26, weight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: _newGroup, tooltip: 'Nuevo grupo', icon: Icon(CupertinoIcons.person_3_fill, color: Tx.text, size: 26)),
          IconButton(onPressed: _composeMenu, tooltip: 'Nuevo', icon: Icon(CupertinoIcons.square_pencil, color: Tx.text)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Container(
                height: 40,
                decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(CupertinoIcons.search, color: Tx.subtle, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: _onSearch,
                      textInputAction: TextInputAction.search,
                      style: Tx.body(15.5),
                      decoration: InputDecoration(
                        hintText: 'Buscar',
                        hintStyle: Tx.body(15.5, color: Tx.subtle),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_term.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _search.clear();
                        _onSearch('');
                      },
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18)),
                    ),
                ]),
              ),
            ),
          ),
          if (_term.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 104,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  children: [
                    _ActiveItem(
                      label: 'Nuevo grupo',
                      onTap: _newGroup,
                      avatar: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(color: Tx.surface2, shape: BoxShape.circle),
                        child: Icon(CupertinoIcons.add, color: Tx.text, size: 26),
                      ),
                    ),
                    for (final c in active)
                      _ActiveItem(
                        label: c.title.split(' ').first,
                        onTap: () => _open(c),
                        avatar: Avatar(user: c.user, size: 58, online: true),
                      ),
                  ],
                ),
              ),
            ),
          if (_term.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                child: Row(children: [
                  _FilterChip(label: 'Todos', selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
                  _FilterChip(
                    label: unread > 0 ? 'No leídos ($unread)' : 'No leídos',
                    selected: _filter == _Filter.unread,
                    onTap: () => setState(() => _filter = _Filter.unread),
                  ),
                  _FilterChip(label: 'Grupos', selected: _filter == _Filter.groups, onTap: () => setState(() => _filter = _Filter.groups)),
                ]),
              ),
            ),
          if (_error != null && !_loaded)
            SliverFillRemaining(hasScrollBody: false, child: ErrorState(error: _error!, onRetry: _refresh))
          else if (!_loaded)
            const SliverFillRemaining(hasScrollBody: false, child: Loading())
          else if (visible.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _term.isNotEmpty
                  ? EmptyState(icon: CupertinoIcons.search, title: 'Sin resultados', message: 'Ningún chat ni mensaje coincide con «$_term».')
                  : _filter == _Filter.groups
                      ? EmptyState(
                          icon: CupertinoIcons.person_3,
                          title: 'Sin grupos',
                          message: 'Crea un grupo o únete con un enlace de invitación.',
                          action: GradientButton(label: 'Nuevo grupo', icon: CupertinoIcons.person_3, expand: false, onPressed: _newGroup),
                        )
                      : _filter == _Filter.unread
                          ? const EmptyState(icon: CupertinoIcons.checkmark_circle, title: 'Todo leído', message: 'No tienes chats sin leer.')
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
            )
          else
            SliverList.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final c = visible[i];
                return _ConversationTile(conversation: c, term: _term, onTap: () => _open(c), onLongPress: () => _tileMenu(c));
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ]),
      ),
    );
  }
}

class _ActiveItem extends StatelessWidget {
  const _ActiveItem({required this.label, required this.avatar, required this.onTap});

  final String label;
  final Widget avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Column(children: [
          avatar,
          const SizedBox(height: 6),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(12, color: Tx.muted)),
        ]),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Tx.alpha(Tx.accent, .18) : Tx.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: selected ? Tx.accent : Tx.text)),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.term, required this.onTap, required this.onLongPress});

  final Conversation conversation;
  final String term;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0 && !c.muted;
    final match = term.isNotEmpty ? c.searchMatch : null;
    final preview = c.blocked ? 'No disponible' : (c.preview.isEmpty ? (c.isGroup ? 'Grupo creado' : 'Empieza la conversación') : c.preview);
    final textColor = unread ? Tx.text : Tx.muted;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          ChatAvatar(conversation: c, size: 58, online: c.online && c.available && !c.isGroup),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(16, weight: c.unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (!c.isGroup && c.user.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                if (c.e2ee) ...[const SizedBox(width: 5), Icon(CupertinoIcons.lock_fill, size: 11, color: Tx.subtle)],
              ]),
              const SizedBox(height: 3),
              if (match != null)
                Row(children: [
                  Icon(CupertinoIcons.search, size: 13, color: Tx.accent),
                  const SizedBox(width: 4),
                  Expanded(child: Text(match, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.text))),
                ])
              else
                Row(children: [
                  if (c.disappearSeconds > 0) ...[Icon(CupertinoIcons.timer, size: 13, color: textColor), const SizedBox(width: 4)],
                  Flexible(
                    child: Text(preview,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: textColor, weight: unread ? FontWeight.w700 : FontWeight.w400)),
                  ),
                  if (c.lastMessageAt != null) Text(' · ${timeAgo(c.lastMessageAt)}', style: Tx.body(14, color: textColor, weight: unread ? FontWeight.w700 : FontWeight.w400)),
                ]),
            ]),
          ),
          const SizedBox(width: 10),
          if (c.muted)
            Icon(CupertinoIcons.bell_slash_fill, size: 16, color: Tx.subtle)
          else if (c.unread > 0)
            Container(width: 12, height: 12, decoration: BoxDecoration(gradient: ChatPalette.of(c.theme).gradient, shape: BoxShape.circle)),
        ]),
      ),
    );
  }
}
