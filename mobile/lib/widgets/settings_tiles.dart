import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Grupo de ajustes con título en mayúsculas y filas separadas, al estilo de Ajustes del iPhone.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, this.footer, required this.children});

  final String? title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 24, 6, 8),
          child: Text(title!.toUpperCase(), style: Tx.body(12, weight: FontWeight.w700, color: Tx.subtle).copyWith(letterSpacing: .8)),
        )
      else
        const SizedBox(height: 20),
      Container(
        decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(Tx.radiusLg), border: Border.all(color: Tx.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 58, color: Tx.border),
            children[i],
          ],
        ]),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(footer!, style: Tx.body(12.5, color: Tx.muted, height: 1.4)),
        ),
    ]);
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: Tx.alpha(color, .16), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: Tx.body(15.5, weight: FontWeight.w500, color: destructive ? Tx.danger : Tx.text)),
                if (subtitle != null) Text(subtitle!, style: Tx.body(12.5, color: Tx.muted)),
              ]),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .38),
                child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: Tx.body(14, color: Tx.muted)),
              ),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!] else if (onTap != null && !destructive) ...[
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_right, size: 15, color: Tx.subtle),
            ],
          ]),
        ),
      ),
    );
  }
}
