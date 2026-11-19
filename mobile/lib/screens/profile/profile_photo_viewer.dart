import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/report_sheet.dart';
import '../settings/settings_screen.dart';

enum ProfilePhotoKind { avatar, cover, gallery }

class ProfilePhotoPage {
  ProfilePhotoPage({required this.kind, required this.url, this.label, this.publishedAt});

  final ProfilePhotoKind kind;
  final String url;
  final String? label;
  final DateTime? publishedAt;
}

/// Visor de foto de perfil / portada estilo red social: opciones, metadatos y deslizar entre fotos.
Future<void> openProfilePhotos(
  BuildContext context, {
  required User user,
  required List<ProfilePhotoPage> pages,
  required int initialIndex,
  bool isOwn = false,
  bool alerts = false,
  VoidCallback? onAlertsToggle,
  VoidCallback? onProfileChanged,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withAlpha(240),
      pageBuilder: (_, __, ___) => ProfilePhotoViewer(
        user: user,
        pages: pages,
        initialIndex: initialIndex,
        isOwn: isOwn,
        alerts: alerts,
        onAlertsToggle: onAlertsToggle,
        onProfileChanged: onProfileChanged,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class ProfilePhotoViewer extends StatefulWidget {
  const ProfilePhotoViewer({
    super.key,
    required this.user,
    required this.pages,
    required this.initialIndex,
    required this.isOwn,
    this.alerts = false,
    this.onAlertsToggle,
    this.onProfileChanged,
  });

  final User user;
  final List<ProfilePhotoPage> pages;
  final int initialIndex;
  final bool isOwn;
  final bool alerts;
  final VoidCallback? onAlertsToggle;
  final VoidCallback? onProfileChanged;

  @override
  State<ProfilePhotoViewer> createState() => _ProfilePhotoViewerState();
}

class _ProfilePhotoViewerState extends State<ProfilePhotoViewer> {
  late final PageController _pager = PageController(initialPage: widget.initialIndex);
  int _index = 0;

  ProfilePhotoPage get _current => widget.pages[_index.clamp(0, widget.pages.length - 1)];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await DeviceAccess.saveImage(_current.url);
      if (mounted) toast(context, tr('Foto guardada.'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _current.url));
    if (mounted) toast(context, tr('Enlace copiado.'));
  }

  void _share() => Share.share(_current.url, subject: widget.user.displayName);

  Future<void> _delete() async {
    if (!widget.isOwn) return;
    final field = _current.kind == ProfilePhotoKind.cover ? 'cover' : 'avatar';
    if (!await confirm(context, tr('Eliminar foto'), tr('¿Quitar esta imagen de tu perfil?'), action: tr('Eliminar'), destructive: true)) return;
    try {
      await api.delete('me/$field');
      widget.onProfileChanged?.call();
      if (mounted) {
        toast(context, tr('Foto eliminada.'));
        Navigator.maybePop(context);
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _setAsCover() async {
    if (!widget.isOwn || _current.kind != ProfilePhotoKind.avatar) return;
    try {
      final res = await http.get(Uri.parse(_current.url)).timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) throw StateError('download');
      final file = File('${(await getTemporaryDirectory()).path}/trevix_cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await file.writeAsBytes(res.bodyBytes);
      await api.upload('me/cover', files: [Upload('cover', file.path)]);
      await file.delete();
      widget.onProfileChanged?.call();
      if (mounted) toast(context, tr('Portada actualizada.'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _editCaption() async {
    if (!widget.isOwn) {
      toast(context, tr('Próximamente: editar pie de foto.'), error: true);
      return;
    }
    toast(context, tr('Próximamente: editar pie de foto.'));
  }

  void _options() {
    final own = widget.isOwn;
    final kind = _current.kind;
    actionSheet(context, [
      if (own && kind == ProfilePhotoKind.avatar) SheetAction(tr('Elegir como foto de portada'), CupertinoIcons.photo, _setAsCover),
      if (own && (kind == ProfilePhotoKind.avatar || kind == ProfilePhotoKind.cover))
        SheetAction(tr('Eliminar foto'), CupertinoIcons.trash, _delete, destructive: true),
      SheetAction(tr('Guardar foto'), CupertinoIcons.arrow_down_circle, _save),
      SheetAction(tr('Copiar enlace'), CupertinoIcons.doc_on_doc, _copy),
      SheetAction(tr('Compartir'), CupertinoIcons.share, _share),
      if (own) SheetAction(tr('Editar privacidad'), CupertinoIcons.lock, () => push(context, const SettingsScreen())),
      if (own) SheetAction(tr('Editar pie de foto'), CupertinoIcons.text_bubble, _editCaption),
      if (own) SheetAction(tr('Editar texto alternativo'), CupertinoIcons.textformat_alt, () => toast(context, tr('Próximamente.'))),
      if (own) SheetAction(tr('Desactivar notificaciones'), CupertinoIcons.bell_slash, () => toast(context, tr('Sin notificaciones para esta foto.'))),
      if (!own) SheetAction(tr('Reportar foto'), CupertinoIcons.flag, () => showReportSheet(context, 'user', widget.user.id), destructive: true),
      if (!own && widget.onAlertsToggle != null)
        SheetAction(tr('Avisarme de fotos nuevas'), widget.alerts ? CupertinoIcons.bell_slash : CupertinoIcons.bell, widget.onAlertsToggle!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
  final date = _current.publishedAt;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(children: [
              CupertinoButton(padding: const EdgeInsets.all(8), onPressed: () => Navigator.maybePop(context), child: const Icon(CupertinoIcons.xmark, color: Colors.white)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  GestureDetector(onTap: () => openProfile(context, u.username), child: NameLine(user: u, size: 16)),
                  if (date != null) Text(timeAgo(date), style: TxDark.body(12.5, color: Colors.white60)),
                  if (_current.label != null) Text(_current.label!, style: TxDark.body(12.5, color: Colors.white70)),
                ]),
              ),
              CupertinoButton(padding: const EdgeInsets.all(8), onPressed: _options, child: const Icon(CupertinoIcons.ellipsis, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: widget.pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(child: NetImage(widget.pages[i].url, fit: BoxFit.contain)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _barBtn(CupertinoIcons.heart, tr('Me gusta'), () => toast(context, tr('Próximamente.'))),
              _barBtn(CupertinoIcons.chat_bubble, tr('Comentar'), () => toast(context, tr('Próximamente.'))),
              _barBtn(CupertinoIcons.share, tr('Compartir'), _share),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _barBtn(IconData icon, String label, VoidCallback onTap) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(label, style: TxDark.body(11.5, color: Colors.white70)),
      ]),
    );
  }
}