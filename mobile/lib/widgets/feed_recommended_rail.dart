import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'post_card.dart';

/// Carril horizontal de publicaciones recomendadas (comunidades e intereses).
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Row(children: [
            Icon(CupertinoIcons.sparkles, size: 17, color: Tx.accent),
            const SizedBox(width: 6),
            Text(tr('Recomendado para ti'), style: Tx.body(15, weight: FontWeight.w700)),
          ]),
        ),
        SizedBox(
          height: 340,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final p = posts[i];
              return SizedBox(
                width: 300,
                child: Material(
                  color: Tx.surface1,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => openPost(context, p.id),
                    child: PostCard(post: p, onReplaced: (n) => setState(() => posts[i] = n)),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}