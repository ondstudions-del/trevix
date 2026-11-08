import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/song_chip.dart';

/// Ficha de una canción: reproductor completo y publicaciones que la usan.
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

  void _menu(Song s) {
    actionSheet(context, [
      SheetAction('Usar en una publicación', CupertinoIcons.square_pencil, () => openComposer(context, song: s)),
      if (s.webUrl.isNotEmpty) SheetAction('Compartir', CupertinoIcons.share, () => Share.share('${s.title} · ${s.artistLine}\n${s.webUrl}')),
      if (s.webUrl.isNotEmpty)
        SheetAction('Copiar enlace', CupertinoIcons.link, () {
          Clipboard.setData(ClipboardData(text: s.webUrl));
          toast(context, 'Enlace copiado.');
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = _song;
    if (s == null) {
      return Scaffold(
        appBar: const GlassBar(title: 'Canción'),
        body: _error != null
            ? (_error is ApiException && (_error as ApiException).status == 404
                ? const EmptyState(icon: CupertinoIcons.music_note_2, title: 'Canción no disponible', message: 'Puede que el artista la haya retirado.')
                : ErrorState(error: _error!, onRetry: () {
                    setState(() => _error = null);
                    _load();
                  }))
            : const Loading(),
      );
    }
    return Scaffold(
      appBar: GlassBar(
        title: 'Canción',
        actions: [IconButton(onPressed: () => _menu(s), icon: const Icon(CupertinoIcons.ellipsis_circle, color: Tx.text))],
      ),
      body: PagedView<Post>(
        paged: _posts,
        onRefresh: _load,
        header: [
          SliverToBoxAdapter(child: _Player(song: s, playKey: _key, onUse: () => openComposer(context, song: s))),
          SliverToBoxAdapter(
            child: SectionTitle('Publicaciones con esta canción', padding: const EdgeInsets.fromLTRB(16, 26, 16, 8)),
          ),
        ],
        empty: const EmptyState(
          icon: CupertinoIcons.music_note_list,
          title: 'Aún nadie la ha usado',
          message: 'Sé la primera persona en publicar con esta canción.',
        ),
        itemBuilder: postBuilder(_posts),
      ),
    );
  }
}

class _Player extends StatelessWidget {
  const _Player({required this.song, required this.playKey, required this.onUse});

  final Song song;
  final String playKey;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cover = (width - 120).clamp(180.0, 320.0).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .45), blurRadius: 50, offset: const Offset(0, 18))],
          ),
          child: SongCover(url: song.coverUrl, size: cover, radius: 28),
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
            Flexible(child: Text(song.artistLine, maxLines: 2, textAlign: TextAlign.center, style: Tx.body(15, weight: FontWeight.w600, color: Tx.purple300))),
            if (song.artist?.isVerified ?? false) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (song.genreLabel.isNotEmpty) song.genreLabel,
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
        GradientButton(label: 'Usar en una publicación', icon: CupertinoIcons.square_pencil, height: 50, onPressed: onUse),
        if (song.isExternal) ...[
          const SizedBox(height: 14),
          Text(song.credit, textAlign: TextAlign.center, style: Tx.body(12.5, color: Tx.subtle, height: 1.4)),
          if (song.externalUrl != null)
            CupertinoButton(
              padding: const EdgeInsets.only(top: 6),
              onPressed: () => openUrl(context, song.externalUrl!),
              child: Text('Ver en ${song.sourceLabel}', style: Tx.body(14, weight: FontWeight.w600, color: Tx.purple300)),
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
                  activeTrackColor: Tx.purple400,
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
