import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/api.dart';
import '../core/catalog.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/routes.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../screens/ads/ads_screen.dart';
import '../screens/reels/reels_screen.dart';
import '../screens/wallet/gifts_screen.dart';
import 'common.dart';
import 'event_card.dart';
import 'gif_picker.dart';
import 'media.dart';
import 'post_translation.dart';
import 'report_sheet.dart';
import 'rich_body.dart';
import 'share_sheet.dart';
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

  /// Traducción con IX: la del texto actual (si se edita la publicación deja de valer) y si se está mostrando.
  PostTranslation? _translation;
  String? _translatedBody;
  bool _translating = false;
  bool _showTranslation = false;

  Post get p => widget.post;

  Future<void> _translate() async {
    final body = p.body.trim();
    if (body.isEmpty || _translating) return;
    if (_translation != null && _translatedBody == body) {
      setState(() => _showTranslation = !_showTranslation);
      return;
    }
    setState(() => _translating = true);
    try {
      final t = await translatePost(p.id, body);
      if (!mounted) return;
      setState(() {
        _translation = t;
        _translatedBody = body;
        _showTranslation = !t.sameLanguage;
      });
      if (t.sameLanguage) toast(context, tr('Esta publicación ya está en {lang}.', {'lang': languageName(Lang.instance.code)}));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _translating = false);
  }

  /// «Ver traducción» · «Traduciendo…» · «Ver original · Traducido del inglés con IX».
  Widget _translationLink(String body, {bool onColor = false}) {
    final t = _translatedBody == body ? _translation : null;
    if (t != null && t.sameLanguage) return const SizedBox.shrink();
    final shown = _showTranslation && t != null;
    final color = onColor ? Colors.white.withAlpha(220) : Tx.accent;
    final label = _translating ? tr('Traduciendo…') : (shown ? tr('Ver original') : tr('Ver traducción'));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _translate,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.globe, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: Tx.body(13, weight: FontWeight.w600, color: color)),
          if (shown) ...[
            Text('  ·  ', style: Tx.body(12, color: onColor ? Colors.white70 : Tx.subtle)),
            Flexible(
              child: Text(t.credit, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: onColor ? Colors.white70 : Tx.subtle)),
            ),
          ],
        ]),
      ),
    );
  }

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
      if (mounted) toast(context, p.saved ? tr('Guardado en tu colección.') : tr('Quitado de guardados.'));
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
      toast(context, tr('La publicación original ya no está disponible.'), error: true);
      return;
    }
    final text = target.body.trim();
    await showShareSheet(
      context,
      url: target.webUrl,
      title: text.isEmpty
          ? tr('{name} en TREVIX', {'name': target.user.displayName})
          : tr('{name} en TREVIX: {text}', {'name': target.user.displayName, 'text': text.length > 120 ? '${text.substring(0, 119)}…' : text}),
      extra: [
        if (target.visibility != 'subscribers')
          SheetAction(tr('Compartir en TREVIX'), CupertinoIcons.arrow_2_squarepath, () async {
            final created = await openComposer(context, share: target);
            if (created != null && mounted) {
              setState(() => p.shares += p.shared == null ? 1 : 0);
            }
          }),
      ],
    );
  }

  void _menu() {
    final actions = <SheetAction>[];
    if (p.isAuthor) {
      if (!p.isShare) {
        actions.add(SheetAction(tr('Editar'), CupertinoIcons.pencil, () async {
          final edited = await openComposer(context, edit: p);
          if (edited != null) widget.onReplaced?.call(edited);
        }));
      }
      if (!p.isShare && p.visibility == 'public' && p.community == null) {
        actions.add(SheetAction(tr('Promocionar con OND-ADS'), CupertinoIcons.speaker_2, () {
          push(context, AdsScreen(kind: 'post', targetId: p.id));
        }));
      }
      actions.add(SheetAction(tr('Eliminar'), CupertinoIcons.trash, _delete, destructive: true));
    }
    final community = p.community;
    if (community != null && community.canModerate && !p.isAuthor) {
      actions.add(SheetAction(tr('Quitar de la comunidad'), CupertinoIcons.minus_circle, () async {
        if (!await confirm(context, tr('Quitar de «{community}»', {'community': community.name}), tr('La publicación dejará de verse en la comunidad.'),
            action: tr('Quitar'), destructive: true)) {
          return;
        }
        try {
          await api.delete('communities/${community.id}/posts/${p.id}');
          widget.onRemoved?.call();
          if (mounted) toast(context, tr('Quitaste la publicación de la comunidad.'));
        } catch (e) {
          if (mounted) toastError(context, e);
        }
      }, destructive: true));
    }
    final publicPost = p.visibility == 'public' && !p.isShare;
    if ((context.read<AppState>().me?.isAdmin ?? false) && (publicPost || p.featured)) {
      actions.add(SheetAction(p.featured ? tr('Quitar de destacadas') : tr('Destacar publicación'), CupertinoIcons.star, _feature));
    }
    actions.add(SheetAction(tr('Copiar enlace'), CupertinoIcons.link, () {
      Clipboard.setData(ClipboardData(text: p.webUrl));
      toast(context, tr('Enlace copiado.'));
    }));
    if (p.body.trim().isNotEmpty) {
      final translated = _showTranslation && _translatedBody == p.body.trim();
      actions.add(SheetAction(translated ? tr('Ver original') : tr('Traducir'), CupertinoIcons.globe, _translate));
    }
    if (p.body.isNotEmpty) {
      actions.add(SheetAction(tr('Copiar texto'), CupertinoIcons.doc_on_doc, () {
        Clipboard.setData(ClipboardData(text: p.body));
        toast(context, tr('Texto copiado.'));
      }));
    }
    if (!p.isAuthor) {
      actions.add(SheetAction(tr('Ver perfil de @{username}', {'username': p.user.username}), CupertinoIcons.person, () => openProfile(context, p.user.username)));
      actions.add(SheetAction(tr('Reportar'), CupertinoIcons.flag, () => showReportSheet(context, 'post', p.id), destructive: true));
    }
    actionSheet(context, actions);
  }

  Future<void> _delete() async {
    if (!await confirm(context, tr('Eliminar publicación'), tr('Se eliminará para siempre junto con sus comentarios.'),
        action: tr('Eliminar'), destructive: true)) {
      return;
    }
    try {
      await api.delete('posts/${p.id}');
      widget.onRemoved?.call();
      if (mounted) toast(context, tr('Publicación eliminada.'));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _feature() async {
    final was = p.featured;
    try {
      final res = was ? await api.delete('admin/posts/${p.id}/feature') : await api.post('admin/posts/${p.id}/feature');
      setState(() => p.featured = !was);
      if (mounted) toast(context, asStr(res.map['message'], was ? tr('Ya no está destacada.') : tr('Publicación destacada.')));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final original = p.body.trim();
    final translation = _showTranslation && _translatedBody == original ? _translation : null;
    final body = translation?.body.trim().isNotEmpty == true ? translation!.body.trim() : original;
    final offerTranslate = original.isNotEmpty && (widget.detail || translation != null || offerTranslation(original));
    final background = p.isThread ? p.background : null;
    final life = p.lifeEvent;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (p.featured)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            const Icon(CupertinoIcons.star_fill, size: 13, color: Color(0xFFFBBF24)),
            const SizedBox(width: 5),
            Text(tr('Destacado'), style: Tx.body(12.5, weight: FontWeight.w700, color: const Color(0xFFFBBF24))),
          ]),
        ),
      _header(),
      if (life != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
            decoration: BoxDecoration(gradient: Tx.brandSoft, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
                child: Icon(lifeEventIcon(life.key), color: Colors.white, size: 26),
              ),
              const SizedBox(height: 10),
              Text(life.label, style: Tx.display(18), textAlign: TextAlign.center),
            ]),
          ),
        ),
      if (body.isNotEmpty && background != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 200),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(gradient: Tx.storyBackground(background), borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RichBody(
                body,
                maxLines: widget.detail ? null : 12,
                style: Tx.display(21, color: Colors.white, height: 1.35),
                textAlign: TextAlign.center,
              ),
              if (offerTranslate) ...[const SizedBox(height: 8), _translationLink(original, onColor: true)],
            ]),
          ),
        )
      else if (body.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RichBody(
              body,
              maxLines: widget.detail ? null : (p.isThread ? 14 : 10),
              style: p.isThread ? Tx.body(17, height: 1.5) : Tx.body(15.5, height: 1.45),
            ),
            if (offerTranslate) _translationLink(original),
          ]),
        ),
      if (p.gif != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: GifView(gif: p.gif!, maxWidth: 300, maxHeight: 300),
        ),
      if (p.event != null)
        Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: EventCard(event: p.event!)),
      if (p.media.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Stack(alignment: Alignment.center, children: [
            MediaGallery(
              media: p.media,
              onDoubleTap: () => _like(fromDoubleTap: true),
              onVideoTap: () => openReels(context, start: p),
            ),
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
              Icon(CupertinoIcons.eye_slash, color: Tx.subtle, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('Esta publicación ya no está disponible.'), style: Tx.body(14, color: Tx.subtle))),
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
              if (p.place != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: GestureDetector(
                    onTap: p.place!.lat == null
                        ? null
                        : () => openUrl(context,
                            'https://www.openstreetmap.org/?mlat=${p.place!.lat}&mlon=${p.place!.lng}#map=13/${p.place!.lat}/${p.place!.lng}'),
                    child: Row(children: [
                      Icon(CupertinoIcons.location_solid, size: 12, color: Tx.muted),
                      const SizedBox(width: 3),
                      Flexible(child: Text(p.place!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted))),
                    ]),
                  ),
                ),
              Row(children: [
                Flexible(
                  child: Text(
                    '@${p.user.username} · ${timeAgo(p.createdAt)}${p.isEdited ? ' · ${tr('editado')}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tx.body(12.5, color: Tx.subtle),
                  ),
                ),
                if (p.visibility != 'public' && community == null) ...[
                  const SizedBox(width: 5),
                  Icon(
                    switch (p.visibility) {
                      'private' => CupertinoIcons.lock_fill,
                      'subscribers' => CupertinoIcons.star_circle_fill,
                      _ => CupertinoIcons.person_2_fill,
                    },
                    size: 12,
                    color: p.visibility == 'subscribers' ? Tx.warning : Tx.subtle,
                  ),
                ],
              ]),
            ]),
          ),
        ),
        if (p.isThread) _Tag(label: tr('Hilo'), icon: CupertinoIcons.text_quote),
        if (p.visibility == 'subscribers' && community == null) _Tag(label: tr('Exclusiva'), icon: CupertinoIcons.star_circle_fill),
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
          icon: TxIcon(TxGlyph.more, color: Tx.muted, size: 22),
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
          glyph: TxGlyph.heart,
          color: p.liked ? Tx.like : Tx.muted,
          label: p.likes > 0 ? compact(p.likes) : '',
          onTap: _like,
          pop: p.liked,
        ),
        _Action(
          glyph: TxGlyph.comment,
          label: p.comments > 0 ? compact(p.comments) : '',
          onTap: widget.onComment ?? () => openPost(context, p.id, post: p, comment: true),
        ),
        _Action(glyph: TxGlyph.repost, label: p.shares > 0 ? compact(p.shares) : '', onTap: _share),
        const Spacer(),
        if (!p.isAuthor)
          Semantics(
            label: tr('Enviar un regalo'),
            button: true,
            child: _Action(glyph: TxGlyph.gift, label: '', onTap: () => sendGift(context, p.user, where: 'post', refId: p.id)),
          ),
        _Action(
          glyph: TxGlyph.bookmark,
          color: p.saved ? Tx.accentSoft : Tx.muted,
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
        Icon(icon, size: 12, color: Tx.accent),
        const SizedBox(width: 4),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.accent))),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.glyph, required this.label, required this.onTap, Color? color, this.pop = false}) : _color = color;

  final TxGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final Color? _color;
  Color get color => _color ?? Tx.muted;
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
            child: TxIcon(glyph, key: ValueKey('${glyph.name}$pop'), size: 22, color: color, filled: pop, stroke: 1.9),
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
            child: const TxIcon(
              TxGlyph.heart,
              size: 96,
              filled: true,
              stroke: 1.2,
              gradient: LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFEC4899), Tx.purple500]),
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
            MediaGallery(media: post.media, radius: 14, onVideoTap: () => openReels(context, start: post)),
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
