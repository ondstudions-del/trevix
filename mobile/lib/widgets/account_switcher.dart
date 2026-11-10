import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/accounts.dart';
import '../core/api.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Cambiar de cuenta y agregar cuentas (como en Facebook): las cuentas con sesión abierta en este teléfono.
Future<void> showAccountSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AccountSwitcher(),
  );
}

class _AccountSwitcher extends StatefulWidget {
  const _AccountSwitcher();

  @override
  State<_AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends State<_AccountSwitcher> {
  final Map<int, int> _pending = {};
  int? _busy;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  /// Avisos sin ver de las demás cuentas, con su propio token.
  Future<void> _loadCounts() async {
    final others = context.read<AppState>().otherAccounts;
    for (final a in others) {
      try {
        final c = Counts.fromJson((await api.request('GET', 'me/counts', asToken: a.token)).map);
        if (mounted) setState(() => _pending[a.id] = c.messages + c.activity);
      } catch (_) {}
    }
  }

  Future<void> _switch(SavedAccount a) async {
    if (_busy != null) return;
    final state = context.read<AppState>();
    setState(() => _busy = a.id);
    try {
      await state.switchTo(a);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      toastError(context, e);
    }
  }

  void _add() {
    final state = context.read<AppState>();
    try {
      state.beginAddAccount();
      Navigator.pop(context);
    } catch (e) {
      toastError(context, e);
    }
  }

  Future<void> _remove(SavedAccount a) async {
    final state = context.read<AppState>();
    final active = a.id == state.me?.id;
    final ok = await confirm(
      context,
      active ? 'Cerrar sesión' : 'Quitar cuenta',
      active
          ? (state.otherAccounts.isEmpty
              ? '¿Quieres cerrar sesión en este dispositivo?'
              : 'Se cerrará la sesión de @${a.username} y pasarás a otra de tus cuentas.')
          : 'Se cerrará la sesión de @${a.username} en este teléfono. Para volver a usarla tendrás que escribir tu contraseña.',
      action: active ? 'Cerrar sesión' : 'Quitar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (active) Navigator.pop(context);
    await state.removeAccount(a);
    if (mounted && !active) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    final saved = state.accounts.where((a) => a.id != me?.id).toList();
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Text('Cuentas', style: Tx.display(20)),
        ),
        if (me != null)
          _AccountRow(
            user: me.user,
            subtitle: 'Cuenta actual',
            trailing: Icon(CupertinoIcons.checkmark_circle_fill, color: Tx.accent, size: 24),
            onLongPress: () => _remove(SavedAccount.of(me.user, api.token ?? '')),
          ),
        for (final a in saved)
          _AccountRow(
            user: a.user,
            subtitle: '@${a.username}',
            badge: _pending[a.id] ?? 0,
            busy: _busy == a.id,
            onTap: () => _switch(a),
            trailing: IconButton(
              tooltip: 'Más opciones',
              onPressed: () => actionSheet(context, [
                SheetAction('Quitar cuenta de este teléfono', CupertinoIcons.person_crop_circle_badge_minus, () => _remove(a), destructive: true),
              ], title: '@${a.username}'),
              icon: Icon(CupertinoIcons.ellipsis, color: Tx.muted),
            ),
          ),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _add,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Tx.surface3, shape: BoxShape.circle, border: Border.all(color: Tx.border)),
                child: Icon(CupertinoIcons.add, color: Tx.text, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('Agregar cuenta', style: Tx.body(16, weight: FontWeight.w600))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Text(
            'Hasta ${AccountStore.max} cuentas con la sesión abierta en este teléfono. Los avisos en segundo plano son de la cuenta activa.',
            style: Tx.body(12.5, color: Tx.subtle, height: 1.35),
          ),
        ),
      ]),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.user, required this.subtitle, this.trailing, this.onTap, this.onLongPress, this.badge = 0, this.busy = false});

  final User user;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final int badge;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: busy ? null : onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(user: user, size: 48),
            if (badge > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 20),
                  decoration: BoxDecoration(color: Tx.danger, borderRadius: BorderRadius.circular(10), border: Border.all(color: Tx.surface1, width: 2)),
                  child: Text(badge > 99 ? '99+' : '$badge', textAlign: TextAlign.center, style: Tx.body(11, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(user.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(16, weight: FontWeight.w600))),
                if (user.isVerified) ...[const SizedBox(width: 5), const VerifiedBadge(size: 15)],
              ]),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
            ]),
          ),
          if (busy)
            const Padding(padding: EdgeInsets.all(12), child: CupertinoActivityIndicator())
          else if (trailing != null)
            trailing!,
        ]),
      ),
    );
  }
}
