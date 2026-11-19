import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  Json? _data;
  Object? _error;
  bool _busy = false;
  final _announcement = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _announcement.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/settings');
      if (mounted) {
        setState(() {
          _data = res.map;
          _error = null;
          _announcement.text = asStr(res.map['site_announcement']);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _save() async {
    if (_data == null || _busy) return;
    setState(() => _busy = true);
    final flags = asMap(_data!['flags']);
    final body = <String, dynamic>{'site_announcement': _announcement.text.trim()};
    for (final k in flags.keys) {
      body[k] = asBool(flags[k]['value']);
    }
    try {
      final res = await api.patch('admin/settings', body);
      if (mounted) toast(context, asStr(res.map['message'], tr('Guardado.')));
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _toggle(String key, bool v) {
    final flags = asMap(_data!['flags']);
    flags[key] = {...asMap(flags[key]), 'value': v};
    setState(() => _data = {..._data!, 'flags': flags});
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Scaffold(appBar: GlassBar(title: tr('Configuración')), body: _error != null ? ErrorState(error: _error!, onRetry: _load) : const Loading());
    }
    final flags = asMap(data['flags']);
    final maxAnn = asInt(data['max_announcement'], 200);
    return Scaffold(
      appBar: GlassBar(
        title: tr('Configuración'),
        actions: [
          if (_busy)
            const Padding(padding: EdgeInsets.all(14), child: CupertinoActivityIndicator())
          else
            TextButton(onPressed: _save, child: Text(tr('Guardar'), style: Tx.body(15, weight: FontWeight.w600, color: Tx.accent))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
        children: [
          SettingsGroup(
            title: tr('Plataforma'),
            children: [
              for (final e in flags.entries)
                SettingsRow(
                  icon: CupertinoIcons.gear,
                  color: Tx.accentSoft,
                  label: tr(asStr(e.value['label'], e.key)),
                  subtitle: asStrOrNull(e.value['hint']) != null ? tr(asStr(e.value['hint'])) : null,
                  trailing: CupertinoSwitch(
                    value: asBool(e.value['value']),
                    activeTrackColor: Tx.accentSoft,
                    onChanged: (v) => _toggle(e.key, v),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('Aviso en el sitio'), style: Tx.body(13, weight: FontWeight.w600, color: Tx.muted)),
          const SizedBox(height: 8),
          TextField(
            controller: _announcement,
            maxLength: maxAnn,
            maxLines: 3,
            style: Tx.body(15),
            decoration: fieldDecoration(tr('Mensaje visible en la web')).copyWith(
              filled: true,
              fillColor: Tx.surface1,
            ),
          ),
        ],
      ),
    );
  }
}