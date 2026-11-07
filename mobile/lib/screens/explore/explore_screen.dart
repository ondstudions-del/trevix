import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/follow_button.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/post_card.dart';
import '../../widgets/user_tile.dart';
import '../communities/communities_screen.dart';
import '../communities/community_widgets.dart';
import '../home/home_shell.dart';
import '../music/music_screen.dart';

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

  static const _types = {'people': 'Personas', 'posts': 'Publicaciones', 'tags': 'Etiquetas', 'communities': 'Comunidades'};

  @override
  void initState() {
    super.initState();
    tabReselect.addListener(_onReselect);
    _load();
  }

  @override
  void dispose() {
    tabReselect.removeListener(_onReselect);
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
              textInputAction: TextInputAction.search,
              style: Tx.body(15),
              decoration: fieldDecoration(
                'Buscar en TREVIX',
                prefix: const Icon(CupertinoIcons.search, color: Tx.subtle, size: 19),
                suffix: _search.text.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _search.clear();
                          _onChanged('');
                          _focus.unfocus();
                        },
                        child: const Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                      ),
              ).copyWith(contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12)),
            ),
          ),
        ),
      ),
      body: _query.isEmpty ? _discover() : _searchResults(),
    );
  }

  Widget _searchResults() {
    final paged = _paged(_type);
    return Column(children: [
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
          empty: EmptyState(icon: CupertinoIcons.search, title: 'Sin resultados', message: 'No encontramos nada para «$_query».'),
          itemBuilder: (context, item, i) {
            if (item is User) return UserTile(user: item);
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
                  title: 'Música',
                  subtitle: 'Canciones de artistas',
                  colors: const [Tx.purple500, Tx.blue],
                  onTap: () => push(context, const MusicScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickCard(
                  icon: CupertinoIcons.person_3_fill,
                  title: 'Comunidades',
                  subtitle: 'Encuentra a tu gente',
                  colors: const [Color(0xFFDB2777), Tx.purple],
                  onTap: () => push(context, const CommunitiesScreen()),
                ),
              ),
            ]),
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionTitle('Tendencias')),
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
                          child: Text('${i + 1}', style: Tx.display(18, color: i < 3 ? Tx.purple300 : Tx.subtle)),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (tags[i].category != null)
                              Text(tags[i].category!, style: Tx.body(11.5, color: Tx.subtle)),
                            Text('#${tags[i].tag}', style: Tx.body(15.5, weight: FontWeight.w700)),
                            Text(plural(tags[i].postsCount, 'publicación', 'publicaciones'), style: Tx.body(12, color: Tx.muted)),
                          ]),
                        ),
                        const Icon(CupertinoIcons.chevron_forward, size: 16, color: Tx.subtle),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ],
        if (people.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionTitle('Personas para ti')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 226,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: people.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PersonCard(user: people[i]),
              ),
            ),
          ),
        ],
        if (communities.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              'Comunidades',
              trailing: GestureDetector(
                onTap: () => push(context, const CommunitiesScreen()),
                child: Text('Ver todas', style: Tx.body(14, weight: FontWeight.w600, color: Tx.purple300)),
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
          const SliverToBoxAdapter(child: SectionTitle('Multimedia')),
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
      child: const Icon(CupertinoIcons.number, color: Tx.purple300, size: 20),
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
      onTap: () => openPost(context, post.id, post: post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          first.isVideo
              ? Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.surface3, Tx.surface4])),
                  child: const Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 26)),
                )
              : NetImage(first.url),
          if (post.media.length > 1)
            const Positioned(top: 6, right: 6, child: Icon(CupertinoIcons.square_stack_fill, color: Colors.white, size: 16)),
          if (first.isVideo)
            const Positioned(top: 6, right: 6, child: Icon(CupertinoIcons.videocam_fill, color: Colors.white, size: 16)),
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
  const _PersonCard({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openProfile(context, user.username),
      child: Container(
        width: 156,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        decoration: BoxDecoration(
          color: Tx.surface1,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Tx.border),
        ),
        child: Column(children: [
          Avatar(user: user, size: 68),
          const SizedBox(height: 10),
          NameLine(user: user, size: 14.5),
          const SizedBox(height: 2),
          Text('@${user.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
          const SizedBox(height: 4),
          Text(user.reason ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, color: Tx.muted)),
          const Spacer(),
          FollowButton(user: user, expand: true, height: 34),
        ]),
      ),
    );
  }
}
