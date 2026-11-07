import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'follow_button.dart';

/// Fila de persona con botón de seguir (o un widget propio al final).
class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, this.subtitle, this.trailing, this.onTap, this.showFollow = true});

  final User user;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showFollow;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle ??
        (user.reason ??
            (user.bio.isNotEmpty
                ? user.bio
                : user.followersCount > 0
                    ? plural(user.followersCount, 'seguidor', 'seguidores')
                    : '@${user.username}'));
    return InkWell(
      onTap: onTap ?? () => openProfile(context, user.username),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Avatar(user: user, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NameLine(user: user),
              const SizedBox(height: 2),
              Text(
                user.reason != null || user.bio.isNotEmpty ? '@${user.username} · $sub' : sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tx.body(13, color: Tx.muted),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          if (trailing != null) trailing! else if (showFollow) FollowButton(user: user),
        ]),
      ),
    );
  }
}
