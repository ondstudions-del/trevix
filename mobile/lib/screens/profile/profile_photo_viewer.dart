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

enum ProfilePhotoKind { avatar, cover, gallery }

class ProfilePhotoPage {
  ProfilePhotoPage({required this.kind, required this.url, this.label, this.publishedAt});

  final ProfilePhotoKind kind;
  final String url;
  final String? label;
  final DateTime? publishedAt;
}

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
  Json? _meta;
  bool _metaBusy = false;

  ProfilePhotoPage get _current => widget.pages[_index.clamp(0, widget.pages.length - 1)];

  String? get _apiKind => switch (_current.kind) {
        ProfilePhotoKind.avatar => 'avatar',
        ProfilePhotoKind.cover => 'cover',
        ProfilePhotoKind.gallery => null,
      };

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _loadMeta();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    final kind = _apiKind;
    if (kind == null) {
      setState(() => _meta = null);
      return;
    }
    setState(() => _metaBusy = true);
    try {
      final res = await api.get('users/${widget.user.id}/profile-photos/$kind');
      if (mounted) setState(() => _meta = asMap(res.map));
    } catch (_) {
      if (mounted) setState(() => _meta = null);
    }
    if (mounted) setState(() => _metaBusy = false);
  }

  Future<void> _patchMeta(Map<String, dynamic> fields) async {
    final kind = _apiKind;
    if (kind == null || !widget.isOwn) return;
    try {
      final res = await api.patch('me/profile-photos/$kind', fields);
      if (mounted) {
        setState(() => _meta = asMap(res.map));
        widget.onProfileChanged?.call();
        toast(context, tr('Guardado.'));
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _toggleLike() async {
    final kind = _apiKind;
    if (kind == null) return;
    final liked = asBool(_meta?['liked']);
    final can = _meta == null || asBool(_meta!['can_like']);
    if (!can && !liked) {
      toast(context, tr('No puedes dar «Me gusta» a esta foto.'), error: true);
      return;
    }
    try {
      final path = 'users/${widget.user.id}/profile-photos/$kind/like';
      final res = liked ? await api.delete(path) : await api.put(path, {});
      if (!mounted) return;
      setState(() {
        _meta = {...?_meta, ...asMap(res.map)};
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _comments() async {
    final kind = _apiKind;
    if (kind == null) return;
    if (_meta != null && !asBool(_meta!['can_comment']) && !widget.isOwn) {
      toast(context, tr('No puedes comentar esta foto.'), error: true);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tx.bg,
        builder: (ctx) => _PhotoCommentsSheet(ownerId: widget.user.id, kind: kind, canComment: widget.isOwn || (_meta != null && asBool(_meta!['can_comment']))),
    );
    await _loadMeta();
  }

  Future<void> _editCaption() async {
    final text = await _promptText(tr('Pie de foto'), asStr(_meta?['caption']));
    if (text == null) return;
    await _patchMeta({'caption': text});
  }

  Future<void> _editAlt() async {
    final text = await _promptText(tr('Texto alternativo'), asStr(_meta?['alt_text']));
    if (text == null) return;
    await _patchMeta({'alt_text': text});
  }

  Future<void> _editPrivacy() async {
    final current = asStr(_meta?['privacy'], 'public');
    await actionSheet(context, [
      SheetAction(tr('Público') + (current == 'public' ? ' ✓' : ''), CupertinoIcons.globe, () => _patchMeta({'privacy': 'public'})),
      SheetAction(tr('Solo seguidores') + (current == 'followers' ? ' ✓' : ''), CupertinoIcons.person_2, () => _patchMeta({'privacy': 'followers'})),
      SheetAction(tr('Solo yo') + (current == 'only_me' ? ' ✓' : ''), CupertinoIcons.lock, () => _patchMeta({'privacy': 'only_me'})),
    ], title: tr('Privacidad de la foto'));
  }

  Future<void> _toggleNotifyMuted() async {
    final muted = asBool(_meta?['notify_muted']);
    await _patchMeta({'notify_muted': !muted});
  }

  Future<String?> _promptText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, maxLines: 4, autofocus: true, decoration: fieldDecoration(tr('Escribe aquí'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancelar'))),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Guardar'))),
        ],
      ),
    );
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

  void _options() {
    final own = widget.isOwn;
    final kind = _current.kind;
    final hasApi = _apiKind != null;
    final muted = asBool(_meta?['notify_muted']);
    actionSheet(context, [
      if (own && kind == ProfilePhotoKind.avatar) SheetAction(tr('Elegir como foto de portada'), CupertinoIcons.photo, _setAsCover),
      if (own && (kind == ProfilePhotoKind.avatar || kind == ProfilePhotoKind.cover))
        SheetAction(tr('Eliminar foto'), CupertinoIcons.trash, _delete, destructive: true),
      SheetAction(tr('Guardar foto'), CupertinoIcons.arrow_down_circle, _save),
      SheetAction(tr('Copiar enlace'), CupertinoIcons.doc_on_doc, _copy),
      SheetAction(tr('Compartir'), CupertinoIcons.share, _share),
      if (own && hasApi) SheetAction(tr('Editar privacidad'), CupertinoIcons.lock, _editPrivacy),
      if (own && hasApi) SheetAction(tr('Editar pie de foto'), CupertinoIcons.text_bubble, _editCaption),
      if (own && hasApi) SheetAction(tr('Editar texto alternativo'), CupertinoIcons.textformat_alt, _editAlt),
      if (own && hasApi)
        SheetAction(
          muted ? tr('Activar notificaciones de esta foto') : tr('Desactivar notificaciones de esta foto'),
          muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash,
          _toggleNotifyMuted,
        ),
      if (!own) SheetAction(tr('Reportar foto'), CupertinoIcons.flag, () => showReportSheet(context, 'user', widget.user.id), destructive: true),
      if (!own && widget.onAlertsToggle != null)
        SheetAction(tr('Avisarme de fotos nuevas'), widget.alerts ? CupertinoIcons.bell_slash : CupertinoIcons.bell, widget.onAlertsToggle!),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final date = _current.publishedAt;
    final caption = asStr(_meta?['caption']);
    final likes = asInt(_meta?['likes_count']);
    final comments = asInt(_meta?['comments_count']);
    final liked = asBool(_meta?['liked']);
    final interact = _apiKind != null;
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
                  if (caption.isNotEmpty)
                    Text(caption, style: TxDark.body(12.5, color: Colors.white70))
                  else if (_current.label != null)
                    Text(_current.label!, style: TxDark.body(12.5, color: Colors.white70)),
                ]),
              ),
              if (_metaBusy) const Padding(padding: EdgeInsets.only(right: 8), child: CupertinoActivityIndicator(color: Colors.white54)),
              CupertinoButton(padding: const EdgeInsets.all(8), onPressed: _options, child: const Icon(CupertinoIcons.ellipsis, color: Colors.white)),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: widget.pages.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _loadMeta();
              },
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Semantics(
                    label: asStr(_meta?['alt_text'], _current.label ?? ''),
                    child: NetImage(widget.pages[i].url, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _barBtn(CupertinoIcons.heart, liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart, tr('Me gusta'), likes > 0 ? '$likes' : null, interact ? _toggleLike : null, active: liked),
              _barBtn(CupertinoIcons.chat_bubble, null, tr('Comentar'), comments > 0 ? '$comments' : null, interact ? _comments : null),
              _barBtn(CupertinoIcons.share, null, tr('Compartir'), null, _share),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _barBtn(IconData icon, IconData? iconActive, String label, String? count, VoidCallback? onTap, {bool active = false}) {
    final ic = iconActive ?? icon;
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, color: active ? const Color(0xFFF472B6) : Colors.white, size: 24),
        const SizedBox(height: 4),
        Text(count != null ? '$label ($count)' : label, style: TxDark.body(11.5, color: Colors.white70)),
      ]),
    );
  }
}

class _PhotoCommentsSheet extends StatefulWidget {
  const _PhotoCommentsSheet({required this.ownerId, required this.kind, required this.canComment});

  final int ownerId;
  final String kind;
  final bool canComment;

  @override
  State<_PhotoCommentsSheet> createState() => _PhotoCommentsSheetState();
}

class _PhotoCommentsSheetState extends State<_PhotoCommentsSheet> {
  final _items = <Json>[];
  final _text = TextEditingController();
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await api.get('users/${widget.ownerId}/profile-photos/${widget.kind}/comments');
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll((res.map as List).map((e) => asMap(e)));
        });
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await api.post('users/${widget.ownerId}/profile-photos/${widget.kind}/comments', {'body': body});
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        builder: (_, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(tr('Comentarios'), style: Tx.display(17)),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CupertinoActivityIndicator())
                : _items.isEmpty
                    ? Center(child: Text(tr('Sé la primera persona en comentar.'), style: Tx.body(14, color: Tx.muted)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          final user = User.fromJson(asMap(c['user']));
                          return ListTile(
                            leading: Avatar(user: user, size: 36),
                            title: Text(user.displayName, style: Tx.display(14, weight: FontWeight.w600)),
                            subtitle: Text(asStr(c['body']), style: Tx.body(13.5)),
                          );
                        },
                      ),
          ),
          if (widget.canComment)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  Expanded(child: TextField(controller: _text, decoration: fieldDecoration(tr('Escribe un comentario…')), maxLines: 3, minLines: 1)),
                  const SizedBox(width: 8),
                  GradientButton(label: tr('Enviar'), loading: _sending, onPressed: _sending ? null : _send),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}