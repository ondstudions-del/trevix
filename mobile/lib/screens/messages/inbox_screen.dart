import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/private_chats.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';
import 'chat_style.dart';
import 'e2ee_screens.dart';
import 'group_screens.dart';
import 'new_message_screen.dart';
import 'private_chats_screens.dart';

/// Bandeja de chats al estilo Messenger: título grande, personas activas, filtros y grupos.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

enum _Filter { all, unread, favorites, groups }

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
  final Set<int> _selected = {};
  bool _busy = false;
  int _maxPinned = 3;

  String get _term => _search.text.trim();
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh(silent: true));
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
      final unlock = asStrOrNull(res.meta['private_token']);
      if (unlock != null && unlock.isNotEmpty) {
        _loading = false;
        unawaited(_openPrivate(unlock, res.list.map(Conversation.fromJson).toList()));
        return;
      }
      setState(() {
        _items = res.list.map(Conversation.fromJson).toList();
        _maxPinned = asInt(res.meta['max_pinned_chats'], _maxPinned);
        _selected.retainAll(_items.map((c) => c.id));
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

  /// El buscador recibió el PIN de los chats privados: se borra de la caja y se abren los privados.
  Future<void> _openPrivate(String token, List<Conversation> items) async {
    _debounce?.cancel();
    _search.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    privateChats.unlock(token);
    HapticFeedback.mediumImpact();
    setState(_selected.clear);
    await push(context, PrivateChatsScreen(initial: items));
    privateChats.lock();
    _refresh(silent: true);
  }

  Future<void> _newGroup() async {
    await push(context, const CreateGroupScreen());
    _refresh(silent: true);
  }

  void _composeMenu() {
    actionSheet(context, [
      SheetAction(tr('Nuevo mensaje'), CupertinoIcons.square_pencil, () async {
        await push(context, const NewMessageScreen());
        _refresh(silent: true);
      }),
      SheetAction(tr('Nuevo grupo'), CupertinoIcons.person_3, _newGroup),
      SheetAction(tr('Buscar grupos públicos'), CupertinoIcons.globe, () => push(context, const PublicGroupsScreen())),
      SheetAction(tr('Cifrado de los chats'), CupertinoIcons.lock_shield, () => push(context, const E2eeSettingsScreen())),
    ]);
  }

  // ---- Selección de chats (mantener pulsado) ----

  void _toggleSelect(Conversation c) {
    setState(() => _selected.contains(c.id) ? _selected.remove(c.id) : _selected.add(c.id));
  }

  List<Conversation> get _chosen => _items.where((c) => _selected.contains(c.id)).toList();

  /// Aplica una acción a los chats elegidos (fijar, silenciar, leído, favoritos, vaciar o eliminar).
  Future<void> _bulk(String action) async {
    final chosen = _chosen;
    if (chosen.isEmpty || _busy) return;
    final many = chosen.length > 1;
    if (action == 'pin') {
      final pinnedElsewhere = _items.where((c) => c.pinnedChat && !_selected.contains(c.id)).length;
      if (pinnedElsewhere + chosen.length > _maxPinned) {
        toast(context, tr('Puedes fijar hasta {max} chats. Desfija alguno primero.', {'max': _maxPinned}), error: true);
        return;
      }
    }
    if (action == 'clear' || action == 'delete') {
      final groups = chosen.any((c) => c.isGroup);
      final ok = action == 'clear'
          ? await confirm(
              context,
              many ? tr('¿Vaciar {n} chats?', {'n': chosen.length}) : tr('¿Vaciar este chat?'),
              tr('Se borrarán los mensajes solo para ti; los demás los seguirán viendo.'),
              action: tr('Vaciar'),
              destructive: true,
            )
          : await confirm(
              context,
              many ? tr('¿Eliminar {n} chats?', {'n': chosen.length}) : tr('¿Eliminar este chat?'),
              groups
                  ? tr('Desaparecerá de tu bandeja y se borrarán sus mensajes solo para ti. Si te vuelven a escribir, aparecerá de nuevo. Seguirás en los grupos; para salir usa «Salir del grupo».')
                  : tr('Desaparecerá de tu bandeja y se borrarán sus mensajes solo para ti. Si te vuelven a escribir, aparecerá de nuevo.'),
              action: tr('Eliminar'),
              destructive: true,
            );
      if (!ok || !mounted) return;
    }
    if (action == 'private') {
      try {
        if (!await ensurePrivatePin(context) || !mounted) return;
      } catch (e) {
        if (mounted) toastError(context, e);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final res = await api.post('conversations/bulk', {'ids': chosen.map((c) => c.id).toList(), 'action': action});
      if (!mounted) return;
      toast(
        context,
        action == 'private'
            ? tr('Para verlos, escribe tu PIN en el buscador de los chats.')
            : '${res.map['message'] ?? tr('Listo.')}',
      );
      setState(_selected.clear);
      await _refresh(silent: true);
      if (mounted) context.read<AppState>().refreshCounts();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  List<Conversation> get _visible => switch (_filter) {
        _Filter.all => _items,
        _Filter.unread => _items.where((c) => c.unread > 0).toList(),
        _Filter.favorites => _items.where((c) => c.favorite).toList(),
        _Filter.groups => _items.where((c) => c.isGroup).toList(),
      };

  Widget _selectionBar() {
    final chosen = _chosen;
    final allPinned = chosen.isNotEmpty && chosen.every((c) => c.pinnedChat);
    final allMuted = chosen.isNotEmpty && chosen.every((c) => c.muted);
    final allFavorite = chosen.isNotEmpty && chosen.every((c) => c.favorite);
    final enabled = chosen.isNotEmpty && !_busy;
    Widget item(IconData icon, String label, String action, {bool danger = false}) => Expanded(
          child: InboxBarAction(icon: icon, label: label, danger: danger, onTap: enabled ? () => _bulk(action) : null),
        );
    return Container(
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            item(allPinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin, allPinned ? tr('Desfijar') : tr('Fijar'), allPinned ? 'unpin' : 'pin'),
            item(allMuted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, allMuted ? tr('Reactivar') : tr('Silenciar'), allMuted ? 'unmute' : 'mute'),
            item(CupertinoIcons.checkmark_circle, tr('Leído'), 'read'),
            item(CupertinoIcons.lock, tr('Privado'), 'private'),
            item(allFavorite ? CupertinoIcons.star_slash : CupertinoIcons.star, allFavorite ? tr('Quitar') : tr('Favorito'), allFavorite ? 'unfavorite' : 'favorite'),
            item(CupertinoIcons.text_badge_xmark, tr('Vaciar'), 'clear', danger: true),
            item(CupertinoIcons.trash, tr('Eliminar'), 'delete', danger: true),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _items.where((c) => !c.isGroup && c.online && c.available && !c.blocked).toList();
    final unread = _items.where((c) => c.unread > 0).length;
    final visible = _visible;
    final favorites = _items.where((c) => c.favorite).length;
    final allSelected = visible.isNotEmpty && visible.every((c) => _selected.contains(c.id));
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? GlassBar(
                leading: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => setState(_selected.clear),
                  child: Icon(CupertinoIcons.xmark, color: Tx.text, size: 24),
                ),
                titleWidget:
                    Text(_selected.length == 1 ? tr('1 seleccionado') : tr('{n} seleccionados', {'n': _selected.length}), style: Tx.display(18, weight: FontWeight.w700)),
                actions: [
                  TextButton(
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.removeAll(visible.map((c) => c.id));
                      } else {
                        _selected.addAll(visible.map((c) => c.id));
                      }
                    }),
                    child: Text(allSelected ? tr('Ninguno') : tr('Seleccionar todos'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent)),
                  ),
                ],
              )
            : GlassBar(
                titleWidget: Text(tr('Chats'), style: Tx.display(26, weight: FontWeight.w800)),
                actions: [
                  IconButton(onPressed: _newGroup, tooltip: tr('Nuevo grupo'), icon: Icon(CupertinoIcons.person_3_fill, color: Tx.text, size: 26)),
                  IconButton(onPressed: _composeMenu, tooltip: tr('Nuevo'), icon: Icon(CupertinoIcons.square_pencil, color: Tx.text)),
                ],
              ),
        bottomNavigationBar: _selecting ? _selectionBar() : null,
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
                          hintText: tr('Buscar'),
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
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10), child: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18)),
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
                        label: tr('Nuevo grupo'),
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
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Row(children: [
                    _FilterChip(label: tr('Todos los chats'), selected: _filter == _Filter.all, onTap: () => setState(() => _filter = _Filter.all)),
                    _FilterChip(
                      label: unread > 0 ? tr('No leídos ({n})', {'n': unread}) : tr('No leídos'),
                      selected: _filter == _Filter.unread,
                      onTap: () => setState(() => _filter = _Filter.unread),
                    ),
                    _FilterChip(
                      label: favorites > 0 ? tr('Favoritos ({n})', {'n': favorites}) : tr('Favoritos'),
                      selected: _filter == _Filter.favorites,
                      onTap: () => setState(() => _filter = _Filter.favorites),
                    ),
                    _FilterChip(label: tr('Grupos'), selected: _filter == _Filter.groups, onTap: () => setState(() => _filter = _Filter.groups)),
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
                    ? EmptyState(icon: CupertinoIcons.search, title: tr('Sin resultados'), message: tr('Ningún chat ni mensaje coincide con «{term}».', {'term': _term}))
                    : _filter == _Filter.groups
                        ? EmptyState(
                            icon: CupertinoIcons.person_3,
                            title: tr('Sin grupos'),
                            message: tr('Crea un grupo o únete con un enlace de invitación.'),
                            action: GradientButton(label: tr('Nuevo grupo'), icon: CupertinoIcons.person_3, expand: false, onPressed: _newGroup),
                          )
                        : _filter == _Filter.unread
                            ? EmptyState(icon: CupertinoIcons.checkmark_circle, title: tr('Todo leído'), message: tr('No tienes chats sin leer.'))
                            : _filter == _Filter.favorites
                                ? EmptyState(
                                    icon: CupertinoIcons.star,
                                    title: tr('Sin favoritos'),
                                    message: tr('Mantén pulsado un chat y toca «Favorito» para tenerlo a mano aquí.'),
                                  )
                                : EmptyState(
                                    icon: CupertinoIcons.chat_bubble_2,
                                    title: tr('Tu bandeja está vacía'),
                                    message: tr('Escribe a alguien para empezar una conversación.'),
                                    action: GradientButton(
                                      label: tr('Nuevo mensaje'),
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
                  return ConversationTile(
                    conversation: c,
                    term: _term,
                    selecting: _selecting,
                    selected: _selected.contains(c.id),
                    onTap: () => _selecting ? _toggleSelect(c) : _open(c),
                    onLongPress: () {
                      HapticFeedback.selectionClick();
                      _toggleSelect(c);
                    },
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ]),
        ),
      ),
    );
  }
}

class InboxBarAction extends StatelessWidget {
  const InboxBarAction({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Tx.subtle : (danger ? Tx.danger : Tx.text);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 3),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11, weight: FontWeight.w600, color: color)),
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

class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.term,
    required this.onTap,
    required this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  final Conversation conversation;
  final String term;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0 && !c.muted;
    final match = term.isNotEmpty ? c.searchMatch : null;
    final preview = c.blocked ? tr('No disponible') : (c.preview.isEmpty ? (c.isGroup ? tr('Grupo creado') : tr('Empieza la conversación')) : c.preview);
    final textColor = unread ? Tx.text : Tx.muted;
    final accent = ChatPalette.of(c.theme).accent;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        color: selected ? Tx.alpha(Tx.accent, .12) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            child: selecting
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                      color: selected ? Tx.accent : Tx.subtle,
                      size: 24,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          ChatAvatar(conversation: c, size: 58, online: c.online && c.available && !c.isGroup),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child:
                      Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(16, weight: c.unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (!c.isGroup && c.user.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                if (c.e2ee) ...[const SizedBox(width: 5), Icon(CupertinoIcons.lock_fill, size: 11, color: Tx.subtle)],
                if (c.favorite) ...[const SizedBox(width: 5), const Icon(CupertinoIcons.star_fill, size: 12, color: Color(0xFFFBBF24))],
              ]),
              const SizedBox(height: 3),
              if (match != null)
                Row(children: [
                  Icon(CupertinoIcons.search, size: 13, color: Tx.accent),
                  const SizedBox(width: 4),
                  Expanded(child: Text(match, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: Tx.text))),
                ])
              else if (c.typing)
                Text(tr('escribiendo…'), maxLines: 1, style: Tx.body(14, weight: FontWeight.w600, color: accent))
              else
                Row(children: [
                  if (c.disappearSeconds > 0) ...[Icon(CupertinoIcons.timer, size: 13, color: textColor), const SizedBox(width: 4)],
                  Flexible(
                    child: Text(preview,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, color: textColor, weight: unread ? FontWeight.w700 : FontWeight.w400)),
                  ),
                  if (c.lastMessageAt != null)
                    Text(' · ${timeAgo(c.lastMessageAt)}', style: Tx.body(14, color: textColor, weight: unread ? FontWeight.w700 : FontWeight.w400)),
                ]),
            ]),
          ),
          const SizedBox(width: 10),
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (c.pinnedChat) Icon(CupertinoIcons.pin_fill, size: 15, color: Tx.subtle),
            if (c.pinnedChat && (c.muted || c.unread > 0)) const SizedBox(height: 6),
            if (c.muted)
              Icon(CupertinoIcons.bell_slash_fill, size: 16, color: Tx.subtle)
            else if (c.unread > 0)
              Container(width: 12, height: 12, decoration: BoxDecoration(gradient: ChatPalette.of(c.theme).gradient, shape: BoxShape.circle)),
          ]),
        ]),
      ),
    );
  }
}
