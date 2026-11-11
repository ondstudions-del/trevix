import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/paged.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/paged_view.dart';

class HashtagScreen extends StatefulWidget {
  const HashtagScreen({super.key, required this.tag});

  final String tag;

  @override
  State<HashtagScreen> createState() => _HashtagScreenState();
}

class _HashtagScreenState extends State<HashtagScreen> {
  late final Paged<Post> _posts = Paged<Post>('hashtags/${Uri.encodeComponent(widget.tag)}', Post.fromJson);

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: '#${widget.tag}'),
      body: PagedView<Post>(
        paged: _posts,
        itemBuilder: postBuilder(_posts),
        header: [
          SliverToBoxAdapter(
            child: ListenableBuilder(
              listenable: _posts,
              builder: (context, _) {
                final meta = asMap(_posts.meta['hashtag']);
                final count = asInt(meta['posts_count']);
                return Panel(
                  gradient: true,
                  margin: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(18)),
                      child: const Icon(CupertinoIcons.number, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        GradientText('#${widget.tag}', style: Tx.display(24)),
                        if (_posts.loaded) Text(plural(count, 'publicación', 'publicaciones'), style: Tx.body(14, color: Tx.muted)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
          ),
        ],
        empty: EmptyState(icon: CupertinoIcons.number, title: tr('Sin publicaciones'), message: tr('Nadie ha usado esta etiqueta todavía.')),
      ),
    );
  }
}
