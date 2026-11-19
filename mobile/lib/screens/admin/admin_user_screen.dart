import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class AdminUserScreen extends StatefulWidget {
  const AdminUserScreen({super.key, required this.userId});
  final int userId;

  @override
  State<AdminUserScreen> createState() => _AdminUserScreenState();
}

class _AdminUserScreenState extends State<AdminUserScreen> {
  Json? _data;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/users/${widget.userId}');
      if (mounted) setState(() {
        _data = res.map;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(Future<ApiResponse> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await call();
      if (mounted) toast(context, asStr(res.map['message'], tr('Listo.')));
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _warn() async {
    final reason = await prompt(context, tr('Advertir cuenta'), hint: tr('Motivo'), action: tr('Advertir'), maxLength: 255);
    if (reason == null) return;
    await _run(() => api.post('admin/users/${widget.userId}/warn', {'reason': reason}));
  }

  Future<void> _suspend() async {
    final reason = await prompt(context, tr('Suspender cuenta'), hint: tr('Motivo'), action: tr('Suspender'), maxLength: 255);
    if (reason == null) return;
    await _run(() => api.post('admin/users/${widget.userId}/suspend', {'days': 7, 'reason': reason}));
  }

  Future<void> _unsuspend() async {
    await _run(() => api.post('admin/users/${widget.userId}/unsuspend', {}));
  }

  Future<void> _role(String role) async {
    await _run(() => api.put('admin/users/${widget.userId}/role', {'role': role}));
  }

  Future<void> _verified(bool on) async {
    await _run(() => on ? api.post('admin/users/${widget.userId}/verification', {}) : api.delete('admin/users/${widget.userId}/verification'));
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
  final me = context.watch<AppState>().me;
    if (data == null) {
      return Scaffold(appBar: GlassBar(title: tr('Usuario')), body: _error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading());
    }
    final raw = asMap(data['user']);
    final user = User.fromJson(raw);
    final canAct = asBool(data['can_act']);
    final isSelf = asBool(data['is_self']);
    final warnings = data['warnings'] is List ? asList(data['warnings'], (j) => j) : const <Json>[];

    return Scaffold(
      appBar: GlassBar(title: '@${user.username}'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          Row(children: [
            Avatar(user: user, size: 64, onTap: () => openProfile(context, user.username)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.displayName, style: Tx.display(22)),
                Text('@${user.username}', style: Tx.body(14, color: Tx.accent)),
                Text(asStr(raw['status']), style: Tx.body(13, color: Tx.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          if (canAct && !isSelf) ...[
            if (_busy) const Center(child: CupertinoActivityIndicator())
            else ...[
              if (asStr(raw['status']) == 'suspended')
                GradientButton(label: tr('Levantar suspensión'), icon: CupertinoIcons.arrow_uturn_left, onPressed: _unsuspend)
              else
                SoftButton(label: tr('Suspender'), icon: CupertinoIcons.pause_circle, color: Tx.danger, onPressed: _suspend),
              const SizedBox(height: 10),
              SoftButton(label: tr('Advertir'), icon: CupertinoIcons.exclamationmark_triangle, onPressed: _warn),
              if (me?.isAdmin ?? false) ...[
                const SizedBox(height: 10),
                SoftButton(
                  label: tr('Cambiar rol'),
                  icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                  onPressed: () => actionSheet(context, [
                    SheetAction(tr('Usuario'), CupertinoIcons.person, () => _role('user')),
                    SheetAction(tr('Moderador'), CupertinoIcons.shield_lefthalf_fill, () => _role('moderator')),
                    SheetAction(tr('Administrador'), CupertinoIcons.shield_fill, () => _role('admin')),
                  ], title: tr('Cambiar rol')),
                ),
                const SizedBox(height: 10),
                SoftButton(
                  label: asBool(raw['is_verified']) ? tr('Quitar verificado') : tr('Dar verificado'),
                  icon: CupertinoIcons.checkmark_seal_fill,
                  onPressed: () => _verified(!asBool(raw['is_verified'])),
                ),
              ],
            ],
          ],
          if (warnings.isNotEmpty) ...[
            SectionTitle(tr('Advertencias'), padding: const EdgeInsets.fromLTRB(0, 24, 0, 10)),
            for (final w in warnings)
              ListTile(
                title: Text(asStr(w['reason']), style: Tx.body(14)),
                subtitle: Text(timeAgo(asDate(w['created_at'])), style: Tx.body(12, color: Tx.subtle)),
              ),
          ],
        ],
      ),
    );
  }
}