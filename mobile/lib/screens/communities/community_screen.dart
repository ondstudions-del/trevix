import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import 'community_form_screen.dart';
import 'community_members_screen.dart';
import 'community_widgets.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key, required this.slugOrId});

  final String slugOrId;

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  Community? _community;
  Object? _error;
  String _sort = 'recent';
  Paged<Post>? _posts;
  bool _busy = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _posts?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('communities/${Uri.encodeComponent(widget.slugOrId)}');
      if (!mounted) return;
      final c = Community.fromJson(res.map);
      final changedAccess = _community?.access?.canView != c.access?.canView;
      setState(() {
        _community = c;
        _error = null;
      });
      if (_posts == null) {
        _makePosts();
      } else if (changedAccess) {
        _posts!.refresh();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _makePosts() {
    final old = _posts;
    setState(() => _posts = Paged<Post>('communities/${_community!.slug}/posts', Post.fromJson, query: {'sort': _sort}));
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _apply(ApiResponse res) {
    if (!mounted) return;
    toast(context, '${res.map['message'] ?? 'Listo.'}');
    if (res.map['community'] is Map) {
      final c = Community.fromJson(asMap(res.map['community']));
      final changedAccess = _community?.access?.canView != c.access?.canView;
      setState(() => _community = c);
      if (changedAccess) _posts?.refresh();
    } else {
      _load();
    }
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      _apply(await api.post('communities/${_community!.id}/join'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _leave() async {
    final c = _community!;
    final pending = c.access?.pending ?? false;
    if (!pending &&
        !await confirm(context, 'Salir de ${c.name}', c.isPrivate ? 'Para volver tendrás que enviar otra solicitud.' : 'Podrás volver a unirte cuando quieras.',
            action: 'Salir', destructive: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      _apply(await api.delete('communities/${c.id}/membership'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _compose() async {
    final post = await openComposer(context, community: _community);
    if (post != null && _sort == 'recent') _posts?.insert(post);
  }

  void _menu(Community c) {
    final link = c.webUrl.isNotEmpty ? c.webUrl : '';
    actionSheet(context, [
      if (link.isNotEmpty)
        SheetAction('Compartir', CupertinoIcons.share, () => showShareSheet(context, url: link, title: 'Únete a «${c.name}» en TREVIX')),
      if (link.isNotEmpty)
        SheetAction('Copiar enlace', CupertinoIcons.link, () {
          Clipboard.setData(ClipboardData(text: link));
          toast(context, 'Enlace copiado.');
        }),
      if (c.access?.manager ?? false)
        SheetAction('Miembros y solicitudes', CupertinoIcons.person_3, () => _members(c)),
      if (c.access?.owner ?? false)
        SheetAction('Editar comunidad', CupertinoIcons.pencil, () => _edit(c)),
      if (!(c.access?.owner ?? false))
        SheetAction('Reportar comunidad', CupertinoIcons.flag, () => showReportSheet(context, 'community', c.id), destructive: true),
    ]);
  }

  Future<void> _edit(Community c) async {
    final updated = await push<Community>(context, CommunityFormScreen(community: c), fullscreen: true);
    if (updated != null && mounted) setState(() => _community = updated);
    _load();
  }

  Future<void> _members(Community c) async {
    await push(context, CommunityMembersScreen(community: c));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _community;
    final posts = _posts;
    if (c == null || posts == null) {
      return Scaffold(
        appBar: const GlassBar(title: 'Comunidad'),
        body: _error != null
            ? (_error is ApiException && (_error as ApiException).status == 404
                ? const EmptyState(icon: CupertinoIcons.person_3, title: 'Comunidad no disponible', message: 'Puede que ya no exista o que esté suspendida.')
                : ErrorState(error: _error!, onRetry: () {
                    setState(() => _error = null);
                    _load();
                  }))
            : const Loading(),
      );
    }
    final access = c.access;
    return Scaffold(
      floatingActionButton: (access?.canPost ?? false)
          ? Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: _compose,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: Tx.brand,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .45), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(CupertinoIcons.add, color: Colors.white, size: 28),
                ),
              ),
            )
          : null,
      body: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 700) posts.loadMore();
            return false;
          },
          child: CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              CupertinoSliverRefreshControl(onRefresh: () async {
                await Future.wait([_load(), posts.refresh()]);
              }),
              SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_cover(c), _header(c)])),
              SliverToBoxAdapter(
                child: Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tx.border))),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(children: [
                    PillChip(label: 'Recientes', icon: CupertinoIcons.clock, selected: _sort == 'recent', onTap: () {
                      if (_sort == 'recent') return;
                      _sort = 'recent';
                      _makePosts();
                    }),
                    const SizedBox(width: 8),
                    PillChip(label: 'Populares', icon: CupertinoIcons.flame, selected: _sort == 'popular', onTap: () {
                      if (_sort == 'popular') return;
                      _sort = 'popular';
                      _makePosts();
                    }),
                  ]),
                ),
              ),
              ListenableBuilder(
                listenable: posts,
                builder: (context, _) {
                  if (!posts.loaded && !posts.loading) Future.microtask(posts.refresh);
                  return PagedSliver<Post>(
                    paged: posts,
                    itemBuilder: (context, post, i) => Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 10 : 0),
                      child: postBuilder(posts)(context, post, i),
                    ),
                    privateState: const EmptyState(
                      icon: CupertinoIcons.lock_fill,
                      title: 'Comunidad privada',
                      message: 'Solo los miembros pueden ver las publicaciones. Envía una solicitud para unirte.',
                    ),
                    empty: EmptyState(
                      icon: CupertinoIcons.square_pencil,
                      title: 'Aún no hay publicaciones',
                      message: (access?.canPost ?? false) ? 'Sé la primera persona en publicar aquí.' : 'Únete para participar.',
                    ),
                  );
                },
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),
        ),
        _topBar(c),
      ]),
    );
  }

  Widget _topBar(Community c) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ListenableBuilder(
        listenable: _scroll,
        builder: (context, _) {
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;
          final t = ((offset - 110) / 60).clamp(0.0, 1.0).toDouble();
          return Container(
            color: Tx.bg.withAlpha((t * 235).round()),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 52,
                child: Row(children: [
                  const SizedBox(width: 10),
                  _RoundIcon(icon: CupertinoIcons.chevron_back, onTap: () => Navigator.of(context).maybePop()),
                  Expanded(
                    child: Opacity(
                      opacity: t,
                      child: Text(c.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.display(17)),
                    ),
                  ),
                  _RoundIcon(icon: CupertinoIcons.ellipsis, onTap: () => _menu(c)),
                  const SizedBox(width: 10),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cover(Community c) {
    final top = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 140 + top,
      child: Stack(fit: StackFit.expand, children: [
        if (c.coverUrl != null)
          NetImage(c.coverUrl)
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
              colors: [Colors.black.withAlpha(110), Colors.transparent, Tx.bg.withAlpha(210)],
              stops: const [0, .45, 1],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _header(Community c) {
    final access = c.access;
    final member = access?.member ?? false;
    final pending = access?.pending ?? false;
    final banned = access?.banned ?? false;
    Widget action;
    if (access?.owner ?? false) {
      action = SoftButton(label: 'Editar', icon: CupertinoIcons.pencil, onPressed: () => _edit(c));
    } else if (banned) {
      action = SoftButton(label: 'Vetado', icon: CupertinoIcons.nosign, color: Tx.danger, onPressed: null);
    } else if (member) {
      action = SoftButton(label: 'Miembro', icon: CupertinoIcons.checkmark_alt, loading: _busy, onPressed: _leave);
    } else if (pending) {
      action = SoftButton(label: 'Solicitud enviada', icon: CupertinoIcons.clock, loading: _busy, onPressed: _leave);
    } else {
      action = GradientButton(label: c.isPrivate ? 'Solicitar' : 'Unirme', expand: false, height: 40, loading: _busy, onPressed: _join);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Transform.translate(
            offset: const Offset(0, -28),
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Tx.bg, width: 4)),
              child: CommunityAvatar(community: c, size: 84),
            ),
          ),
          const Spacer(),
          Padding(padding: const EdgeInsets.only(bottom: 30), child: action),
        ]),
        Transform.translate(
          offset: const Offset(0, -16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: Tx.display(24)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _Tag(icon: CupertinoIcons.tag, text: c.category),
              _Tag(icon: c.isPrivate ? CupertinoIcons.lock_fill : CupertinoIcons.globe, text: c.isPrivate ? 'Privada' : 'Pública'),
              if (c.role == 'owner') const _Tag(icon: CupertinoIcons.star_fill, text: 'Administras', accent: true),
              if (c.role == 'moderator') const _Tag(icon: CupertinoIcons.shield_lefthalf_fill, text: 'Moderas', accent: true),
            ]),
            if (c.description.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(c.description.trim(), style: Tx.body(15, height: 1.45)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              _Stat(value: c.membersCount, label: c.membersCount == 1 ? 'miembro' : 'miembros', onTap: (access?.canView ?? false) ? () => _members(c) : null),
              _Stat(value: c.postsCount, label: c.postsCount == 1 ? 'publicación' : 'publicaciones'),
            ]),
            if ((access?.manager ?? false) && c.pendingRequests > 0) ...[
              const SizedBox(height: 10),
              Panel(
                gradient: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: () => _members(c),
                child: Row(children: [
                  Icon(CupertinoIcons.person_badge_plus, color: Tx.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text(plural(c.pendingRequests, 'solicitud pendiente', 'solicitudes pendientes'), style: Tx.body(14.5, weight: FontWeight.w600))),
                  Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.muted),
                ]),
              ),
            ],
            if (c.ownerUsername != null) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => openProfile(context, c.ownerUsername!),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Creada por ', style: Tx.body(13, color: Tx.subtle)),
                  TextSpan(text: c.ownerName ?? '@${c.ownerUsername}', style: Tx.body(13, weight: FontWeight.w600, color: Tx.accent)),
                  if (c.createdAt != null) TextSpan(text: ' · ${monthYear(c.createdAt)}', style: Tx.body(13, color: Tx.subtle)),
                ])),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, this.accent = false});

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        gradient: accent ? Tx.brandSoft : null,
        color: accent ? null : Tx.surface3,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: accent ? Tx.alpha(Tx.purple500, .4) : Tx.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: accent ? Tx.accent : Tx.muted),
        const SizedBox(width: 5),
        Text(text, style: Tx.body(12.5, weight: FontWeight.w600, color: accent ? Tx.accent : Tx.muted)),
      ]),
    );
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

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});

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
