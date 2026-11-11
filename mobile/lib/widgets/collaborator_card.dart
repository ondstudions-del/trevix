import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/nav.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../screens/wallet/collaborator_screen.dart';
import '../screens/wallet/wallet_screen.dart';
import 'common.dart';

/// Tarjeta del perfil de un colaborador: su plan, el acceso de quien mira y el botón para suscribirse (iOS).
/// En Android solo se muestra si ya hay acceso o si el perfil es propio.
class CollaboratorCard extends StatelessWidget {
  const CollaboratorCard({super.key, required this.profile, required this.onChanged});

  final Profile profile;
  final VoidCallback onChanged;

  static bool visibleFor(Profile p) {
    final c = p.collaborator;
    if (c == null || p.isBlocked) return false;
    return c.isOwner || c.hasAccess || (walletAvailable && c.accepting);
  }

  Future<void> _subscribe(BuildContext context, CollaboratorOffer c) async {
    final until = await subscribeTo(context, profile.user, c.price!, c.days!);
    if (until != null) {
      c.accessUntil = until;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = profile.collaborator!;
    final canBuy = walletAvailable && c.accepting && c.price != null && c.days != null;
    final offer = c.price != null && c.days != null ? tr('{price} por {days} días', {'price': c.price!.formatted, 'days': c.days}) : null;
    final exclusive = c.exclusivePosts == 1 ? tr('1 publicación exclusiva') : tr('{n} publicaciones exclusivas', {'n': c.exclusivePosts});

    final String title;
    final String detail;
    Widget? action;
    if (c.isOwner) {
      title = c.accepting ? tr('Tu plan de colaborador') : tr('Tu plan está en pausa');
      detail = [if (offer != null) offer, exclusive].join(' · ');
      if (walletAvailable) action = SoftButton(label: tr('Gestionar'), height: 36, onPressed: () => push(context, const CollaboratorScreen()));
    } else if (c.hasAccess) {
      title = tr('Estás suscrito');
      detail = '${tr('Acceso hasta el {date}', {'date': fullDate(c.accessUntil)})} · $exclusive';
      if (canBuy) action = SoftButton(label: tr('Extender'), height: 36, onPressed: () => _subscribe(context, c));
    } else {
      title = tr('Contenido exclusivo');
      detail = [if (offer != null) offer, exclusive].join(' · ');
    }

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: Tx.brandSoft,
        borderRadius: BorderRadius.circular(Tx.radiusLg),
        border: Border.all(color: Tx.alpha(Tx.purple500, .35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
            child: Icon(c.hasAccess ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.star_circle_fill, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Tx.body(15, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(detail, style: Tx.body(12.5, color: Tx.muted, height: 1.35)),
            ]),
          ),
          if (action != null) ...[const SizedBox(width: 8), action],
        ]),
        if (c.description != null && !c.isOwner) ...[
          const SizedBox(height: 10),
          Text(c.description!, style: Tx.body(13.5, height: 1.4)),
        ],
        if (!c.isOwner && !c.hasAccess && canBuy) ...[
          const SizedBox(height: 12),
          GradientButton(
            label: tr('Suscribirme por {price}', {'price': c.price!.formatted}),
            icon: CupertinoIcons.star_fill,
            height: 44,
            onPressed: () => _subscribe(context, c),
          ),
        ],
      ]),
    );
  }
}
