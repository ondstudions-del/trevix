import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/song_chip.dart';

class PickedSong {
  const PickedSong(this.song, this.start);

  final Song song;
  final int start;
}

/// Selector de canciones de la biblioteca. Con [withClip], permite elegir el fragmento de 30 s.
Future<PickedSong?> pickSong(BuildContext context, {bool withClip = true, int clipSeconds = 30, PickedSong? current}) async {
  final picked = await showModalBottomSheet<PickedSong>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MusicPicker(withClip: withClip, clipSeconds: clipSeconds, current: current),
  );
  await songPlayer.stop();
  return picked;
}

class _MusicPicker extends StatefulWidget {
  const _MusicPicker({required this.withClip, required this.clipSeconds, this.current});

  final bool withClip;
  final int clipSeconds;
  final PickedSong? current;

  @override
  State<_MusicPicker> createState() => _MusicPickerState();
}

class _MusicPickerState extends State<_MusicPicker> {
  late final Paged<CatalogEntry> _songs = Paged<CatalogEntry>('music/browse', CatalogEntry.fromJson, query: {'sort': 'popular'});
  final _search = TextEditingController();
  Timer? _debounce;
  Song? _selected;
  double _start = 0;
  String? _importing;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    if (current != null && widget.withClip) {
      _selected = current.song;
      _start = current.start.toDouble();
    }
    _songs.refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _songs.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _songs.query = {'sort': q.trim().isEmpty ? 'popular' : 'recent', if (q.trim().isNotEmpty) 'q': q.trim()};
      _songs.refresh();
    });
  }

  /// Guarda la pista del catálogo como canción de TREVIX y la usa.
  Future<void> _useTrack(CatalogTrack track) async {
    if (_importing != null) return;
    setState(() => _importing = track.externalId);
    try {
      final res = await api.post('music/catalog/${track.source}/import', {'external_id': track.externalId});
      if (!mounted) return;
      await songPlayer.stop();
      _choose(Song.fromJson(res.map));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _importing = null);
  }

  int get _maxStart {
    final s = _selected;
    if (s == null) return 0;
    final max = s.duration - widget.clipSeconds;
    return max > 0 ? max : 0;
  }

  void _preview() {
    final s = _selected;
    if (s == null) return;
    songPlayer.play('picker', s.withClip(_start.round(), widget.clipSeconds), clip: true);
  }

  void _choose(Song song) {
    if (!widget.withClip) {
      Navigator.pop(context, PickedSong(song, 0));
      return;
    }
    setState(() {
      _selected = song;
      _start = 0;
    });
    _preview();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * .82;
    return SheetFrame(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: height,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _selected == null ? _list() : _clip(_selected!),
        ),
      ),
    );
  }

  Widget _list() {
    return Column(key: const ValueKey('list'), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(children: [
          Expanded(child: Text('Añadir música', style: Tx.display(20))),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: Tx.body(15, weight: FontWeight.w600, color: Tx.muted)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          style: Tx.body(15),
          decoration: fieldDecoration('Buscar canciones o artistas', prefix: const Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListenableBuilder(
          listenable: _songs,
          builder: (context, _) {
            if (_songs.items.isEmpty) {
              if (_songs.error != null) return ErrorState(error: _songs.error!, onRetry: _songs.retry);
              if (_songs.loading || !_songs.loaded) return const Loading();
              return const EmptyState(
                icon: CupertinoIcons.music_note_list,
                title: 'Sin canciones',
                message: 'No encontramos canciones con esa búsqueda.',
              );
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 400) _songs.loadMore();
                return false;
              },
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 30),
                itemCount: _songs.items.length + 1,
                itemBuilder: (_, i) {
                  if (i >= _songs.items.length) {
                    if (_songs.hasMore) return const Loading(padding: 20);
                    return CatalogCredit(unavailable: catalogUnavailable(_songs.meta));
                  }
                  final entry = _songs.items[i];
                  return CatalogEntryTile(
                    entry: entry,
                    playKeyPrefix: 'pick',
                    busy: entry.track != null && _importing == entry.track!.externalId,
                    onSong: _choose,
                    onUseTrack: _useTrack,
                  );
                },
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _clip(Song song) {
    final max = _maxStart;
    final start = _start.round().clamp(0, max);
    final end = (start + widget.clipSeconds).clamp(0, song.duration);
    return Padding(
      key: const ValueKey('clip'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () {
              songPlayer.stop();
              setState(() => _selected = null);
            },
            child: const Icon(CupertinoIcons.chevron_back, color: Tx.text),
          ),
          Expanded(child: Text('Elige el fragmento', style: Tx.display(20))),
        ]),
        const Spacer(),
        Center(child: SongCover(url: song.coverUrl, size: 180, radius: 28)),
        const SizedBox(height: 22),
        Text(song.title, textAlign: TextAlign.center, style: Tx.display(22)),
        const SizedBox(height: 4),
        Text(song.artistLine, textAlign: TextAlign.center, style: Tx.body(15, color: Tx.muted)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tx.border)),
          child: Column(children: [
            Row(children: [
              PlayButton(playKey: 'picker', song: song.withClip(start, widget.clipSeconds), clip: true, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${clock(start)} – ${clock(end)}', style: Tx.display(20)),
                  Text('Sonará este fragmento de ${widget.clipSeconds} s', style: Tx.body(12.5, color: Tx.muted)),
                ]),
              ),
            ]),
            if (max > 0)
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: Tx.purple500,
                  inactiveTrackColor: Tx.surface4,
                  thumbColor: Colors.white,
                  overlayColor: Tx.alpha(Tx.purple500, .2),
                ),
                child: Slider(
                  value: _start.clamp(0, max.toDouble()).toDouble(),
                  min: 0,
                  max: max.toDouble(),
                  onChanged: (v) => setState(() => _start = v),
                  onChangeEnd: (_) => _preview(),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('La canción es corta: sonará completa.', style: Tx.body(13, color: Tx.muted)),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        GradientButton(
          label: 'Usar esta canción',
          icon: CupertinoIcons.checkmark_alt,
          onPressed: () => Navigator.pop(context, PickedSong(song, start)),
        ),
      ]),
    );
  }
}
