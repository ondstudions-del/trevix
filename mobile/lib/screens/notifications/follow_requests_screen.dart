import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final _requests = Paged<User>('me/follow-requests', User.fromJson);
  final _busy = <int>{};

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

  Future<void> _resolve(User user, bool accept) async {
    setState(() => _busy.add(user.id));
    try {
      final res = await api.post('me/follow-requests/${user.id}/${accept ? 'accept' : 'reject'}');
      _requests.remove((u) => u.id == user.id);
      if (mounted) {
        context.read<AppState>().refreshCounts();
        toast(context, '${res.map['message'] ?? (accept ? tr('Solicitud aceptada.') : tr('Solicitud rechazada.'))}');
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(user.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Solicitudes')),
      body: PagedView<User>(
        paged: _requests,
        empty: EmptyState(icon: CupertinoIcons.person_badge_plus, title: tr('Sin solicitudes'), message: tr('Cuando alguien pida seguirte, aparecerá aquí.')),
        itemBuilder: (context, u, _) => UserTile(
          user: u,
          subtitle: tr('Solicitó {time}', {'time': timeAgo(u.extraDate)}),
          trailing: _busy.contains(u.id)
              ? const CupertinoActivityIndicator()
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () => _resolve(u, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(14)),
                      child: Text(tr('Aceptar'), style: Tx.body(13, weight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _resolve(u, false),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Tx.surface3, shape: BoxShape.circle, border: Border.all(color: Tx.borderStrong)),
                      child: Icon(CupertinoIcons.xmark, size: 14, color: Tx.muted),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}
