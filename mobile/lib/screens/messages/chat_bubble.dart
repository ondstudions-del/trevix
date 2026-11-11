import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/audio.dart';
import '../../core/chat_media.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/emoji_text.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/rich_body.dart';
import '../../widgets/song_chip.dart';
import 'chat_style.dart';
import 'chat_video.dart';

/// Burbuja de un mensaje al estilo Messenger: esquinas agrupadas, color del estilo del chat, emojis grandes,
/// foto/voz cifradas y fotos de visualización única.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.palette,
    required this.first,
    required this.last,
    required this.onLongPress,
    this.showName = false,
    this.showAvatar = false,
    this.avatarSlot = false,
    this.replyName,
    this.onDoubleTap,
    this.onReplyTap,
    this.onLocationTap,
    this.onViewOnce,
    this.onUnlock,
    this.onAvatarTap,
    this.highlight = false,
  });

  final Message message;
  final ChatPalette palette;

  /// Primera y última burbuja seguida de la misma persona.
  final bool first;
  final bool last;

  /// Grupos: nombre sobre la primera burbuja de otra persona.
  final bool showName;

  /// Foto pequeña junto a la última burbuja de otra persona (con [avatarSlot] se reserva el espacio).
  final bool showAvatar;
  final bool avatarSlot;
  final String Function(MessageReply reply)? replyName;
  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onReplyTap;
  final VoidCallback? onLocationTap;
  final VoidCallback? onViewOnce;

  /// El chat está cifrado y falta el PIN en este teléfono.
  final VoidCallback? onUnlock;
  final VoidCallback? onAvatarTap;
  final bool highlight;

  static const _big = Radius.circular(20);
  static const _small = Radius.circular(5);

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.isMine;
    final radius = mine
        ? BorderRadius.only(topLeft: _big, bottomLeft: _big, topRight: first ? _big : _small, bottomRight: last ? _big : _small)
        : BorderRadius.only(topRight: _big, bottomRight: _big, topLeft: first ? _big : _small, bottomLeft: last ? _big : _small);
    final fg = mine ? Colors.white : Tx.text;
    final soft = mine ? Colors.white.withAlpha(205) : Tx.muted;
    final p = m.payload;
    final text = m.text;
    final emojiOnly = !m.deleted && text.isNotEmpty && isOnlyEmoji(text) && m.reply == null && !m.forwarded && m.story == null;

    final top = <Widget>[];
    if (m.forwarded && !m.deleted) {
      top.add(Padding(
        padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.arrowshape_turn_up_right_fill, size: 11, color: Tx.subtle),
          const SizedBox(width: 4),
          Text(tr('Reenviado'), style: Tx.body(11.5, color: Tx.subtle)),
        ]),
      ));
    }
    final reply = m.reply;
    if (reply != null && !m.deleted) {
      top.add(GestureDetector(
        onTap: onReplyTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 14),
          constraints: const BoxConstraints(maxWidth: 240),
          decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(CupertinoIcons.reply, size: 11, color: Tx.subtle),
              const SizedBox(width: 4),
              Flexible(
                child: Text(replyName?.call(reply) ?? (reply.isMine ? tr('Tú') : reply.senderName),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.subtle)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(reply.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.muted)),
          ]),
        ),
      ));
    }

    final content = <Widget>[];
    var mediaOnly = false;
    var bare = false;
    if (m.deleted) {
      content.add(Text(tr('Mensaje eliminado'), style: Tx.body(14.5, color: soft).copyWith(fontStyle: FontStyle.italic)));
    } else if (m.viewOnce != null) {
      content.add(_ViewOnceTile(message: m, mine: mine, onTap: onViewOnce));
    } else if (m.encrypted && p == null) {
      content.add(GestureDetector(
        onTap: onUnlock,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.lock_fill, size: 14, color: soft),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              onUnlock != null
                  ? tr('Mensaje cifrado · toca para escribir tu PIN')
                  : (m.undecryptable ? tr('No se puede leer este mensaje en este teléfono') : tr('Descifrando…')),
              style: Tx.body(14, color: soft).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ]),
      ));
    } else if (m.mediaCleared && (m.file != null || m.imageUrl == null) && (p?.file != null || (m.body ?? '').isEmpty && m.gif == null && m.location == null)) {
      content.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.trash_slash, size: 14, color: soft),
        const SizedBox(width: 6),
        Flexible(child: Text(tr('Archivo eliminado para liberar espacio'), style: Tx.body(14, color: soft).copyWith(fontStyle: FontStyle.italic))),
      ]));
    } else {
      final story = m.story;
      if (story != null) content.add(_StoryRefRow(message: m, story: story, soft: soft));
      if (m.context == 'note_reply' && m.noteText != null) {
        content.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(mine ? tr('Respondiste a su nota') : tr('Respondió a tu nota'), style: Tx.body(12, color: soft)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: mine ? Colors.white.withAlpha(38) : Tx.surface4, borderRadius: BorderRadius.circular(16)),
              child: Text(m.noteText!, style: Tx.body(13.5, weight: FontWeight.w600, color: fg)),
            ),
          ]),
        ));
      }
      final type = p?.type;
      final hasImage = m.imageUrl != null || m.video != null || type == 'image' || type == 'video';
      final gif = m.gif ?? (type == 'gif' && p?.gif != null ? Gif.fromJson(_gifJson(p!.gif!)) : null);
      final location = m.location ?? (type == 'location' && p?.location != null ? MessageLocation.maybe(p!.location) : null);
      if (m.imageUrl != null) {
        content.add(GestureDetector(
          onTap: () => pushFade(context, MediaViewer(media: [Media(type: 'image', url: m.imageUrl!)])),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300, maxWidth: 240),
            child: NetImage(m.imageUrl, radius: 18, fit: BoxFit.cover),
          ),
        ));
      } else if (type == 'image') {
        content.add(_SecureImage(message: m));
      } else if (m.video != null || type == 'video') {
        content.add(ChatVideoTile(message: m));
      }
      if (gif != null) content.add(GifView(gif: gif, maxWidth: 200, maxHeight: 200));
      if (location != null) content.add(_LocationCard(location: location, mine: mine, onTap: onLocationTap));
      if (m.voice != null) {
        content.add(VoicePlayer(voice: m.voice!, playKey: 'voice:${m.id}', mine: mine));
      } else if (type == 'voice') {
        content.add(_SecureVoice(message: m, mine: mine));
      }
      if (m.song != null) {
        content.add(SizedBox(width: 250, child: SongChip(song: m.song!, playKey: 'msg:${m.id}', compact: true)));
      }
      final caption = type == 'voice' ? '' : text;
      if (caption.isNotEmpty) {
        if (content.isNotEmpty) content.add(const SizedBox(height: 6));
        content.add(emojiOnly || m.isStoryReaction
            ? Text(caption, style: const TextStyle(fontSize: 44, height: 1.1))
            : RichBody(caption, onlyLinks: true, style: Tx.body(15.5, color: fg, height: 1.33), linkColor: mine ? Colors.white : Tx.accent));
      }
      mediaOnly = caption.isEmpty && (hasImage || gif != null) && story == null;
      bare = (mediaOnly && gif != null && gif.isSticker) || emojiOnly || m.isStoryReaction && caption.isNotEmpty && story == null;
      if (mediaOnly && hasImage) bare = true;
    }
    if (!m.deleted && (m.pinned || m.expiresAt != null || m.encrypted)) {
      content.add(Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.pinned) Icon(CupertinoIcons.pin_fill, size: 10, color: bare ? Tx.subtle : soft),
          if (m.expiresAt != null) ...[const SizedBox(width: 4), Icon(CupertinoIcons.timer, size: 10, color: bare ? Tx.subtle : soft)],
          if (m.encrypted) ...[const SizedBox(width: 4), Icon(CupertinoIcons.lock_fill, size: 9, color: bare ? Tx.subtle : soft)],
        ]),
      ));
    }

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        padding: bare ? EdgeInsets.zero : (mediaOnly ? const EdgeInsets.all(3) : const EdgeInsets.symmetric(horizontal: 13, vertical: 9)),
        decoration: bare
            ? BoxDecoration(color: highlight ? Tx.alpha(palette.accent, .2) : Colors.transparent, borderRadius: radius)
            : BoxDecoration(
                gradient: mine && !highlight ? palette.gradient : null,
                color: highlight ? Tx.alpha(palette.accent, mine ? .7 : .25) : (mine ? null : (Tx.isDark ? const Color(0xFF26262B) : const Color(0xFFEDEDF1))),
                borderRadius: radius,
              ),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: content),
      ),
    );

    final column = Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (showName && !mine)
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 3),
          child: Text(m.sender?.displayName ?? '', style: Tx.body(12, weight: FontWeight.w600, color: Tx.subtle)),
        ),
      ...top,
      bubble,
      if (m.reactions.isNotEmpty) _ReactionPill(message: m, onTap: onLongPress),
    ]);

    return Padding(
      padding: EdgeInsets.only(top: first ? 8 : 1.5),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine && avatarSlot)
            Padding(
              padding: EdgeInsets.only(right: 8, bottom: m.reactions.isNotEmpty ? 18 : 0),
              child: showAvatar && m.sender != null ? Avatar(user: m.sender!, size: 28, onTap: onAvatarTap) : const SizedBox(width: 28),
            ),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(left: mine ? 56 : 0, right: mine ? 0 : 48),
              child: column,
            ),
          ),
        ],
      ),
    );
  }

  static Json _gifJson(Map<String, dynamic> g) => {'id': g['id'], 'kind': g['kind'], 'url': g['url'], 'width': g['w'], 'height': g['h'], 'title': g['title']};
}

class _StoryRefRow extends StatelessWidget {
  const _StoryRefRow({required this.message, required this.story, required this.soft});

  final Message message;
  final StoryRef story;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!story.expired && story.type == 'text')
          Container(width: 34, height: 50, decoration: BoxDecoration(gradient: Tx.storyBackground(story.background), borderRadius: BorderRadius.circular(8)))
        else if (!story.expired && story.mediaUrl != null && story.type == 'image')
          NetImage(story.mediaUrl, width: 34, height: 50, radius: 8)
        else
          Container(
            width: 34,
            height: 50,
            decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: const Icon(CupertinoIcons.time, size: 14, color: Colors.white70),
          ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            story.expired
                ? tr('Historia no disponible')
                : message.isStoryReaction
                    ? (mine ? tr('Reaccionaste a su historia') : tr('Reaccionó a tu historia'))
                    : (mine ? tr('Respondiste a su historia') : tr('Respondió a tu historia')),
            style: Tx.body(12, color: soft),
          ),
        ),
      ]),
    );
  }
}

/// Reacciones como una pastilla bajo la burbuja (como Messenger).
class _ReactionPill extends StatelessWidget {
  const _ReactionPill({required this.message, required this.onTap});

  final Message message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final total = m.reactions.fold<int>(0, (a, r) => a + r.count);
    final sorted = [...m.reactions]..sort((a, b) => b.count.compareTo(a.count));
    return Transform.translate(
      offset: const Offset(0, -6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(left: m.isMine ? 0 : 10, right: m.isMine ? 10 : 0),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Tx.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Tx.bg, width: 2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final r in sorted.take(3)) Text(r.emoji, style: const TextStyle(fontSize: 13)),
            if (total > 1) ...[const SizedBox(width: 3), Text('$total', style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.muted))],
          ]),
        ),
      ),
    );
  }
}

/// Foto o video de visualización única dentro del chat.
class _ViewOnceTile extends StatelessWidget {
  const _ViewOnceTile({required this.message, required this.mine, this.onTap});

  final Message message;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = message.viewOnce!;
    final video = message.fileIsVideo;
    final kind = video ? tr('Video') : tr('Foto');
    final opened = video ? tr('Video abierto') : tr('Foto abierta');
    final fg = mine ? Colors.white : Tx.text;
    final String label;
    final IconData icon;
    if (mine) {
      label = v.views > 0 ? (v.opened ? opened : (video ? tr('Video visto') : tr('Foto vista'))) : '$kind · ${tr(v.label)}';
      icon = v.views > 0 ? CupertinoIcons.eye_slash : (v.seconds == null || v.seconds == 0 ? CupertinoIcons.eye : CupertinoIcons.timer);
    } else if (v.viewed || v.opened) {
      label = opened;
      icon = CupertinoIcons.eye_slash;
    } else {
      label = '$kind · ${tr(v.label)}';
      icon = video ? CupertinoIcons.videocam : (v.seconds == null || v.seconds == 0 ? CupertinoIcons.eye : CupertinoIcons.timer);
    }
    final active = !mine && !v.viewed && !v.opened;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: active ? fg : fg.withAlpha(110), width: 1.8, strokeAlign: BorderSide.strokeAlignInside),
          ),
          child: Icon(icon, size: 15, color: active ? fg : fg.withAlpha(150)),
        ),
        const SizedBox(width: 10),
        Text(label, style: Tx.body(15, weight: FontWeight.w600, color: active || mine ? fg : fg.withAlpha(160))),
      ]),
    );
  }
}

/// Foto cifrada: se descarga y descifra al mostrarla (queda en la caché del teléfono).
class _SecureImage extends StatefulWidget {
  const _SecureImage({required this.message});

  final Message message;

  @override
  State<_SecureImage> createState() => _SecureImageState();
}

class _SecureImageState extends State<_SecureImage> {
  late Future<File> _file = ChatMedia.load(widget.message);

  @override
  Widget build(BuildContext context) {
    final aspect = (widget.message.payload?.aspect ?? 1).clamp(.5, 2.0);
    const width = 230.0;
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        Widget child;
        if (file != null) {
          child = GestureDetector(
            onTap: () => pushFade(context, MediaViewer.file(file)),
            child: Image.file(file, fit: BoxFit.cover, width: width, height: width / aspect, gaplessPlayback: true),
          );
        } else if (snap.hasError) {
          child = GestureDetector(
            onTap: () => setState(() => _file = ChatMedia.load(widget.message)),
            child: Container(
              width: width,
              height: width / aspect,
              color: Tx.surface3,
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.exclamationmark_circle, color: Tx.subtle),
                const SizedBox(height: 6),
                Text(tr('Toca para reintentar'), style: Tx.body(12.5, color: Tx.subtle)),
              ]),
            ),
          );
        } else {
          child = Container(
            width: width,
            height: width / aspect,
            color: Tx.surface3,
            alignment: Alignment.center,
            child: const CupertinoActivityIndicator(),
          );
        }
        return ClipRRect(borderRadius: BorderRadius.circular(18), child: child);
      },
    );
  }
}

class _SecureVoice extends StatefulWidget {
  const _SecureVoice({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  State<_SecureVoice> createState() => _SecureVoiceState();
}

class _SecureVoiceState extends State<_SecureVoice> {
  late Future<File> _file = ChatMedia.load(widget.message);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        if (file != null) {
          return VoicePlayer(
            voice: VoiceNote(url: Uri.file(file.path).toString(), duration: widget.message.payload?.duration ?? 0),
            playKey: 'voice:${widget.message.id}',
            mine: widget.mine,
          );
        }
        final fg = widget.mine ? Colors.white : Tx.text;
        return SizedBox(
          width: 200,
          height: 38,
          child: Row(children: [
            if (snap.hasError)
              IconButton(
                onPressed: () => setState(() => _file = ChatMedia.load(widget.message)),
                icon: Icon(CupertinoIcons.arrow_clockwise, color: fg, size: 18),
              )
            else
              const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator()),
            Text(snap.hasError ? tr('No se pudo cargar') : tr('Nota de voz'), style: Tx.body(13, color: fg)),
          ]),
        );
      },
    );
  }
}

/// Reproductor de una nota de voz dentro de la burbuja.
class VoicePlayer extends StatelessWidget {
  const VoicePlayer({super.key, required this.voice, required this.playKey, required this.mine});

  final VoiceNote voice;
  final String playKey;
  final bool mine;

  Future<void> _toggle(BuildContext context) async {
    final song = Song(id: 0, title: tr('Nota de voz'), duration: voice.duration, audioUrl: voice.url);
    await songPlayer.toggle(playKey, song);
    final error = songPlayer.error;
    if (error != null && songPlayer.currentKey == null && context.mounted) toast(context, error, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : Tx.text;
    return SizedBox(
      width: 210,
      child: ListenableBuilder(
        listenable: songPlayer,
        builder: (context, _) {
          final active = songPlayer.currentKey == playKey;
          final playing = songPlayer.isPlaying(playKey);
          final loading = songPlayer.isLoading(playKey);
          return Row(children: [
            GestureDetector(
              onTap: () => _toggle(context),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? Colors.white : Tx.alpha(Tx.purple500, .22)),
                child: loading
                    ? Padding(padding: const EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: mine ? Tx.purple : fg))
                    : Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: mine ? Tx.purple : fg, size: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: active ? songPlayer.position : null,
                builder: (context, snap) {
                  final total = (songPlayer.duration?.inMilliseconds ?? voice.duration * 1000).toDouble();
                  final pos = active ? (snap.data?.inMilliseconds ?? 0).toDouble() : 0.0;
                  final progress = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
                  return Row(children: [
                    Expanded(child: CustomPaint(size: const Size(double.infinity, 26), painter: _WavePainter(progress, fg, voice.duration + playKey.length))),
                    const SizedBox(width: 8),
                    Text(clock(active && pos > 0 ? pos / 1000 : voice.duration), style: Tx.body(12, weight: FontWeight.w600, color: fg)),
                  ]);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.progress, this.color, this.seed);

  final double progress;
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 26;
    final gap = size.width / bars;
    for (var i = 0; i < bars; i++) {
      final h = (((i * 7 + seed) * 31) % 17 + 5) / 22 * size.height;
      final paint = Paint()
        ..color = i / bars <= progress ? color : color.withAlpha(90)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final x = i * gap + gap / 2;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress || old.color != color;
}

/// Tarjeta de una ubicación enviada; al tocarla se abre en la app de mapas.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.mine, this.onTap});

  final MessageLocation location;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : Tx.text;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 230,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0EA5E9), Color(0xFF10B981)]),
            ),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              const Center(child: Icon(CupertinoIcons.location_solid, color: Colors.white, size: 38)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(location.name ?? tr('Ubicación'), maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600, color: fg)),
          const SizedBox(height: 2),
          Text('${location.lat.toStringAsFixed(5)}, ${location.lng.toStringAsFixed(5)}',
              style: Tx.body(12, color: mine ? Colors.white.withAlpha(200) : Tx.muted)),
          const SizedBox(height: 4),
          Text(tr('Abrir en Mapas'), style: Tx.body(13, weight: FontWeight.w600, color: mine ? Colors.white : Tx.accent)),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(45)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

/// Aviso centrado dentro del chat (p. ej. «activó los mensajes temporales»).
class SystemNote extends StatelessWidget {
  const SystemNote({super.key, required this.text, required this.onWallpaper});

  final String text;
  final bool onWallpaper;

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    final lock = t.contains('cifrad') || t.contains('código de seguridad') || t.contains('encrypt') || t.contains('security code');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 28),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(lock ? CupertinoIcons.lock_fill : CupertinoIcons.info_circle, size: 13, color: onWallpaper ? Colors.white70 : Tx.subtle),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, textAlign: TextAlign.center, style: Tx.body(12.5, color: onWallpaper ? Colors.white : Tx.subtle, height: 1.35)),
        ),
      ]),
    );
  }
}

/// Emoji (o el botón «+») de la barra de reacciones.
class ReactionOption extends StatelessWidget {
  const ReactionOption({super.key, this.emoji, this.icon, this.selected = false, required this.onTap});

  final String? emoji;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? Tx.alpha(Tx.accent, .25) : Colors.transparent),
        child: emoji != null ? Text(emoji!, style: const TextStyle(fontSize: 28)) : Icon(icon, color: Tx.muted, size: 22),
      ),
    );
  }
}

/// Deslizar una burbuja hacia la derecha para responderla.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({super.key, required this.child, required this.onReply, this.enabled = true});

  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> {
  double _dx = 0;
  bool _fired = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final next = (_dx + d.delta.dx).clamp(0.0, 80.0);
        if (next >= 56 && !_fired) {
          _fired = true;
          HapticFeedback.lightImpact();
        }
        setState(() => _dx = next);
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(alignment: Alignment.centerLeft, children: [
        if (_dx > 4)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Opacity(
              opacity: (_dx / 56).clamp(0.0, 1.0),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: Tx.surface3, shape: BoxShape.circle),
                child: Icon(CupertinoIcons.reply, size: 16, color: Tx.text),
              ),
            ),
          ),
        AnimatedContainer(
          duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
          transform: Matrix4.translationValues(_dx, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}
