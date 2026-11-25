import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'common.dart';

/// Texto del botón de acción según el tipo de campaña (nunca la URL cruda).
String ondAdActionLabel(Json ad) {
  final kind = asStr(ad['kind']);
  if (kind == 'post') return tr('Ver publicación');
  final community = asMapOrNull(ad['community']);
  if (kind == 'community' && community != null) return tr('Ver comunidad');
  final group = asMapOrNull(ad['group']);
  if (kind == 'group' && group != null) {
    return asBool(group['is_member']) ? tr('Ver grupo') : tr('Unirme al grupo');
  }
  final custom = asMapOrNull(ad['custom']);
  return asStr(custom?['cta_label'], tr('Más información'));
}

/// Debajo del botón: dominio, correo, teléfono o @usuario (no el enlace completo).
String? ondAdLinkHint(Json ad) {
  final custom = asMapOrNull(ad['custom']);
  if (custom == null) return null;
  final cta = asStr(custom['cta']);
  final url = asStr(custom['link_url']);
  if (cta == 'contact') {
    if (url.toLowerCase().startsWith('mailto:')) return url.substring(7);
    if (url.toLowerCase().startsWith('tel:')) return url.substring(4);
    final domain = asStr(custom['domain']);
    if (domain.isNotEmpty) return domain;
  }
  if (cta == 'subscribe') {
    final u = asStr(custom['cta_target']);
    if (u.isNotEmpty) return '@$u';
  }
  final domain = asStr(custom['domain']);
  if (domain.isNotEmpty && cta != 'subscribe') return domain;
  return null;
}

Future<void> followOndAdClick(BuildContext context, Json ad) async {
  final id = asInt(ad['id']);
  try {
    final res = (await api.post('ads/$id/click')).map;
    if (!context.mounted) return;
    switch (asStr(res['kind'])) {
      case 'post':
        openPost(context, asInt(res['post_id']));
      case 'community':
        openCommunity(context, asStr(res['community_slug']));
      case 'group':
        openGroupInvite(context, asStr(res['invite_code']));
      case 'profile':
        openProfile(context, asStr(res['username']));
      default:
        openUrl(context, asStr(res['url']));
    }
  } catch (e) {
    if (context.mounted) toastError(context, e);
  }
}

/// Publicación promocionada: badge Patrocinador en la tarjeta y CTA de anuncio.
class SponsoredPostChrome extends StatelessWidget {
  const SponsoredPostChrome({super.key, required this.ad, required this.child, this.footer = true});

  final Json ad;
  final Widget child;
  final bool footer;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              Positioned(top: 10, left: 14, child: ondAdSponsorBadge()),
            ],
          ),
          if (footer)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
              child: OndAdActionFooter(ad: ad, compact: true),
            ),
        ],
      );
}

Widget ondAdSponsorBadge({double fontSize = 10.5, Color? color, bool onDark = false}) {
  final fg = color ?? (onDark ? Colors.white70 : Tx.subtle);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: onDark ? Colors.black.withValues(alpha: .45) : Tx.alpha(Tx.bg, .88),
      borderRadius: BorderRadius.circular(8),
      border: onDark ? null : Border.all(color: Tx.alpha(Tx.border, .6)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(CupertinoIcons.speaker_2_fill, size: fontSize + 2, color: onDark ? Colors.white : Tx.accent),
      const SizedBox(width: 5),
      Text(tr('Patrocinador'), style: Tx.body(fontSize, weight: FontWeight.w800, color: fg)),
    ]),
  );
}

/// Botón + hint de enlace para anuncios con URL (feed, reel, historia).
class OndAdActionFooter extends StatelessWidget {
  const OndAdActionFooter({super.key, required this.ad, this.compact = false, this.onDark = false});

  final Json ad;
  final bool compact;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final action = ondAdActionLabel(ad);
    final hint = ondAdLinkHint(ad);
  final cta = asStr(asMapOrNull(ad['custom'])?['cta']);
    final icon = switch (cta) {
      'shop' => CupertinoIcons.cart_fill,
      'visit' || 'sign_up' => CupertinoIcons.globe,
      'contact' when (asStr(asMapOrNull(ad['custom'])?['link_url']).toLowerCase().startsWith('mailto:')) => CupertinoIcons.mail_solid,
      'contact' when (asStr(asMapOrNull(ad['custom'])?['link_url']).toLowerCase().startsWith('tel:')) => CupertinoIcons.phone_fill,
      'subscribe' => CupertinoIcons.person_add_solid,
      _ => CupertinoIcons.arrow_up_right_square_fill,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hint != null && !compact)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(icon, size: 14, color: onDark ? Colors.white54 : Tx.subtle),
            const SizedBox(width: 6),
            Expanded(child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: onDark ? Colors.white54 : Tx.subtle))),
          ]),
        ),
      GradientButton(
        label: action,
        height: compact ? 40 : 44,
        icon: compact ? null : icon,
        onPressed: () => followOndAdClick(context, ad),
      ),
    ]);
  }
}

/// Vista previa al tocar el anuncio en la barra de historias (etiqueta + botón claro).
Future<void> openOndAdStorySheet(BuildContext context, Json ad) {
  final sponsor = User.fromJson(asMap(ad['sponsor']));
  final custom = asMapOrNull(ad['custom']);
  final post = asMapOrNull(ad['post']);
  final image = asStrOrNull(custom?['image_url']) ??
      asStrOrNull(post?['media']?[0]?['poster_url']) ??
      sponsor.avatarUrl;
  final title = asStr(custom?['title'], post != null ? asStr(post['body']).replaceAll('\n', ' ').trim() : sponsor.displayName);
  final subtitle = asStr(custom?['body'], '');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(ctx).bottom),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(user: sponsor, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(sponsor.displayName, style: Tx.body(15, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                ondAdSponsorBadge(fontSize: 10),
              ]),
            ),
          ]),
          if (image != null && image.isNotEmpty) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tx.radiusMd),
              child: AspectRatio(aspectRatio: 1.2, child: NetImage(image, fit: BoxFit.cover)),
            ),
          ],
          if (title.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(title, style: Tx.body(16, weight: FontWeight.w700)),
          ],
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(subtitle, maxLines: 4, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.muted, height: 1.35)),
            ),
          const SizedBox(height: 16),
          OndAdActionFooter(ad: ad),
        ]),
      ),
    ),
  );
}