import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// Seguir · Solicitado · Siguiendo, con el estado real devuelto por el servidor.
class FollowButton extends StatefulWidget {
  const FollowButton({super.key, required this.user, this.height = 34, this.onChanged, this.expand = false});

  final User user;
  final double height;
  final VoidCallback? onChanged;
  final bool expand;

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _busy = false;

  Relation get _rel => widget.user.relation ??= Relation();

  Future<void> _toggle() async {
    final rel = _rel;
    if (rel.following || rel.requested) {
      final ok = await confirm(
        context,
        rel.following ? tr('Dejar de seguir a @{username}', {'username': widget.user.username}) : tr('Cancelar la solicitud'),
        rel.following && widget.user.isPrivate ? tr('Es una cuenta privada: tendrás que volver a solicitar seguirla.') : '',
        action: rel.following ? tr('Dejar de seguir') : tr('Cancelar solicitud'),
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    HapticFeedback.selectionClick();
    try {
      final res = rel.following || rel.requested
          ? await api.delete('users/${widget.user.id}/follow')
          : await api.post('users/${widget.user.id}/follow');
      final data = res.map;
      if (data['relation'] is Map) {
        widget.user.relation = Relation.fromJson(Map<String, dynamic>.from(data['relation'] as Map));
      }
      if (data['followers_count'] != null) widget.user.followersCount = asInt(data['followers_count']);
      widget.onChanged?.call();
      if (mounted) context.read<AppState>().refreshCounts();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    if (me != null && me.id == widget.user.id) return const SizedBox.shrink();
    final rel = _rel;
    final active = rel.following || rel.requested;
    final label = rel.following
        ? tr('Siguiendo')
        : rel.requested
            ? tr('Solicitado')
            : rel.followsYou
                ? tr('Seguir también')
                : tr('Seguir');
    return GestureDetector(
      onTap: _busy ? null : _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: widget.height,
        width: widget.expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: active ? null : Tx.brand,
          color: active ? Tx.surface3 : null,
          borderRadius: BorderRadius.circular(widget.height / 2.4),
          border: Border.all(color: active ? Tx.borderStrong : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: active ? Tx.text : Colors.white)),
      ),
    );
  }
}
