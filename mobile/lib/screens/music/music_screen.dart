import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/catalog.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
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
  late Paged<Song> _list = _make();

  Paged<Song> _make() => Paged<Song>('music', Song.fromJson, query: {
        'sort': _sort,
        if (_genre != null) 'genre': _genre,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    final artist = me?.user.isMusicArtist ?? false;
    return Scaffold(
      appBar: GlassBar(
        title: 'Música',
        actions: [
          IconButton(
            tooltip: 'Panel de artista',
            onPressed: () => push(context, const ArtistScreen()),
            icon: Icon(artist ? CupertinoIcons.music_mic : CupertinoIcons.cloud_upload, color: Tx.text),
          ),
        ],
      ),
      body: PagedView<Song>(
        paged: _list,
        header: [
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
                decoration: fieldDecoration('Canción, invitado o artista', prefix: const Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(label: 'Todos', selected: _genre == null, onTap: () {
                      _genre = null;
                      _reload();
                    }),
                  ),
                  for (final g in songGenres.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(label: g.value, selected: _genre == g.key, onTap: () {
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
                Expanded(child: Text(_sort == 'recent' ? 'Lo más nuevo' : 'Lo más usado', style: Tx.display(18))),
                CupertinoSlidingSegmentedControl<String>(
                  groupValue: _sort,
                  backgroundColor: Tx.surface3,
                  thumbColor: Tx.purple700,
                  children: {
                    'recent': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Recientes', style: Tx.body(13, weight: FontWeight.w600))),
                    'popular': Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Populares', style: Tx.body(13, weight: FontWeight.w600))),
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
        empty: const EmptyState(
          icon: CupertinoIcons.music_note_list,
          title: 'No hay canciones',
          message: 'Prueba con otra búsqueda o género.',
        ),
        itemBuilder: (context, song, _) => SongTile(song: song),
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
            GradientText('Suena en TREVIX', style: Tx.display(22)),
            const SizedBox(height: 6),
            Text(
              'Escucha canciones de artistas de la comunidad y úsalas en tus publicaciones, historias y mensajes.',
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
                  Text(artist ? 'Mi panel de artista' : 'Sube tu música', style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
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
