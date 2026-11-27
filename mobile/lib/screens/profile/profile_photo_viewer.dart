import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/profile_image_picker.dart';
import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/mention_field.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import '../post/post_screen.dart' show CommentTile;

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

  String get _shareUrl => AppConfig.web('profile.php?u=${Uri.encodeComponent(widget.user.username)}');

  String get _shareTitle =>
      tr('{name} (@{username}) en TREVIX', {'name': widget.user.displayName, 'username': widget.user.username});

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
        _meta = {
          ...?_meta,
          ...asMap(res.map),
          'can_like': true,
        };
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _comments() async {
    final kind = _apiKind;
    if (kind == null) return;
    final can = widget.isOwn || _meta == null || asBool(_meta!['can_comment']);
    if (!can) {
      toast(context, tr('No puedes comentar esta foto.'), error: true);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Tx.surface1,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _PhotoCommentsSheet(ownerId: widget.user.id, kind: kind, canComment: can),
      ),
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

  Future<void> _share() async {
    await showShareSheet(
      context,
      url: _shareUrl,
      title: _shareTitle,
      imageUrl: _current.url,
    );
  }

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
      final suffix = profileImageFileSuffix(url: _current.url, contentType: res.headers['content-type']);
      final file = File('${(await getTemporaryDirectory()).path}/trevix_cover_${DateTime.now().millisecondsSinceEpoch}$suffix');
      await file.writeAsBytes(res.bodyBytes);
      await api.upload('me/cover', files: [Upload('cover', file.path, filename: 'cover$suffix')]);
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
    final date = _current.publishedAt ?? (asStr(_meta?['updated_at']).isNotEmpty ? asDate(_meta?['updated_at']) : null);
    final caption = asStr(_meta?['caption']);
    final likes = asInt(_meta?['likes_count']);
    final comments = asInt(_meta?['comments_count']);
    final liked = asBool(_meta?['liked']);
    final interact = _apiKind != null;
    final counter = widget.pages.length > 1 ? '${_index + 1} de ${widget.pages.length}' : null;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Tx.immersive,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            // Imagen a pantalla completa (estilo Facebook).
            Positioned.fill(
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
                      child: NetImage(
                        widget.pages[i].url,
                        fit: BoxFit.contain,
                        width: MediaQuery.sizeOf(context).width,
                        height: MediaQuery.sizeOf(context).height,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Header: X · contador · menú
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: Row(children: [
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: () => Navigator.maybePop(context),
                    child: const TxIcon(TxGlyph.close, color: Colors.white, size: 22),
                  ),
                  Expanded(
                    child: counter != null
                        ? Text(
                            counter,
                            textAlign: TextAlign.center,
                            style: TxDark.body(15, weight: FontWeight.w600, color: Colors.white),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (_metaBusy)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: CupertinoActivityIndicator(color: Colors.white54, radius: 8),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: _options,
                    child: const TxIcon(TxGlyph.more, color: Colors.white, size: 22),
                  ),
                ]),
              ),
            ),

            // Footer: nombre + pie (izq) · acciones centradas
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(200)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  GestureDetector(
                    onTap: () => openProfile(context, u.username),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            u.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TxDark.display(16, weight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        if (u.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 15),
                        ],
                      ]),
                      if (date != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(timeAgo(date), style: TxDark.body(12.5, color: Colors.white60)),
                        ),
                      if (caption.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(caption, style: TxDark.body(14.5, color: Colors.white, height: 1.35)),
                        )
                      else if (_current.label != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(_current.label!, style: TxDark.body(14.5, color: Colors.white70)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _feedAction(
                      glyph: TxGlyph.heart,
                      count: likes,
                      color: liked ? Tx.like : Colors.white,
                      filled: liked,
                      onTap: interact ? _toggleLike : null,
                    ),
                    const SizedBox(width: 28),
                    _feedAction(
                      glyph: TxGlyph.comment,
                      count: comments,
                      color: Colors.white,
                      onTap: interact ? _comments : null,
                    ),
                    const SizedBox(width: 28),
                    _feedAction(
                      glyph: TxGlyph.repost,
                      count: 0,
                      color: Colors.white,
                      onTap: _share,
                    ),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _feedAction({
    required TxGlyph glyph,
    required int count,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween(begin: .5, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.elasticOut)),
              child: child,
            ),
            child: TxIcon(glyph, key: ValueKey('${glyph.name}$filled'), size: 24, color: color, filled: filled, stroke: 1.9),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text('$count', style: TxDark.body(14, weight: FontWeight.w600, color: color)),
          ],
        ]),
      ),
    );
  }
}

/// Misma UX de comentarios de publicaciones: hilos, like, GIF/foto, reportar/eliminar/ocultar.
class _PhotoCommentsSheet extends StatefulWidget {
  const _PhotoCommentsSheet({required this.ownerId, required this.kind, required this.canComment});

  final int ownerId;
  final String kind;
  final bool canComment;

  @override
  State<_PhotoCommentsSheet> createState() => _PhotoCommentsSheetState();
}

class _PhotoCommentsSheetState extends State<_PhotoCommentsSheet> {
  final _items = <Comment>[];
  final _hidden = <int>{};
  final _input = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  Gif? _gif;
  XFile? _photo;
  bool _loading = true;
  bool _sending = false;

  String get _base => 'users/${widget.ownerId}/profile-photos/${widget.kind}/comments';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await api.get(_base);
      final rows = res.list.isNotEmpty
          ? res.list
          : (res.data is List
              ? (res.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
              : <Json>[]);
      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(rows.map(Comment.fromJson).where((c) => !_hidden.contains(c.id)));
        });
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickGif() async {
    final gif = await pickGif(context);
    if (gif != null && mounted) setState(() => _gif = gif);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (file != null && mounted) {
      setState(() {
        _photo = file;
        _gif = null;
      });
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final gif = _gif;
    final photo = _photo;
    if ((text.isEmpty && gif == null && photo == null) || _sending) return;
    setState(() => _sending = true);
    final parent = _replyTo;
    try {
      final res = photo != null
          ? await api.upload(_base, fields: {
              'body': text,
              if (parent != null) 'parent_id': '${parent.id}',
            }, files: [Upload('image', photo.path, filename: photo.name)])
          : await api.post(_base, {
              'body': text,
              if (parent != null) 'parent_id': parent.id,
              if (gif != null) 'gif_id': gif.id,
              if (gif != null) 'gif_kind': gif.kind,
            });
      final comment = Comment.fromJson(res.map);
      _input.clear();
      setState(() {
        _replyTo = null;
        _gif = null;
        _photo = null;
        if (comment.parentId != null) {
          final root = _items.where((c) => c.id == comment.parentId).firstOrNull;
          if (root != null) {
            root.replies.add(comment);
            root.repliesCount += 1;
          } else {
            _items.insert(0, comment);
          }
        } else {
          _items.insert(0, comment);
        }
      });
      _focus.unfocus();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(Comment c) async {
    if (!await confirm(
      context,
      tr('Eliminar comentario'),
      c.parentId == null && c.replies.isNotEmpty ? tr('También se eliminarán sus respuestas.') : '',
      action: tr('Eliminar'),
      destructive: true,
    )) {
      return;
    }
    try {
      await api.delete('profile-photo-comments/${c.id}');
      setState(() {
        if (c.parentId == null) {
          _items.removeWhere((x) => x.id == c.id);
        } else {
          for (final root in _items) {
            if (root.replies.remove(c)) root.repliesCount -= 1;
          }
        }
      });
      if (mounted) toast(context, tr('Comentario eliminado.'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _hide(Comment c) {
    setState(() {
      _hidden.add(c.id);
      if (c.parentId == null) {
        _items.removeWhere((x) => x.id == c.id);
      } else {
        for (final root in _items) {
          root.replies.removeWhere((r) => r.id == c.id);
        }
      }
    });
    toast(context, tr('Comentario oculto.'));
  }

  void _reply(Comment c) {
    setState(() => _replyTo = c);
    final mention = '@${c.user.username} ';
    if (c.parentId != null && !_input.text.startsWith(mention)) {
      _input.text = mention + _input.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    final gifs = context.read<AppState>().feature('gifs');
    final visible = _items.where((c) => !_hidden.contains(c.id)).toList();
    final count = visible.fold<int>(0, (n, c) => n + 1 + c.replies.where((r) => !_hidden.contains(r.id)).length);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 36, height: 4, decoration: BoxDecoration(color: Tx.borderStrong, borderRadius: BorderRadius.circular(99))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              count == 0 ? tr('Comentarios') : plural(count, 'comentario', 'comentarios'),
              style: Tx.display(17),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CupertinoActivityIndicator())
              : visible.isEmpty
                  ? Center(
                      child: EmptyState(
                        icon: CupertinoIcons.chat_bubble_2,
                        title: tr('Sé el primero en comentar'),
                        message: tr('Comparte lo que piensas.'),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: visible.length,
                      itemBuilder: (_, i) {
                        final c = visible[i];
                        return CommentTile(
                          comment: c,
                          onReply: _reply,
                          onDelete: _delete,
                          onHide: _hide,
                          reactionPath: (x) => 'profile-photo-comments/${x.id}/reaction',
                          reportTarget: 'comment',
                        );
                      },
                    ),
        ),
        if (widget.canComment && me != null)
          Container(
            decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_replyTo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        tr('Respondiendo a @{username}', {'username': _replyTo!.user.username}),
                        style: Tx.body(12.5, color: Tx.accent),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _replyTo = null),
                      child: Icon(CupertinoIcons.xmark, size: 15, color: Tx.muted),
                    ),
                  ]),
                ),
              if (_gif != null) GifAttachment(gif: _gif!, onRemove: () => setState(() => _gif = null)),
              if (_photo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Stack(alignment: Alignment.topRight, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Tx.radiusSm),
                      child: Image.file(File(_photo!.path), width: 120, height: 120, fit: BoxFit.cover),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _photo = null),
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(CupertinoIcons.xmark, size: 14, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              MentionSuggestions(controller: _input),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                GestureDetector(
                  onTap: _pickPhoto,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    child: Icon(CupertinoIcons.photo, size: 22, color: Tx.accent),
                  ),
                ),
                if (gifs)
                  GestureDetector(
                    onTap: _pickGif,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Tx.accent, width: 1.4),
                        ),
                        child: Text('GIF', style: Tx.body(11.5, weight: FontWeight.w800, color: Tx.accent)),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: context.read<AppState>().limit('comment_body', 1000),
                    textCapitalization: TextCapitalization.sentences,
                    style: Tx.body(15),
                    decoration: fieldDecoration(
                      _replyTo != null ? tr('Escribe tu respuesta…') : tr('Añade un comentario… usa @ para mencionar'),
                    ).copyWith(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (_, value, __) {
                    final enabled = (value.text.trim().isNotEmpty || _gif != null || _photo != null) && !_sending;
                    return GestureDetector(
                      onTap: enabled ? _send : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: enabled ? Tx.brand : null,
                          color: enabled ? null : Tx.surface3,
                          shape: BoxShape.circle,
                        ),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(CupertinoIcons.arrow_up, color: enabled ? Colors.white : Tx.subtle, size: 20),
                      ),
                    );
                  },
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
