import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../models/models.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';
import 'ads_screen.dart';

/// Preferencias de OND-ADS: dónde ver anuncios y acceso al monedero de promociones.
class AdsSettingsScreen extends StatefulWidget {
  const AdsSettingsScreen({super.key});

  @override
  State<AdsSettingsScreen> createState() => _AdsSettingsScreenState();
}

class _AdsSettingsScreenState extends State<AdsSettingsScreen> {
  final _saving = <String>{};
  final _pending = <String, bool>{};

  Future<void> _patch(String field, bool value) async {
    setState(() {
      _pending[field] = value;
      _saving.add(field);
    });
    try {
      final res = await api.patch('me/ad-settings', {field: value});
      if (!mounted) return;
      final user = asMapOrNull(res.map['user']);
      if (user != null) context.read<AppState>().setMe(user);
      setState(() => _pending.remove(field));
      toast(context, asStr(res.map['message'], tr('Guardado.')));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _saving.remove(field));
  }

  bool _val(Map<String, dynamic> settings, String key) {
    final pending = _pending[key];
    if (pending != null) return pending;
    return settings[key] != false;
  }

  Widget _switch(String field, Map<String, dynamic> settings, {String? subtitle}) {
    return SettingsRow(
      icon: CupertinoIcons.speaker_2,
      color: Tx.accent,
      label: tr(_labels[field] ?? field),
      subtitle: subtitle != null ? tr(subtitle) : null,
      trailing: _saving.contains(field)
          ? const CupertinoActivityIndicator()
          : TxSwitch(value: _val(settings, field), onChanged: (v) => _patch(field, v)),
    );
  }

  static const _labels = {
    'ads_personalized': 'Anuncios personalizados',
    'ads_feed': 'Feed e inicio',
    'ads_profile': 'Perfiles',
    'ads_stories': 'Historias',
    'ads_reels': 'Reels',
    'ads_community': 'Comunidades',
  };

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me!;
    final settings = me.settings;
    final personalized = _val(settings, 'ads_personalized');
    return Scaffold(
      appBar: GlassBar(title: tr('OND-ADS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          Panel(
            gradient: true,
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Anuncios en TREVIX'), style: Tx.body(17, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                tr('Los anuncios aprobados se integran como publicaciones, historias o reels. Puedes limitar dónde los ves o crear los tuyos con el monedero.'),
                style: Tx.body(13.5, color: Tx.muted, height: 1.45),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SettingsGroup(children: [
            _switch('ads_personalized', settings, subtitle: 'Si lo desactivas, no verás promociones de OND-ADS.'),
            if (personalized) ...[
              _switch('ads_feed', settings),
              _switch('ads_profile', settings),
              _switch('ads_stories', settings),
              _switch('ads_reels', settings),
              _switch('ads_community', settings),
            ],
          ]),
          const SizedBox(height: 16),
          SettingsGroup(children: [
            SettingsRow(
              icon: CupertinoIcons.speaker_2_fill,
              color: Tx.warning,
              label: tr('Crear o gestionar anuncios'),
              subtitle: tr('Promociona publicaciones, apps, sitios web, productos o videos.'),
              onTap: () => push(context, const AdsScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}