import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/events.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/logo.dart';
import '../../widgets/note_bubble.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/post_card.dart';
import '../../widgets/profile_about.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/song_chip.dart';
import '../explore/explore_screen.dart';
import '../home/home_shell.dart';
import '../messages/chat_screen.dart';
import '../notes/note_sheets.dart';
import '../settings/settings_screen.dart';
import '../stories/story_viewer.dart';
import 'edit_profile_screen.dart';
import 'follow_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.username, this.asTab = false});

  final String username;
  final bool asTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Profile? _profile;
  Object? _error;
  String _tab = 'posts';
  final Map<String, Paged<dynamic>> _lists = {};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    notesChanged.addListener(_load);
    if (widget.asTab) {
      tabReselect.addListener(_onReselect);
      postCreated.addListener(_onCreated);
    }
  }

  @override
  void dispose() {
    tabReselect.removeListener(_onReselect);
    postCreated.removeListener(_onCreated);
    notesChanged.removeListener(_load);
    final id = _profile?.user.id;
    if (id != null && songPlayer.currentKey == 'profile:$id') songPlayer.stop();
    _scroll.dispose();
    for (final l in _lists.values) {
      l.dispose();
    }
    super.dispose();
  }

  void _onReselect() {
    if (tabReselect.value == 4 && _scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    }
  }

  void _onCreated() {
    final post = postCreated.value;
    if (post == null) return;
    final key = post.isThread ? 'threads' : 'posts';
    final list = _lists[key];
    if (list != null && list.loaded) list.insert(post);
    if (post.media.isNotEmpty) _lists['media']?.insert(post);
  }

  Future<void> _load() async {
    try {
      final res = await api.get('users/${Uri.encodeComponent(widget.username)}');
      if (!mounted) return;
      setState(() {
        _profile = Profile.fromJson(res.map);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refresh() async {
    await _load();
    await _list(_tab).refresh();
  }

  Paged<dynamic> _list(String tab) => _lists.putIfAbsent(tab, () {
        final u = Uri.encodeComponent(widget.username);
        switch (tab) {
          case 'music':
            return Paged<dynamic>('users/$u/music', Song.fromJson);
          case 'saved':
            return Paged<dynamic>('me/saved', Post.fromJson);
          default:
            return Paged<dynamic>('users/$u/posts', Post.fromJson, query: {'tab': tab});
        }
      });

  Map<String, String> _tabs(Profile p) => {
        'posts': tr('Publicaciones'),
        'threads': tr('Hilos'),
        'media': tr('Multimedia'),
        if (p.user.isMusicArtist) 'music': tr('Música'),
        if (p.isOwn) 'saved': tr('Guardados'),
      };

  Future<void> _openStories(Profile p) async {
    try {
      final res = await api.get('users/${Uri.encodeComponent(p.user.username)}/stories');
      if (res.data is! Map || !mounted) return;
      final group = StoryGroup.fromJson(res.map);
      if (group.items.isEmpty) return;
      await pushFade(context, StoryViewer(groups: [group]));
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _message(Profile p) {
    final reason = p.messageBlockedReason;
    if (p.conversationId == null && reason != null) {
      toast(context, reason, error: true);
      return;
    }
    push(context, ChatScreen(conversationId: p.conversationId, user: p.user));
  }

  Future<void> _toggleBlock(Profile p) async {
    final blocking = !p.isBlocked;
    if (blocking &&
        !await confirm(context, tr('Bloquear a @{username}', {'username': p.user.username}), tr('No podrá ver tu perfil ni escribirte, y dejarán de seguirse mutuamente.'),
            action: tr('Bloquear'), destructive: true)) {
      return;
    }
    try {
      final res = blocking ? await api.post('users/${p.user.id}/block') : await api.delete('users/${p.user.id}/block');
      if (mounted) toast(context, '${res.map['message'] ?? (blocking ? tr('Bloqueaste la cuenta.') : tr('Desbloqueaste la cuenta.'))}');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _removeFollower(Profile p) async {
    if (!await confirm(context, tr('Quitar seguidor'), tr('@{username} dejará de seguirte. No se le notificará.', {'username': p.user.username}), action: tr('Quitar'), destructive: true)) return;
    try {
      final res = await api.delete('users/${p.user.id}/follower');
      if (mounted) toast(context, '${res.map['message'] ?? tr('Quitaste a este seguidor.')}');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _warn(Profile p) async {
    final reason = await prompt(
      context,
      tr('Advertir a @{username}', {'username': p.user.username}),
      hint: tr('Motivo (lo verá la persona)'),
      action: tr('Advertir'),
      maxLength: 255,
      message: tr('Recibirá un aviso con el motivo y no podrá pedir el verificado durante 30 días. Quedará registrado en la auditoría.'),
    );
    if (reason == null || !mounted) return;
    try {
      final res = await api.post('admin/users/${p.user.id}/warn', {'reason': reason});
      if (mounted) toast(context, '${res.map['message'] ?? tr('Advertencia enviada.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _menu(Profile p) {
    final me = context.read<AppState>().me;
    final canWarn = !p.isOwn && me != null && me.isStaff && (me.isAdmin ? p.user.role != 'admin' : !p.user.isStaffRole);
    actionSheet(context, [
      SheetAction(tr('Compartir perfil'), CupertinoIcons.share,
          () => showShareSheet(context, url: p.webUrl, title: tr('{name} (@{username}) en TREVIX', {'name': p.user.displayName, 'username': p.user.username}))),
      SheetAction(tr('Copiar enlace'), CupertinoIcons.link, () {
        Clipboard.setData(ClipboardData(text: p.webUrl));
        toast(context, tr('Enlace copiado.'));
      }),
      if (!p.isOwn && (p.user.relation?.followsYou ?? false))
        SheetAction(tr('Quitar de mis seguidores'), CupertinoIcons.person_crop_circle_badge_minus, () => _removeFollower(p)),
      if (!p.isOwn)
        SheetAction(p.isBlocked ? tr('Desbloquear') : tr('Bloquear'), CupertinoIcons.nosign, () => _toggleBlock(p), destructive: !p.isBlocked),
      if (!p.isOwn) SheetAction(tr('Reportar cuenta'), CupertinoIcons.flag, () => showReportSheet(context, 'user', p.user.id), destructive: true),
      if (canWarn) SheetAction(tr('Advertir (equipo)'), CupertinoIcons.exclamationmark_triangle, () => _warn(p), destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (p == null) {
      return Scaffold(
        appBar: GlassBar(title: '@${widget.username}', showBack: !widget.asTab),
        body: _error != null
            ? (_error is ApiException && (_error as ApiException).status == 404
                ? EmptyState(icon: CupertinoIcons.person_crop_circle_badge_xmark, title: tr('Esta cuenta no está disponible'), message: tr('Puede que no exista o que no tengas acceso.'))
                : ErrorState(error: _error!, onRetry: () {
                    setState(() => _error = null);
                    _load();
                  }))
            : const Loading(),
      );
    }
    final tabs = _tabs(p);
    if (!tabs.containsKey(_tab)) _tab = 'posts';
    final list = _list(_tab);
    final locked = !p.canView || p.isBlocked;

    return Scaffold(
      body: Stack(children: [
        NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (!locked && n.metrics.extentAfter < 700) list.loadMore();
          return false;
        },
        child: CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_cover(p), _header(p)])),
            if (locked)
              SliverToBoxAdapter(
                child: p.isBlocked
                    ? EmptyState(
                        icon: CupertinoIcons.nosign,
                        title: tr('Bloqueaste esta cuenta'),
                        message: tr('No verás su contenido mientras esté bloqueada.'),
                        action: SoftButton(label: tr('Desbloquear'), onPressed: () => _toggleBlock(p)),
                      )
                    : EmptyState(
                        icon: CupertinoIcons.lock_fill,
                        title: tr('Esta cuenta es privada'),
                        message: tr('Síguela para ver sus publicaciones e historias.'),
                      ),
              )
            else ...[
              SliverPersistentHeader(delegate: _TabsHeader(tabs: tabs, selected: _tab, onSelect: (t) => setState(() => _tab = t))),
              ListenableBuilder(
                listenable: list,
                builder: (context, _) {
                  if (!list.loaded && !list.loading) Future.microtask(list.refresh);
                  if (_tab == 'media' && list.items.isNotEmpty) {
                    final posts = list.items.cast<Post>().where((x) => x.media.isNotEmpty).toList();
                    return SliverPadding(
                      padding: const EdgeInsets.all(10),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                        delegate: SliverChildBuilderDelegate((_, i) => MediaTile(post: posts[i]), childCount: posts.length),
                      ),
                    );
                  }
                  return PagedSliver<dynamic>(
                    paged: list,
                    empty: _emptyFor(_tab, p),
                    itemBuilder: (context, item, i) {
                      if (item is Song) return SongTile(song: item, playKeyPrefix: 'profile');
                      final post = item as Post;
                      return Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 10 : 0),
                        child: PostCardFor(post: post, list: list),
                      );
                    },
                  );
                },
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
        _topBar(p),
      ]),
    );
  }

  Widget _topBar(Profile p) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ListenableBuilder(
        listenable: _scroll,
        builder: (context, _) {
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          final t = ((offset - 120) / 60).clamp(0.0, 1.0).toDouble();
          return Container(
            decoration: BoxDecoration(
              color: Tx.bg.withAlpha((t * 235).round()),
              border: Border(bottom: BorderSide(color: Tx.border.withAlpha((t * 18).round()))),
            ),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(children: [
                  const SizedBox(width: 10),
                  if (!widget.asTab) _CircleIcon(icon: CupertinoIcons.chevron_back, onTap: () => Navigator.of(context).maybePop()),
                  Expanded(
                    child: Opacity(
                      opacity: t,
                      child: Text(p.user.displayName, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.display(17)),
                    ),
                  ),
                  if (p.isOwn) ...[
                    _CircleIcon(icon: CupertinoIcons.gear_alt, onTap: () => push(context, const SettingsScreen())),
                    const SizedBox(width: 8),
                  ],
                  _CircleIcon(icon: CupertinoIcons.ellipsis, onTap: () => _menu(p)),
                  const SizedBox(width: 10),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyFor(String tab, Profile p) {
    final own = p.isOwn;
    return switch (tab) {
      'threads' => EmptyState(icon: CupertinoIcons.text_quote, title: tr('Sin hilos'), message: own ? tr('Comparte una idea larga con un hilo.') : tr('Todavía no ha publicado hilos.')),
      'media' => EmptyState(icon: CupertinoIcons.photo_on_rectangle, title: tr('Sin fotos ni videos'), message: own ? tr('Tus fotos y videos aparecerán aquí.') : null),
      'music' => EmptyState(icon: CupertinoIcons.music_note_list, title: tr('Sin canciones publicadas')),
      'saved' => EmptyState(icon: CupertinoIcons.bookmark, title: tr('Nada guardado'), message: tr('Guarda publicaciones para verlas después. Solo tú ves esta lista.')),
      _ => EmptyState(icon: CupertinoIcons.square_pencil, title: tr('Sin publicaciones'), message: own ? tr('Comparte tu primera publicación.') : tr('Todavía no ha publicado nada.')),
    };
  }

  Widget _cover(Profile p) {
    final top = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 150 + top,
      child: Stack(fit: StackFit.expand, children: [
        if (p.user.coverUrl != null)
          NetImage(p.user.coverUrl, fit: BoxFit.cover)
        else
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Tx.purple700, Tx.blue, Color(0xFF0E7490)]),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withAlpha(110), Colors.transparent, Tx.bg.withAlpha(200)],
              stops: const [0, .45, 1],
            ),
          ),
        ),
        if (!p.isBlocked && (p.note != null || p.isOwn))
          Positioned(
            left: 22,
            bottom: 27,
            child: NoteCloud(
              text: p.note?.label ?? tr('Publicar una nota'),
              sticker: p.note?.sticker,
              placeholder: p.note == null,
              maxWidth: 170,
              fontSize: 12.5,
              maxLines: 3,
              onTap: () => p.note != null ? openNote(context, p.note!) : composeNote(context),
            ),
          ),
      ]),
    );
  }

  Widget _header(Profile p) {
    final u = p.user;
    final d = p.details;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Transform.translate(
            offset: const Offset(0, -30),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 4)),
              child: Avatar(
                user: u,
                size: 92,
                ring: p.storiesActive,
                ringSeen: p.storiesActive && !p.storiesUnseen,
                online: u.online && !p.isOwn,
                onTap: p.storiesActive ? () => _openStories(p) : null,
              ),
            ),
          ),
          const Spacer(),
          if (p.isOwn) ...[
            SoftButton(
              label: tr('Editar perfil'),
              icon: CupertinoIcons.pencil,
              onPressed: () async {
                await push(context, const EditProfileScreen());
                _load();
              },
            ),
          ] else if (!p.isBlocked) ...[
            if (p.canView || p.conversationId != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SoftButton(label: tr('Mensaje'), icon: CupertinoIcons.chat_bubble_text, onPressed: () => _message(p)),
              ),
            FollowButton(user: u, height: 40, onChanged: _load),
          ],
        ]),
        Transform.translate(
          offset: const Offset(0, -18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(u.displayName, style: Tx.display(24))),
              if (u.isVerified) ...[const SizedBox(width: 6), const VerifiedBadge(size: 21)],
            ]),
            const SizedBox(height: 2),
            Row(children: [
              Text('@${u.username}', style: Tx.body(14.5, color: Tx.muted)),
              if (u.relation?.followsYou == true && !p.isOwn) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(6)),
                  child: Text(tr('Te sigue'), style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.muted)),
                ),
              ],
              if (u.isPrivate) ...[const SizedBox(width: 8), Icon(CupertinoIcons.lock_fill, size: 13, color: Tx.subtle)],
            ]),
            if (u.creatorLabel != null || u.isStaffRole) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (u.creatorLabel != null)
                  _Badge(icon: u.isMusicArtist ? CupertinoIcons.music_mic : CupertinoIcons.star_fill, label: u.creatorLabel!, gradient: true),
                if (u.role == 'admin') _Badge(icon: CupertinoIcons.shield_fill, label: tr('Administrador')),
                if (u.role == 'moderator') _Badge(icon: CupertinoIcons.shield_lefthalf_fill, label: tr('Moderador')),
              ]),
            ],
            if (u.bio.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              RichBody(u.bio.trim(), style: Tx.body(15, height: 1.45)),
            ],
            if (d?.song != null && d!.song!.available) ...[
              const SizedBox(height: 12),
              ProfileSongPill(song: d.song!, playKey: 'profile:${u.id}'),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 14, runSpacing: 6, children: [
              if (d?.city != null) _Meta(icon: CupertinoIcons.house, text: tr('Vive en {city}', {'city': d!.city})),
              if (d?.hometown != null) _Meta(icon: CupertinoIcons.location, text: tr('De {hometown}', {'hometown': d!.hometown})),
              for (final l in d?.links.take(2) ?? const <ProfileLink>[])
                GestureDetector(
                  onTap: () => openUrl(context, l.url),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.link, size: 14, color: Tx.accent),
                    const SizedBox(width: 4),
                    Text(l.title, style: Tx.body(13.5, color: Tx.accent)),
                  ]),
                ),
              if (u.website != null)
                GestureDetector(
                  onTap: () => openUrl(context, u.website!),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.link, size: 14, color: Tx.accent),
                    const SizedBox(width: 4),
                    Text(u.website!.replaceFirst(RegExp(r'^https?://(www\.)?'), ''), style: Tx.body(13.5, color: Tx.accent)),
                  ]),
                ),
              if (u.country != null) _Meta(icon: CupertinoIcons.location, text: context.read<AppState>().countryName(u.country!)),
              if (u.createdAt != null) _Meta(icon: CupertinoIcons.calendar, text: tr('Se unió en {date}', {'date': monthYear(u.createdAt)})),
              if (d != null && (d.hasAbout || d.interests.isNotEmpty || d.links.length > 2))
                GestureDetector(
                  onTap: () => showProfileAbout(context, u, d),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(CupertinoIcons.info_circle, size: 14, color: Tx.accent),
                    const SizedBox(width: 4),
                    Text(tr('Información'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.accent)),
                  ]),
                ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _Stat(value: u.postsCount, label: tr('publicaciones')),
              _Stat(
                value: u.followersCount,
                label: u.followersCount == 1 ? tr('seguidor') : tr('seguidores'),
                onTap: p.canView ? () => push(context, FollowListScreen(username: u.username, followers: true)) : null,
              ),
              _Stat(
                value: u.followingCount,
                label: tr('siguiendo'),
                onTap: p.canView ? () => push(context, FollowListScreen(username: u.username, followers: false)) : null,
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

/// Tarjeta de publicación conectada a una lista mixta del perfil.
class PostCardFor extends StatelessWidget {
  const PostCardFor({super.key, required this.post, required this.list});

  final Post post;
  final Paged<dynamic> list;

  @override
  Widget build(BuildContext context) {
    return PostCard(
      key: ValueKey('profile-post-${post.id}'),
      post: post,
      onRemoved: () => list.remove((x) => x is Post && x.id == post.id),
      onReplaced: (p) {
        final i = list.items.indexWhere((x) => x is Post && x.id == post.id);
        if (i >= 0) {
          list.items[i] = p;
          list.changed();
        }
      },
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.tabs, required this.selected, required this.onSelect});

  final Map<String, String> tabs;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(color: Tx.bg, border: Border(bottom: BorderSide(color: Tx.border))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        children: [
          for (final e in tabs.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PillChip(label: e.value, selected: selected == e.key, onTap: () => onSelect(e.key)),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) => old.selected != selected || old.tabs.length != tabs.length;
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: Colors.black.withAlpha(100), shape: BoxShape.circle, border: Border.all(color: Colors.white.withAlpha(30))),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, this.gradient = false});

  final IconData icon;
  final String label;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: gradient ? Tx.brandSoft : null,
        color: gradient ? null : Tx.surface3,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: gradient ? Tx.alpha(Tx.purple500, .4) : Tx.borderStrong),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: gradient ? Tx.accent : Tx.muted),
        const SizedBox(width: 5),
        gradient
            ? GradientText(label, style: Tx.body(12.5, weight: FontWeight.w700))
            : Text(label, style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.muted)),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: Tx.subtle),
      const SizedBox(width: 4),
      Text(text, style: Tx.body(13.5, color: Tx.muted)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
          child: Column(children: [
            Text(compact(value), style: Tx.display(19)),
            const SizedBox(height: 2),
            Text(label, style: Tx.body(12, color: Tx.muted)),
          ]),
        ),
      ),
    );
  }
}
