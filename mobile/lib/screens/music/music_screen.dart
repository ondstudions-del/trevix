import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/catalog.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/song_chip.dart';
import 'artist_screen.dart';

/// Biblioteca de música: canciones aprobadas que se pueden escuchar y usar.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key});

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _genre;
  String _sort = 'recent';
  String? _importing;
  late Paged<CatalogEntry> _list = _make();

  Paged<CatalogEntry> _make() => Paged<CatalogEntry>('music/browse', CatalogEntry.fromJson, query: {
        'sort': _sort,
        if (_genre != null) 'genre': _genre,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Guarda la pista como canción de TREVIX y abre su página (desde ahí se usa en publicaciones e historias).
  Future<void> _useTrack(CatalogTrack track) async {
    if (_importing != null) return;
    setState(() => _importing = track.externalId);
    try {
      final res = await api.post('music/catalog/${track.source}/import', {'external_id': track.externalId});
      if (!mounted) return;
      await songPlayer.stop();
      final song = Song.fromJson(res.map);
      if (mounted) openSong(context, song.id, song: song);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _importing = null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  List<Widget> _header(bool artist) => [
        SliverToBoxAdapter(child: _Hero(artist: artist)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
            child: TextField(
              controller: _search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), _reload);
              },
              textInputAction: TextInputAction.search,
              style: Tx.body(15),
              decoration: fieldDecoration(tr('Canción o artista en TREVIX, Audius y Free To Use'),
                  prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
            ),
          ),
        ),
        ...[
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(label: tr('Todos'), selected: _genre == null, onTap: () {
                      _genre = null;
                      _reload();
                    }),
                  ),
                  for (final g in songGenres.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(label: tr(g.value), selected: _genre == g.key, onTap: () {
                        _genre = g.key;
                        _reload();
                      }),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 2),
              child: Row(children: [
                Expanded(child: Text(_sort == 'recent' ? tr('Lo más nuevo') : tr('Lo más usado'), style: Tx.display(18))),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: _sort,
                  backgroundColor: Tx.surface3,
                  thumbColor: Tx.purple700,
                  children: {
                    'recent': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(tr('Recientes'), style: Tx.body(13, weight: FontWeight.w600))),
                    'popular': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(tr('Populares'), style: Tx.body(13, weight: FontWeight.w600))),
                  },
                  onValueChanged: (v) {
                    if (v == null || v == _sort) return;
                    _sort = v;
                    _reload();
                  },
                ),
              ]),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: ListenableBuilder(
            listenable: _list,
            builder: (_, __) => _list.items.any((e) => e.source != 'trevix') || catalogUnavailable(_list.meta).isNotEmpty
                ? CatalogCredit(unavailable: catalogUnavailable(_list.meta))
                : const SizedBox.shrink(),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    final artist = me?.user.isMusicArtist ?? false;
    return Scaffold(
      appBar: GlassBar(
        title: tr('Música'),
        actions: [
          IconButton(
            tooltip: tr('Panel de artista'),
            onPressed: () => push(context, const ArtistScreen()),
            icon: Icon(artist ? CupertinoIcons.music_mic : CupertinoIcons.cloud_upload, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<CatalogEntry>(
        paged: _list,
        header: _header(artist),
        empty: EmptyState(
          icon: CupertinoIcons.music_note_list,
          title: tr('No hay canciones'),
          message: tr('Prueba con otra búsqueda o género.'),
        ),
        itemBuilder: (context, entry, _) => CatalogEntryTile(
          entry: entry,
          busy: entry.track != null && _importing == entry.track!.externalId,
          onUseTrack: _useTrack,
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.artist});

  final bool artist;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4C1D95), Color(0xFF1E3A8A), Color(0xFF0E7490)]),
        boxShadow: [BoxShadow(color: Tx.alpha(Tx.purple, .3), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GradientText(tr('Suena en TREVIX'), style: Tx.display(22)),
            const SizedBox(height: 6),
            Text(
              tr('Escucha canciones de artistas de la comunidad, de Audius y de Free To Use, y úsalas en tus publicaciones e historias.'),
              style: Tx.body(13.5, color: Colors.white.withAlpha(215), height: 1.4),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => push(context, const ArtistScreen()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withAlpha(50))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(artist ? CupertinoIcons.music_mic : CupertinoIcons.cloud_upload, size: 16, color: Colors.white),
                  const SizedBox(width: 7),
                  Text(artist ? tr('Mi panel de artista') : tr('Sube tu música'), style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withAlpha(25), border: Border.all(color: Colors.white.withAlpha(45))),
          child: const Icon(CupertinoIcons.music_note_2, color: Colors.white, size: 36),
        ),
      ]),
    );
  }
}
