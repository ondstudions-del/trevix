import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/mention_field.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/comment_translation.dart';
import '../../widgets/post_card.dart';
import '../../widgets/post_translation.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/rich_body.dart';

class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId, this.initial, this.focusComment = false});

  final int postId;
  final Post? initial;
  final bool focusComment;

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  late Post? _post = widget.initial;
  Object? _error;
  bool _deleted = false;
  late final Paged<Comment> _comments = Paged<Comment>('posts/${widget.postId}/comments', Comment.fromJson);
  final _input = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  Gif? _gif;
  XFile? _photo;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.focusComment) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _comments.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('posts/${widget.postId}');
      if (mounted) setState(() => _post = Post.fromJson(res.map));
    } catch (e) {
      if (mounted && _post == null) setState(() => _error = e);
    }
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
          ? await api.upload('posts/${widget.postId}/comments', fields: {
              'body': text,
              if (parent != null) 'parent_id': '${parent.id}',
            }, files: [Upload('image', photo.path, filename: photo.name)])
          : await api.post('posts/${widget.postId}/comments', {
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
        _post?.comments += 1;
        if (comment.parentId != null) {
          final root = _comments.items.where((c) => c.id == comment.parentId).firstOrNull;
          if (root != null) {
            root.replies.add(comment);
            root.repliesCount += 1;
          }
        } else {
          _comments.items.insert(0, comment);
        }
      });
      _comments.changed();
      _focus.unfocus();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _deleteComment(Comment c) async {
    if (!await confirm(context, tr('Eliminar comentario'), c.parentId == null && c.replies.isNotEmpty ? tr('También se eliminarán sus respuestas.') : '',
        action: tr('Eliminar'), destructive: true)) {
      return;
    }
    try {
      await api.delete('comments/${c.id}');
      setState(() {
        if (c.parentId == null) {
          _comments.items.removeWhere((x) => x.id == c.id);
          _post?.comments -= 1 + c.replies.length;
        } else {
          for (final root in _comments.items) {
            if (root.replies.remove(c)) root.repliesCount -= 1;
          }
          _post?.comments -= 1;
        }
      });
      _comments.changed();
      if (mounted) toast(context, tr('Comentario eliminado.'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
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
    final post = _post;
    final me = context.watch<AppState>().me!;
    return Scaffold(
      appBar: GlassBar(title: post?.isThread == true ? tr('Hilo') : tr('Publicación')),
      body: _deleted
          ? EmptyState(icon: CupertinoIcons.trash, title: tr('Publicación eliminada'))
          : post == null
              ? (_error != null
                  ? ErrorState(error: _error!, onRetry: () {
                      setState(() => _error = null);
                      _load();
                    })
                  : const Loading())
              : Column(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      child: PagedView<Comment>(
                        paged: _comments,
                        onRefresh: _load,
                        padding: const EdgeInsets.only(bottom: 20),
                        header: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: PostCard(
                                key: ValueKey('detail-${post.id}-${post.body.hashCode}'),
                                post: post,
                                detail: true,
                                onComment: () => _focus.requestFocus(),
                                onRemoved: () {
                                  setState(() => _deleted = true);
                                  Navigator.of(context).maybePop();
                                },
                                onReplaced: (p) => setState(() => _post = p),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                              child: Text(
                                post.comments == 0 ? tr('Comentarios') : plural(post.comments, 'comentario', 'comentarios'),
                                style: Tx.display(17),
                              ),
                            ),
                          ),
                        ],
                        empty: EmptyState(
                          icon: CupertinoIcons.chat_bubble_2,
                          title: tr('Sé el primero en comentar'),
                          message: tr('Comparte lo que piensas.'),
                        ),
                        itemBuilder: (context, c, _) => CommentTile(
                          comment: c,
                          onReply: _reply,
                          onDelete: _deleteComment,
                        ),
                      ),
                    ),
                  ),
                  _inputBar(me),
                ]),
    );
  }

  Widget _inputBar(Me me) {
    final reply = _replyTo;
    final gif = _gif;
    final photo = _photo;
    final gifs = context.read<AppState>().feature('gifs');
    return Container(
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : MediaQuery.of(context).padding.bottom)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Row(children: [
              Expanded(child: Text(tr('Respondiendo a @{username}', {'username': reply.user.username}), style: Tx.body(12.5, color: Tx.accent))),
              GestureDetector(onTap: () => setState(() => _replyTo = null), child: Icon(CupertinoIcons.xmark, size: 15, color: Tx.muted)),
            ]),
          ),
        if (gif != null) GifAttachment(gif: gif, onRemove: () => setState(() => _gif = null)),
        if (photo != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Stack(alignment: Alignment.topRight, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tx.radiusSm),
                child: Image.file(File(photo.path), width: 120, height: 120, fit: BoxFit.cover),
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
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Tx.accent, width: 1.4)),
                  child: Text('GIF', style: Tx.body(11.5, weight: FontWeight.w800, color: Tx.accent)),
                ),
              ),
            )
          else
            Avatar(user: me.user, size: 34),
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
              decoration: fieldDecoration(reply != null ? tr('Escribe tu respuesta…') : tr('Añade un comentario… usa @ para mencionar')).copyWith(
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
                  decoration: BoxDecoration(gradient: enabled ? Tx.brand : null, color: enabled ? null : Tx.surface3, shape: BoxShape.circle),
                  child: _sending
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(CupertinoIcons.arrow_up, color: enabled ? Colors.white : Tx.subtle, size: 20),
                ),
              );
            },
          ),
        ]),
      ]),
    );
  }
}

/// «Me gusta» / «No me gusta» de un comentario. El servidor devuelve los conteos reales tras cada cambio.
class _CommentReactions extends StatefulWidget {
  const _CommentReactions({required this.comment, this.reactionPath});

  final Comment comment;
  /// Ruta API alternativa (p. ej. foto de perfil). Por defecto comentarios de post.
  final String Function(Comment c)? reactionPath;

  @override
  State<_CommentReactions> createState() => _CommentReactionsState();
}

class _CommentReactionsState extends State<_CommentReactions> {
  bool _busy = false;

  Comment get c => widget.comment;

  Future<void> _react(String value) async {
    if (_busy) return;
    final next = c.reaction == value ? 'none' : value;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final path = widget.reactionPath?.call(c) ?? 'comments/${c.id}/reaction';
      final res = await api.post(path, {'value': next});
      final data = res.map;
      if (!mounted) return;
      setState(() {
        c.reaction = asStrOrNull(data['reaction']);
        c.likes = asInt(data['likes_count']);
        c.dislikes = asInt(data['dislikes_count']);
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _button(String value, IconData icon, IconData active, int count, String label) {
    final on = c.reaction == value;
    return Semantics(
      button: true,
      label: label,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _react(value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? active : icon, size: 15, color: on ? Tx.accent : Tx.subtle),
            if (count > 0) ...[
              const SizedBox(width: 3),
              Text(compact(count), style: Tx.body(12, weight: FontWeight.w600, color: on ? Tx.accent : Tx.muted)),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _button('like', CupertinoIcons.hand_thumbsup, CupertinoIcons.hand_thumbsup_fill, c.likes, tr('Me gusta')),
      const SizedBox(width: 4),
      _button('dislike', CupertinoIcons.hand_thumbsdown, CupertinoIcons.hand_thumbsdown_fill, c.dislikes, tr('No me gusta')),
    ]);
  }
}

class CommentTile extends StatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.onReply,
    required this.onDelete,
    this.isReply = false,
    this.onHide,
    this.reactionPath,
    this.reportTarget = 'comment',
  });

  final Comment comment;
  final ValueChanged<Comment> onReply;
  final ValueChanged<Comment> onDelete;
  final ValueChanged<Comment>? onHide;
  final bool isReply;
  final String Function(Comment c)? reactionPath;
  final String reportTarget;

  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  CommentTranslation? _translation;
  String? _translatedBody;
  bool _showTranslation = false;
  bool _translating = false;

  Comment get comment => widget.comment;

  Future<void> _translate() async {
    final body = comment.body.trim();
    if (body.isEmpty || _translating) return;
    if (_translation != null && _translatedBody == body) {
      setState(() => _showTranslation = !_showTranslation);
      return;
    }
    setState(() => _translating = true);
    try {
      final t = await translateComment(comment.id, body);
      if (!mounted) return;
      setState(() {
        _translation = t;
        _translatedBody = body;
        _showTranslation = !t.sameLanguage;
      });
      if (t.sameLanguage) toast(context, tr('Este comentario ya está en {lang}.', {'lang': languageName(Lang.instance.code)}));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _translating = false);
  }

  void _menu(BuildContext context) {
    actionSheet(context, [
      SheetAction(tr('Responder'), CupertinoIcons.reply, () => widget.onReply(comment)),
      if (comment.body.trim().isNotEmpty)
        SheetAction(tr('Ver traducción'), CupertinoIcons.globe, _translate),
      SheetAction(tr('Ver perfil'), CupertinoIcons.person, () => openProfile(context, comment.user.username)),
      if (widget.onHide != null) SheetAction(tr('Ocultar comentario'), CupertinoIcons.eye_slash, () => widget.onHide!(comment)),
      if (comment.canDelete) SheetAction(tr('Eliminar'), CupertinoIcons.trash, () => widget.onDelete(comment), destructive: true),
      if (!comment.canDelete || comment.user.id != context.read<AppState>().me?.id)
        SheetAction(tr('Reportar'), CupertinoIcons.flag, () => showReportSheet(context, widget.reportTarget, comment.id), destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final mine = comment.user.id == context.read<AppState>().me?.id;
    final body = (_showTranslation && _translatedBody == comment.body && _translation != null) ? _translation!.body : comment.body;
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.isReply ? 46 : 16, 8, widget.isReply ? 0 : 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onLongPress: () => _menu(context),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(user: comment.user, size: widget.isReply ? 30 : 36, onTap: () => openProfile(context, comment.user.username)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                  decoration: BoxDecoration(
                    color: mine ? Tx.alpha(Tx.purple, .12) : Tx.surface2,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                      topLeft: Radius.circular(6),
                    ),
                    border: Border.all(color: mine ? Tx.alpha(Tx.purple500, .25) : Tx.border),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GestureDetector(onTap: () => openProfile(context, comment.user.username), child: NameLine(user: comment.user, size: 13.5)),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      RichBody(body, style: Tx.body(14.5, height: 1.4)),
                    ],
                    if (comment.body.trim().isNotEmpty && _translation?.sameLanguage != true) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _translate,
                        child: Text(
                          _translating
                              ? tr('Traduciendo…')
                              : (_showTranslation && _translation != null ? tr('Ver original') : tr('Ver traducción')),
                          style: Tx.body(12, weight: FontWeight.w600, color: Tx.accent),
                        ),
                      ),
                    ],
                    if (comment.gif != null) ...[
                      const SizedBox(height: 6),
                      GifView(gif: comment.gif!, maxWidth: 180, maxHeight: 180),
                    ],
                    if (comment.media != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: NetImage(comment.media!.url, width: 200, fit: BoxFit.cover),
                      ),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 4),
                  child: Row(children: [
                    Text(timeAgo(comment.createdAt), style: Tx.body(12, color: Tx.subtle)),
                    const SizedBox(width: 12),
                    _CommentReactions(comment: comment, reactionPath: widget.reactionPath),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => widget.onReply(comment),
                      child: Text(tr('Responder'), style: Tx.body(12, weight: FontWeight.w600, color: Tx.muted)),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _menu(context),
                      child: Icon(CupertinoIcons.ellipsis, size: 15, color: Tx.subtle),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
        if (!widget.isReply)
          for (final r in comment.replies)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: CommentTile(
                comment: r,
                onReply: widget.onReply,
                onDelete: widget.onDelete,
                onHide: widget.onHide,
                isReply: true,
                reactionPath: widget.reactionPath,
                reportTarget: widget.reportTarget,
              ),
            ),
      ]),
    );
  }
}
