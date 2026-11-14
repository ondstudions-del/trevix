import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/signals.dart';
import '../../core/theme.dart';
import '../../core/video_render.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/emoji_text.dart';
import '../../widgets/media.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/share_sheet.dart';
import '../../widgets/story_layers.dart' show filtered;
import '../messages/send_post_screen.dart';
import '../playlists/playlist_screens.dart';
import '../wallet/gifts_screen.dart';
import 'reel_comments.dart';

/// Abre Reels; con [start] empieza por ese video (el que se tocó en el inicio, Explorar o un perfil).
/// Con [list] reproduce solo esos videos y en su orden (una lista de reproducción o los videos de un sonido),
/// empezando por [start]; [title] reemplaza «Reels» arriba.
Future<void> openReels(BuildContext context, {Post? start, Paged<Post>? list, String? title}) => Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => ReelsScreen(start: start, list: list, title: title)),
    );

/// Reels: todos los videos publicados en TREVIX a pantalla completa, uno tras otro al deslizar hacia arriba.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.start, this.list, this.title});

  final Post? start;

  /// Lista ya cargada por la pantalla que abrió Reels (no se libera al salir).
  final Paged<Post>? list;
  final String? title;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> with WidgetsBindingObserver {
  /// El sonido se recuerda mientras la app está abierta, como en Facebook.
  static bool _muted = false;

  final _seed = Random().nextInt(999999) + 1;
  late final Paged<Post> _paged = widget.list ??
      Paged<Post>('reels', Post.fromJson, query: {
        'seed': '$_seed',
        if (widget.start != null) 'start': '${widget.start!.id}',
      });
  bool get _listMode => widget.list != null;
  late final PageController _page;
  int _index = 0;
  bool _foreground = true;
  List<Post> _items = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    songPlayer.pause();
    final start = widget.start;
    if (_listMode) {
      _items = _videos(_paged.items);
      _index = start == null ? 0 : max(0, _items.indexWhere((p) => p.id == start.id));
      _page = PageController(initialPage: _index);
      _paged.addListener(_sync);
      if (!_paged.loaded) _paged.refresh();
      return;
    }
    _page = PageController();
    if (start != null && start.media.any((m) => m.isVideo)) _items = [start];
    _paged.addListener(_sync);
    _paged.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paged.removeListener(_sync);
    if (!_listMode) _paged.dispose();
    _page.dispose();
    super.dispose();
  }

  static List<Post> _videos(List<Post> posts) {
    final seen = <int>{};
    return [for (final p in posts) if (p.media.any((m) => m.isVideo) && seen.add(p.id)) p];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground != _foreground && mounted) setState(() => _foreground = foreground);
  }

  /// Une lo cargado sin repetir videos (el que se tocó llega primero y no debe saltar al cargar).
  void _sync() {
    if (!mounted) return;
    final first = !_listMode && _items.isNotEmpty && _paged.items.isEmpty ? _items.first : null;
    setState(() => _items = _videos([if (first != null) first, ..._paged.items]));
  }

  void _onPage(int i) {
    setState(() => _index = i);
    if (i >= _items.length - 3 && _paged.hasMore) _paged.loadMore();
  }

  void _toggleMute() {
    HapticFeedback.selectionClick();
    setState(() => _muted = !_muted);
  }

  void _removed(Post post) {
    final i = _items.indexWhere((p) => p.id == post.id);
    if (i < 0) return;
    _paged.remove((p) => p.id == post.id);
    setState(() {
      _items.removeAt(i);
      if (_index >= _items.length && _index > 0) _index = _items.length - 1;
    });
  }

  /// Abre otra pantalla con el video en pausa y lo reanuda al volver.
  Future<void> _away(Future<void> Function() open) async {
    setState(() => _foreground = false);
    await open();
    if (mounted) setState(() => _foreground = true);
  }

  Future<void> _create() => _away(() async {
        final post = await openReelCamera(context);
        if (post != null && mounted && post.media.any((m) => m.isVideo)) {
          setState(() => _items.insert(_index, post));
        }
      });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _body()),
          Positioned(
            top: top + 4,
            left: 4,
            right: 8,
            child: Row(children: [
              _GlassIcon(icon: CupertinoIcons.chevron_back, onTap: () => Navigator.maybePop(context), tooltip: tr('Volver')),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title ?? 'Reels',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TxDark.display(widget.title == null ? 22 : 18, color: Colors.white).copyWith(shadows: _shadow),
                ),
              ),
              const SizedBox(width: 6),
              _GlassIcon(
                icon: _muted ? CupertinoIcons.speaker_slash_fill : CupertinoIcons.speaker_2_fill,
                onTap: _toggleMute,
                tooltip: _muted ? tr('Activar sonido') : tr('Silenciar'),
              ),
              if (!_listMode) ...[
                const SizedBox(width: 6),
                _GlassIcon(icon: CupertinoIcons.camera, onTap: _create, tooltip: tr('Crear reel')),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      if (_paged.error != null) {
        return Center(child: _Message(
          icon: CupertinoIcons.wifi_exclamationmark,
          title: tr('No se pudieron cargar los reels'),
          text: errorText(_paged.error!),
          action: tr('Reintentar'),
          onAction: _paged.refresh,
        ));
      }
      if (!_paged.loaded || _paged.loading) {
        return const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
      }
      if (_listMode) {
        return Center(child: _Message(
          icon: CupertinoIcons.film,
          title: tr('No hay videos'),
          text: tr('Esta lista todavía no tiene videos.'),
          action: tr('Volver'),
          onAction: () => Navigator.maybePop(context),
        ));
      }
      return Center(child: _Message(
        icon: CupertinoIcons.film,
        title: tr('Todavía no hay reels'),
        text: tr('Los videos que se publiquen en TREVIX aparecerán aquí. ¡Sube el primero!'),
        action: tr('Crear reel'),
        onAction: _create,
      ));
    }
    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: Colors.black54,
      edgeOffset: MediaQuery.paddingOf(context).top + 40,
      onRefresh: () async {
        await _paged.refresh();
        if (_page.hasClients) _page.jumpToPage(0);
        if (mounted) setState(() => _index = 0);
      },
      child: PageView.builder(
        controller: _page,
        scrollDirection: Axis.vertical,
        allowImplicitScrolling: true,
        itemCount: _items.length + (_paged.hasMore || _paged.loading ? 1 : 0),
        onPageChanged: _onPage,
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            if (_paged.error != null) {
              return Center(child: _Message(
                icon: CupertinoIcons.wifi_exclamationmark,
                title: tr('No se pudieron cargar más reels'),
                text: errorText(_paged.error!),
                action: tr('Reintentar'),
                onAction: _paged.retry,
              ));
            }
            return const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14));
          }
          final post = _items[i];
          return _ReelPage(
            key: ValueKey('reel-${post.id}'),
            post: post,
            active: i == _index && _foreground,
            near: (i - _index).abs() <= 1,
            muted: _muted,
            onToggleMute: _toggleMute,
            onAway: _away,
            onRemoved: () => _removed(post),
          );
        },
      ),
    );
  }
}

const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 8)];

/// Un reel: el video ajustado a la pantalla, la autora o el autor, el texto y las acciones.
class _ReelPage extends StatefulWidget {
  const _ReelPage({
    super.key,
    required this.post,
    required this.active,
    required this.near,
    required this.muted,
    required this.onToggleMute,
    required this.onAway,
    required this.onRemoved,
  });

  final Post post;
  final bool active;
  final bool near;
  final bool muted;
  final VoidCallback onToggleMute;
  final Future<void> Function(Future<void> Function() open) onAway;
  final VoidCallback onRemoved;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> with SingleTickerProviderStateMixin {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _pausedByUser = false;
  bool _expanded = false;
  bool _likeBusy = false;
  bool _followBusy = false;
  double? _scrub;
  late final AnimationController _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));

  /// Tiempo que el reel estuvo en pantalla (alimenta los intereses de «Para ti»).
  final _time = ScreenTime();

  Post get p => widget.post;
  Media get _video => p.media.firstWhere((m) => m.isVideo);

  @override
  void initState() {
    super.initState();
    if (widget.near) {
      _load();
      if (_video.songSync) songPlayer.prefetch(p.song);
    }
    if (widget.active) _time.start();
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.near && _c == null && !_failed) {
      _load();
      if (_video.songSync) songPlayer.prefetch(p.song);
    }
    if (!widget.near && _c != null) _release();
    if (old.active && !widget.active) _pausedByUser = false;
    if (!old.active && widget.active) _time.start();
    if (old.active && !widget.active) Signals.view(p, _time.stop());
    _applyPlayback();
  }

  @override
  void dispose() {
    if (_time.running) Signals.view(p, _time.stop());
    _heart.dispose();
    final c = _c;
    _c = null;
    c?.removeListener(_tick);
    releaseVideo(c);
    songPlayer.stop(_songKey);
    super.dispose();
  }

  Future<void> _load() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(_video.url), videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      if (_c != c || !mounted) return;
      c.addListener(_tick);
      setState(() {});
      _applyPlayback();
    } catch (_) {
      if (_c == c && mounted) {
        setState(() {
          _c = null;
          _failed = true;
        });
      }
      releaseVideo(c);
    }
  }

  void _release() {
    final c = _c;
    _c = null;
    c?.removeListener(_tick);
    releaseVideo(c);
    songPlayer.stop(_songKey);
  }

  void _tick() {
    if (mounted) setState(() {});
    _keepSongInSync();
  }

  /// Lo que suena, como en TikTok: la canción con su artista o el sonido original con el @ de quien lo publicó.
  String get _soundLabel {
    final song = p.song;
    if (song == null) return tr('Sonido original · @{username}', {'username': p.user.username});
    if (!song.available) return tr('Canción no disponible');
    if (song.isOriginal) return '${song.title.isEmpty ? tr('Sonido original') : song.title} · @${song.artist?.username ?? p.user.username}';
    return song.artist != null && song.artist!.displayName.isNotEmpty ? '${song.title} · ${song.artist!.displayName}' : song.title;
  }

  void _openSound() {
    final song = p.song;
    if (song == null || !song.available) {
      toast(context, tr('Este video usa su propio sonido.'));
      return;
    }
    widget.onAway(() async => openSong(context, song.id, song: song));
  }

  /// Video grabado sobre la canción (cámara de reels): no tiene sonido propio y la canción suena a su compás.
  bool get _synced => _video.songSync && p.song != null && p.song!.available;
  String get _songKey => 'reel-sync:${p.id}';
  bool _songStarting = false;
  DateTime _lastSongSeek = DateTime.fromMillisecondsSinceEpoch(0);

  Song get _syncedSong {
    final song = p.song!;
    final length = max(30, _video.duration ?? 30);
    return song.withClip(song.clipStart ?? 0, length);
  }

  Future<void> _startSong(VideoPlayerController c) async {
    if (_songStarting) return;
    _songStarting = true;
    try {
      if (songPlayer.currentKey != _songKey) {
        final ok = await songPlayer.prepare(_songKey, _syncedSong, clip: true, at: c.value.position);
        if (!ok || !mounted) return;
      } else {
        await songPlayer.seek(c.value.position);
      }
      await songPlayer.setVolume(widget.muted ? 0 : 1);
      if (widget.active && !_pausedByUser && c.value.isPlaying) await songPlayer.resume(_songKey);
    } finally {
      _songStarting = false;
    }
  }

  /// Corrige el desfase entre el video y la canción (también cuando el video vuelve a empezar).
  void _keepSongInSync() {
    final c = _c;
    if (!_synced || c == null || !c.value.isPlaying || songPlayer.currentKey != _songKey || _songStarting) return;
    // Si la canción es más corta que el video, el resto del video sigue en silencio.
    final song = _syncedSong;
    if (song.hasClip && c.value.position.inSeconds >= song.clipEnd! - song.clipStart!) return;
    final drift = (songPlayer.positionNow - c.value.position).inMilliseconds.abs();
    final now = DateTime.now();
    if (drift > 300 && now.difference(_lastSongSeek) > const Duration(milliseconds: 900)) {
      _lastSongSeek = now;
      songPlayer.seek(c.value.position);
    }
    if (!songPlayer.playing) songPlayer.resume(_songKey);
  }

  void _applyPlayback() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final synced = _synced;
    c.setVolume(widget.muted || synced ? 0 : 1);
    final play = widget.active && !_pausedByUser;
    if (play && !c.value.isPlaying) {
      if (!synced) songPlayer.pause();
      c.play().then((_) {
        if (synced && mounted) _startSong(c);
      });
    } else if (!play && c.value.isPlaying) {
      c.pause();
      if (synced && songPlayer.currentKey == _songKey) songPlayer.pause();
    } else if (play && synced && songPlayer.currentKey == _songKey) {
      songPlayer.setVolume(widget.muted ? 0 : 1);
    }
    if (!widget.active && synced && songPlayer.currentKey == _songKey) songPlayer.stop(_songKey);
    if (!widget.active && c.value.position > Duration.zero && !widget.near) c.seekTo(Duration.zero);
  }

  void _togglePause() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    setState(() => _pausedByUser = !_pausedByUser);
    _applyPlayback();
  }

  Future<void> _like({bool fromDoubleTap = false}) async {
    if (fromDoubleTap) {
      _heart.forward(from: 0);
      if (p.liked) return;
    }
    if (_likeBusy) return;
    _likeBusy = true;
    final was = p.liked;
    HapticFeedback.lightImpact();
    setState(() {
      p.liked = !was;
      p.likes += was ? -1 : 1;
    });
    try {
      final res = was ? await api.delete('posts/${p.id}/like') : await api.post('posts/${p.id}/like');
      p.liked = asBool(res.map['liked']);
      p.likes = asInt(res.map['count'], p.likes);
    } catch (e) {
      p.liked = was;
      p.likes += was ? 1 : -1;
      if (mounted) toastError(context, e);
    }
    _likeBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> _follow() async {
    if (_followBusy) return;
    setState(() => _followBusy = true);
    HapticFeedback.selectionClick();
    try {
      final res = await api.post('users/${p.user.id}/follow');
      final rel = res.map['relation'];
      p.user.relation = rel is Map ? Relation.fromJson(Map<String, dynamic>.from(rel)) : Relation(following: true);
      if (mounted) {
        toast(context, p.user.relation!.requested ? tr('Solicitud enviada a @{username}.', {'username': p.user.username}) : tr('Ahora sigues a @{username}.', {'username': p.user.username}));
        context.read<AppState>().refreshCounts();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _followBusy = false);
  }

  void _comments([String initialText = '']) => widget.onAway(
        () => showReelComments(context, p, initialText: initialText, onChanged: () {
          if (mounted) setState(() {});
        }),
      );

  void _profile() => widget.onAway(() => openProfile(context, p.user.username));

  Future<void> _share() async {
    final text = plainText(p.body.trim());
    await showShareSheet(
      context,
      url: p.webUrl,
      onShared: () => Signals.share(p),
      title: text.isEmpty
          ? tr('Reel de {name} en TREVIX', {'name': p.user.displayName})
          : tr('{name} en TREVIX: {text}', {'name': p.user.displayName, 'text': text.length > 120 ? '${text.substring(0, 119)}…' : text}),
      extra: [
        SheetAction(tr('Enviar por mensaje'), CupertinoIcons.paperplane, () => widget.onAway(() => openSendPost(context, p))),
        SheetAction(tr('Compartir en TREVIX'), CupertinoIcons.arrow_2_squarepath, () async {
          await widget.onAway(() async {
            final created = await openComposer(context, share: p);
            if (created != null && mounted) setState(() => p.shares += 1);
          });
        }),
        SheetAction(tr('Descargar'), CupertinoIcons.arrow_down_to_line, () => widget.onAway(() => downloadReel(context, p))),
      ],
    );
  }

  void _menu() {
    actionSheet(context, [
      if (!p.isAuthor) SheetAction(tr('No me importa'), CupertinoIcons.eye_slash, _notInterested),
      SheetAction(tr('Copiar enlace'), CupertinoIcons.link, () {
        Clipboard.setData(ClipboardData(text: p.webUrl));
        toast(context, tr('Enlace copiado.'));
      }),
      if (!p.isAuthor) SheetAction(tr('Ver perfil de @{username}', {'username': p.user.username}), CupertinoIcons.person, _profile),
      if (p.isAuthor && (context.read<AppState>().me?.user.isCreator ?? false))
        SheetAction(tr('Agregar a una lista'), CupertinoIcons.list_bullet, () => widget.onAway(() => showPlaylistPicker(context, p))),
      if (p.isAuthor) SheetAction(tr('Eliminar'), CupertinoIcons.trash, _delete, destructive: true),
      if (!p.isAuthor) SheetAction(tr('Reportar'), CupertinoIcons.flag, () => showReportSheet(context, 'post', p.id), destructive: true),
    ]);
  }

  Future<void> _notInterested() async {
    try {
      await api.post('posts/${p.id}/not-interested');
      if (!mounted) return;
      toast(context, tr('Listo: verás menos reels como este.'));
      widget.onRemoved();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete() async {
    if (!await confirm(context, tr('Eliminar reel'), tr('Se eliminará para siempre junto con sus comentarios.'), action: tr('Eliminar'), destructive: true)) return;
    try {
      await api.delete('posts/${p.id}');
      if (mounted) toast(context, tr('Reel eliminado.'));
      widget.onRemoved();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _seekTo(double fraction) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final total = c.value.duration.inMilliseconds;
    if (total <= 0) return;
    c.seekTo(Duration(milliseconds: (total * fraction.clamp(0.0, 1.0)).round()));
  }

  @override
  Widget build(BuildContext context) {
    final media = _video;
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final aspect = ready && c.value.aspectRatio > 0 ? c.value.aspectRatio : (media.width != null && media.height != null && media.height! > 0 ? media.width! / media.height! : 9 / 16);
    // Vertical (como los reels grabados con el móvil): llena la pantalla. Horizontal o cuadrado: entero y centrado.
    final fill = aspect < (screen.width / screen.height) * 1.25;
    final fit = fill ? BoxFit.cover : BoxFit.contain;

    Widget picture;
    if (ready) {
      final size = c.value.size;
      picture = SizedBox.expand(
        child: FittedBox(fit: fit, clipBehavior: Clip.hardEdge, child: SizedBox(width: size.width, height: size.height, child: filtered(media.filter, VideoPlayer(c)))),
      );
    } else {
      picture = media.posterUrl != null ? SizedBox.expand(child: filtered(media.filter, NetImage(media.posterUrl, fit: fit))) : const SizedBox.expand();
    }

    final total = ready ? c.value.duration.inMilliseconds : 0;
    final progress = _scrub ?? (total > 0 ? c!.value.position.inMilliseconds / total : 0.0);
    final buffering = ready && c.value.isBuffering && widget.active && !_pausedByUser;
    final body = p.body.trim();
    final me = context.read<AppState>().me;
    final rel = p.user.relation;
    final canFollow = me != null && me.id != p.user.id && !(rel?.following ?? false) && !(rel?.requested ?? false);

    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (!fill && media.posterUrl != null)
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Opacity(opacity: .45, child: NetImage(media.posterUrl, fit: BoxFit.cover)),
        ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _togglePause,
        onDoubleTap: () => _like(fromDoubleTap: true),
        child: picture,
      ),
      if (!ready && !_failed && widget.near) const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
      if (buffering) const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
      if (_failed)
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.white70, size: 30),
            const SizedBox(height: 8),
            Text(tr('No se pudo reproducir este video'), style: TxDark.body(14, color: Colors.white70)),
            const SizedBox(height: 10),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              onPressed: () {
                setState(() => _failed = false);
                _load();
              },
              child: Text(tr('Reintentar'), style: TxDark.body(14, weight: FontWeight.w700, color: Colors.white)),
            ),
          ]),
        ),
      if (ready && _pausedByUser)
        IgnorePointer(
          child: Center(
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withAlpha(100)),
              child: const Padding(padding: EdgeInsets.only(left: 5), child: Icon(CupertinoIcons.play_fill, color: Colors.white, size: 36)),
            ),
          ),
        ),
      IgnorePointer(child: Center(child: _HeartBurst(controller: _heart))),
      // Degradados para que el texto y los botones se lean sobre cualquier video.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x80000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
              stops: [0, .16, .55, 1],
            ),
          ),
        ),
      ),
      Positioned(
        right: 8,
        bottom: pad.bottom + 34,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: _profile,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
              child: Avatar(user: p.user, size: 42),
            ),
          ),
          const SizedBox(height: 18),
          _SideAction(
            glyph: TxGlyph.heart,
            filled: p.liked,
            color: p.liked ? Tx.like : Colors.white,
            label: p.likes > 0 ? compact(p.likes) : tr('Me gusta'),
            onTap: _like,
          ),
          _SideAction(glyph: TxGlyph.comment, label: p.comments > 0 ? compact(p.comments) : tr('Comentar'), onTap: _comments),
          _SideAction(glyph: TxGlyph.share, label: p.shares > 0 ? compact(p.shares) : tr('Compartir'), onTap: _share),
          if (!p.isAuthor) _SideAction(glyph: TxGlyph.gift, label: tr('Regalo'), onTap: () => sendGift(context, p.user, where: 'post', refId: p.id)),
          _SideAction(glyph: TxGlyph.more, label: '', onTap: _menu),
          const SizedBox(height: 6),
          _SoundDisc(
            song: p.song != null && p.song!.available ? p.song : null,
            user: p.user,
            spinning: ready && widget.active && !_pausedByUser,
            onTap: _openSound,
          ),
        ]),
      ),
      // Comentar con emojis sin salir del video (como en los reels de Facebook).
      Positioned(
        left: 12,
        right: 76,
        bottom: pad.bottom + 28,
        height: 40,
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _comments,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(36),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withAlpha(60)),
                ),
                child: Text(tr('Añade un comentario…'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TxDark.body(13.5, color: Colors.white.withAlpha(220))),
              ),
            ),
          ),
          for (final e in const ['❤️', '😂', '🔥'])
            GestureDetector(
              onTap: () => _comments(e),
              behavior: HitTestBehavior.opaque,
              child: Padding(padding: const EdgeInsets.only(left: 8), child: Text(e, style: const TextStyle(fontSize: 24))),
            ),
        ]),
      ),
      Positioned(
        left: 14,
        right: 76,
        bottom: pad.bottom + 80,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Flexible(
              child: GestureDetector(
                onTap: _profile,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: ShadowText(
                      p.user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TxDark.body(15.5, weight: FontWeight.w700, color: Colors.white).copyWith(shadows: _shadow),
                    ),
                  ),
                  if (p.user.isVerified) ...[
                    const SizedBox(width: 4),
                    const Icon(CupertinoIcons.checkmark_seal_fill, size: 15, color: Color(0xFF60A5FA)),
                  ],
                ]),
              ),
            ),
            if (canFollow) ...[
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _follow,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withAlpha(200)),
                    color: Colors.white.withAlpha(25),
                  ),
                  child: _followBusy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(tr('Seguir'), style: TxDark.body(13, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 3),
          Text(
            [
              '@${p.user.username}',
              timeAgo(p.createdAt),
              // Visualizaciones: solo las ve quien publicó el reel.
              if (p.views != null) tr('{n} visualizaciones', {'n': compact(p.views!)}),
            ].join(' · '),
            style: TxDark.body(12.5, color: Colors.white.withAlpha(200)).copyWith(shadows: _shadow),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _expanded ? screen.height * .35 : double.infinity),
                child: SingleChildScrollView(
                  physics: _expanded ? null : const NeverScrollableScrollPhysics(),
                  child: RichBody(
                    body,
                    maxLines: _expanded ? null : 2,
                    style: TxDark.body(14.5, color: Colors.white, height: 1.4).copyWith(shadows: _shadow),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _openSound,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const TxIcon(TxGlyph.music, size: 14, color: Colors.white, stroke: 2.2),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: _Marquee(
                    text: _soundLabel,
                    running: ready && widget.active && !_pausedByUser,
                    style: TxDark.body(13, weight: FontWeight.w600, color: Colors.white).copyWith(shadows: _shadow),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
      // Barra de progreso: se puede arrastrar para adelantar o retroceder.
      Positioned(
        left: 0,
        right: 0,
        bottom: pad.bottom,
        height: 26,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: ready ? (d) => setState(() => _scrub = d.localPosition.dx / screen.width) : null,
          onHorizontalDragUpdate: ready ? (d) => setState(() => _scrub = (d.localPosition.dx / screen.width).clamp(0.0, 1.0)) : null,
          onHorizontalDragEnd: ready
              ? (_) {
                  final f = _scrub;
                  setState(() => _scrub = null);
                  if (f != null) _seekTo(f);
                }
              : null,
          onTapUp: ready ? (d) => _seekTo(d.localPosition.dx / screen.width) : null,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Stack(children: [
              Container(height: _scrub != null ? 5 : 2.5, color: Colors.white.withAlpha(60)),
              FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0).toDouble(),
                child: Container(height: _scrub != null ? 5 : 2.5, color: Colors.white),
              ),
            ]),
          ),
        ),
      ),
      if (_scrub != null && total > 0)
        Positioned(
          bottom: pad.bottom + 40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(12)),
              child: Text(
                '${clockText((total * _scrub! / 1000).round())} / ${clockText((total / 1000).round())}',
                style: TxDark.body(14, weight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({required this.glyph, required this.label, required this.onTap, this.color = Colors.white, this.filled = false});

  final TxGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            AnimatedScale(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              scale: filled ? 1.12 : 1,
              child: DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 14)]),
                child: TxIcon(glyph, size: 30, color: color, filled: filled, stroke: 2),
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TxDark.body(12, weight: FontWeight.w600, color: Colors.white).copyWith(shadows: _shadow),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Texto en una línea que, si no cabe, se desplaza en bucle mientras [running] (el nombre del sonido del reel).
class _Marquee extends StatefulWidget {
  const _Marquee({required this.text, required this.style, required this.running});

  final String text;
  final TextStyle style;
  final bool running;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  static const _gap = 42.0;
  late final AnimationController _c = AnimationController(vsync: this);
  bool _overflows = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _sync(double cycle) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ms = (cycle * 30).round().clamp(2000, 60000);
      if (_c.duration?.inMilliseconds != ms) _c.duration = Duration(milliseconds: ms);
      if (_overflows && widget.running) {
        if (!_c.isAnimating) _c.repeat();
      } else if (_c.isAnimating) {
        _c.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        maxLines: 1,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      final height = painter.height;
      painter.dispose();
      _overflows = box.hasBoundedWidth && width > box.maxWidth;
      final cycle = width + _gap;
      _sync(cycle);
      if (!_overflows) return Text(widget.text, maxLines: 1, style: widget.style);
      final line = Text(widget.text, maxLines: 1, softWrap: false, style: widget.style);
      return SizedBox(
        width: box.maxWidth,
        height: height,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform.translate(offset: Offset(-cycle * _c.value, 0), child: child),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              child: Row(mainAxisSize: MainAxisSize.min, children: [line, const SizedBox(width: _gap), line]),
            ),
          ),
        ),
      );
    });
  }
}

/// Disco que gira mientras suena el reel, con la portada de la canción (o la foto de quien publicó el sonido).
class _SoundDisc extends StatefulWidget {
  const _SoundDisc({required this.song, required this.user, required this.spinning, required this.onTap});

  final Song? song;
  final User user;
  final bool spinning;
  final VoidCallback onTap;

  @override
  State<_SoundDisc> createState() => _SoundDiscState();
}

class _SoundDiscState extends State<_SoundDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _turn.repeat();
  }

  @override
  void didUpdateWidget(covariant _SoundDisc old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!widget.spinning && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final owner = song?.isOriginal == true ? (song!.artist ?? widget.user) : widget.user;
    final cover = song != null && (!song.isOriginal || song.coverCustom) ? song.coverUrl : null;
    return Semantics(
      button: true,
      label: tr('Ver el sonido'),
      child: GestureDetector(
        onTap: widget.onTap,
        child: RotationTransition(
          turns: _turn,
          child: Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(colors: [Color(0xFF1A1A1A), Color(0xFF444444), Color(0xFF1A1A1A), Color(0xFF444444), Color(0xFF1A1A1A)]),
              border: Border.all(color: Colors.white24),
              boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10)],
            ),
            child: ClipOval(
              child: cover != null ? NetImage(cover, fit: BoxFit.cover) : Avatar(user: owner, size: 26),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 40,
              height: 40,
              color: Colors.black.withAlpha(70),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeartBurst extends StatelessWidget {
  const _HeartBurst({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final scale = t < .3 ? Curves.easeOutBack.transform(t / .3) * 1.1 : 1.1 - (t - .3) * .3;
        final opacity = t < .7 ? 1.0 : 1 - (t - .7) / .3;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: const TxIcon(TxGlyph.heart, size: 110, color: Colors.white, filled: true),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: TxDark.display(20, color: Colors.white)),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: TxDark.body(14, color: TxDark.muted, height: 1.45)),
        const SizedBox(height: 18),
        GestureDetector(
          onTap: onAction,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(14)),
            child: Text(action, style: TxDark.body(15, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ]),
    );
  }
}
