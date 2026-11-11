import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/emoji_picker.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/paged_view.dart';
import '../post/post_screen.dart';

/// Comentarios de un reel en una hoja sobre el video (sin salir de Reels), con emojis rápidos y el teclado de emojis.
/// [initialText] llega desde los emojis rápidos de la barra del reel. [onChanged] avisa cuando cambia el contador.
Future<void> showReelComments(BuildContext context, Post post, {String initialText = '', VoidCallback? onChanged}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReelComments(post: post, initialText: initialText, onChanged: onChanged),
  );
}

class _ReelComments extends StatefulWidget {
  const _ReelComments({required this.post, required this.initialText, this.onChanged});

  final Post post;
  final String initialText;
  final VoidCallback? onChanged;

  @override
  State<_ReelComments> createState() => _ReelCommentsState();
}

class _ReelCommentsState extends State<_ReelComments> {
  late final Paged<Comment> _comments = Paged<Comment>('posts/${widget.post.id}/comments', Comment.fromJson);
  late final _input = TextEditingController(text: widget.initialText);
  final _focus = FocusNode();
  Comment? _replyTo;
  Gif? _gif;
  bool _sending = false;
  bool _emojis = false;

  Post get p => widget.post;

  @override
  void initState() {
    super.initState();
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    if (widget.initialText.isNotEmpty) {
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

  void _insert(String emoji) {
    final sel = _input.selection;
    final text = _input.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _input.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    HapticFeedback.selectionClick();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final gif = _gif;
    if ((text.isEmpty && gif == null) || _sending) return;
    setState(() => _sending = true);
    final parent = _replyTo;
    try {
      final res = await api.post('posts/${p.id}/comments', {
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
        p.comments += 1;
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
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _delete(Comment c) async {
    if (!await confirm(context, tr('Eliminar comentario'), c.parentId == null && c.replies.isNotEmpty ? tr('También se eliminarán sus respuestas.') : '',
        action: tr('Eliminar'), destructive: true)) {
      return;
    }
    try {
      await api.delete('comments/${c.id}');
      setState(() {
        if (c.parentId == null) {
          _comments.items.removeWhere((x) => x.id == c.id);
          p.comments -= 1 + c.replies.length;
        } else {
          for (final root in _comments.items) {
            if (root.replies.remove(c)) root.repliesCount -= 1;
          }
          p.comments -= 1;
        }
      });
      _comments.changed();
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _reply(Comment c) {
    setState(() {
      _replyTo = c;
      _emojis = false;
    });
    final mention = '@${c.user.username} ';
    if (c.parentId != null && !_input.text.startsWith(mention)) {
      _input.text = mention + _input.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: DraggableScrollableSheet(
        initialChildSize: keyboard > 0 ? .9 : .72,
        minChildSize: .4,
        maxChildSize: .94,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: BoxDecoration(color: Tx.surface1, borderRadius: const BorderRadius.vertical(top: Radius.circular(22))),
          child: Column(children: [
            const SizedBox(height: 8),
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Tx.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
              child: Text(p.comments == 0 ? tr('Comentarios') : plural(p.comments, 'comentario', 'comentarios'), style: Tx.display(17)),
            ),
            Divider(height: 1, color: Tx.border),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: PagedView<Comment>(
                  paged: _comments,
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 12),
                  empty: EmptyState(icon: CupertinoIcons.chat_bubble_2, title: tr('Sé el primero en comentar'), message: tr('Toca un emoji para empezar.')),
                  itemBuilder: (context, c, _) => CommentTile(comment: c, onReply: _reply, onDelete: _delete),
                ),
              ),
            ),
            _inputBar(media),
          ]),
        ),
      ),
    );
  }

  Widget _inputBar(MediaQueryData media) {
    final me = context.read<AppState>().me;
    final reply = _replyTo;
    final gif = _gif;
    final gifs = context.read<AppState>().feature('gifs');
    return Container(
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + (media.viewInsets.bottom > 0 || _emojis ? 0 : media.padding.bottom)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 40,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            for (final e in quickEmojis)
              GestureDetector(
                onTap: () => _insert(e),
                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(e, style: const TextStyle(fontSize: 26))),
              ),
          ]),
        ),
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4, top: 2),
            child: Row(children: [
              Expanded(child: Text(tr('Respondiendo a @{username}', {'username': reply.user.username}), style: Tx.body(12.5, color: Tx.accent))),
              GestureDetector(onTap: () => setState(() => _replyTo = null), child: Icon(CupertinoIcons.xmark, size: 15, color: Tx.muted)),
            ]),
          ),
        if (gif != null) GifAttachment(gif: gif, onRemove: () => setState(() => _gif = null)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (me != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Avatar(user: me.user, size: 34)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              minLines: 1,
              maxLines: 4,
              maxLength: context.read<AppState>().limit('comment_body', 1000),
              textCapitalization: TextCapitalization.sentences,
              style: Tx.body(15),
              onTap: () => setState(() => _emojis = false),
              decoration: fieldDecoration(reply != null ? tr('Escribe tu respuesta…') : tr('Añade un comentario…')).copyWith(
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (gifs)
                    GestureDetector(
                      onTap: () async {
                        final g = await pickGif(context);
                        if (g != null && mounted) setState(() => _gif = g);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('GIF', style: Tx.body(12, weight: FontWeight.w800, color: Tx.accent)),
                      ),
                    ),
                  IconButton(
                    tooltip: tr('Emojis'),
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _emojis = !_emojis);
                    },
                    icon: Icon(_emojis ? CupertinoIcons.keyboard : CupertinoIcons.smiley, color: Tx.muted, size: 22),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (_, value, __) {
              final enabled = (value.text.trim().isNotEmpty || _gif != null) && !_sending;
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
        if (_emojis) EmojiGrid(height: 260, onPick: _insert),
      ]),
    );
  }
}
