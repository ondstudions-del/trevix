import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api.dart';
import '../core/catalog.dart';
import '../core/format.dart';
import '../core/nav.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';
import 'media.dart';
import 'report_sheet.dart';
import 'rich_body.dart';
import 'song_chip.dart';

/// Tarjeta de publicación o hilo, con me gusta y guardado optimistas y el menú de acciones.
class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.post, this.onRemoved, this.onReplaced, this.detail = false, this.onComment});

  final Post post;
  final VoidCallback? onRemoved;
  final ValueChanged<Post>? onReplaced;
  final bool detail;
  final VoidCallback? onComment;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  bool _likeBusy = false;
  bool _saveBusy = false;

  Post get p => widget.post;

  @override
  void dispose() {
    _heart.dispose();
    super.dispose();
  }

  Future<void> _like({bool fromDoubleTap = false}) async {
    if (fromDoubleTap) {
      _heart.forward(from: 0);
      if (p.liked) return;
    }
    if (_likeBusy) return;
    _likeBusy = true;
    final was = p.liked;
    HapticFeedback.lightImpact();
    setState(() {
      p.liked = !was;
      p.likes += was ? -1 : 1;
    });
    try {
      final res = was ? await api.delete('posts/${p.id}/like') : await api.post('posts/${p.id}/like');
      p.liked = asBool(res.map['liked']);
      p.likes = asInt(res.map['count'], p.likes);
    } catch (e) {
      p.liked = was;
      p.likes += was ? 1 : -1;
      if (mounted) toastError(context, e);
    }
    _likeBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saveBusy) return;
    _saveBusy = true;
    final was = p.saved;
    HapticFeedback.selectionClick();
    setState(() => p.saved = !was);
    try {
      final res = was ? await api.delete('posts/${p.id}/save') : await api.post('posts/${p.id}/save');
      p.saved = asBool(res.map['saved']);
      p.saves = asInt(res.map['count'], p.saves);
      if (mounted) toast(context, p.saved ? 'Guardado en tu colección.' : 'Quitado de guardados.');
    } catch (e) {
      p.saved = was;
      if (mounted) toastError(context, e);
    }
    _saveBusy = false;
    if (mounted) setState(() {});
  }

  Future<void> _share() async {
    final target = p.shared ?? p;
    if (p.sharedUnavailable && p.shared == null) {
      toast(context, 'La publicación original ya no está disponible.', error: true);
      return;
    }
    await actionSheet(context, [
      SheetAction('Compartir en TREVIX', CupertinoIcons.arrow_2_squarepath, () async {
        final created = await openComposer(context, share: target);
        if (created != null && mounted) {
          setState(() => p.shares += p.shared == null ? 1 : 0);
        }
      }),
      SheetAction('Enviar fuera de TREVIX', CupertinoIcons.share, () => Share.share(target.webUrl)),
      SheetAction('Copiar enlace', CupertinoIcons.link, () {
        Clipboard.setData(ClipboardData(text: target.webUrl));
        toast(context, 'Enlace copiado.');
      }),
    ]);
  }

  void _menu() {
    final actions = <SheetAction>[];
    if (p.isAuthor) {
      if (!p.isShare) {
        actions.add(SheetAction('Editar', CupertinoIcons.pencil, () async {
          final edited = await openComposer(context, edit: p);
          if (edited != null) widget.onReplaced?.call(edited);
        }));
      }
      actions.add(SheetAction('Eliminar', CupertinoIcons.trash, _delete, destructive: true));
    }
    final community = p.community;
    if (community != null && community.canModerate && !p.isAuthor) {
      actions.add(SheetAction('Quitar de la comunidad', CupertinoIcons.minus_circle, () async {
        if (!await confirm(context, 'Quitar de «${community.name}»', 'La publicación dejará de verse en la comunidad.', action: 'Quitar', destructive: true)) return;
        try {
          await api.delete('communities/${community.id}/posts/${p.id}');
          widget.onRemoved?.call();
          if (mounted) toast(context, 'Quitaste la publicación de la comunidad.');
        } catch (e) {
          if (mounted) toastError(context, e);
        }
      }, destructive: true));
    }
    actions.add(SheetAction('Copiar enlace', CupertinoIcons.link, () {
      Clipboard.setData(ClipboardData(text: p.webUrl));
      toast(context, 'Enlace copiado.');
    }));
    if (p.body.isNotEmpty) {
      actions.add(SheetAction('Copiar texto', CupertinoIcons.doc_on_doc, () {
        Clipboard.setData(ClipboardData(text: p.body));
        toast(context, 'Texto copiado.');
      }));
    }
    if (!p.isAuthor) {
      actions.add(SheetAction('Ver perfil de @${p.user.username}', CupertinoIcons.person, () => openProfile(context, p.user.username)));
      actions.add(SheetAction('Reportar', CupertinoIcons.flag, () => showReportSheet(context, 'post', p.id), destructive: true));
    }
    actionSheet(context, actions);
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Eliminar publicación', 'Se eliminará para siempre junto con sus comentarios.', action: 'Eliminar', destructive: true)) return;
    try {
      await api.delete('posts/${p.id}');
      widget.onRemoved?.call();
      if (mounted) toast(context, 'Publicación eliminada.');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = p.body.trim();
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(),
      if (body.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: RichBody(
            body,
            maxLines: widget.detail ? null : (p.isThread ? 14 : 10),
            style: p.isThread ? Tx.body(17, height: 1.5) : Tx.body(15.5, height: 1.45),
          ),
        ),
      if (p.media.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Stack(alignment: Alignment.center, children: [
            MediaGallery(media: p.media, onDoubleTap: () => _like(fromDoubleTap: true)),
            IgnorePointer(child: _BigHeart(controller: _heart)),
          ]),
        ),
      if (p.song != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: SongChip(song: p.song!, playKey: 'post:${p.id}', clip: true),
        ),
      if (p.shared != null)
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: _SharedEmbed(post: p.shared!))
      else if (p.sharedUnavailable)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Tx.surface3, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
            child: Row(children: [
              const Icon(CupertinoIcons.eye_slash, color: Tx.subtle, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('Esta publicación ya no está disponible.', style: Tx.body(14, color: Tx.subtle))),
            ]),
          ),
        ),
      _actions(),
    ]);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Tx.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Tx.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: widget.detail ? null : () => openPost(context, p.id, post: p),
          onDoubleTap: p.media.isEmpty ? () => _like(fromDoubleTap: true) : null,
          child: Stack(alignment: Alignment.center, children: [
            content,
            if (p.media.isEmpty) IgnorePointer(child: _BigHeart(controller: _heart)),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    final community = p.community;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 0),
      child: Row(children: [
        Avatar(user: p.user, size: 42, onTap: () => openProfile(context, p.user.username)),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openProfile(context, p.user.username),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NameLine(user: p.user, size: 15),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                    '@${p.user.username} · ${timeAgo(p.createdAt)}${p.isEdited ? ' · editado' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tx.body(12.5, color: Tx.subtle),
                  ),
                ),
                if (p.visibility != 'public' && community == null) ...[
                  const SizedBox(width: 5),
                  Icon(p.visibility == 'private' ? CupertinoIcons.lock_fill : CupertinoIcons.person_2_fill, size: 12, color: Tx.subtle),
                ],
              ]),
            ]),
          ),
        ),
        if (p.isThread) const _Tag(label: 'Hilo', icon: CupertinoIcons.text_quote),
        if (community != null)
          GestureDetector(
            onTap: () => openCommunity(context, community.slug),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _Tag(label: community.name, icon: CupertinoIcons.person_3_fill),
            ),
          ),
        IconButton(
          onPressed: _menu,
          icon: const Icon(CupertinoIcons.ellipsis, color: Tx.muted, size: 20),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: Row(children: [
        _Action(
          icon: p.liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          color: p.liked ? Tx.like : Tx.muted,
          label: p.likes > 0 ? compact(p.likes) : '',
          onTap: _like,
          pop: p.liked,
        ),
        _Action(
          icon: CupertinoIcons.chat_bubble,
          label: p.comments > 0 ? compact(p.comments) : '',
          onTap: widget.onComment ?? () => openPost(context, p.id, post: p, comment: true),
        ),
        _Action(icon: CupertinoIcons.arrow_2_squarepath, label: p.shares > 0 ? compact(p.shares) : '', onTap: _share),
        const Spacer(),
        _Action(
          icon: p.saved ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
          color: p.saved ? Tx.purple400 : Tx.muted,
          label: '',
          onTap: _save,
          pop: p.saved,
        ),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(gradient: Tx.brandSoft, borderRadius: BorderRadius.circular(10), border: Border.all(color: Tx.alpha(Tx.purple500, .3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: Tx.purple300),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.purple300))),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color = Tx.muted, this.pop = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: Tween(begin: .5, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.elasticOut)),
              child: child,
            ),
            child: Icon(icon, key: ValueKey('$icon$pop'), size: 22, color: color),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(label, style: Tx.body(13.5, weight: FontWeight.w600, color: color == Tx.muted ? Tx.muted : color)),
          ],
        ]),
      ),
    );
  }
}

class _BigHeart extends StatelessWidget {
  const _BigHeart({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        if (t == 0 || t == 1) return const SizedBox.shrink();
        final scale = t < .3 ? Curves.easeOutBack.transform(t / .3) * 1.1 : 1.1 - (t - .3) * .2;
        final opacity = t < .7 ? 1.0 : 1 - (t - .7) / .3;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(
            scale: scale,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (b) => const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFEC4899), Tx.purple500])
                  .createShader(Offset.zero & b.size),
              child: const Icon(CupertinoIcons.heart_fill, size: 96),
            ),
          ),
        );
      },
    );
  }
}

class _SharedEmbed extends StatelessWidget {
  const _SharedEmbed({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openPost(context, post.id, post: post),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.borderStrong)),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(user: post.user, size: 26),
            const SizedBox(width: 8),
            Flexible(child: NameLine(user: post.user, size: 13.5)),
            const SizedBox(width: 6),
            Text('· ${timeAgo(post.createdAt)}', style: Tx.body(12, color: Tx.subtle)),
          ]),
          if (post.body.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            RichBody(post.body.trim(), maxLines: 6, style: Tx.body(14.5, height: 1.4)),
          ],
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 10),
            MediaGallery(media: post.media, radius: 14),
          ],
          if (post.song != null) ...[
            const SizedBox(height: 10),
            SongChip(song: post.song!, playKey: 'shared:${post.id}', clip: true, compact: true),
          ],
        ]),
      ),
    );
  }
}

String visibilityLabel(String v) => visibilities[v] ?? v;
