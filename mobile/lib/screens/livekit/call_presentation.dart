import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Fondo difuminado (estilo Messenger) con el avatar del contacto.
class CallBlurBackdrop extends StatelessWidget {
  const CallBlurBackdrop({super.key, required this.user, this.avatarUrl});

  final User? user;
  final String? avatarUrl;

  String? get _url => avatarUrl ?? user?.avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF4A4A4A)),
        if (url != null && url.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Transform.scale(
              scale: 1.15,
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
            ),
          ),
        ColoredBox(color: Colors.black.withAlpha(150)),
      ],
    );
  }
}

class CallTopBar extends StatelessWidget {
  const CallTopBar({super.key, required this.title, this.onMinimize, this.onMore});

  final String title;
  final VoidCallback? onMinimize;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: onMinimize,
            icon: const Icon(CupertinoIcons.chevron_down, color: Colors.white, size: 28),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tx.body(17, weight: FontWeight.w600, color: Colors.white),
            ),
          ),
          IconButton(
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz, color: Colors.white, size: 26),
          ),
        ],
      ),
    );
  }
}

class CallCallerBlock extends StatelessWidget {
  const CallCallerBlock({
    super.key,
    required this.user,
    this.avatarUrl,
    this.nameOverride,
    this.subtitle,
    this.avatarSize = 140,
    this.pulse,
  });

  final User? user;
  final String? avatarUrl;
  final String? nameOverride;
  final String? subtitle;
  final double avatarSize;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final name = nameOverride ?? user?.displayName ?? '';
    Widget avatar = Avatar(
      user: user ?? User(id: 0, username: 'u', displayName: name, avatarUrl: avatarUrl),
      size: avatarSize,
    );
    if (pulse != null) {
      avatar = ScaleTransition(
        scale: Tween(begin: 0.97, end: 1.03).animate(CurvedAnimation(parent: pulse!, curve: Curves.easeInOut)),
        child: avatar,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        avatar,
        const SizedBox(height: 20),
        Text(
          name,
          style: Tx.display(30, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(subtitle!, style: Tx.body(16, color: Colors.white.withAlpha(210)), textAlign: TextAlign.center),
        ],
      ],
    );
  }
}

class CallDockButton extends StatelessWidget {
  const CallDockButton({super.key, required this.icon, this.onTap, this.active = true, this.danger = false});

  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFE53935)
        : (active ? Colors.white.withAlpha(38) : Colors.white.withAlpha(22));
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: danger ? 56 : 48,
          height: danger ? 56 : 48,
          child: Icon(icon, color: Colors.white, size: danger ? 28 : 22),
        ),
      ),
    );
  }
}

class CallOutgoingDock extends StatelessWidget {
  const CallOutgoingDock({
    super.key,
    required this.video,
    required this.onEnd,
    this.onToggleVideo,
    this.onToggleMic,
    this.onToggleSpeaker,
    this.videoOn = false,
    this.micOn = true,
    this.speakerOn = true,
  });

  final bool video;
  final VoidCallback onEnd;
  final VoidCallback? onToggleVideo;
  final VoidCallback? onToggleMic;
  final VoidCallback? onToggleSpeaker;
  final bool videoOn;
  final bool micOn;
  final bool speakerOn;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          CallDockButton(
            icon: video
                ? (videoOn ? CupertinoIcons.videocam_fill : CupertinoIcons.videocam)
                : CupertinoIcons.videocam,
            active: video && videoOn,
            onTap: video ? onToggleVideo : null,
          ),
          CallDockButton(
            icon: micOn ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill,
            active: micOn,
            onTap: onToggleMic,
          ),
          CallDockButton(
            icon: speakerOn ? CupertinoIcons.speaker_2_fill : CupertinoIcons.speaker_slash_fill,
            active: speakerOn,
            onTap: onToggleSpeaker,
          ),
          CallDockButton(icon: CupertinoIcons.phone_down_fill, danger: true, onTap: onEnd),
        ],
      ),
    );
  }
}

class CallAnswerRow extends StatelessWidget {
  const CallAnswerRow({super.key, required this.onDecline, required this.onAccept, this.video = false, this.busy = false});

  final VoidCallback onDecline;
  final VoidCallback onAccept;
  final bool video;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _LabeledCircle(
            color: const Color(0xFFE53935),
            icon: CupertinoIcons.xmark,
            label: tr('Rechazar'),
            onTap: busy ? null : onDecline,
            size: 72,
          ),
          _LabeledCircle(
            color: const Color(0xFF22C55E),
            icon: video ? CupertinoIcons.videocam_fill : CupertinoIcons.phone_fill,
            label: tr('Contestar'),
            onTap: busy ? null : onAccept,
            size: 72,
          ),
        ],
      ),
    );
  }
}

class _LabeledCircle extends StatelessWidget {
  const _LabeledCircle({required this.color, required this.icon, required this.label, this.onTap, this.size = 72});

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: size * 0.42)),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: Tx.body(15, color: Colors.white)),
      ],
    );
  }
}