import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../core/paged.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';

/// Seguidores o seguidos de una cuenta.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key, required this.username, required this.followers});

  final String username;
  final bool followers;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  late final Paged<User> _list =
      Paged<User>('users/${Uri.encodeComponent(widget.username)}/${widget.followers ? 'followers' : 'following'}', User.fromJson);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: widget.followers ? tr('Seguidores') : tr('Siguiendo')),
      body: PagedView<User>(
        paged: _list,
        header: const [SliverToBoxAdapter(child: SizedBox(height: 6))],
        privateState: EmptyState(icon: CupertinoIcons.lock_fill, title: tr('Lista privada'), message: tr('Sigue a esta cuenta para ver la lista.')),
        empty: EmptyState(
          icon: CupertinoIcons.person_2,
          title: widget.followers ? tr('Sin seguidores todavía') : tr('No sigue a nadie todavía'),
        ),
        itemBuilder: (context, u, _) => UserTile(user: u),
      ),
    );
  }
}
