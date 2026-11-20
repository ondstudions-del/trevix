import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';

/// Configuración avanzada de la comunidad (estilo Facebook Groups): reglas, quién publica, formatos, etc.
class CommunitySettingsScreen extends StatefulWidget {
  const CommunitySettingsScreen({super.key, required this.community});

  final Community community;

  @override
  State<CommunitySettingsScreen> createState() => _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  late Community _c = widget.community;
  List<Json> _rules = [];
  Json _settings = {};
  Json _savedSettings = {};
  bool _hidden = false;
  bool _savedHidden = false;
  String? _location;
  String? _savedLocation;
  String? _welcome;
  String? _savedWelcome;
  String _query = '';
  bool _busy = false;
  bool _loading = true;
  Object? _error;

  static const _examples = [
    ('Sé amable y cordial', 'Para fomentar un entorno agradable debemos tratarnos con respeto. Puedes debatir sobre diversos temas siempre que seas cordial con los demás.'),
    ('No hagas bullying ni uses lenguaje ofensivo', 'Asegúrate de que todos se sientan seguros. No se permite el bullying ni los comentarios degradantes.'),
    ('No publiques promociones ni spam', 'Da más de lo que recibes. En esta comunidad no se permiten la autopromoción, el spam ni los enlaces irrelevantes.'),
    ('Respeta la privacidad de los demás', 'Las conversaciones sinceras y abiertas son confidenciales. Lo que se comparte en la comunidad no debe salir de ella.'),
  ];

  bool get _dirty =>
      _hidden != _savedHidden ||
      (_location ?? '') != (_savedLocation ?? '') ||
      (_welcome ?? '') != (_savedWelcome ?? '') ||
      _encode(_settings) != _encode(_savedSettings);

  static String _encode(Json m) {
    final keys = m.keys.toList()..sort();
    final buf = StringBuffer('{');
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final v = m[k];
      buf.write(k);
      buf.write(':');
      if (v is Map) {
        buf.write(_encode(Map<String, dynamic>.from(v)));
      } else if (v is List) {
        buf.write(v.map((e) => e is Map ? _encode(Map<String, dynamic>.from(e)) : '$e').join(','));
      } else {
        buf.write('$v');
      }
      if (i < keys.length - 1) buf.write(',');
    }
    buf.write('}');
    return buf.toString();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('communities/${_c.id}');
      if (!mounted) return;
      final c = Community.fromJson(res.map);
      final settings = Map<String, dynamic>.from(asMap(res.map['settings']));
      final hidden = asBool(res.map['hidden']);
      final location = asStrOrNull(res.map['location']);
      final welcome = asStrOrNull(res.map['welcome_message']);
      setState(() {
        _c = c;
        _settings = settings;
        _savedSettings = Map<String, dynamic>.from(settings);
        _hidden = hidden;
        _savedHidden = hidden;
        _location = location;
        _savedLocation = location;
        _welcome = welcome;
        _savedWelcome = welcome;
        _rules = asList(res.map['rules'], (j) => j);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _setSetting(String key, dynamic value) {
    setState(() {
      _settings = Map<String, dynamic>.from(_settings)..[key] = value;
    });
  }

  void _toggleFormat(String key) {
    final formats = Map<String, dynamic>.from(asMap(_settings['formats']));
    formats[key] = !(formats.containsKey(key) ? asBool(formats[key]) : true);
    _setSetting('formats', formats);
  }

  Future<void> _save() async {
    if (!_dirty || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await api.patch('communities/${_c.id}/settings', {
        'settings': _settings,
        'hidden': _hidden,
        'location': _location ?? '',
        'welcome_message': _welcome ?? '',
      });
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Guardado.')));
      await _reload();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _addRule({String title = '', String body = ''}) async {
    final result = await push<_RuleDraft?>(
      context,
      _AddRuleScreen(initialTitle: title, initialBody: body),
      fullscreen: true,
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      final res = await api.post('communities/${_c.id}/rules', {'title': result.title, 'body': result.body});
      if (!mounted) return;
      toast(context, asStr(res.map['message'], tr('Regla agregada.')));
      await _reload();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _deleteRule(int id) async {
    setState(() => _busy = true);
    try {
      await api.delete('communities/${_c.id}/rules/$id');
      await _reload();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _match(String label, [String? subtitle]) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) || (subtitle?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final formats = asMap(_settings['formats']);
    return Scaffold(
      appBar: GlassBar(
        title: tr('Configuración de la comunidad'),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onPressed: _dirty && !_busy ? _save : null,
            child: Text(
              tr('Guardar'),
              style: Tx.body(
                16,
                weight: FontWeight.w700,
                color: _dirty && !_busy ? Tx.accent : Tx.subtle,
              ),
            ),
          ),
        ],
      ),
      body: _error != null && _settings.isEmpty && !_loading
          ? ErrorState(error: _error!, onRetry: _reload)
          : _loading
              ? const Center(child: CupertinoActivityIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                  children: [
                    CupertinoSearchTextField(
                      placeholder: tr('Buscar'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    if (_busy) const Padding(padding: EdgeInsets.all(12), child: Center(child: CupertinoActivityIndicator())),
                    if (_match(tr('Reglas de la comunidad'))) ...[
                      SectionTitle(tr('Reglas de la comunidad'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
                      Panel(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(tr('Crea reglas para tu comunidad'), style: Tx.body(16, weight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text(tr('Escribe hasta 10 reglas para la sección «Información». Puedes usar ejemplos o crear las tuyas.'), style: Tx.body(13, color: Tx.muted, height: 1.35)),
                          const SizedBox(height: 12),
                          GradientButton(label: tr('Agregar regla'), icon: CupertinoIcons.plus, onPressed: _busy || _rules.length >= 10 ? null : () => _addRule()),
                        ]),
                      ),
                      if (_rules.isEmpty) ...[
                        const SizedBox(height: 10),
                        Text(tr('Reglas de ejemplo'), style: Tx.body(13, color: Tx.subtle)),
                        for (final e in _examples)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(tr(e.$1), style: Tx.body(15, weight: FontWeight.w600)),
                            subtitle: Text(tr(e.$2), style: Tx.body(12.5, color: Tx.muted)),
                            trailing: Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.subtle),
                            onTap: () => _addRule(title: e.$1, body: e.$2),
                          ),
                      ] else
                        for (final r in _rules)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(asStr(r['title']), style: Tx.body(15, weight: FontWeight.w600)),
                            subtitle: Text(asStr(r['body']), style: Tx.body(12.5, color: Tx.muted)),
                            trailing: IconButton(
                              icon: const Icon(CupertinoIcons.trash, color: Tx.danger, size: 18),
                              onPressed: () => _deleteRule(asInt(r['id'])),
                            ),
                          ),
                    ],
                    if (_match(tr('Configurar comunidad'))) ...[
                      SectionTitle(tr('Configurar comunidad'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
                      SettingsGroup(children: [
                        if (_match(tr('Privacidad'), _c.visibility))
                          SettingsRow(
                            icon: CupertinoIcons.lock,
                            color: Tx.muted,
                            label: tr('Privacidad'),
                            subtitle: _c.visibility == 'private' ? tr('Privado') : tr('Público'),
                          ),
                        if (_match(tr('Ocultar comunidad')))
                          SettingsRow(
                            icon: CupertinoIcons.eye_slash,
                            color: Tx.muted,
                            label: tr('Ocultar comunidad'),
                            subtitle: _hidden ? tr('Oculto en descubrir') : tr('Visible'),
                            trailing: CupertinoSwitch(
                              value: _hidden,
                              onChanged: (v) => setState(() => _hidden = v),
                            ),
                          ),
                        if (_match(tr('Ubicación')))
                          SettingsRow(
                            icon: CupertinoIcons.location,
                            color: Tx.muted,
                            label: tr('Ubicación'),
                            subtitle: (_location == null || _location!.isEmpty) ? tr('Opcional') : _location,
                            onTap: () async {
                              final loc = await prompt(
                                context,
                                tr('Ubicación'),
                                hint: tr('Ciudad o lugar'),
                                initial: _location ?? '',
                                action: tr('Listo'),
                                maxLength: 120,
                                required: false,
                              );
                              if (loc != null) setState(() => _location = loc.trim());
                            },
                          ),
                        if (_match(tr('Presentación para miembros nuevos')))
                          SettingsRow(
                            icon: CupertinoIcons.hand_raised,
                            color: Tx.muted,
                            label: tr('Presentación para miembros nuevos'),
                            subtitle: (_welcome == null || _welcome!.isEmpty) ? null : _welcome,
                            onTap: () async {
                              final msg = await prompt(
                                context,
                                tr('Bienvenida'),
                                hint: tr('Mensaje para miembros nuevos'),
                                initial: _welcome ?? '',
                                action: tr('Listo'),
                                maxLength: 500,
                                multiline: true,
                                required: false,
                              );
                              if (msg != null) setState(() => _welcome = msg.trim());
                            },
                          ),
                      ]),
                    ],
                    if (_match(tr('Administrar conversación'))) ...[
                      SectionTitle(tr('Administrar conversación'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
                      SettingsGroup(children: [
                        _choice(
                          tr('Quién puede publicar'),
                          asStr(_settings['who_can_post'], 'members'),
                          {'members': tr('Cualquier miembro de la comunidad'), 'admins': tr('Solo administradores')},
                          (v) => _setSetting('who_can_post', v),
                        ),
                        SettingsRow(
                          icon: CupertinoIcons.checkmark_seal,
                          color: Tx.muted,
                          label: tr('Aprobación de publicaciones'),
                          subtitle: asBool(_settings['post_approval']) ? tr('Activado') : tr('Desactivado'),
                          trailing: CupertinoSwitch(
                            value: asBool(_settings['post_approval']),
                            onChanged: (v) => _setSetting('post_approval', v),
                          ),
                        ),
                        SettingsRow(
                          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
                          color: Tx.muted,
                          label: tr('Participación anónima'),
                          subtitle: asBool(_settings['anonymous']) ? tr('Activado') : tr('Desactivado'),
                          trailing: CupertinoSwitch(
                            value: asBool(_settings['anonymous']),
                            onChanged: (v) => _setSetting('anonymous', v),
                          ),
                        ),
                      ]),
                    ],
                    if (_match(tr('Solicitudes de miembros'))) ...[
                      SectionTitle(tr('Solicitudes de miembros'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
                      SettingsGroup(children: [
                        _choice(
                          tr('Quién puede aprobar solicitudes de miembros'),
                          asStr(_settings['who_can_approve'], 'admins'),
                          {'admins': tr('Administradores y moderadores'), 'members': tr('Cualquier miembro de la comunidad')},
                          (v) => _setSetting('who_can_approve', v),
                        ),
                      ]),
                    ],
                    if (_match(tr('Formatos de publicación'))) ...[
                      SectionTitle(tr('Formatos de publicación'), padding: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
                      SettingsGroup(children: [
                        _format(tr('Archivos'), tr('Permite que las personas compartan archivos'), CupertinoIcons.folder_fill, Colors.blue, 'files', formats),
                        _format(tr('Encuesta'), tr('Permite que las personas realicen encuestas'), CupertinoIcons.chart_bar_alt_fill, Colors.amber, 'polls', formats),
                        _format(tr('Eventos'), tr('Programa eventos online y presenciales'), CupertinoIcons.calendar, Colors.redAccent, 'events', formats),
                        _format('GIF', tr('Permite que las personas publiquen imágenes GIF'), CupertinoIcons.photo, Colors.teal, 'gif', formats),
                      ]),
                    ],
                  ],
                ),
    );
  }

  Widget _choice(String label, String value, Map<String, String> options, ValueChanged<String> onPick) {
    if (!_match(label, options[value])) return const SizedBox.shrink();
    return SettingsRow(
      icon: CupertinoIcons.person_2,
      color: Tx.muted,
      label: label,
      subtitle: options[value] ?? value,
      onTap: () => actionSheet(
        context,
        [
          for (final e in options.entries) SheetAction(e.value, CupertinoIcons.circle, () => onPick(e.key)),
        ],
        title: label,
      ),
    );
  }

  Widget _format(String label, String subtitle, IconData icon, Color color, String key, Json formats) {
    if (!_match(label, subtitle)) return const SizedBox.shrink();
    final on = formats.containsKey(key) ? asBool(formats[key]) : true;
    return SettingsRow(
      icon: icon,
      color: color,
      label: label,
      subtitle: subtitle,
      trailing: CupertinoSwitch(value: on, onChanged: (_) => _toggleFormat(key)),
    );
  }
}

class _RuleDraft {
  const _RuleDraft(this.title, this.body);
  final String title;
  final String body;
}

class _AddRuleScreen extends StatefulWidget {
  const _AddRuleScreen({this.initialTitle = '', this.initialBody = ''});
  final String initialTitle;
  final String initialBody;

  @override
  State<_AddRuleScreen> createState() => _AddRuleScreenState();
}

class _AddRuleScreenState extends State<_AddRuleScreen> {
  late final _title = TextEditingController(text: widget.initialTitle);
  late final _body = TextEditingController(text: widget.initialBody);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Agregar regla')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Text(tr('Reglas de ejemplo'), style: Tx.body(13, color: Tx.subtle)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _CommunitySettingsScreenState._examples)
                ActionChip(
                  label: Text(tr(e.$1), style: Tx.body(12.5)),
                  onPressed: () => setState(() {
                    _title.text = e.$1;
                    _body.text = e.$2;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(tr('Resumen de regla de la comunidad'), style: Tx.body(13, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _title,
            maxLength: 50,
            decoration: InputDecoration(hintText: tr('Sé amable y cordial'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (_) => setState(() {}),
          ),
          Text('${_title.text.characters.length}/50', style: Tx.body(12, color: Tx.subtle)),
          const SizedBox(height: 14),
          Text(tr('Detalles adicionales de la regla'), style: Tx.body(13, weight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _body,
            maxLength: 500,
            maxLines: 5,
            decoration: InputDecoration(hintText: tr('Explica la regla…'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
            onChanged: (_) => setState(() {}),
          ),
          Text('${_body.text.characters.length}/500', style: Tx.body(12, color: Tx.subtle)),
          const SizedBox(height: 20),
          GradientButton(
            label: tr('Agregar regla'),
            onPressed: _title.text.trim().length < 3 || _body.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _RuleDraft(_title.text.trim(), _body.text.trim())),
          ),
        ],
      ),
    );
  }
}
