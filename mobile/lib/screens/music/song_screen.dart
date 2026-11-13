import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/song_chip.dart';
import '../explore/explore_screen.dart';
import '../notes/note_sheets.dart';
import '../reels/reels_screen.dart';
import '../stories/story_create_screen.dart';

/// Ficha de una canción o de un sonido original: reproductor completo, «Usar» (reel, historia, nota, publicación o
/// perfil) y publicaciones que la usan.
class SongScreen extends StatefulWidget {
  const SongScreen({super.key, required this.songId, this.initial});

  final int songId;
  final Song? initial;

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  late Song? _song = widget.initial;
  Object? _error;
  late final Paged<Post> _posts = Paged<Post>('music/${widget.songId}/posts', Post.fromJson);

  String get _key => 'song:${widget.songId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _posts.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('music/${widget.songId}');
      if (mounted) {
        setState(() {
          _song = Song.fromJson(res.map);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Usar la canción o el sonido original: grabar un reel a su compás, en una historia, una nota, una publicación o
  /// como canción del perfil.
  void _use(Song s) {
    actionSheet(context, [
      SheetAction(tr('Grabar un reel con este sonido'), CupertinoIcons.videocam, () => openReelCamera(context, song: s)),
      SheetAction(tr('Usar en una historia'), CupertinoIcons.circle_grid_hex, () => push(context, StoryCreateScreen(song: s), fullscreen: true)),
      SheetAction(tr('Usar en una nota'), CupertinoIcons.text_bubble, () => composeNote(context, song: s)),
      SheetAction(tr('Usar en una publicación'), CupertinoIcons.square_pencil, () => openComposer(context, song: s)),
      SheetAction(tr('Poner en mi perfil'), CupertinoIcons.person_crop_circle, () => _setProfileSong(s)),
    ], title: s.isOriginal ? tr('Usar este sonido') : tr('Usar esta canción'));
  }

  Future<void> _setProfileSong(Song s) async {
    try {
      final res = await api.put('me/profile-song', {'song_id': s.id, 'song_start': s.clipStart ?? 0});
      if (mounted) toast(context, '${res.map['message'] ?? tr('Tu perfil ya tiene canción.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// El sonido original es de quien lo escucha: puede ponerle nombre y portada.
  bool _canEdit(Song s) {
    final me = context.read<AppState>().me;
    return s.isOriginal && me != null && s.artist?.id == me.id;
  }

  void _editSound(Song s) {
    actionSheet(context, [
      SheetAction(tr('Cambiar el nombre'), CupertinoIcons.pencil, () => _rename(s)),
      SheetAction(s.coverCustom ? tr('Cambiar la portada') : tr('Ponerle una portada'), CupertinoIcons.photo, () => _pickCover(s)),
      if (s.coverCustom) SheetAction(tr('Quitar la portada'), CupertinoIcons.trash, () => _saveSound(s, {'remove_cover': 1}), destructive: true),
    ], title: tr('Editar sonido'));
  }

  Future<void> _rename(Song s) async {
    final original = tr('Sonido original');
    final title = await prompt(
      context,
      tr('Nombre del sonido'),
      hint: tr('Por ejemplo: «Mi ritmo de verano»'),
      initial: s.title == original ? '' : s.title,
      maxLength: 100,
      message: tr('Se verá en tus reels y en la biblioteca de música, no en tu perfil.'),
    );
    if (title == null || title.isEmpty || title == s.title || !mounted) return;
    await _saveSound(s, {'title': title});
  }

  Future<void> _pickCover(Song s) async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir la galería.'), error: true);
      return;
    }
    if (file == null || !mounted) return;
    await _saveSound(s, const {}, cover: file.path);
  }

  Future<void> _saveSound(Song s, Map<String, dynamic> body, {String? cover}) async {
    try {
      final res = cover != null
          ? await api.upload('me/sounds/${s.id}', files: [Upload('cover', cover)])
          : await api.post('me/sounds/${s.id}', body);
      if (!mounted) return;
      final song = res.map['song'];
      if (song is Map) setState(() => _song = Song.fromJson(Map<String, dynamic>.from(song)));
      toast(context, '${res.map['message'] ?? tr('Guardamos los cambios del sonido.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _menu(Song s) {
    actionSheet(context, [
      if (_canEdit(s)) SheetAction(tr('Editar nombre y portada'), CupertinoIcons.pencil_circle, () => _editSound(s)),
      SheetAction(s.isOriginal ? tr('Usar este sonido') : tr('Usar esta canción'), CupertinoIcons.music_note_2, () => _use(s)),
      if (s.isOriginal && s.originPostId != null)
        SheetAction(tr('Ver video original'), CupertinoIcons.film, () => openPost(context, s.originPostId!)),
      if (s.webUrl.isNotEmpty)
        SheetAction(tr('Compartir'), CupertinoIcons.share,
            () => showShareSheet(context, url: s.webUrl, title: tr('Escucha «{title}» de {artist} en TREVIX', {'title': s.title, 'artist': s.artistLine}))),
      if (s.webUrl.isNotEmpty)
        SheetAction(tr('Copiar enlace'), CupertinoIcons.link, () {
          Clipboard.setData(ClipboardData(text: s.webUrl));
          toast(context, tr('Enlace copiado.'));
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _song;
    if (s == null) {
      return Scaffold(
        appBar: GlassBar(title: tr('Canción')),
        body: _error != null
            ? (_error is ApiException && (_error as ApiException).status == 404
                ? EmptyState(icon: CupertinoIcons.music_note_2, title: tr('Canción no disponible'), message: tr('Puede que el artista la haya retirado.'))
                : ErrorState(error: _error!, onRetry: () {
                    setState(() => _error = null);
                    _load();
                  }))
            : const Loading(),
      );
    }
    return Scaffold(
      appBar: GlassBar(
        title: s.isOriginal ? tr('Sonido') : tr('Canción'),
        actions: [IconButton(onPressed: () => _menu(s), icon: Icon(CupertinoIcons.ellipsis_circle, color: Tx.text))],
      ),
      body: s.isOriginal ? _videoGrid(s) : PagedView<Post>(
        paged: _posts,
        onRefresh: _load,
        header: [
          SliverToBoxAdapter(child: _player(s)),
          SliverToBoxAdapter(
            child: SectionTitle(tr('Publicaciones con esta canción'), padding: const EdgeInsets.fromLTRB(16, 26, 16, 8)),
          ),
        ],
        empty: EmptyState(
          icon: CupertinoIcons.music_note_list,
          title: tr('Aún nadie la ha usado'),
          message: tr('Sé la primera persona en publicar con esta canción.'),
        ),
        itemBuilder: postBuilder(_posts),
      ),
    );
  }

  Widget _player(Song s) => _Player(
        song: s,
        playKey: _key,
        onUse: () => _use(s),
        onOrigin: s.isOriginal && s.originPostId != null ? () => openPost(context, s.originPostId!) : null,
        onEdit: _canEdit(s) ? () => _editSound(s) : null,
      );

  /// Sonido original: rejilla de los reels que lo usan; al tocar uno se reproducen en Reels en ese orden.
  Widget _videoGrid(Song s) {
    if (!_posts.loaded && !_posts.loading) Future.microtask(_posts.refresh);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _posts.loadMore();
        return false;
      },
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          CupertinoSliverRefreshControl(onRefresh: () => Future.wait([_load(), _posts.refresh()])),
          SliverToBoxAdapter(child: _player(s)),
          SliverToBoxAdapter(child: SectionTitle(tr('Videos con este sonido'), padding: const EdgeInsets.fromLTRB(16, 26, 16, 8))),
          ListenableBuilder(
            listenable: _posts,
            builder: (context, _) {
              final videos = _posts.items.where((p) => p.hasVideo).toList();
              if (videos.isEmpty) {
                if (_posts.error != null) return SliverToBoxAdapter(child: ErrorState(error: _posts.error!, onRetry: _posts.retry));
                if (!_posts.loaded || _posts.loading) return const SliverToBoxAdapter(child: Loading(padding: 50));
                return SliverToBoxAdapter(
                  child: EmptyState(
                    icon: CupertinoIcons.music_note_list,
                    title: tr('Aún nadie la ha usado'),
                    message: tr('Sé la primera persona en grabar un reel con este sonido.'),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 9 / 14),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => MediaTile(post: videos[i], onTap: () => openReels(context, start: videos[i], list: _posts, title: s.title)),
                    childCount: videos.length,
                  ),
                ),
              );
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({required this.song, required this.playKey, required this.onUse, this.onOrigin, this.onEdit});

  final Song song;
  final String playKey;
  final VoidCallback onUse;

  /// Sonido original: abre el video del que sale.
  final VoidCallback? onOrigin;

  /// Sonido original propio: cambiar nombre y portada.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cover = (width - 120).clamp(180.0, 320.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(children: [
        GestureDetector(
          onTap: onEdit,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .45), blurRadius: 50, offset: const Offset(0, 18))],
              ),
              child: SongCover(url: song.coverUrl, size: cover, radius: 28),
            ),
            if (onEdit != null)
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.black.withAlpha(170), shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.pencil, color: Colors.white, size: 18),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(child: Text(song.title, textAlign: TextAlign.center, style: Tx.display(24))),
          if (song.isExplicit) ...[const SizedBox(width: 8), const ExplicitTag()],
        ]),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: song.artist != null && !song.isExternal ? () => openProfile(context, song.artist!.username) : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (song.artist != null && !song.isExternal) ...[Avatar(user: song.artist!, size: 22), const SizedBox(width: 8)],
            Flexible(child: Text(song.artistLine, maxLines: 2, textAlign: TextAlign.center, style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent))),
            if (song.artist?.isVerified ?? false) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (song.isOriginal) tr('Sonido original de un video') else if (song.genreLabel.isNotEmpty) song.genreLabel,
            plural(song.usesCount, 'uso', 'usos'),
            if (song.publishedAt != null) monthYear(song.publishedAt),
          ].join(' · '),
          style: Tx.body(13, color: Tx.subtle),
        ),
        const SizedBox(height: 18),
        _Progress(song: song, playKey: playKey),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _SkipButton(icon: CupertinoIcons.gobackward_15, playKey: playKey, delta: -15),
          const SizedBox(width: 26),
          PlayButton(playKey: playKey, song: song, size: 72),
          const SizedBox(width: 26),
          _SkipButton(icon: CupertinoIcons.goforward_15, playKey: playKey, delta: 15),
        ]),
        const SizedBox(height: 22),
        GradientButton(label: song.isOriginal ? tr('Usar este sonido') : tr('Usar esta canción'), icon: CupertinoIcons.music_note_2, height: 50, onPressed: onUse),
        if (onEdit != null) ...[
          const SizedBox(height: 10),
          SoftButton(label: tr('Editar nombre y portada'), icon: CupertinoIcons.pencil, height: 44, expand: true, onPressed: onEdit),
        ],
        if (onOrigin != null)
          CupertinoButton(
            padding: const EdgeInsets.only(top: 10),
            onPressed: onOrigin,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.film, size: 17, color: Tx.accent),
              const SizedBox(width: 6),
              Text(tr('Ver video original'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
            ]),
          ),
        if (song.isExternal) ...[
          const SizedBox(height: 14),
          Text(song.credit, textAlign: TextAlign.center, style: Tx.body(12.5, color: Tx.subtle, height: 1.4)),
          if (song.externalUrl != null)
            CupertinoButton(
              padding: const EdgeInsets.only(top: 6),
              onPressed: () => openUrl(context, song.externalUrl!),
              child: Text(tr('Ver en {source}', {'source': song.sourceLabel}), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent)),
            ),
        ],
      ]),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.song, required this.playKey});

  final Song song;
  final String playKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: songPlayer,
      builder: (context, _) {
        final active = songPlayer.currentKey == playKey;
        final total = (songPlayer.duration?.inMilliseconds ?? song.duration * 1000).toDouble();
        return StreamBuilder<Duration>(
          stream: active ? songPlayer.position : null,
          builder: (context, snap) {
            final pos = active ? (snap.data?.inMilliseconds ?? 0).toDouble() : 0.0;
            final max = total <= 0 ? 1.0 : total;
            return Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: Tx.accentSoft,
                  inactiveTrackColor: Tx.surface4,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: pos.clamp(0.0, max).toDouble(),
                  max: max,
                  onChanged: active ? (v) => songPlayer.seek(Duration(milliseconds: v.round())) : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  Text(clock(pos / 1000), style: Tx.body(12, color: Tx.subtle)),
                  const Spacer(),
                  Text(clock(max / 1000), style: Tx.body(12, color: Tx.subtle)),
                ]),
              ),
            ]);
          },
        );
      },
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.icon, required this.playKey, required this.delta});

  final IconData icon;
  final String playKey;
  final int delta;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: songPlayer.position,
      builder: (context, snap) => IconButton(
        iconSize: 30,
        onPressed: () {
          if (songPlayer.currentKey != playKey) return;
          final now = snap.data ?? Duration.zero;
          final target = now + Duration(seconds: delta);
          songPlayer.seek(target.isNegative ? Duration.zero : target);
        },
        icon: Icon(icon, color: Tx.muted),
      ),
    );
  }
}
