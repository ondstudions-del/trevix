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

/// Apps OAuth del desarrollador: crear solicitud y ver ID / clave (una sola vez).
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
                        itemBuilder: (context, i) => _AppCard(app: _apps[i]),
                      ),
                    ),
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app});

  final Map<String, dynamic> app;

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tx.surface2,
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
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  'ID: ${app['client_id'] ?? ''}',
                  style: Tx.body(12, color: Tx.subtle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: tr('Copiar ID'),
                icon: Icon(CupertinoIcons.doc_on_doc, size: 18, color: Tx.accent),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${app['client_id'] ?? ''}'));
                  toast(context, tr('ID copiado'));
                },
              ),
            ]),
            if (app['review_note'] != null && '${app['review_note']}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${app['review_note']}', style: Tx.body(12.5, color: Tx.muted)),
              ),
          ]),
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
      final res = await api.upload(
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
      final secret = '${res.map['client_secret'] ?? ''}';
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(tr('Guarda tu clave API')),
          content: Text(
            secret.isEmpty
                ? tr('Solicitud enviada. Cuando la aprueben, la API funcionará.')
                : tr('Esta clave solo se muestra una vez:\n\n{secret}\n\nTREVIX no vuelve a mostrarla.', {'secret': secret}),
          ),
          actions: [
            if (secret.isNotEmpty)
              CupertinoDialogAction(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: secret));
                  Navigator.pop(ctx);
                  toast(context, tr('Clave copiada'));
                },
                child: Text(tr('Copiar clave')),
              ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Entendido')),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
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
