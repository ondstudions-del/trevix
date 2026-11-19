import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../models/models.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import 'admin_user_screen.dart';

/// Búsqueda y listado de cuentas (equipo).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _q = TextEditingController();
  String? _role;
  String? _status;
  late Paged<Json> _list = _make();

  Paged<Json> _make() => Paged<Json>(
        'admin/users',
        (j) => j,
        query: {
          if (_q.text.trim().isNotEmpty) 'q': _q.text.trim(),
          if (_role != null) 'role': _role!,
          if (_status != null) 'status': _status!,
        },
      );

  void _reload() {
    final old = _list;
    setState(() => _list = _make());
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _q.dispose();
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Usuarios')),
      body: PagedView<Json>(
        paged: _list,
        header: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: TextField(
                controller: _q,
                style: Tx.body(15),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _reload(),
                decoration: fieldDecoration(tr('Buscar @usuario o nombre')).copyWith(
                  suffixIcon: IconButton(icon: const Icon(CupertinoIcons.search), onPressed: _reload),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                children: [
                  PillChip(label: tr('Todos'), selected: _role == null && _status == null, onTap: () {
                    _role = null;
                    _status = null;
                    _reload();
                  }),
                  PillChip(label: tr('Suspendidos'), selected: _status == 'suspended', onTap: () {
                    _status = _status == 'suspended' ? null : 'suspended';
                    _reload();
                  }),
                  PillChip(label: tr('Moderadores'), selected: _role == 'moderator', onTap: () {
                    _role = _role == 'moderator' ? null : 'moderator';
                    _reload();
                  }),
                  PillChip(label: tr('Administradores'), selected: _role == 'admin', onTap: () {
                    _role = _role == 'admin' ? null : 'admin';
                    _reload();
                  }),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
        itemBuilder: (context, u, _) {
          final user = User.fromJson(u);
          final role = asStr(u['role']);
          final status = asStr(u['status']);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  await push(context, AdminUserScreen(userId: user.id));
                  _list.refresh();
                },
                child: Ink(
                  decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Avatar(user: user, size: 44, onTap: () => openProfile(context, user.username)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600)),
                        Text('@${user.username}', style: Tx.body(13, color: Tx.accent)),
                        Text(
                          [
                            if (role == 'admin') tr('Administrador'),
                            if (role == 'moderator') tr('Moderador'),
                            if (status == 'suspended') tr('Suspendida'),
                          ].join(' · '),
                          style: Tx.body(12, color: status == 'suspended' ? Tx.danger : Tx.muted),
                        ),
                      ]),
                    ),
                    Icon(CupertinoIcons.chevron_forward, size: 16, color: Tx.subtle),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}