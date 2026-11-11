import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/recent_searches.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/media.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/post_card.dart';
import '../../widgets/user_tile.dart';
import '../browser/browser_screen.dart';
import '../communities/communities_screen.dart';
import '../communities/community_widgets.dart';
import '../home/home_shell.dart';
import '../music/music_screen.dart';
import '../reels/reels_screen.dart';
import 'post_list_screens.dart';
import 'suggestions_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  String _type = 'people';
  final Map<String, Paged<dynamic>> _results = {};

  Json? _explore;
  Object? _error;

  static Map<String, String> get _types => {'people': tr('Personas'), 'posts': tr('Publicaciones'), 'tags': tr('Etiquetas'), 'communities': tr('Comunidades')};

  @override
  void initState() {
    super.initState();
    tabReselect.addListener(_onReselect);
    _focus.addListener(_onFocus);
    recentSearches.load();
    _load();
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  void _openFromSearch(User user) {
    recentSearches.add(user);
    openProfile(context, user.username);
  }

  @override
  void dispose() {
    tabReselect.removeListener(_onReselect);
    _focus.removeListener(_onFocus);
    _debounce?.cancel();
    _search.dispose();
    _focus.dispose();
    _scroll.dispose();
    for (final p in _results.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _onReselect() {
    if (tabReselect.value != 1) return;
    if (_scroll.hasClients && _scroll.offset > 10) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _load() async {
    try {
      final res = await api.get('explore');
      if (mounted) setState(() => _explore = res.map);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      final q = value.trim();
      if (q == _query) return;
      for (final p in _results.values) {
        p.dispose();
      }
      _results.clear();
      setState(() => _query = q);
    });
  }

  Paged<dynamic> _paged(String type) => _results.putIfAbsent(type, () {
        dynamic parse(Json j) => switch (type) {
              'people' => User.fromJson(j),
              'posts' => Post.fromJson(j),
              'tags' => Hashtag.fromJson(j),
              _ => Community.fromJson(j),
            };
        return Paged<dynamic>('search', parse, query: {'q': _query, 'type': type});
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        showBack: false,
        titleWidget: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _search,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: (text) {
                if (looksLikeUrl(text)) openUrl(context, browserTarget(text).toString());
              },
              textInputAction: TextInputAction.search,
              style: Tx.body(15),
              decoration: fieldDecoration(
                tr('Buscar en TREVIX'),
                prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 19),
                suffix: _search.text.isEmpty && !_focus.hasFocus
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _search.clear();
                          _onChanged('');
                          _focus.unfocus();
                        },
                        child: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                      ),
              ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: tr('Navegador'),
            icon: Icon(CupertinoIcons.globe, color: Tx.text, size: 23),
            onPressed: () => push(context, const BrowserScreen()),
          ),
        ],
      ),
      body: _query.isNotEmpty
          ? _searchResults()
          : _focus.hasFocus
              ? _recent()
              : _discover(),
    );
  }

  Widget _recent() {
    return ValueListenableBuilder<List<User>>(
      valueListenable: recentSearches,
      builder: (context, users, _) {
        if (users.isEmpty) {
          return EmptyState(
            icon: CupertinoIcons.search,
            title: tr('Busca en TREVIX'),
            message: tr('Encuentra personas por nombre, usuario, ciudad o intereses, además de publicaciones, etiquetas y comunidades.'),
          );
        }
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            SectionTitle(
              tr('Recientes'),
              trailing: GestureDetector(
                onTap: recentSearches.clear,
                child: Text(tr('Borrar todo'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ),
            for (final u in users)
              UserTile(
                key: ValueKey('recent-${u.id}'),
                user: u,
                subtitle: '@${u.username}',
                onTap: () => _openFromSearch(u),
                trailing: IconButton(
                  tooltip: tr('Quitar'),
                  icon: Icon(CupertinoIcons.xmark, size: 17, color: Tx.subtle),
                  onPressed: () => recentSearches.remove(u.id),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Abrir lo escrito como página web o buscarlo en la web, en el navegador de la app.
  Widget _webRow() {
    final url = looksLikeUrl(_query);
    return InkWell(
      onTap: () => url ? openUrl(context, browserTarget(_query).toString()) : push(context, BrowserScreen(url: _query)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Tx.surface3, shape: BoxShape.circle),
            child: Icon(url ? CupertinoIcons.globe : CupertinoIcons.search, size: 18, color: Tx.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              url ? tr('Abrir {site}', {'site': _query}) : tr('Buscar «{query}» en la web', {'query': _query}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(14.5, weight: FontWeight.w600),
            ),
          ),
          Icon(CupertinoIcons.arrow_up_right, size: 15, color: Tx.subtle),
        ]),
      ),
    );
  }

  Widget _searchResults() {
    final paged = _paged(_type);
    return Column(children: [
      _webRow(),
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          children: [
            for (final e in _types.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PillChip(label: e.value, selected: _type == e.key, onTap: () => setState(() => _type = e.key)),
              ),
          ],
        ),
      ),
      Expanded(
        child: PagedView<dynamic>(
          key: ValueKey('search-$_type-$_query'),
          paged: paged,
          empty: EmptyState(icon: CupertinoIcons.search, title: tr('Sin resultados'), message: tr('No encontramos nada para «{query}».', {'query': _query})),
          itemBuilder: (context, item, i) {
            if (item is User) return UserTile(user: item, onTap: () => _openFromSearch(item));
            if (item is Post) {
              return PostCard(
                key: ValueKey('search-post-${item.id}'),
                post: item,
                onRemoved: () => paged.remove((x) => x is Post && x.id == item.id),
              );
            }
            if (item is Hashtag) {
              return ListTile(
                onTap: () => openHashtag(context, item.tag),
                leading: const _TagIcon(),
                title: Text('#${item.tag}', style: Tx.body(15.5, weight: FontWeight.w600)),
                subtitle: Text(plural(item.postsCount, 'publicación', 'publicaciones'), style: Tx.body(13, color: Tx.muted)),
              );
            }
            if (item is Community) return CommunityTile(community: item);
            return const SizedBox.shrink();
          },
        ),
      ),
    ]);
  }

  Widget _discover() {
    final data = _explore;
    if (data == null) {
      return _error != null
          ? ErrorState(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : const Loading();
    }
    final people = asList(data['people'], User.fromJson);
    final tags = asList(data['hashtags'], Hashtag.fromJson);
    final communities = asList(data['communities'], Community.fromJson);
    final media = asList(data['media'], Post.fromJson).where((p) => p.media.isNotEmpty).toList();
    final featured = asList(data['featured'], Post.fromJson);

    return CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _load),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Row(children: [
              Expanded(
                child: _QuickCard(
                  icon: CupertinoIcons.music_note_2,
                  title: tr('Música'),
                  subtitle: tr('Canciones de artistas'),
                  colors: const [Tx.purple500, Tx.blue],
                  onTap: () => push(context, const MusicScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: CupertinoIcons.person_3_fill,
                  title: tr('Comunidades'),
                  subtitle: tr('Encuentra a tu gente'),
                  colors: const [Color(0xFFDB2777), Tx.purple],
                  onTap: () => push(context, const CommunitiesScreen()),
                ),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(
                child: _QuickCard(
                  icon: CupertinoIcons.calendar,
                  title: tr('Eventos'),
                  subtitle: tr('Planes cerca de ti'),
                  colors: const [Color(0xFFF59E0B), Color(0xFFDB2777)],
                  onTap: () => push(context, const EventsScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: CupertinoIcons.star_fill,
                  title: tr('Destacados'),
                  subtitle: tr('Elegidos por TREVIX'),
                  colors: const [Tx.blue, Tx.cyan],
                  onTap: () => push(context, const FeaturedScreen()),
                ),
              ),
            ]),
          ),
        ),
        if (people.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              tr('Personas que quizá conozcas'),
              trailing: GestureDetector(
                onTap: () => push(context, const SuggestionsScreen()),
                child: Text(tr('Ver todas'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 226,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: people.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PersonCard(
                  key: ValueKey('explore-person-${people[i].id}'),
                  user: people[i],
                  onDismissed: () => setState(() => (_explore?['people'] as List?)?.removeWhere((u) => u is Map && u['id'] == people[i].id)),
                ),
              ),
            ),
          ),
        ],
        if (featured.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              tr('Destacados'),
              trailing: GestureDetector(
                onTap: () => push(context, const FeaturedScreen()),
                child: Text(tr('Ver todas'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => PostCard(
                key: ValueKey('explore-featured-${featured[i].id}'),
                post: featured[i],
                onRemoved: () => setState(() => (_explore?['featured'] as List?)?.removeWhere((p) => p is Map && p['id'] == featured[i].id)),
              ),
              childCount: featured.length,
            ),
          ),
        ],
        if (tags.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(tr('Tendencias'))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(children: [
                for (var i = 0; i < tags.length && i < 8; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => openHashtag(context, tags[i].tag),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      child: Row(children: [
                        SizedBox(
                          width: 30,
                          child: Text('${i + 1}', style: Tx.display(18, color: i < 3 ? Tx.accent : Tx.subtle)),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (tags[i].category != null)
                              Text(tags[i].category!, style: Tx.body(11.5, color: Tx.subtle)),
                            Text('#${tags[i].tag}', style: Tx.body(15.5, weight: FontWeight.w700)),
                            Text(plural(tags[i].postsCount, 'publicación', 'publicaciones'), style: Tx.body(12, color: Tx.muted)),
                          ]),
                        ),
                        Icon(CupertinoIcons.chevron_forward, size: 16, color: Tx.subtle),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ],
        if (communities.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              tr('Comunidades'),
              trailing: GestureDetector(
                onTap: () => push(context, const CommunitiesScreen()),
                child: Text(tr('Ver todas'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 190,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: communities.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => CommunityCard(community: communities[i]),
              ),
            ),
          ),
        ],
        if (media.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionTitle(tr('Multimedia'))),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
              delegate: SliverChildBuilderDelegate(
                (context, i) => MediaTile(post: media[i]),
                childCount: media.length,
              ),
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
      ],
    );
  }
}

class _TagIcon extends StatelessWidget {
  const _TagIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(gradient: Tx.brandSoft, borderRadius: BorderRadius.circular(13), border: Border.all(color: Tx.alpha(Tx.purple500, .3))),
      child: Icon(CupertinoIcons.number, color: Tx.accent, size: 20),
    );
  }
}

/// Miniatura cuadrada de una publicación con fotos o video (rejillas de Explorar y del perfil).
class MediaTile extends StatelessWidget {
  const MediaTile({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final first = post.media.first;
    return GestureDetector(
      onTap: () => first.isVideo ? openReels(context, start: post) : openPost(context, post.id, post: post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          if (first.isVideo) ...[
            const ColoredBox(color: Colors.black),
            VideoPoster(media: first),
            const Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 26, shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)])),
          ] else
            NetImage(first.url),
          if (post.media.length > 1)
            const Positioned(top: 6, right: 6, child: Icon(CupertinoIcons.square_stack_fill, color: Colors.white, size: 16)),
          if (first.isVideo)
            const Positioned(top: 6, right: 6, child: TxIcon(TxGlyph.reels, size: 16, color: Colors.white, stroke: 2.2)),
          if (first.isVideo && (first.duration ?? 0) > 0)
            Positioned(
              left: 6,
              bottom: 6,
              child: Text(
                clockText(first.duration!),
                style: TxDark.body(11.5, weight: FontWeight.w700, color: Colors.white).copyWith(shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 6)]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.subtitle, required this.colors, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 96,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colors[0].withAlpha(60), colors[1].withAlpha(30)]),
          border: Border.all(color: colors[0].withAlpha(80)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Tx.body(15, weight: FontWeight.w700)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.muted)),
          ]),
        ]),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({super.key, required this.user, required this.onDismissed});

  final User user;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProfile(context, user.username),
      child: Container(
        width: 156,
        decoration: BoxDecoration(
          color: Tx.surface1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Tx.border),
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(children: [
              Avatar(user: user, size: 68),
              const SizedBox(height: 10),
              NameLine(user: user, size: 14.5),
              const SizedBox(height: 2),
              Text('@${user.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
              const SizedBox(height: 4),
              Text(user.reason ?? '', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, color: Tx.muted)),
              const Spacer(),
              FollowButton(user: user, expand: true, height: 34),
            ]),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: tr('No me interesa'),
              visualDensity: VisualDensity.compact,
              icon: Icon(CupertinoIcons.xmark, size: 15, color: Tx.subtle),
              onPressed: () async {
                if (await dismissSuggestion(context, user)) onDismissed();
              },
            ),
          ),
        ]),
      ),
    );
  }
}
