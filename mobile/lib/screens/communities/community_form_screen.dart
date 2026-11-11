import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/catalog.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'community_widgets.dart';

/// Crear una comunidad o editar una existente (solo su administrador).
class CommunityFormScreen extends StatefulWidget {
  const CommunityFormScreen({super.key, this.community});

  final Community? community;

  @override
  State<CommunityFormScreen> createState() => _CommunityFormScreenState();
}

class _CommunityFormScreenState extends State<CommunityFormScreen> {
  late Community? _community = widget.community;
  late final _name = TextEditingController(text: widget.community?.name ?? '');
  late final _description = TextEditingController(text: widget.community?.description ?? '');
  late String? _category = widget.community?.category;
  late String _visibility = widget.community?.visibility ?? 'public';
  bool _busy = false;
  String? _imageBusy;
  Map<String, String> _errors = {};

  bool get _editing => widget.community != null;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_category == null) {
      setState(() => _errors = {'category': tr('Elige una categoría.')});
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    final body = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category,
      'visibility': _visibility,
    };
    try {
      if (_editing) {
        final res = await api.patch('communities/${widget.community!.id}', body);
        if (!mounted) return;
        toast(context, '${res.map['message'] ?? tr('Cambios guardados.')}');
        Navigator.pop(context, res.map['community'] is Map ? Community.fromJson(asMap(res.map['community'])) : null);
      } else {
        final res = await api.post('communities', body);
        if (!mounted) return;
        toast(context, tr('¡Tu comunidad está lista!'));
        Navigator.pop(context, Community.fromJson(res.map));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errors = e.fields.isEmpty ? {'form': e.message} : e.fields;
      });
    }
  }

  Future<void> _image(String kind) async {
    final c = _community!;
    final has = kind == 'avatar' ? c.avatarUrl != null : c.coverUrl != null;
    actionSheet(context, [
      SheetAction(tr('Elegir de la galería'), CupertinoIcons.photo, () => _upload(kind)),
      if (has)
        SheetAction(tr('Quitar'), CupertinoIcons.trash, () async {
          setState(() => _imageBusy = kind);
          try {
            final res = await api.delete('communities/${c.id}/$kind');
            _apply(res);
          } catch (e) {
            if (mounted) toastError(context, e);
          }
          if (mounted) setState(() => _imageBusy = null);
        }, destructive: true),
    ], title: kind == 'avatar' ? tr('Imagen de la comunidad') : tr('Portada'));
  }

  Future<void> _upload(String kind) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: kind == 'avatar' ? 1200 : 2400);
      if (file == null) return;
      setState(() => _imageBusy = kind);
      final res = await api.upload('communities/${_community!.id}/$kind', files: [Upload(kind, file.path, filename: file.name)]);
      _apply(res);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _imageBusy = null);
  }

  void _apply(ApiResponse res) {
    if (!mounted) return;
    if (res.map['community'] is Map) setState(() => _community = Community.fromJson(asMap(res.map['community'])));
    toast(context, '${res.map['message'] ?? tr('Listo.')}');
  }

  Future<void> _transfer() async {
    final username = await prompt(context, tr('Transferir la comunidad'), hint: tr('Usuario del nuevo administrador'), action: tr('Continuar'), maxLength: 30,
        message: tr('Debe ser un miembro activo. Tú pasarás a ser moderador.'));
    if (username == null || !mounted) return;
    final password = await prompt(context, tr('Confirma con tu contraseña'), hint: tr('Contraseña'), action: tr('Transferir'), obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.post('communities/${widget.community!.id}/transfer', {'username': username.replaceFirst('@', ''), 'password': password});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Transferiste la comunidad.')}');
      Navigator.pop(context, res.map['community'] is Map ? Community.fromJson(asMap(res.map['community'])) : null);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete() async {
    final c = widget.community!;
    final confirmSlug = await prompt(context, tr('Eliminar «{name}»', {'name': c.name}), hint: c.slug, action: tr('Continuar'), maxLength: 60,
        message: tr('Se eliminarán la comunidad y todas sus publicaciones. Escribe «{slug}» para confirmar.', {'slug': c.slug}));
    if (confirmSlug == null || !mounted) return;
    final password = await prompt(context, tr('Confirma con tu contraseña'), hint: tr('Contraseña'), action: tr('Eliminar para siempre'), obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.delete('communities/${c.id}', {'confirm': confirmSlug, 'password': password});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Comunidad eliminada.')}');
      Navigator.of(context)
        ..pop()
        ..pop();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _community;
    final state = context.read<AppState>();
    return Scaffold(
      appBar: GlassBar(
        title: _editing ? tr('Editar comunidad') : tr('Nueva comunidad'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GradientButton(label: _editing ? tr('Guardar') : tr('Crear'), expand: false, height: 38, loading: _busy, onPressed: _submit),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 60), children: [
        if (c != null) ...[
          GestureDetector(
            onTap: () => _image('cover'),
            child: Container(
              height: 120,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
              child: Stack(fit: StackFit.expand, children: [
                c.coverUrl != null ? NetImage(c.coverUrl) : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.purple700, Tx.blue]))),
                Container(color: Colors.black.withAlpha(80)),
                Center(
                  child: _imageBusy == 'cover'
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(tr('Cambiar portada'), style: Tx.body(13.5, weight: FontWeight.w600, color: Colors.white)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            GestureDetector(
              onTap: () => _image('avatar'),
              child: Stack(children: [
                CommunityAvatar(community: c, size: 64),
                if (_imageBusy == 'avatar') const Positioned.fill(child: Center(child: CupertinoActivityIndicator(color: Colors.white))),
              ]),
            ),
            const SizedBox(width: 12),
            Text(tr('Toca para cambiar la imagen'), style: Tx.body(13.5, color: Tx.muted)),
          ]),
          const SizedBox(height: 18),
        ],
        if (_errors['form'] != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger))),
        TextField(
          controller: _name,
          maxLength: state.limit('community_name', 80),
          style: Tx.body(16),
          decoration: fieldDecoration(tr('Nombre de la comunidad'), error: _errors['name'], label: tr('Nombre')),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _description,
          maxLength: state.limit('community_description', 500),
          minLines: 3,
          maxLines: 6,
          style: Tx.body(16),
          decoration: fieldDecoration(tr('¿De qué trata?'), error: _errors['description'], label: tr('Descripción')),
        ),
        const SizedBox(height: 12),
        Text(tr('Categoría'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final cat in communityCategories) PillChip(label: tr(cat), selected: _category == cat, onTap: () => setState(() => _category = cat)),
        ]),
        if (_errors['category'] != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['category']!, style: Tx.body(13, color: Tx.danger))),
        const SizedBox(height: 18),
        Text(tr('Visibilidad'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.muted)),
        const SizedBox(height: 8),
        _VisibilityOption(
          icon: CupertinoIcons.globe,
          title: tr('Pública'),
          subtitle: tr('Cualquiera puede ver las publicaciones y unirse.'),
          selected: _visibility == 'public',
          onTap: () => setState(() => _visibility = 'public'),
        ),
        const SizedBox(height: 8),
        _VisibilityOption(
          icon: CupertinoIcons.lock_fill,
          title: tr('Privada'),
          subtitle: tr('Solo los miembros ven las publicaciones. Para unirse hay que enviar una solicitud.'),
          selected: _visibility == 'private',
          onTap: () => setState(() => _visibility = 'private'),
        ),
        if (_editing && (widget.community!.access?.owner ?? false)) ...[
          const SizedBox(height: 30),
          SoftButton(label: tr('Transferir a otro miembro'), icon: CupertinoIcons.arrow_right_arrow_left, expand: true, height: 46, onPressed: _transfer),
          const SizedBox(height: 10),
          SoftButton(label: tr('Eliminar comunidad'), icon: CupertinoIcons.trash, color: Tx.danger, expand: true, height: 46, onPressed: _delete),
        ],
      ]),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  const _VisibilityOption({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: selected ? Tx.brandSoft : null,
          color: selected ? null : Tx.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Tx.purple500 : Tx.border, width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? Tx.accent : Tx.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Tx.body(15, weight: FontWeight.w600)),
              Text(subtitle, style: Tx.body(12.5, color: Tx.muted, height: 1.35)),
            ]),
          ),
          if (selected) Icon(CupertinoIcons.checkmark_circle_fill, color: Tx.accentSoft),
        ]),
      ),
    );
  }
}
