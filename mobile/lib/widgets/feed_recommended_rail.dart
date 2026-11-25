import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Carril horizontal: publicaciones de comunidades recomendadas (diseño compacto, no PostCard completa).
class FeedRecommendedRail extends StatefulWidget {
  const FeedRecommendedRail({super.key, required this.enabled});

  final bool enabled;

  @override
  State<FeedRecommendedRail> createState() => _FeedRecommendedRailState();
}

class _FeedRecommendedRailState extends State<FeedRecommendedRail> {
  List<Post>? _posts;
  Object? _error;

  @override
  void didUpdateWidget(covariant FeedRecommendedRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled && _posts == null && _error == null) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('feed/recommended');
      if (!mounted) return;
      setState(() => _posts = res.list.map(Post.fromJson).toList());
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final posts = _posts;
    if (_error != null || posts == null || posts.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(10)),
              child: const Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('De tus comunidades'), style: Tx.body(16, weight: FontWeight.w800)),
                Text(tr('Publicaciones que coinciden con tus intereses'), style: Tx.body(12.5, color: Tx.muted)),
              ]),
            ),
          ]),
        ),
        SizedBox(
          height: 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _CommunityRecoCard(post: posts[i]),
          ),
        ),
      ]),
    );
  }
}

class _CommunityRecoCard extends StatelessWidget {
  const _CommunityRecoCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final community = post.community;
    final media = post.media.isNotEmpty ? post.media.first : null;
    final body = post.body.trim();
    final preview = body.isNotEmpty ? body : (post.listing != null ? asStr(post.listing!.title) : '');
    return SizedBox(
      width: 268,
      child: Material(
        color: Tx.surface1,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Tx.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openPost(context, post.id),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (community != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Tx.alpha(Tx.purple, .14), Tx.alpha(Tx.cyan, .08)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Tx.alpha(Tx.accent, .15), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      community.name.isNotEmpty ? community.name[0].toUpperCase() : 'C',
                      style: Tx.body(15, weight: FontWeight.w800, color: Tx.accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(community.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, weight: FontWeight.w800)),
                      Text(tr('Comunidad'), style: Tx.body(11, color: Tx.muted)),
                    ]),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14, color: Tx.subtle),
                ]),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (media != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: media.isVideo
                            ? Stack(fit: StackFit.expand, children: [
                                NetImage(media.posterUrl ?? media.url, fit: BoxFit.cover),
                                const Center(child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 22)),
                              ])
                            : NetImage(media.url, fit: BoxFit.cover),
                      ),
                    ),
                  if (media != null) const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Avatar(user: post.user, size: 22),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(post.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, weight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Tx.body(13, height: 1.35, color: Tx.muted),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(children: [
                Icon(CupertinoIcons.heart, size: 14, color: Tx.subtle),
                const SizedBox(width: 4),
                Text(compact(post.likes), style: Tx.body(11.5, color: Tx.subtle)),
                const SizedBox(width: 12),
                Icon(CupertinoIcons.chat_bubble, size: 14, color: Tx.subtle),
                const SizedBox(width: 4),
                Text(compact(post.comments), style: Tx.body(11.5, color: Tx.subtle)),
                const Spacer(),
                Text(tr('Ver más'), style: Tx.body(12, weight: FontWeight.w700, color: Tx.accent)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}