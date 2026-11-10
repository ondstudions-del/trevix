import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// Colores de cada estilo del chat (las claves las define el servidor en app.chat.themes).
class ChatPalette {
  const ChatPalette(this.start, this.end);

  final Color start;
  final Color end;

  LinearGradient get gradient => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [start, end]);
  Color get accent => Color.lerp(start, end, .5)!;

  static const _all = <String, ChatPalette>{
    'trevix': ChatPalette(Color(0xFF8B5CF6), Color(0xFF2563EB)),
    'ocean': ChatPalette(Color(0xFF22D3EE), Color(0xFF0369A1)),
    'sunset': ChatPalette(Color(0xFFFB923C), Color(0xFFDB2777)),
    'forest': ChatPalette(Color(0xFF34D399), Color(0xFF047857)),
    'berry': ChatPalette(Color(0xFFF43F5E), Color(0xFF7E22CE)),
    'love': ChatPalette(Color(0xFFFF6FA5), Color(0xFFE11D48)),
    'gold': ChatPalette(Color(0xFFFBBF24), Color(0xFFD97706)),
    'lavender': ChatPalette(Color(0xFFC4B5FD), Color(0xFF8B5CF6)),
    'mono': ChatPalette(Color(0xFF71717A), Color(0xFF27272A)),
  };

  static ChatPalette of(String? key) => _all[key] ?? _all['trevix']!;
}

/// Foto del chat: la de la persona o la del grupo (con un icono de grupo si no tiene foto).
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.conversation, this.size = 56, this.online = false});

  final Conversation conversation;
  final double size;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    if (!c.isGroup) return Avatar(user: c.user, size: size, online: online);
    final url = c.group?.avatarUrl ?? c.user.avatarUrl;
    if (url != null) return ClipOval(child: NetImage(url, width: size, height: size));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: ChatPalette.of(c.theme).gradient),
      child: Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: size * .5),
    );
  }
}

/// Avatares que aparecen en el chat cuando falta de qué leer (marca de «Visto»).
class SeenAvatars extends StatelessWidget {
  const SeenAvatars({super.key, required this.users, this.size = 15});

  final List<User> users;
  final double size;

  @override
  Widget build(BuildContext context) {
    final shown = users.take(5).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final u in shown) Padding(padding: const EdgeInsets.only(left: 2), child: Avatar(user: u, size: size)),
        if (users.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('+${users.length - shown.length}', style: Tx.body(10.5, color: Tx.subtle)),
          ),
      ],
    );
  }
}
