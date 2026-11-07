import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/audio.dart';
import '../core/format.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Portada de una canción (o un disco con degradado si no tiene).
class SongCover extends StatelessWidget {
  const SongCover({super.key, required this.url, this.size = 48, this.radius = 12});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (url != null) return NetImage(url, width: size, height: size, radius: radius);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(radius)),
      child: Icon(CupertinoIcons.music_note_2, color: Colors.white, size: size * .45),
    );
  }
}

/// Botón de reproducir/pausar enlazado al reproductor único.
class PlayButton extends StatelessWidget {
  const PlayButton({super.key, required this.playKey, required this.song, this.clip = false, this.size = 40, this.loop = false});

  final String playKey;
  final Song song;
  final bool clip;
  final double size;
  final bool loop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: songPlayer,
      builder: (context, _) {
        final playing = songPlayer.isPlaying(playKey);
        final loading = songPlayer.isLoading(playKey);
        return GestureDetector(
          onTap: () => songPlayer.toggle(playKey, song, clip: clip),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Tx.brand,
              boxShadow: playing ? [BoxShadow(color: Tx.alpha(Tx.purple, .5), blurRadius: 14)] : null,
            ),
            child: loading
                ? Padding(padding: EdgeInsets.all(size * .28), child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: Colors.white, size: size * .45),
          ),
        );
      },
    );
  }
}

/// Barras animadas de «sonando».
class Equalizer extends StatefulWidget {
  const Equalizer({super.key, this.color = Tx.purple300, this.size = 14});

  final Color color;
  final double size;

  @override
  State<Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<Equalizer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final t = (_c.value + i * .33) % 1;
              final h = .3 + .7 * (t < .5 ? t * 2 : (1 - t) * 2);
              return Container(
                width: widget.size / 4.5,
                height: widget.size * h,
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
              );
            }),
          ),
        );
      },
    );
  }
}

/// Canción adjunta a una publicación, historia o mensaje.
class SongChip extends StatelessWidget {
  const SongChip({super.key, required this.song, required this.playKey, this.clip = false, this.compact = false});

  final Song song;
  final String playKey;
  final bool clip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!song.available) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
        child: Row(children: [
          const Icon(CupertinoIcons.music_note_2, color: Tx.subtle, size: 20),
          const SizedBox(width: 10),
          Text('Canción no disponible', style: Tx.body(14, color: Tx.subtle)),
        ]),
      );
    }
    final range = clip && song.hasClip ? '${clock(song.clipStart!)} – ${clock(song.clipEnd!)}' : clock(song.duration);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0x267C3AED), Color(0x142563EB)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Tx.alpha(Tx.purple500, .28)),
      ),
      child: Row(children: [
        GestureDetector(onTap: () => openSong(context, song.id, song: song), child: SongCover(url: song.coverUrl, size: compact ? 40 : 48)),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openSong(context, song.id, song: song),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ListenableBuilder(
                  listenable: songPlayer,
                  builder: (_, __) => songPlayer.isPlaying(playKey)
                      ? const Padding(padding: EdgeInsets.only(right: 6), child: Equalizer(size: 12))
                      : const SizedBox.shrink(),
                ),
                Flexible(
                  child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600)),
                ),
                if (song.isExplicit) ...[const SizedBox(width: 6), const ExplicitTag()],
              ]),
              const SizedBox(height: 2),
              Text('${song.artistLine} · $range',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        PlayButton(playKey: playKey, song: song, clip: clip, size: compact ? 36 : 40),
      ]),
    );
  }
}

class ExplicitTag extends StatelessWidget {
  const ExplicitTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(color: Tx.surface4, borderRadius: BorderRadius.circular(4)),
      child: Text('E', style: Tx.body(10, weight: FontWeight.w700, color: Tx.muted)),
    );
  }
}

/// Fila de canción para listas (biblioteca, perfil, selector).
class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song, this.onTap, this.trailing, this.playKeyPrefix = 'lib'});

  final Song song;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String playKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final key = '$playKeyPrefix:${song.id}';
    return InkWell(
      onTap: onTap ?? () => openSong(context, song.id, song: song),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            SongCover(url: song.coverUrl, size: 54),
            ListenableBuilder(
              listenable: songPlayer,
              builder: (_, __) => songPlayer.isPlaying(key)
                  ? Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: Colors.black.withAlpha(110), borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Equalizer(color: Colors.white, size: 18)),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600))),
                if (song.isExplicit) ...[const SizedBox(width: 6), const ExplicitTag()],
              ]),
              const SizedBox(height: 3),
              Text(song.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
              const SizedBox(height: 2),
              Text('${song.genreLabel} · ${clock(song.duration)} · ${plural(song.usesCount, 'uso', 'usos')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.subtle)),
            ]),
          ),
          const SizedBox(width: 8),
          trailing ?? PlayButton(playKey: key, song: song, size: 38),
        ]),
      ),
    );
  }
}
