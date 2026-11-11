import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/audio.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'song_chip.dart';

/// Canción del perfil: al tocarla suena su fragmento de 30 s (y se pausa al tocarla otra vez).
class ProfileSongPill extends StatelessWidget {
  const ProfileSongPill({super.key, required this.song, required this.playKey});

  final Song song;
  final String playKey;

  @override
  Widget build(BuildContext context) {
    if (!song.available) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: songPlayer,
      builder: (context, _) {
        final playing = songPlayer.isPlaying(playKey);
        final loading = songPlayer.isLoading(playKey);
        return Semantics(
          button: true,
          label: playing
              ? tr('Pausar {title} de {artist}', {'title': song.title, 'artist': song.artist?.displayName ?? ''})
              : tr('Reproducir {title} de {artist}', {'title': song.title, 'artist': song.artist?.displayName ?? ''}),
          child: GestureDetector(
            onTap: () => songPlayer.toggle(playKey, song, clip: song.hasClip),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
              decoration: BoxDecoration(
                color: playing ? null : Tx.surface2,
                gradient: playing ? Tx.brandSoft : null,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: playing ? Tx.alpha(Tx.purple500, .5) : Tx.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Stack(alignment: Alignment.center, children: [
                  SongCover(url: song.coverUrl, size: 30, radius: 15),
                  if (playing || loading)
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: Colors.black.withAlpha(110), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Equalizer(color: Colors.white, size: 13),
                    ),
                ]),
                const SizedBox(width: 9),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: song.title, style: Tx.body(13.5, weight: FontWeight.w600)),
                      TextSpan(text: ' · ${song.artist?.displayName ?? ''}', style: Tx.body(13, color: Tx.muted)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 14, color: Tx.accent),
              ]),
            ),
          ),
        );
      },
    );
  }
}

IconData contactIcon(String type) => switch (type) {
      'email' => CupertinoIcons.mail,
      'phone' => CupertinoIcons.phone,
      'whatsapp' => CupertinoIcons.chat_bubble_2,
      'telegram' => CupertinoIcons.paperplane,
      'youtube' => CupertinoIcons.play_rectangle,
      'twitch' => CupertinoIcons.game_controller,
      'linkedin' => CupertinoIcons.briefcase,
      'instagram' => CupertinoIcons.camera,
      'tiktok' => CupertinoIcons.music_note,
      'snapchat' => CupertinoIcons.smiley,
      _ => CupertinoIcons.at,
    };

/// «Información»: todos los datos personales que esa persona deja ver.
Future<void> showProfileAbout(BuildContext context, User user, ProfileDetails d) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SheetFrame(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .8),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
          Text(tr('Información de {name}', {'name': user.displayName}), style: Tx.display(18), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          if (d.city != null) _AboutRow(icon: CupertinoIcons.house, label: tr('Vive en'), value: d.city!),
          if (d.hometown != null) _AboutRow(icon: CupertinoIcons.location, label: tr('Es de'), value: d.hometown!),
          if (d.hasBirthday) _AboutRow(icon: CupertinoIcons.gift, label: tr('Cumpleaños'), value: birthday(d.birthDay!, d.birthMonth!, d.birthYear)),
          if (d.relationshipLabel != null) _AboutRow(icon: CupertinoIcons.heart, label: tr('Situación sentimental'), value: d.relationshipLabel!),
          if (d.genderLabel != null) _AboutRow(icon: CupertinoIcons.person, label: tr('Género'), value: d.genderLabel!),
          if (d.interests.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Intereses'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final i in d.interests) InterestTag(i)]),
            const SizedBox(height: 12),
          ],
          if (d.links.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(tr('Enlaces'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
            for (final l in d.links)
              _AboutRow(icon: CupertinoIcons.link, label: l.title, value: l.url.replaceFirst(RegExp(r'^https?://(www\.)?'), ''), onTap: () => openUrl(ctx, l.url)),
          ],
          if (d.contacts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tr('Contacto'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
            for (final c in d.contacts)
              _AboutRow(icon: contactIcon(c.type), label: c.label, value: c.value, onTap: c.url == null ? null : () => openUrl(ctx, c.url!)),
          ],
          if (!d.hasAbout && d.interests.isEmpty && d.links.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(tr('No hay información para mostrar.'), style: Tx.body(14.5, color: Tx.muted), textAlign: TextAlign.center),
            ),
        ]),
      ),
    ),
  );
}

class InterestTag extends StatelessWidget {
  const InterestTag(this.label, {super.key, this.onRemove});

  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 7, onRemove != null ? 6 : 12, 7),
      decoration: BoxDecoration(gradient: Tx.brandSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: Tx.alpha(Tx.purple500, .3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: Tx.body(13.5, weight: FontWeight.w600)),
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: Padding(padding: const EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.xmark_circle_fill, size: 17, color: Tx.subtle)),
          ),
      ]),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.icon, required this.label, required this.value, this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: Tx.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Tx.body(12.5, color: Tx.muted)),
              const SizedBox(height: 1),
              Text(value, style: Tx.body(15, weight: FontWeight.w500, color: onTap != null ? Tx.accent : Tx.text)),
            ]),
          ),
          if (onTap != null) Icon(CupertinoIcons.arrow_up_right, size: 14, color: Tx.subtle),
        ]),
      ),
    );
  }
}
