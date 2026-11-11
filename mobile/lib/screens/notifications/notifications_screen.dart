import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/background.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/push.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/paged_view.dart';
import '../home/home_shell.dart';
import '../music/artist_screen.dart';
import '../settings/account_status_screen.dart';
import '../settings/verification_screen.dart';
import '../wallet/collaborator_screen.dart';
import '../wallet/gifts_screen.dart';
import '../wallet/wallet_screen.dart';
import 'follow_requests_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';
  final Map<String, Paged<NotificationItem>> _lists = {};
  final _scroll = ScrollController();

  Paged<NotificationItem> get _list => _lists.putIfAbsent(
        _filter,
        () => Paged<NotificationItem>('notifications', NotificationItem.fromJson, query: {'filter': _filter}, onMeta: (meta) {
          if (meta['counts'] is Map && mounted) context.read<AppState>().setCounts(asMap(meta['counts']));
          final seen = _lists[_filter]?.items;
          if (seen != null && seen.isNotEmpty) BackgroundNotices.markSeen(notificationId: seen.first.id);
          AndroidPush.clearActivity();
        }),
      );

  @override
  void initState() {
    super.initState();
    tabReselect.addListener(_onReselect);
  }

  @override
  void dispose() {
    tabReselect.removeListener(_onReselect);
    _scroll.dispose();
    for (final l in _lists.values) {
      l.dispose();
    }
    super.dispose();
  }

  void _onReselect() {
    if (tabReselect.value != 3) return;
    if (_scroll.hasClients && _scroll.offset > 10) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _list.refresh();
    }
  }

  Future<void> _readAll() async {
    try {
      await api.post('notifications/read-all');
      for (final l in _lists.values) {
        for (final n in l.items) {
          n.read = true;
        }
        l.changed();
      }
      if (mounted) {
        context.read<AppState>().refreshCounts();
        toast(context, tr('Todo marcado como leído.'));
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _open(NotificationItem n) async {
    final wasUnread = !n.read;
    setState(() => n.read = true);
    Json target = {};
    try {
      final res = await api.post('notifications/${n.id}/read');
      target = asMap(res.map['target']);
      if (wasUnread && mounted) context.read<AppState>().refreshCounts();
    } catch (_) {}
    if (!mounted) return;
    if (n.isMusic) {
      if (n.type == 'song_approved' && n.songId != null && n.songId! > 0) {
        openSong(context, n.songId!);
      } else {
        push(context, const ArtistScreen());
      }
      return;
    }
    if (n.type == 'warning') {
      push(context, const AccountStatusScreen());
      return;
    }
    if (n.type.startsWith('verification_')) {
      push(context, const VerificationScreen());
      if (n.type == 'verification_approved') context.read<AppState>().refreshMe();
      return;
    }
    if (n.type.startsWith('topup_') || n.type.startsWith('withdrawal_') || n.type == 'wallet_adjusted') {
      push(context, const WalletScreen());
      return;
    }
    if (n.type == 'subscription') {
      push(context, const SubscribersScreen());
      return;
    }
    if (n.type == 'collaborator_enabled') {
      push(context, const CollaboratorScreen());
      return;
    }
    if (n.type == 'gift') {
      push(context, const GiftsScreen(tab: 'received'));
      return;
    }
    final storyOwner = asStrOrNull(target['username']) ?? n.actor?.username;
    if (n.type == 'new_story' && storyOwner != null) {
      openUserStories(context, storyOwner);
      return;
    }
    final postId = asIntOrNull(target['post_id']) ?? n.postId;
    final slug = asStrOrNull(target['community_slug']);
    final username = asStrOrNull(target['username']) ?? n.actor?.username;
    if (postId != null && postId > 0) {
      openPost(context, postId, comment: n.commentId != null);
    } else if (slug != null) {
      openCommunity(context, slug);
    } else if (username != null) {
      openProfile(context, username);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final list = _list;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Notificaciones'),
        showBack: false,
        actions: [
          IconButton(
            tooltip: tr('Marcar todo como leído'),
            onPressed: _readAll,
            icon: Icon(CupertinoIcons.checkmark_seal, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<NotificationItem>(
        paged: list,
        controller: _scroll,
        onRefresh: state.refreshCounts,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(children: [
                PillChip(label: tr('Todas'), selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                const SizedBox(width: 8),
                PillChip(label: tr('Menciones'), icon: CupertinoIcons.at, selected: _filter == 'mentions', onTap: () => setState(() => _filter = 'mentions')),
              ]),
            ),
          ),
          if (state.counts.followRequests > 0)
            SliverToBoxAdapter(
              child: Panel(
                gradient: true,
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                padding: const EdgeInsets.all(14),
                onTap: () => push(context, const FollowRequestsScreen()),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.person_badge_plus_fill, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Solicitudes de seguimiento'), style: Tx.body(15, weight: FontWeight.w600)),
                      Text(plural(state.counts.followRequests, 'solicitud pendiente', 'solicitudes pendientes'), style: Tx.body(13, color: Tx.muted)),
                    ]),
                  ),
                  CountBadge(state.counts.followRequests),
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_forward, color: Tx.subtle, size: 18),
                ]),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ],
        empty: EmptyState(
          icon: _filter == 'mentions' ? CupertinoIcons.at : CupertinoIcons.bell,
          title: _filter == 'mentions' ? tr('Sin menciones') : tr('Todo al día'),
          message: _filter == 'mentions' ? tr('Cuando alguien te mencione, aparecerá aquí.') : tr('Aquí verás los me gusta, comentarios y nuevos seguidores.'),
        ),
        itemBuilder: (context, n, _) => _NotificationTile(item: n, onTap: () => _open(n)),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  static IconData _icon(String type) => switch (type) {
        'like' => CupertinoIcons.heart_fill,
        'comment' || 'reply' => CupertinoIcons.chat_bubble_fill,
        'mention' => CupertinoIcons.at,
        'share' => CupertinoIcons.arrow_2_squarepath,
        'follow' || 'follow_accepted' => CupertinoIcons.person_fill,
        'community_request' || 'community_accepted' => CupertinoIcons.person_3_fill,
        'song_approved' => CupertinoIcons.checkmark_alt,
        'song_rejected' || 'song_removed' => CupertinoIcons.xmark,
        'warning' => CupertinoIcons.exclamationmark,
        'verification_approved' => CupertinoIcons.checkmark_seal_fill,
        'verification_rejected' => CupertinoIcons.xmark,
        'subscription' => CupertinoIcons.star_fill,
        'topup_approved' || 'withdrawal_paid' || 'wallet_adjusted' => CupertinoIcons.money_dollar,
        'topup_rejected' || 'withdrawal_rejected' => CupertinoIcons.xmark,
        'collaborator_enabled' => CupertinoIcons.star_circle_fill,
        'gift' => CupertinoIcons.gift_fill,
        'new_post' => CupertinoIcons.bell_fill,
        'new_note' => CupertinoIcons.doc_text_fill,
        'new_story' => CupertinoIcons.circle_grid_hex_fill,
        _ => CupertinoIcons.bell_fill,
      };

  static List<Color> _colors(String type) => switch (type) {
        'like' => const [Tx.danger, Color(0xFFEC4899)],
        'comment' || 'reply' || 'mention' => const [Tx.blue, Tx.cyan],
        'share' => const [Tx.success, Color(0xFF0EA5E9)],
        'song_approved' => const [Tx.success, Color(0xFF14B8A6)],
        'song_rejected' || 'song_removed' || 'warning' || 'verification_rejected' || 'topup_rejected' || 'withdrawal_rejected' => const [Tx.warning, Tx.danger],
        'verification_approved' => const [Tx.blue, Tx.cyan],
        'subscription' || 'collaborator_enabled' => const [Tx.warning, Color(0xFFF97316)],
        'topup_approved' || 'withdrawal_paid' || 'wallet_adjusted' => const [Tx.success, Color(0xFF14B8A6)],
        'gift' => const [Color(0xFFF59E0B), Color(0xFFEC4899)],
        _ => const [Tx.purple500, Tx.blue],
      };

  @override
  Widget build(BuildContext context) {
    final actor = item.actor;
    final system = actor == null && !item.isMusic;
    final colors = _colors(item.type);
    final badge = Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2)),
      child: Icon(_icon(item.type), color: Colors.white, size: 11),
    );
    return Material(
      color: item.read ? Colors.transparent : Tx.alpha(Tx.purple, .07),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 50,
              height: 50,
              child: Stack(clipBehavior: Clip.none, children: [
                if (actor != null)
                  Avatar(user: actor, size: 46, onTap: () => openProfile(context, actor.username))
                else
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(gradient: LinearGradient(colors: colors), shape: BoxShape.circle),
                    child: Icon(system ? CupertinoIcons.shield_lefthalf_fill : CupertinoIcons.music_note_2, color: Colors.white, size: 22),
                  ),
                Positioned(right: 0, bottom: 0, child: badge),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(style: Tx.body(14.5, height: 1.35), children: [
                    if (actor != null) TextSpan(text: actor.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (system) const TextSpan(text: 'TREVIX', style: TextStyle(fontWeight: FontWeight.w700)),
                    if (actor != null || system) const TextSpan(text: ' '),
                    TextSpan(text: item.text),
                    TextSpan(text: '  ${timeAgo(item.createdAt)}', style: Tx.body(12.5, color: Tx.subtle)),
                  ]),
                ),
                if (item.excerpt != null && item.excerpt!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.excerpt!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.muted, height: 1.35)),
                ],
                if (item.type == 'follow' && actor != null) ...[
                  const SizedBox(height: 8),
                  FollowButton(user: actor, height: 32),
                ],
              ]),
            ),
            if (item.thumbUrl != null) ...[
              const SizedBox(width: 10),
              NetImage(item.thumbUrl, width: 48, height: 48, radius: 10),
            ],
            if (!item.read && item.thumbUrl == null)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 6),
                width: 9,
                height: 9,
                decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
              ),
          ]),
        ),
      ),
    );
  }
}
