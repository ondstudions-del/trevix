import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/song_chip.dart';
import '../profile/edit_profile_screen.dart';
import 'artist_upload_screen.dart';

/// Panel del artista: subir canciones, seguir su revisión y gestionarlas.
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({super.key});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  String _status = 'all';
  Map<String, int> _counts = {};
  bool? _isArtist;
  final Set<int> _busy = {};
  late Paged<OwnSong> _list = _make();

  Paged<OwnSong> _make() => Paged<OwnSong>('me/music', OwnSong.fromJson, query: {'status': _status}, onMeta: (meta) {
        final counts = asMap(meta['counts']).map((k, v) => MapEntry(k, asInt(v)));
        final artist = asBool(meta['is_music_artist']);
        if (mounted) {
          Future.microtask(() {
            if (mounted) {
              setState(() {
                _counts = counts;
                _isArtist = artist;
              });
            }
          });
        }
      });

  void _switch(String status) {
    if (status == _status) return;
    final old = _list;
    setState(() {
      _status = status;
      _list = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    if (songPlayer.currentKey?.startsWith('own:') ?? false) songPlayer.stop();
    _list.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final sent = await push<bool>(context, const ArtistUploadScreen(), fullscreen: true);
    if (sent == true && mounted) {
      if (_status != 'all' && _status != 'pending') {
        _switch('pending');
      } else {
        await _list.refresh();
      }
    }
  }

  Future<void> _editProfile() async {
    await push(context, const EditProfileScreen());
    if (!mounted) return;
    await context.read<AppState>().refreshMe();
    await _list.refresh();
  }

  static const _actionInfo = {
    'cancel': ('Cancelar envío', CupertinoIcons.xmark_circle, '¿Cancelar el envío?', 'La canción dejará de estar en revisión. Podrás eliminarla después.'),
    'withdraw': ('Retirar de la biblioteca', CupertinoIcons.eye_slash, '¿Retirar la canción?',
        'Dejará de estar en la biblioteca y sonará como «no disponible» donde se haya usado. Podrás volver a publicarla.'),
    'republish': ('Volver a publicar', CupertinoIcons.arrow_up_circle, '', ''),
    'delete': ('Eliminar definitivamente', CupertinoIcons.trash, '¿Eliminar la canción?', 'Se borrará el archivo para siempre.'),
  };

  Future<void> _run(OwnSong s, String action) async {
    final info = _actionInfo[action]!;
    if (info.$3.isNotEmpty && !await confirm(context, info.$3, info.$4, action: info.$1, destructive: action != 'republish')) return;
    setState(() => _busy.add(s.id));
    try {
      final res = action == 'delete' ? await api.delete('me/music/${s.id}') : await api.post('me/music/${s.id}/$action');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Listo.'}');
      songPlayer.stop('own:${s.id}');
      await _list.refresh();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(s.id));
  }

  void _options(OwnSong s) {
    if (s.actions.isEmpty) return;
    actionSheet(context, [
      for (final a in s.actions)
        if (_actionInfo.containsKey(a))
          SheetAction(_actionInfo[a]!.$1, _actionInfo[a]!.$2, () => _run(s, a), destructive: a == 'delete' || a == 'withdraw' || a == 'cancel'),
    ], title: s.title);
  }

  @override
  Widget build(BuildContext context) {
    final profileArtist = context.watch<AppState>().me?.user.isMusicArtist ?? false;
    final artist = _isArtist ?? profileArtist;
    return Scaffold(
      appBar: GlassBar(
        title: 'Panel de artista',
        actions: [
          if (artist) IconButton(onPressed: _upload, icon: Icon(CupertinoIcons.add_circled, color: Tx.text)),
        ],
      ),
      body: PagedView<OwnSong>(
        paged: _list,
        header: [
          SliverToBoxAdapter(child: artist ? _ArtistHero(counts: _counts, onUpload: _upload) : _BecomeArtist(onEdit: _editProfile)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                children: [
                  for (final e in songStatuses.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(
                        label: (_counts[e.key] ?? 0) > 0 && e.key != 'all' ? '${e.value} (${_counts[e.key]})' : e.value,
                        selected: _status == e.key,
                        onTap: () => _switch(e.key),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        empty: EmptyState(
          icon: CupertinoIcons.music_albums,
          title: _status == 'all' ? 'Aún no subiste canciones' : 'Nada en esta lista',
          message: _status == 'all' && artist ? 'Sube tu primera canción: el equipo la revisa antes de publicarla.' : null,
          action: _status == 'all' && artist ? GradientButton(label: 'Subir canción', icon: CupertinoIcons.cloud_upload, expand: false, onPressed: _upload) : null,
        ),
        itemBuilder: (context, s, _) => _OwnSongTile(song: s, busy: _busy.contains(s.id), onMore: () => _options(s)),
      ),
    );
  }
}

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({required this.counts, required this.onUpload});

  final Map<String, int> counts;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int value, Color color) => Expanded(
          child: Column(children: [
            Text(compact(value), style: Tx.display(20, color: color)),
            const SizedBox(height: 2),
            Text(label, style: Tx.body(11.5, color: Colors.white.withAlpha(190))),
          ]),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B21B6), Color(0xFF1D4ED8)]),
        boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.music_mic, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('Tu música en TREVIX', style: Tx.display(19, color: Colors.white))),
        ]),
        const SizedBox(height: 6),
        Text('Cada canción pasa por una revisión antes de entrar en la biblioteca.', style: Tx.body(13, color: Colors.white.withAlpha(200))),
        const SizedBox(height: 16),
        Row(children: [
          stat('publicadas', counts['published'] ?? 0, Colors.white),
          stat('en revisión', counts['pending'] ?? 0, const Color(0xFFFDE68A)),
          stat('con usos', counts['used'] ?? 0, const Color(0xFFA5F3FC)),
        ]),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onUpload,
          child: Container(
            height: 46,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(CupertinoIcons.cloud_upload_fill, color: Tx.purple700, size: 19),
              const SizedBox(width: 8),
              Text('Subir canción', style: Tx.body(15, weight: FontWeight.w700, color: Tx.purple700)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _BecomeArtist extends StatelessWidget {
  const _BecomeArtist({required this.onEdit});

  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Panel(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      gradient: true,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(CupertinoIcons.music_mic, color: Tx.accent),
          const SizedBox(width: 8),
          Expanded(child: Text('Conviértete en artista', style: Tx.display(18))),
        ]),
        const SizedBox(height: 8),
        Text(
          'Para subir canciones, cambia tu cuenta a «Creador de contenido» y elige la categoría «Artista musical» en Editar perfil.',
          style: Tx.body(14, color: Tx.muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        GradientButton(label: 'Ir a Editar perfil', icon: CupertinoIcons.person_crop_circle, height: 46, onPressed: onEdit),
      ]),
    );
  }
}

class _OwnSongTile extends StatelessWidget {
  const _OwnSongTile({required this.song, required this.busy, required this.onMore});

  final OwnSong song;
  final bool busy;
  final VoidCallback onMore;

  Color get _statusColor => switch (song.status) {
        'published' => Tx.success,
        'pending' => Tx.warning,
        'rejected' || 'removed' => Tx.danger,
        _ => Tx.muted,
      };

  @override
  Widget build(BuildContext context) {
    final playable = Song(
      id: song.id,
      title: song.title,
      featuring: song.featuring,
      genreLabel: song.genreLabel,
      isExplicit: song.isExplicit,
      duration: song.duration,
      audioUrl: song.audioUrl,
      coverUrl: song.coverUrl,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SongCover(url: song.coverUrl, size: 58, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w600))),
                if (song.isExplicit) ...[const SizedBox(width: 6), const ExplicitTag()],
              ]),
              if (song.featuring != null && song.featuring!.isNotEmpty)
                Text('feat. ${song.featuring}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted)),
              const SizedBox(height: 5),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Tx.alpha(_statusColor, .14), borderRadius: BorderRadius.circular(8)),
                  child: Text(song.statusLabel, style: Tx.body(11.5, weight: FontWeight.w700, color: _statusColor)),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('${song.genreLabel} · ${clock(song.duration)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.subtle)),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 6),
          if (song.audioUrl.isNotEmpty) PlayButton(playKey: 'own:${song.id}', song: playable, size: 38),
          if (busy)
            const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator())
          else if (song.actions.isNotEmpty)
            IconButton(onPressed: onMore, icon: Icon(CupertinoIcons.ellipsis, color: Tx.muted)),
        ]),
        if (song.reviewNote != null && song.reviewNote!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(12)),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: song.status == 'published' ? 'Nota del equipo: ' : 'Motivo: ', style: Tx.body(12.5, weight: FontWeight.w700, color: _statusColor)),
              TextSpan(text: song.reviewNote!.trim(), style: Tx.body(12.5, color: Tx.muted)),
            ])),
          ),
        ],
        if (song.usesTotal > 0) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 14, children: [
            _Use(icon: CupertinoIcons.square_grid_2x2, text: plural(song.usesPosts, 'publicación', 'publicaciones')),
            _Use(icon: CupertinoIcons.circle_grid_hex, text: plural(song.usesStories, 'historia', 'historias')),
            _Use(icon: CupertinoIcons.chat_bubble_2, text: plural(song.usesMessages, 'mensaje', 'mensajes')),
          ]),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            song.publishedAt != null
                ? 'Publicada el ${fullDate(song.publishedAt)} · ${fileSize(song.sizeBytes)}'
                : 'Enviada el ${fullDate(song.createdAt)} · ${fileSize(song.sizeBytes)}',
            style: Tx.body(11.5, color: Tx.subtle),
          ),
        ),
      ]),
    );
  }
}

class _Use extends StatelessWidget {
  const _Use({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Tx.accent),
      const SizedBox(width: 4),
      Text(text, style: Tx.body(12, color: Tx.muted)),
    ]);
  }
}
