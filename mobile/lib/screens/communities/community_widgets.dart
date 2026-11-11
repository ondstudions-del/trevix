import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({super.key, required this.community, this.size = 48});

  final Community community;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (community.avatarUrl != null) return NetImage(community.avatarUrl, width: size, height: size, radius: size * .3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(size * .3)),
      alignment: Alignment.center,
      child: Text(community.name.isEmpty ? '#' : community.name.characters.first.toUpperCase(), style: Tx.display(size * .42, color: Colors.white)),
    );
  }
}

/// Fila de comunidad para listas y resultados.
class CommunityTile extends StatelessWidget {
  const CommunityTile({super.key, required this.community, this.onTap});

  final Community community;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = community;
    return InkWell(
      onTap: onTap ?? () => openCommunity(context, c.slug),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          CommunityAvatar(community: c, size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w600))),
                if (c.isPrivate) ...[const SizedBox(width: 5), Icon(CupertinoIcons.lock_fill, size: 12, color: Tx.subtle)],
              ]),
              const SizedBox(height: 2),
              Text('${tr(c.category)} · ${plural(c.membersCount, 'miembro', 'miembros')}', style: Tx.body(12.5, color: Tx.muted)),
              if (c.description.isNotEmpty)
                Text(c.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
            ]),
          ),
          if (c.isMember)
            Padding(padding: EdgeInsets.only(left: 8), child: Icon(CupertinoIcons.checkmark_seal_fill, color: Tx.accentSoft, size: 20))
          else if (c.status == 'pending')
            Padding(padding: const EdgeInsets.only(left: 8), child: Text(tr('Pendiente'), style: Tx.body(12, color: Tx.warning))),
        ]),
      ),
    );
  }
}

/// Tarjeta horizontal de comunidad (Explorar).
class CommunityCard extends StatelessWidget {
  const CommunityCard({super.key, required this.community});

  final Community community;

  @override
  Widget build(BuildContext context) {
    final c = community;
    return GestureDetector(
      onTap: () => openCommunity(context, c.slug),
      child: Container(
        width: 210,
        decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tx.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 70,
            width: double.infinity,
            child: c.coverUrl != null
                ? NetImage(c.coverUrl)
                : Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Tx.purple700, Tx.blue]))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Transform.translate(
                offset: const Offset(0, -18),
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.surface1, width: 3)),
                  child: CommunityAvatar(community: c, size: 44),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${tr(c.category)} · ${plural(c.membersCount, 'miembro', 'miembros')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.muted)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
