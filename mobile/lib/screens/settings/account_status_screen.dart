import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

/// Estado de la cuenta: advertencias del equipo de moderación (me/warnings). Las vigentes de los últimos días
/// impiden pedir el verificado.
class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({super.key});

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  Json? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('me/warnings');
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

  static const _about = {
    'post': 'Por una publicación',
    'comment': 'Por un comentario',
    'message': 'Por un mensaje',
    'story': 'Por una historia',
    'community': 'Por una comunidad',
  };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: GlassBar(title: tr('Estado de la cuenta')),
      body: data == null
          ? (_error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading())
          : RefreshIndicator(onRefresh: _load, color: Tx.accentSoft, child: _content(data)),
    );
  }

  Widget _content(Json data) {
    final warnings = asList(data['warnings'], (j) => j);
    final active = asInt(data['active_count']);
    final days = asInt(data['days'], 30);
    final ok = active == 0;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
      Panel(
        gradient: true,
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Icon(ok ? CupertinoIcons.checkmark_shield_fill : CupertinoIcons.exclamationmark_triangle_fill, color: ok ? Tx.success : Tx.warning, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ok ? tr('Tu cuenta está en regla') : plural(active, 'advertencia vigente', 'advertencias vigentes'), style: Tx.body(17, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                ok
                    ? tr('No tienes advertencias en los últimos {days} días.', {'days': days})
                    : tr('Mientras tengas advertencias de los últimos {days} días no podrás pedir el verificado. Si se repiten, el equipo puede suspender tu cuenta.', {'days': days}),
                style: Tx.body(13.5, color: Tx.muted, height: 1.35),
              ),
            ]),
          ),
        ]),
      ),
      if (warnings.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: EmptyState(icon: CupertinoIcons.checkmark_seal, title: tr('Sin advertencias'), message: tr('Nunca has recibido una advertencia. ¡Sigue así!')),
        )
      else
        SettingsGroup(title: tr('Historial'), children: [
          for (final w in warnings)
            SettingsRow(
              icon: asBool(w['revoked'])
                  ? CupertinoIcons.arrow_uturn_left_circle
                  : asBool(w['active'])
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : CupertinoIcons.clock,
              color: asBool(w['revoked'])
                  ? Tx.subtle
                  : asBool(w['active'])
                      ? Tx.warning
                      : Tx.muted,
              label: asStr(w['reason']),
              subtitle: [
                if (_about.containsKey(asStr(w['about']))) tr(_about[asStr(w['about'])]!),
                timeAgo(asDate(w['created_at'])),
                if (asBool(w['revoked'])) tr('Retirada por el equipo') else if (asBool(w['active'])) tr('Vigente') else tr('Ya no cuenta'),
              ].whereType<String>().join(' · '),
            ),
        ]),
      SettingsGroup(children: [
        SettingsRow(
          icon: CupertinoIcons.doc_text,
          color: Tx.muted,
          label: tr('Términos y normas de la comunidad'),
          onTap: () => openInApp(context, AppConfig.web('legal.php?doc=terminos')),
        ),
      ]),
    ]);
  }
}
