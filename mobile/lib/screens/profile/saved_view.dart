import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/events.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart' show VideoFrame;
import '../../widgets/story_layers.dart' show filtered;
import '../stories/story_viewer.dart';

/// Categorías de Perfil › Guardado: lo guardado, lo propio en «Solo yo» y lo que le gustó.
const savedCategories = ['saved', 'private', 'liked'];

/// Endpoint de cada categoría (con ?kind=all|posts|reels).
String savedPath(String category) => switch (category) {
      'private' => 'me/private',
      'liked' => 'me/liked',
      _ => 'me/saved',
    };

/// Cabecera de Guardado: categoría (Guardados, Solo yo, Me gusta) y tipo (Todo, Publicaciones, Reels, Historias).
class SavedFilters extends StatelessWidget {
  const SavedFilters({super.key, required this.category, required this.kind, required this.onChanged});

  final String category;
  final String kind;
  final void Function(String category, String kind) onChanged;

  @override
  Widget build(BuildContext context) {
    final cats = {
      'saved': (CupertinoIcons.bookmark, tr('Guardados')),
      'private': (CupertinoIcons.lock, tr('Solo yo')),
      'liked': (CupertinoIcons.heart, tr('Me gusta')),
    };
    final kinds = {
      'all': tr('Todo'),
      'posts': tr('Publicaciones'),
      'reels': tr('Reels'),
      if (category == 'private') 'stories': tr('Historias'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in cats.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PillChip(label: e.value.$2, icon: e.value.$1, selected: category == e.key, onTap: () => onChanged(e.key, 'all')),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final e in kinds.entries)
            Semantics(
              button: true,
              selected: kind == e.key,
              child: GestureDetector(
                onTap: () => onChanged(category, e.key),
                child: Container(
                  margin: const EdgeInsets.only(right: 16),
                  padding: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kind == e.key ? Tx.accent : Colors.transparent, width: 2))),
                  child: Text(e.value, style: Tx.body(13.5, weight: FontWeight.w600, color: kind == e.key ? Tx.text : Tx.subtle)),
                ),
              ),
            ),
        ]),
        if (category == 'private')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Solo tú ves esta sección. Las historias «Solo yo» no se borran a las 24 horas.'), style: Tx.body(12, color: Tx.subtle)),
          ),
      ]),
    );
  }
}

/// Guardado › Solo yo › Historias: las historias propias marcadas «Solo yo» (también las de más de 24 horas).
class PrivateStoriesSliver extends StatefulWidget {
  const PrivateStoriesSliver({super.key});

  @override
  State<PrivateStoriesSliver> createState() => _PrivateStoriesSliverState();
}

class _PrivateStoriesSliverState extends State<PrivateStoriesSliver> {
  StoryGroup? _group;
  final List<StoryItem> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    storiesChanged.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    storiesChanged.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final res = await api.get('me/private/stories', {'page': '$_page'});
      if (!mounted) return;
      final group = res.data is Map ? StoryGroup.fromJson(res.map) : null;
      setState(() {
        _group = group ?? _group;
        _items.addAll(group?.items ?? const []);
        _hasMore = res.meta['next'] != null;
        _page++;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(int index) async {
    final group = _group;
    if (group == null) return;
    await pushFade(context, StoryViewer(groups: [StoryGroup(user: group.user, own: true, items: _items.sublist(index))]));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      if (_error != null) return SliverToBoxAdapter(child: ErrorState(error: _error!, onRetry: _reload));
      if (_loading) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Loading()));
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: CupertinoIcons.lock,
          title: tr('No tienes historias en Solo yo'),
          message: tr('Al crear una historia, toca «Solo yo»; o en una historia tuya, abre ··· y elige «Solo yo».'),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(10),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 9 / 16),
        delegate: SliverChildBuilderDelegate((context, i) {
          if (i == _items.length - 1 && _hasMore) Future.microtask(_load);
          final s = _items[i];
          return Semantics(
            button: true,
            label: s.isVideo ? tr('Ver video') : tr('Ver historia'),
            child: GestureDetector(
              onTap: () => _open(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(fit: StackFit.expand, children: [
                  if (s.isText)
                    Container(
                      decoration: BoxDecoration(gradient: Tx.storyBackground(s.background)),
                      padding: const EdgeInsets.all(8),
                      alignment: Alignment.center,
                      child: Text(s.body, maxLines: 6, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TxDark.body(12, weight: FontWeight.w700, color: Colors.white)),
                    )
                  else if (s.isVideo && s.mediaUrl != null)
                    filtered(s.filter, VideoFrame(url: s.mediaUrl!))
                  else
                    filtered(s.filter, NetImage(s.mediaUrl, fit: BoxFit.cover)),
                  if (s.isVideo) const Positioned(top: 6, right: 6, child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 14)),
                  if (s.expired)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Text(tr('Archivada'), style: TxDark.body(10.5, weight: FontWeight.w700, color: Colors.white).copyWith(shadows: const [Shadow(color: Color(0x99000000), blurRadius: 4)])),
                    ),
                ]),
              ),
            ),
          );
        }, childCount: _items.length),
      ),
    );
  }
}
