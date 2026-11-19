import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';

enum TeamNative {
  dashboard,
  reports,
  music,
  verification,
  content,
  users,
  communities,
  audit,
  settings,
  web,
}

class TeamSection {
  const TeamSection({
    required this.id,
    required this.label,
    required this.group,
    required this.icon,
    required this.color,
    this.adminOnly = false,
    this.badgeKey,
    required this.kind,
    this.webPath,
    this.moderationTab,
  });

  final String id;
  final String label;
  final String group;
  final IconData icon;
  final Color color;
  final bool adminOnly;
  final String? badgeKey;
  final TeamNative kind;
  final String? webPath;
  final String? moderationTab;
}

const teamSectionGroups = ['Resumen', 'Moderación', 'Cuentas', 'Economía', 'Plataforma'];

final teamSections = <TeamSection>[
  TeamSection(
    id: 'dashboard',
    label: 'Dashboard',
    group: 'Resumen',
    icon: CupertinoIcons.square_grid_2x2_fill,
    color: Tx.accentSoft,
    kind: TeamNative.dashboard,
    moderationTab: 'summary',
  ),
  TeamSection(id: 'reports', label: 'Reportes', group: 'Moderación', icon: CupertinoIcons.flag_fill, color: Tx.danger, badgeKey: 'reports', kind: TeamNative.reports, moderationTab: 'reports'),
  TeamSection(id: 'content', label: 'Contenido', group: 'Moderación', icon: CupertinoIcons.doc_text_fill, color: Tx.blue400, kind: TeamNative.content),
  TeamSection(id: 'music', label: 'Música', group: 'Moderación', icon: CupertinoIcons.music_note_2, color: Tx.pink, badgeKey: 'music', kind: TeamNative.music, moderationTab: 'music'),
  TeamSection(id: 'appeals', label: 'Apelaciones', group: 'Moderación', icon: CupertinoIcons.doc_text, color: Tx.warning, badgeKey: 'appeals', kind: TeamNative.web, webPath: 'admin/appeals.php'),
  TeamSection(
    id: 'support',
    label: 'Soporte IX',
    group: 'Moderación',
    icon: CupertinoIcons.sparkles,
    color: Tx.cyan,
    badgeKey: 'support',
    kind: TeamNative.web,
    webPath: 'admin/support.php',
  ),
  TeamSection(id: 'users', label: 'Usuarios', group: 'Cuentas', icon: CupertinoIcons.person_2_fill, color: Tx.accent, kind: TeamNative.users),
  TeamSection(
    id: 'verification',
    label: 'Verificación',
    group: 'Cuentas',
    icon: CupertinoIcons.checkmark_seal_fill,
    color: Tx.blue400,
    adminOnly: true,
    badgeKey: 'verification',
    kind: TeamNative.verification,
    moderationTab: 'verification',
  ),
  TeamSection(
    id: 'wallet',
    label: 'Monedero',
    group: 'Economía',
    icon: CupertinoIcons.money_dollar_circle_fill,
    color: Tx.success,
    adminOnly: true,
    badgeKey: 'wallet',
    kind: TeamNative.web,
    webPath: 'admin/wallet.php',
  ),
  TeamSection(id: 'gifts', label: 'Regalos', group: 'Economía', icon: CupertinoIcons.gift_fill, color: Tx.pink, adminOnly: true, kind: TeamNative.web, webPath: 'admin/gifts.php'),
  TeamSection(id: 'ads', label: 'OND-ADS', group: 'Economía', icon: CupertinoIcons.speaker_2_fill, color: Tx.warning, adminOnly: true, badgeKey: 'ads', kind: TeamNative.web, webPath: 'admin/ads.php'),
  TeamSection(
    id: 'push',
    label: 'Avisos push',
    group: 'Plataforma',
    icon: CupertinoIcons.bell_fill,
    color: Tx.accentSoft,
    adminOnly: true,
    kind: TeamNative.web,
    webPath: 'admin/push.php',
  ),
  TeamSection(
    id: 'early_access',
    label: 'Acceso Anticipado',
    group: 'Plataforma',
    icon: CupertinoIcons.device_phone_portrait,
    color: Tx.cyan,
    adminOnly: true,
    badgeKey: 'early_access',
    kind: TeamNative.web,
    webPath: 'admin/early-access.php',
  ),
  TeamSection(id: 'communities', label: 'Comunidades', group: 'Plataforma', icon: CupertinoIcons.person_3_fill, color: Tx.purple400, adminOnly: true, kind: TeamNative.communities),
  TeamSection(id: 'settings', label: 'Configuración', group: 'Plataforma', icon: CupertinoIcons.slider_horizontal_3, color: Tx.muted, adminOnly: true, kind: TeamNative.settings),
  TeamSection(id: 'audit', label: 'Auditoría', group: 'Plataforma', icon: CupertinoIcons.clock_fill, color: Tx.subtle, adminOnly: true, kind: TeamNative.audit),
];