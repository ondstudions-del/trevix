import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';

/// Miembros de una comunidad; quien modera ve también solicitudes y vetos.
class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen({super.key, required this.community});

  final Community community;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  late Community _community = widget.community;
  late String _status = (widget.community.access?.manager ?? false) && widget.community.pendingRequests > 0 ? 'pending' : 'active';
  late Paged<Member> _list = _make();
  final Set<int> _busy = {};

  bool get _manager => _community.access?.manager ?? false;
  bool get _owner => _community.access?.owner ?? false;

  Paged<Member> _make() => Paged<Member>('communities/${_community.slug}/members', Member.fromJson, query: {'status': _status});

  void _switch(String status) {
    if (status == _status) return;
    final old = _list;
    setState(() {
      _status = status;
      _list = _make();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  Future<void> _act(Member m, String method, String path, {bool removeFromList = true}) async {
    setState(() => _busy.add(m.user.id));
    try {
      final res = method == 'DELETE' ? await api.delete(path) : await api.post(path);
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Listo.'}');
      if (res.map['community'] is Map) _community = Community.fromJson(asMap(res.map['community']));
      if (removeFromList) {
        _list.remove((x) => x.user.id == m.user.id);
      } else {
        await _list.refresh();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(m.user.id));
  }

  void _options(Member m) {
    final id = _community.id;
    final uid = m.user.id;
    final name = '@${m.user.username}';
    final actions = <SheetAction>[];
    if (_status == 'pending') {
      actions
        ..add(SheetAction('Aceptar solicitud', CupertinoIcons.checkmark_circle, () => _act(m, 'POST', 'communities/$id/requests/$uid/approve')))
        ..add(SheetAction('Rechazar solicitud', CupertinoIcons.xmark_circle, () => _act(m, 'POST', 'communities/$id/requests/$uid/reject'), destructive: true));
    } else if (_status == 'banned') {
      actions.add(SheetAction('Levantar el veto', CupertinoIcons.arrow_uturn_left, () => _act(m, 'DELETE', 'communities/$id/bans/$uid')));
    } else {
      if (_owner && m.role == 'member') {
        actions.add(SheetAction('Nombrar moderador', CupertinoIcons.shield_lefthalf_fill,
            () => _act(m, 'POST', 'communities/$id/moderators/$uid', removeFromList: false)));
      }
      if (_owner && m.role == 'moderator') {
        actions.add(SheetAction('Quitar como moderador', CupertinoIcons.shield_slash,
            () => _act(m, 'DELETE', 'communities/$id/moderators/$uid', removeFromList: false)));
      }
      if (m.role != 'owner' && (_owner || m.role == 'member')) {
        actions.add(SheetAction('Vetar de la comunidad', CupertinoIcons.nosign, () async {
          if (await confirm(context, 'Vetar a $name', 'Saldrá de la comunidad y no podrá volver a unirse mientras dure el veto.',
              action: 'Vetar', destructive: true)) {
            await _act(m, 'POST', 'communities/$id/bans/$uid');
          }
        }, destructive: true));
      }
    }
    if (actions.isEmpty) return;
    actionSheet(context, actions, title: name);
  }

  String _roleLabel(String role) => switch (role) {
        'owner' => 'Administrador',
        'moderator' => 'Moderador',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().me;
    return Scaffold(
      appBar: GlassBar(
        title: 'Miembros',
        bottom: _manager
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    children: [
                      PillChip(label: 'Miembros', selected: _status == 'active', onTap: () => _switch('active')),
                      const SizedBox(width: 8),
                      PillChip(
                        label: _community.pendingRequests > 0 ? 'Solicitudes (${compact(_community.pendingRequests)})' : 'Solicitudes',
                        selected: _status == 'pending',
                        onTap: () => _switch('pending'),
                      ),
                      const SizedBox(width: 8),
                      PillChip(label: 'Vetados', selected: _status == 'banned', onTap: () => _switch('banned')),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: PagedView<Member>(
        paged: _list,
        privateState: const EmptyState(icon: CupertinoIcons.lock_fill, title: 'Comunidad privada', message: 'Solo los miembros ven esta lista.'),
        empty: EmptyState(
          icon: _status == 'banned' ? CupertinoIcons.nosign : CupertinoIcons.person_3,
          title: switch (_status) {
            'pending' => 'No hay solicitudes',
            'banned' => 'Nadie está vetado',
            _ => 'Sin miembros',
          },
        ),
        itemBuilder: (context, m, _) {
          final self = me != null && me.id == m.user.id;
          final role = _roleLabel(m.role);
          final canAct = _manager && !self && m.role != 'owner';
          return UserTile(
            user: m.user,
            subtitle: role.isNotEmpty ? '@${m.user.username} · $role' : '@${m.user.username}',
            showFollow: !canAct && !self,
            trailing: canAct
                ? (_busy.contains(m.user.id)
                    ? const Padding(padding: EdgeInsets.all(10), child: CupertinoActivityIndicator())
                    : _status == 'pending'
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            _CircleAction(
                              icon: CupertinoIcons.xmark,
                              color: Tx.muted,
                              onTap: () => _act(m, 'POST', 'communities/${_community.id}/requests/${m.user.id}/reject'),
                            ),
                            const SizedBox(width: 8),
                            _CircleAction(
                              icon: CupertinoIcons.checkmark_alt,
                              color: Colors.white,
                              gradient: true,
                              onTap: () => _act(m, 'POST', 'communities/${_community.id}/requests/${m.user.id}/approve'),
                            ),
                          ])
                        : IconButton(onPressed: () => _options(m), icon: Icon(CupertinoIcons.ellipsis, color: Tx.muted)))
                : null,
          );
        },
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.color, required this.onTap, this.gradient = false});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: gradient ? Tx.brand : null,
          color: gradient ? null : Tx.surface3,
          shape: BoxShape.circle,
          border: gradient ? null : Border.all(color: Tx.borderStrong),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
