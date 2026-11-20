import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
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

  static const _restrictParts = {
    'messages': 'No enviar mensajes',
    'posts': 'No publicar',
    'stories': 'No subir stories',
    'comments': 'No comentar',
    'gifts': 'No enviar regalos',
    'profile': 'No cambiar el perfil',
    'communities': 'No unirse a grupos/comunidades',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/users/${widget.userId}');
      if (mounted) {
        setState(() {
          _data = res.map;
          _error = null;
        });
      }
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
    final duration = await prompt(context, tr('Duración de la suspensión'), hint: tr('Días (ej. 7) o 0 = indefinida'), action: tr('Siguiente'), maxLength: 5);
    if (duration == null || !mounted) return;
    final days = int.tryParse(duration.trim()) ?? 7;
    final reason = await prompt(context, tr('Suspender cuenta'), hint: tr('Motivo'), action: tr('Suspender'), maxLength: 255);
    if (reason == null || !mounted) return;
    await _run(() => api.post('admin/users/${widget.userId}/suspend', {'days': days, 'reason': reason}));
  }

  Future<void> _unsuspend() async {
    await _run(() => api.post('admin/users/${widget.userId}/unsuspend', {}));
  }

  Future<void> _restrict() async {
    final parts = <String>{};
    var unit = 'days';
    final amountCtrl = TextEditingController(text: '3');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SheetFrame(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Restringir cuenta'), style: Tx.display(20)),
              const SizedBox(height: 6),
              Text(tr('Elige qué no podrá hacer y por cuánto tiempo.'), style: Tx.body(13.5, color: Tx.muted)),
              const SizedBox(height: 12),
              for (final e in _restrictParts.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: parts.contains(e.key),
                  title: Text(tr(e.value), style: Tx.body(14)),
                  onChanged: (v) => setLocal(() {
                    if (v == true) {
                      parts.add(e.key);
                    } else {
                      parts.remove(e.key);
                    }
                  }),
                ),
              const SizedBox(height: 8),
              Text(tr('Duración'), style: Tx.body(13, weight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: fieldDecoration(tr('Cantidad')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(12), border: Border.all(color: Tx.border)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: unit,
                        isExpanded: true,
                        items: [
                          DropdownMenuItem(value: 'hours', child: Text(tr('Horas'))),
                          DropdownMenuItem(value: 'days', child: Text(tr('Días'))),
                        ],
                        onChanged: (v) => setLocal(() => unit = v ?? 'days'),
                      ),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: SoftButton(label: tr('Cancelar'), onPressed: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: GradientButton(label: tr('Continuar'), onPressed: () => Navigator.pop(ctx, true))),
              ]),
            ]),
          );
        });
      },
    );
    final amountText = amountCtrl.text;
    amountCtrl.dispose();
    if (ok != true) return;
    if (parts.isEmpty) {
      if (mounted) toast(context, tr('Elige al menos una restricción.'), error: true);
      return;
    }
    final amount = int.tryParse(amountText.trim()) ?? 0;
    final hours = unit == 'hours' ? amount : amount * 24;
    if (hours < 1) {
      if (mounted) toast(context, tr('Duración no válida.'), error: true);
      return;
    }
    if (!mounted) return;
    final reason = await prompt(context, tr('Motivo de la restricción'), hint: tr('Motivo'), action: tr('Restringir'), maxLength: 255);
    if (reason == null || !mounted) return;
    await _run(() => api.post('admin/users/${widget.userId}/restrict', {
          'hours': hours,
          'reason': reason,
          'parts': parts.toList(),
        }));
  }

  Future<void> _unrestrict() async {
    await _run(() => api.post('admin/users/${widget.userId}/unrestrict', {}));
  }

  Future<void> _role(String role) async {
    await _run(() => api.put('admin/users/${widget.userId}/role', {'role': role}));
  }

  Future<void> _verified(bool on) async {
    await _run(() => on ? api.post('admin/users/${widget.userId}/verification', {}) : api.delete('admin/users/${widget.userId}/verification'));
  }

  Widget _actionCard({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Tx.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tx.border),
          ),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: Tx.alpha(color, .14), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Tx.body(15.5, weight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: Tx.body(12.5, color: Tx.muted)),
              ]),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.subtle),
          ]),
        ),
      ),
    );
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
    final restrictedUntil = asStrOrNull(raw['restricted_until']);
    final restrictionReason = asStrOrNull(raw['restriction_reason']);
    final status = asStr(raw['status']);

    return Scaffold(
      appBar: GlassBar(title: '@${user.username}'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Tx.alpha(Tx.accent, .12), Tx.surface1]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Tx.border),
            ),
            child: Row(children: [
              Avatar(user: user, size: 72, onTap: () => openProfile(context, user.username)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.displayName, style: Tx.display(22)),
                  Text('@${user.username}', style: Tx.body(14, color: Tx.accent)),
                  const SizedBox(height: 4),
                  Text(
                    '${tr(status)} · ${compact(asInt(raw['followers_count']))} ${tr('seguidores')}',
                    style: Tx.body(13, color: Tx.muted),
                  ),
                ]),
              ),
            ]),
          ),
          if (restrictedUntil != null) ...[
            const SizedBox(height: 12),
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Restricción activa'), style: Tx.body(15, weight: FontWeight.w700, color: Tx.warning)),
                const SizedBox(height: 4),
                Text(tr('Hasta: {until}', {'until': restrictedUntil}), style: Tx.body(13, color: Tx.muted)),
                if (restrictionReason != null && restrictionReason.isNotEmpty)
                  Text(tr('Motivo: {reason}', {'reason': restrictionReason}), style: Tx.body(13, color: Tx.muted)),
              ]),
            ),
          ],
          if (canAct && !isSelf) ...[
            SectionTitle(tr('Moderación'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CupertinoActivityIndicator())),
            if (status == 'suspended')
              _actionCard(
                icon: CupertinoIcons.arrow_uturn_left_circle_fill,
                color: Tx.success,
                label: tr('Levantar suspensión'),
                subtitle: tr('La cuenta podrá volver a entrar'),
                onTap: _unsuspend,
              )
            else
              _actionCard(
                icon: CupertinoIcons.pause_circle_fill,
                color: Tx.danger,
                label: tr('Suspender'),
                subtitle: tr('Por días o de forma indefinida'),
                onTap: _suspend,
              ),
            const SizedBox(height: 10),
            _actionCard(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: Tx.warning,
              label: tr('Advertir'),
              subtitle: tr('Suma una advertencia al historial'),
              onTap: _warn,
            ),
            const SizedBox(height: 10),
            _actionCard(
              icon: CupertinoIcons.lock_fill,
              color: const Color(0xFFD4A017),
              label: tr('Restringir (parcial)'),
              subtitle: tr('Bloquea partes concretas por horas o días'),
              onTap: _restrict,
            ),
            if (restrictedUntil != null) ...[
              const SizedBox(height: 10),
              _actionCard(
                icon: CupertinoIcons.lock_open_fill,
                color: Tx.success,
                label: tr('Quitar restricción'),
                subtitle: tr('Restaura todas las funciones'),
                onTap: _unrestrict,
              ),
            ],
            if (me?.isAdmin ?? false) ...[
              const SizedBox(height: 10),
              _actionCard(
                icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                color: Tx.accentSoft,
                label: tr('Cambiar rol'),
                subtitle: tr('Usuario, moderador o administrador'),
                onTap: () => actionSheet(context, [
                  SheetAction(tr('Usuario'), CupertinoIcons.person, () => _role('user')),
                  SheetAction(tr('Moderador'), CupertinoIcons.shield_lefthalf_fill, () => _role('moderator')),
                  SheetAction(tr('Administrador'), CupertinoIcons.shield_fill, () => _role('admin')),
                ], title: tr('Cambiar rol')),
              ),
              const SizedBox(height: 10),
              _actionCard(
                icon: CupertinoIcons.checkmark_seal_fill,
                color: Tx.blue400,
                label: asBool(raw['is_verified']) ? tr('Quitar verificado') : tr('Dar verificado'),
                subtitle: tr('Insignia junto al nombre'),
                onTap: () => _verified(!asBool(raw['is_verified'])),
              ),
            ],
          ],
          if (warnings.isNotEmpty) ...[
            SectionTitle(tr('Advertencias'), padding: const EdgeInsets.fromLTRB(0, 24, 0, 10)),
            for (final w in warnings)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(asStr(w['reason']), style: Tx.body(14)),
                subtitle: Text(timeAgo(asDate(w['created_at'])), style: Tx.body(12, color: Tx.subtle)),
              ),
          ],
        ],
      ),
    );
  }
}
