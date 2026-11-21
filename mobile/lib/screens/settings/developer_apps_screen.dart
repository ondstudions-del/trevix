import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Apps OAuth del desarrollador: claves, HTML de login y guía de integración.
class DeveloperAppsScreen extends StatefulWidget {
  const DeveloperAppsScreen({super.key});

  @override
  State<DeveloperAppsScreen> createState() => _DeveloperAppsScreenState();
}

class _DeveloperAppsScreenState extends State<DeveloperAppsScreen> {
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('me/oauth/apps');
      if (!mounted) return;
      setState(() {
        _apps = res.list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = tr('No se pudieron cargar tus apps.');
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _CreateOAuthAppScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _open(Map<String, dynamic> app) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _OAuthAppDetailScreen(appId: app['id'] as int? ?? int.tryParse('${app['id']}') ?? 0)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: tr('Mis apps'),
        actions: [
          IconButton(
            tooltip: tr('Nueva app'),
            onPressed: _create,
            icon: Icon(CupertinoIcons.add, color: Tx.text),
          ),
        ],
      ),
      body: _loading
          ? const Loading()
          : _error != null
              ? Center(
                  child: EmptyState(
                    icon: CupertinoIcons.exclamationmark_triangle,
                    title: tr('Error'),
                    message: _error,
                    action: SoftButton(label: tr('Reintentar'), onPressed: _load),
                  ),
                )
              : _apps.isEmpty
                  ? Center(
                      child: EmptyState(
                        icon: CupertinoIcons.app_badge,
                        title: tr('Aún no tienes apps'),
                        message: tr('Crea una app para obtener un ID y una clave API. Un administrador o moderador debe aprobarla.'),
                        action: SoftButton(label: tr('Crear app'), icon: CupertinoIcons.add, onPressed: _create),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                        itemCount: _apps.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _AppCard(app: _apps[i], onTap: () => _open(_apps[i])),
                      ),
                    ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});

  final Map<String, dynamic> app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = '${app['status'] ?? ''}';
    final statusLabel = '${app['status_label'] ?? status}';
    final platform = '${app['platform'] ?? ''}';
    final iconUrl = app['icon_url'] as String?;
    final color = switch (status) {
      'approved' => Tx.success,
      'rejected' => Tx.danger,
      'revoked' => Tx.muted,
      _ => Tx.warning,
    };
    return Material(
      color: Tx.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Tx.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: iconUrl != null && iconUrl.isNotEmpty
                  ? Image.network(iconUrl, width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48,
                      height: 48,
                      color: Tx.surface3,
                      child: Icon(CupertinoIcons.app, color: Tx.muted),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${app['name'] ?? ''}', style: Tx.body(16, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(statusLabel, style: Tx.body(13, weight: FontWeight.w600, color: color)),
                const SizedBox(height: 4),
                Text(
                  platform == 'web' ? '${app['website_url'] ?? ''}' : '${app['package_name'] ?? ''}',
                  style: Tx.body(13, color: Tx.muted),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('{n} usuarios han iniciado sesión', {'n': app['logins_count'] ?? 0}),
                  style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.accent),
                ),
                const SizedBox(height: 4),
                Text(tr('Toca para ver claves, HTML y guía'), style: Tx.body(12, color: Tx.subtle)),
              ]),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.subtle),
          ]),
        ),
      ),
    );
  }
}

class _OAuthAppDetailScreen extends StatefulWidget {
  const _OAuthAppDetailScreen({required this.appId});

  final int appId;

  @override
  State<_OAuthAppDetailScreen> createState() => _OAuthAppDetailScreenState();
}

class _OAuthAppDetailScreenState extends State<_OAuthAppDetailScreen> {
  Map<String, dynamic>? _app;
  Map<String, dynamic>? _integration;
  bool _loading = true;
  bool _secretVisible = false;
  bool _regenBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('me/oauth/apps/${widget.appId}');
      if (!mounted) return;
      setState(() {
        _app = Map<String, dynamic>.from(res.map['app'] as Map? ?? {});
        _integration = Map<String, dynamic>.from(res.map['integration'] as Map? ?? {});
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = tr('No se pudo abrir la app.');
        _loading = false;
      });
    }
  }

  void _copy(String label, String value) {
    if (value.isEmpty) return;
    Clipboard.setData(ClipboardData(text: value));
    toast(context, tr('{label} copiado', {'label': label}));
  }

  Future<void> _regenerate() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(tr('¿Regenerar clave API?')),
        content: Text(tr('La clave anterior dejará de funcionar. Actualízala en tu servidor.')),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancelar'))),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Regenerar'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _regenBusy = true);
    try {
      final res = await api.post('me/oauth/apps/${widget.appId}/regenerate-secret');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Clave regenerada.')}');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _regenBusy = false);
  }

  List<String> _strList(dynamic v) =>
      v is List ? v.map((e) => '$e').where((e) => e.isNotEmpty).toList() : const [];

  @override
  Widget build(BuildContext context) {
    final app = _app;
    final integ = _integration;
    return Scaffold(
      appBar: GlassBar(title: app == null ? tr('App') : '${app['name'] ?? tr('App')}'),
      body: _loading
          ? const Loading()
          : _error != null
              ? Center(child: EmptyState(icon: CupertinoIcons.exclamationmark_triangle, title: tr('Error'), message: _error, action: SoftButton(label: tr('Reintentar'), onPressed: _load)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                  children: [
                    Text('${app!['status_label'] ?? ''}', style: Tx.body(14, weight: FontWeight.w700, color: Tx.accent)),
                    const SizedBox(height: 6),
                    Text(tr('{n} usuarios han iniciado sesión', {'n': app['logins_count'] ?? 0}), style: Tx.body(14, color: Tx.muted)),
                    const SizedBox(height: 18),
                    _section(tr('Credenciales')),
                    _SecretRow(
                      label: tr('ID de la app'),
                      value: '${app['client_id'] ?? ''}',
                      obscure: false,
                      onCopy: () => _copy(tr('ID'), '${app['client_id'] ?? ''}'),
                    ),
                    const SizedBox(height: 10),
                    if (app['client_secret'] != null && '${app['client_secret']}'.isNotEmpty)
                      _SecretRow(
                        label: tr('Clave API'),
                        value: '${app['client_secret']}',
                        obscure: !_secretVisible,
                        onToggle: () => setState(() => _secretVisible = !_secretVisible),
                        onCopy: () => _copy(tr('Clave API'), '${app['client_secret']}'),
                      )
                    else ...[
                      Text(tr('Esta app no tiene la clave guardada para mostrarla. Regenera una nueva.'), style: Tx.body(13.5, color: Tx.muted, height: 1.35)),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    SoftButton(
                      label: tr('Regenerar clave API'),
                      loading: _regenBusy,
                      icon: CupertinoIcons.refresh,
                      onPressed: _regenBusy ? null : _regenerate,
                    ),
                    const SizedBox(height: 22),
                    _section(tr('Código HTML (login)')),
                    _CodeBlock(
                      code: '${integ?['html_full'] ?? integ?['html_button'] ?? ''}',
                      onCopy: () => _copy(tr('HTML'), '${integ?['html_full'] ?? integ?['html_button'] ?? ''}'),
                    ),
                    const SizedBox(height: 12),
                    _section(tr('URL de autorización')),
                    _CodeBlock(
                      code: '${integ?['authorize_url'] ?? ''}',
                      onCopy: () => _copy(tr('URL'), '${integ?['authorize_url'] ?? ''}'),
                    ),
                    const SizedBox(height: 12),
                    _section(tr('Ejemplo POST /oauth/token')),
                    _CodeBlock(
                      code: '${integ?['token_example'] ?? ''}',
                      onCopy: () => _copy(tr('Ejemplo'), '${integ?['token_example'] ?? ''}'),
                    ),
                    const SizedBox(height: 22),
                    _section(tr('Instalación paso a paso')),
                    for (final step in _strList(integ?['steps']))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(step, style: Tx.body(14, height: 1.4, color: Tx.text)),
                      ),
                    const SizedBox(height: 18),
                    _section(tr('Requisitos')),
                    for (final item in _strList(integ?['requirements'])) _bullet(item),
                    const SizedBox(height: 16),
                    _section(tr('Política de uso de la API')),
                    for (final item in _strList(integ?['policy'])) _bullet(item),
                    const SizedBox(height: 16),
                    _section(tr('Responsabilidades')),
                    for (final item in _strList(integ?['responsibilities'])) _bullet(item),
                  ],
                ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title, style: Tx.body(15, weight: FontWeight.w800)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 7), child: Icon(CupertinoIcons.circle_fill, size: 6, color: Tx.accent)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Tx.body(13.5, height: 1.4, color: Tx.muted))),
        ]),
      );
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({
    required this.label,
    required this.value,
    required this.obscure,
    required this.onCopy,
    this.onToggle,
  });

  final String label;
  final String value;
  final bool obscure;
  final VoidCallback onCopy;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final shown = obscure ? ('•' * (value.length.clamp(8, 28))) : value;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Tx.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tx.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text(shown, style: Tx.body(13.5, weight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis)),
          if (onToggle != null)
            IconButton(
              tooltip: obscure ? tr('Mostrar') : tr('Ocultar'),
              onPressed: onToggle,
              icon: Icon(obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18, color: Tx.accent),
            ),
          IconButton(
            tooltip: tr('Copiar'),
            onPressed: onCopy,
            icon: Icon(CupertinoIcons.doc_on_doc, size: 18, color: Tx.accent),
          ),
        ]),
      ]),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    if (code.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
      decoration: BoxDecoration(
        color: Tx.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Tx.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SelectableText(code, style: Tx.body(12.5, height: 1.35, color: Tx.text)),
        Align(
          alignment: Alignment.centerRight,
          child: SoftButton(label: tr('Copiar código'), icon: CupertinoIcons.doc_on_doc, height: 34, onPressed: onCopy),
        ),
      ]),
    );
  }
}

class _CreateOAuthAppScreen extends StatefulWidget {
  const _CreateOAuthAppScreen();

  @override
  State<_CreateOAuthAppScreen> createState() => _CreateOAuthAppScreenState();
}

class _CreateOAuthAppScreenState extends State<_CreateOAuthAppScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _package = TextEditingController();
  final _website = TextEditingController();
  final _redirects = TextEditingController();
  String _platform = 'android';
  XFile? _icon;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _package.dispose();
    _website.dispose();
    _redirects.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 512);
      if (file != null && mounted) setState(() => _icon = file);
    } catch (_) {
      if (mounted) toast(context, tr('No se pudo abrir la galería.'), error: true);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final errors = <String, String>{};
    if (_name.text.trim().isEmpty) errors['name'] = tr('Escribe el nombre de la app.');
    if (_description.text.trim().isEmpty) errors['description'] = tr('Describe la app.');
    if (_platform == 'web') {
      if (_website.text.trim().isEmpty) errors['website_url'] = tr('Indica la URL de tu app web.');
    } else if (_package.text.trim().isEmpty) {
      errors['package_name'] = tr('Indica el paquete de la app.');
    }
    if (_redirects.text.trim().isEmpty) errors['redirect_uris'] = tr('Añade al menos una URL de redirección.');
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      await api.upload(
        'me/oauth/apps',
        fields: {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'platform': _platform,
          if (_platform == 'web') 'website_url': _website.text.trim() else 'package_name': _package.text.trim(),
          'redirect_uris': _redirects.text.trim(),
        },
        files: [
          if (_icon != null) Upload('icon', _icon!.path, filename: _icon!.name),
        ],
      );
      if (!mounted) return;
      toast(context, tr('Solicitud enviada. Abre la app para ver claves, HTML y la guía.'));
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = {...e.fields, if (e.fields.isEmpty) 'form': e.message};
      });
      if (e.fields.isEmpty) toast(context, e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, tr('No se pudo crear la app.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(title: tr('Nueva app')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          if (_errors['form'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger)),
            ),
          Text(tr('Icono'), style: Tx.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickIcon,
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                color: Tx.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Tx.border),
              ),
              child: _icon != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(_icon!.path), fit: BoxFit.cover, width: double.infinity),
                    )
                  : Center(child: Text(tr('Elegir icono'), style: Tx.body(14, color: Tx.muted))),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _name, style: Tx.body(16), decoration: fieldDecoration(tr('Nombre de la app'), error: _errors['name'])),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            style: Tx.body(16),
            decoration: fieldDecoration(tr('Descripción'), error: _errors['description']),
          ),
          const SizedBox(height: 16),
          Text(tr('Plataforma'), style: Tx.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final p in const ['android', 'ios', 'web'])
                ChoiceChip(
                  label: Text(p == 'web' ? tr('Web') : p == 'ios' ? 'iOS' : 'Android'),
                  selected: _platform == p,
                  onSelected: (_) => setState(() => _platform = p),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_platform == 'web')
            TextField(
              controller: _website,
              keyboardType: TextInputType.url,
              style: Tx.body(16),
              decoration: fieldDecoration(tr('URL de la app web'), error: _errors['website_url']),
            )
          else
            TextField(
              controller: _package,
              style: Tx.body(16),
              decoration: fieldDecoration(tr('Paquete (ej. com.empresa.app)'), error: _errors['package_name']),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _redirects,
            maxLines: 3,
            style: Tx.body(16),
            decoration: fieldDecoration(tr('URLs de redirección (una por línea)'), error: _errors['redirect_uris']),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Solo se compartirán foto, usuario, nombre y acceso a la plataforma. Nunca contraseñas.'),
            style: Tx.body(13, color: Tx.muted, height: 1.35),
          ),
          const SizedBox(height: 20),
          GradientButton(label: tr('Enviar solicitud'), loading: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}
