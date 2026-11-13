import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../explore/explore_screen.dart';
import '../reels/reels_screen.dart';

/// Pestaña «Listas» del perfil de un creador de contenido: sus listas de reproducción de reels.
class PlaylistsSliver extends StatelessWidget {
  const PlaylistsSliver({super.key, required this.paged, required this.own});

  final Paged<dynamic> paged;
  final bool own;

  Future<void> _create(BuildContext context) async {
    final created = await editPlaylist(context);
    if (created == null || !context.mounted) return;
    await paged.refresh();
    if (context.mounted) push(context, PlaylistScreen(playlist: created));
  }

  @override
  Widget build(BuildContext context) {
    if (paged.items.isEmpty) {
      if (paged.error != null) return SliverToBoxAdapter(child: ErrorState(error: paged.error!, onRetry: paged.retry));
      if (!paged.loaded || paged.loading) return const SliverToBoxAdapter(child: Loading(padding: 60));
      return SliverToBoxAdapter(
        child: EmptyState(
          icon: CupertinoIcons.list_bullet_below_rectangle,
          title: own ? tr('Aún no tienes listas') : tr('Sin listas todavía'),
          message: own
              ? tr('Agrupa tus reels en listas: quien las abra los verá en el orden en que los publicaste en la lista.')
              : tr('Cuando cree listas de reproducción, las verás aquí.'),
          action: own ? SoftButton(label: tr('Nueva lista'), icon: CupertinoIcons.add, onPressed: () => _create(context)) : null,
        ),
      );
    }
    final lists = paged.items.cast<Playlist>();
    final extra = own ? 1 : 0;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .62),
        delegate: SliverChildBuilderDelegate(
          (context, i) {
            if (own && i == 0) return _NewTile(onTap: () => _create(context));
            final list = lists[i - extra];
            return _PlaylistTile(
              playlist: list,
              onTap: () async {
                await push(context, PlaylistScreen(playlist: list));
                paged.refresh();
              },
            );
          },
          childCount: lists.length + extra,
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({required this.playlist, required this.onTap});

  final Playlist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(fit: StackFit.expand, children: [
              if (playlist.coverUrl != null)
                NetImage(playlist.coverUrl)
              else
                Container(
                  decoration: const BoxDecoration(gradient: Tx.brand),
                  child: const Icon(CupertinoIcons.list_bullet_below_rectangle, color: Colors.white, size: 34),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(165), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.play_fill, size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('${playlist.count}', style: TxDark.body(12, weight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
        Text(plural(playlist.count, 'video', 'videos'), style: Tx.body(12, color: Tx.muted)),
      ]),
    );
  }
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Tx.surface2,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Tx.borderStrong),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
                child: const Icon(CupertinoIcons.add, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 10),
              Text(tr('Nueva lista'), style: Tx.body(14, weight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Text(tr('Lista de reproducción'), maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600, color: Tx.muted)),
        Text(tr('Solo creadores'), style: Tx.body(12, color: Tx.subtle)),
      ]),
    );
  }
}

/// Una lista de reproducción: sus videos en el orden en que se agregaron. Al tocar uno se reproducen en Reels
/// desde ahí y en ese orden.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Playlist _playlist = widget.playlist;
  late final Paged<Post> _posts = Paged<Post>('playlists/${widget.playlist.id}/posts', Post.fromJson);

  @override
  void initState() {
    super.initState();
    _posts.refresh();
  }

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final res = await api.get('playlists/${_playlist.id}');
      if (mounted) setState(() => _playlist = Playlist.fromJson(res.map));
    } catch (_) {
      // Sin conexión: se queda con lo que ya se ve.
    }
  }

  Future<void> _refresh() => Future.wait([_posts.refresh(), _reload()]);

  void _play(Post start) => openReels(context, start: start, list: _posts, title: _playlist.title);

  Future<void> _edit() async {
    final updated = await editPlaylist(context, existing: _playlist);
    if (updated != null && mounted) setState(() => _playlist = updated);
  }

  Future<void> _delete() async {
    if (!await confirm(context, tr('Eliminar lista'), tr('Los videos seguirán publicados en tu perfil.'), action: tr('Eliminar'), destructive: true)) return;
    try {
      await api.delete('playlists/${_playlist.id}');
      if (!mounted) return;
      toast(context, tr('Lista eliminada.'));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _remove(Post post) async {
    if (!await confirm(context, tr('Quitar de la lista'), tr('El video seguirá publicado en tu perfil.'), action: tr('Quitar'), destructive: true)) return;
    try {
      final res = await api.delete('playlists/${_playlist.id}/posts/${post.id}');
      _posts.remove((p) => p.id == post.id);
      final updated = res.map['playlist'];
      if (mounted && updated is Map) setState(() => _playlist = Playlist.fromJson(Map<String, dynamic>.from(updated)));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _menu() {
    actionSheet(context, [
      SheetAction(tr('Editar nombre y descripción'), CupertinoIcons.pencil, _edit),
      SheetAction(tr('Eliminar lista'), CupertinoIcons.trash, _delete, destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = _playlist;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Lista de reproducción'),
        actions: [if (l.isOwn) IconButton(onPressed: _menu, icon: Icon(CupertinoIcons.ellipsis_circle, color: Tx.text))],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _posts.loadMore();
          return false;
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            SliverToBoxAdapter(child: _header(l)),
            ListenableBuilder(
              listenable: _posts,
              builder: (context, _) {
                final videos = _posts.items.where((p) => p.hasVideo).toList();
                if (videos.isEmpty) {
                  if (_posts.error != null) return SliverToBoxAdapter(child: ErrorState(error: _posts.error!, onRetry: _posts.retry));
                  if (!_posts.loaded || _posts.loading) return const SliverToBoxAdapter(child: Loading(padding: 60));
                  return SliverToBoxAdapter(
                    child: EmptyState(
                      icon: CupertinoIcons.film,
                      title: tr('La lista está vacía'),
                      message: l.isOwn ? tr('En uno de tus reels, abre «⋯» y elige «Agregar a una lista».') : tr('Cuando agregue videos, los verás aquí.'),
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 9 / 14),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Stack(fit: StackFit.expand, children: [
                        MediaTile(post: videos[i], onTap: () => _play(videos[i]), onLongPress: l.isOwn ? () => _remove(videos[i]) : null),
                        Positioned(
                          left: 6,
                          top: 6,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(8)),
                              child: Text('${i + 1}', style: TxDark.body(11.5, weight: FontWeight.w700, color: Colors.white)),
                            ),
                          ),
                        ),
                      ]),
                      childCount: videos.length,
                    ),
                  ),
                );
              },
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
          ],
        ),
      ),
    );
  }

  Widget _header(Playlist l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 92,
              height: 122,
              child: l.coverUrl != null
                  ? NetImage(l.coverUrl)
                  : Container(
                      decoration: const BoxDecoration(gradient: Tx.brand),
                      child: const Icon(CupertinoIcons.list_bullet_below_rectangle, color: Colors.white, size: 30),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.title, style: Tx.display(21)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => openProfile(context, l.user.username),
                child: Row(children: [
                  Avatar(user: l.user, size: 22),
                  const SizedBox(width: 6),
                  Flexible(child: Text(l.user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14, weight: FontWeight.w600))),
                  if (l.user.isVerified) ...[const SizedBox(width: 4), const VerifiedBadge(size: 13)],
                ]),
              ),
              const SizedBox(height: 6),
              Text(plural(l.count, 'video', 'videos'), style: Tx.body(13, color: Tx.muted)),
            ]),
          ),
        ]),
        if (l.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l.description, style: Tx.body(14.5, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Icon(CupertinoIcons.list_number, size: 14, color: Tx.subtle),
          const SizedBox(width: 6),
          Expanded(child: Text(tr('Los videos se reproducen en el orden en que se publicaron en la lista.'), style: Tx.body(12.5, color: Tx.subtle))),
        ]),
        const SizedBox(height: 14),
        ListenableBuilder(
          listenable: _posts,
          builder: (context, _) {
            final first = _posts.items.where((p) => p.hasVideo).firstOrNull;
            return GradientButton(
              label: tr('Reproducir'),
              icon: CupertinoIcons.play_fill,
              height: 48,
              onPressed: first == null ? null : () => _play(first),
            );
          },
        ),
      ]),
    );
  }
}

/// Crea una lista de reproducción o cambia su nombre y descripción. Devuelve la lista guardada o null.
Future<Playlist?> editPlaylist(BuildContext context, {Playlist? existing}) {
  final title = TextEditingController(text: existing?.title ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  var busy = false;
  String? error;
  return showModalBottomSheet<Playlist>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: StatefulBuilder(builder: (ctx, setSheet) {
        Future<void> save() async {
          setSheet(() {
            busy = true;
            error = null;
          });
          try {
            final body = {'title': title.text.trim(), 'description': description.text.trim()};
            final res = existing == null ? await api.post('playlists', body) : await api.patch('playlists/${existing.id}', body);
            if (ctx.mounted) Navigator.pop(ctx, Playlist.fromJson(res.map));
          } on ApiException catch (e) {
            setSheet(() {
              busy = false;
              error = e.field('title') ?? e.field('description') ?? e.message;
            });
          } catch (e) {
            setSheet(() {
              busy = false;
              error = errorText(e);
            });
          }
        }

        return SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(existing == null ? tr('Nueva lista de reproducción') : tr('Editar lista'), style: Tx.display(18)),
            const SizedBox(height: 6),
            Text(tr('Tus reels se verán en el orden en que los agregues.'), style: Tx.body(13.5, color: Tx.muted)),
            const SizedBox(height: 14),
            TextField(
              controller: title,
              autofocus: existing == null,
              maxLength: 80,
              onChanged: (_) => setSheet(() {}),
              style: Tx.body(16),
              decoration: fieldDecoration(tr('Nombre de la lista')),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: description,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              style: Tx.body(15),
              decoration: fieldDecoration(tr('Descripción (opcional)')),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: Tx.body(13, color: Tx.danger)),
            ],
            const SizedBox(height: 10),
            GradientButton(
              label: existing == null ? tr('Crear lista') : tr('Guardar'),
              loading: busy,
              height: 50,
              onPressed: title.text.trim().isEmpty ? null : save,
            ),
          ]),
        );
      }),
    ),
  ).whenComplete(() => Future.delayed(const Duration(milliseconds: 400), () {
        title.dispose();
        description.dispose();
      }));
}

/// Elegir en qué listas va un reel propio: tocar una la agrega o la quita; también se puede crear una nueva con él.
Future<void> showPlaylistPicker(BuildContext context, Post post) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PlaylistPicker(post: post),
  );
}

class _PlaylistPicker extends StatefulWidget {
  const _PlaylistPicker({required this.post});

  final Post post;

  @override
  State<_PlaylistPicker> createState() => _PlaylistPickerState();
}

class _PlaylistPickerState extends State<_PlaylistPicker> {
  List<Playlist>? _lists;
  Object? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('me/playlists', {'post_id': widget.post.id});
      if (mounted) {
        setState(() {
          _lists = res.list.map(Playlist.fromJson).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _toggle(int index) async {
    final list = _lists![index];
    if (_busy.contains(list.id)) return;
    setState(() => _busy.add(list.id));
    try {
      final res = list.hasPost == true
          ? await api.delete('playlists/${list.id}/posts/${widget.post.id}')
          : await api.post('playlists/${list.id}/posts', {'post_id': widget.post.id});
      final updated = Playlist.fromJson(Map<String, dynamic>.from(res.map['playlist'] as Map));
      if (!mounted) return;
      setState(() => _lists![index] = Playlist(
            id: updated.id,
            title: updated.title,
            description: updated.description,
            count: updated.count,
            coverUrl: updated.coverUrl,
            user: updated.user,
            isOwn: true,
            hasPost: list.hasPost != true,
            webUrl: updated.webUrl,
          ));
      toast(context, list.hasPost == true ? tr('Quitado de «{title}».', {'title': list.title}) : tr('Agregado a «{title}».', {'title': list.title}));
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(list.id));
    }
  }

  Future<void> _create() async {
    final created = await editPlaylist(context);
    if (created == null || !mounted) return;
    try {
      await api.post('playlists/${created.id}/posts', {'post_id': widget.post.id});
      if (mounted) toast(context, tr('Agregado a «{title}».', {'title': created.title}));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    return SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Text(tr('Agregar a una lista'), style: Tx.display(18), textAlign: TextAlign.center),
          ),
          if (_error != null)
            ErrorState(error: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          else if (lists == null)
            const Loading()
          else
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (var i = 0; i < lists.length; i++)
                  ListTile(
                    onTap: () => _toggle(i),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 38,
                        height: 50,
                        child: lists[i].coverUrl != null
                            ? NetImage(lists[i].coverUrl)
                            : Container(
                                decoration: const BoxDecoration(gradient: Tx.brand),
                                child: const Icon(CupertinoIcons.list_bullet, color: Colors.white, size: 18),
                              ),
                      ),
                    ),
                    title: Text(lists[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w600)),
                    subtitle: Text(plural(lists[i].count, 'video', 'videos'), style: Tx.body(12.5, color: Tx.muted)),
                    trailing: _busy.contains(lists[i].id)
                        ? const CupertinoActivityIndicator()
                        : Icon(
                            lists[i].hasPost == true ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.add_circled,
                            color: lists[i].hasPost == true ? Tx.accent : Tx.muted,
                          ),
                  ),
                ListTile(
                  onTap: _create,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(10)),
                    child: Icon(CupertinoIcons.add, color: Tx.text),
                  ),
                  title: Text(tr('Nueva lista'), style: Tx.body(15.5, weight: FontWeight.w600)),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
