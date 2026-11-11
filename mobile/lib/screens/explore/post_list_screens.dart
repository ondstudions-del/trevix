import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/paged.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/post_card.dart';
import '../post/composer_screen.dart';

/// Publicaciones que el equipo de TREVIX destacó.
class FeaturedScreen extends StatefulWidget {
  const FeaturedScreen({super.key});

  @override
  State<FeaturedScreen> createState() => _FeaturedScreenState();
}

class _FeaturedScreenState extends State<FeaturedScreen> {
  final _paged = Paged<Post>('posts/featured', Post.fromJson);

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Destacados')),
      body: PagedView<Post>(
        paged: _paged,
        empty: EmptyState(
          icon: CupertinoIcons.star,
          title: tr('Aún no hay publicaciones destacadas'),
          message: tr('Aquí verás lo que el equipo de TREVIX recomienda.'),
        ),
        itemBuilder: (context, post, i) => PostCard(
          key: ValueKey('featured-${post.id}'),
          post: post,
          onRemoved: () => _paged.remove((p) => p.id == post.id),
        ),
      ),
    );
  }
}

/// Sección Eventos: próximos y pasados, y botón para crear uno.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  static const _tabs = {'upcoming': 'Próximos', 'past': 'Pasados'};
  String _tab = 'upcoming';
  final Map<String, Paged<Post>> _lists = {};

  Paged<Post> get _paged => _lists.putIfAbsent(_tab, () => Paged<Post>('events', Post.fromJson, query: {'tab': _tab}));

  @override
  void initState() {
    super.initState();
    postCreated.addListener(_onCreated);
  }

  @override
  void dispose() {
    postCreated.removeListener(_onCreated);
    for (final p in _lists.values) {
      p.dispose();
    }
    super.dispose();
  }

  void _onCreated() {
    final post = postCreated.value;
    if (post?.event != null && !post!.event!.isPast) _lists['upcoming']?.refresh();
  }

  Future<void> _create() async {
    await Navigator.of(context).push(CupertinoPageRoute(fullscreenDialog: true, builder: (_) => const ComposerScreen(startWithEvent: true)));
  }

  @override
  Widget build(BuildContext context) {
    final paged = _paged;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Eventos'),
        actions: [
          IconButton(onPressed: _create, tooltip: tr('Crear evento'), icon: const Icon(CupertinoIcons.calendar_badge_plus)),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            children: [
              for (final e in _tabs.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillChip(label: tr(e.value), selected: _tab == e.key, onTap: () => setState(() => _tab = e.key)),
                ),
            ],
          ),
        ),
        Expanded(
          child: PagedView<Post>(
            key: ValueKey('events-$_tab'),
            paged: paged,
            empty: EmptyState(
              icon: CupertinoIcons.calendar,
              title: _tab == 'upcoming' ? tr('No hay eventos próximos') : tr('Aún no hay eventos pasados'),
              message: _tab == 'upcoming' ? tr('Crea uno y compártelo con tus seguidores.') : null,
            ),
            itemBuilder: (context, post, i) => PostCard(
              key: ValueKey('event-${post.id}'),
              post: post,
              onRemoved: () => paged.remove((p) => p.id == post.id),
            ),
          ),
        ),
      ]),
    );
  }
}
