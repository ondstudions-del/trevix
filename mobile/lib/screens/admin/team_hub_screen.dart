import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'admin_audit_screen.dart';
import 'admin_communities_screen.dart';
import 'admin_content_screen.dart';
import 'admin_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_users_screen.dart';
import 'team_sections.dart';

/// Panel del equipo: mismo mapa de secciones que el administrador web, con badges y búsqueda.
class TeamHubScreen extends StatefulWidget {
  const TeamHubScreen({super.key});

  @override
  State<TeamHubScreen> createState() => _TeamHubScreenState();
}

class _TeamHubScreenState extends State<TeamHubScreen> {
  final _search = TextEditingController();
  Json? _dash;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() => _query = _search.text.trim().toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('admin/dashboard');
      if (mounted) setState(() {
        _dash = res.map;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(TeamSection s) {
    switch (s.kind) {
      case TeamNative.dashboard:
      case TeamNative.reports:
      case TeamNative.music:
      case TeamNative.verification:
        push(context, AdminScreen(initialTab: s.moderationTab ?? 'summary'));
      case TeamNative.content:
        push(context, const AdminContentScreen());
      case TeamNative.users:
        push(context, const AdminUsersScreen());
      case TeamNative.communities:
        push(context, const AdminCommunitiesScreen());
      case TeamNative.audit:
        push(context, const AdminAuditScreen());
      case TeamNative.settings:
        push(context, const AdminSettingsScreen());
      case TeamNative.web:
        openInApp(context, AppConfig.web(s.webPath ?? 'admin/'));
    }
  }

  List<TeamSection> _visible(bool isAdmin) {
    return teamSections.where((s) {
      if (s.adminOnly && !isAdmin) return false;
      if (_query.isEmpty) return true;
      final hay = '${tr(s.label)} ${tr(s.group)}'.toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AppState>().me;
    final isAdmin = me?.isAdmin ?? false;
    final badges = _dash == null ? <String, int>{} : asMap(_dash!['badges']).map((k, v) => MapEntry(k, asInt(v)));
    final stats = _dash == null ? null : asMap(_dash!['stats']);
    final visible = _visible(isAdmin);

    return Scaffold(
      backgroundColor: Tx.bg,
      appBar: GlassBar(
        title: tr('Panel del equipo'),
        actions: [
          IconButton(
            tooltip: tr('Panel web completo'),
            onPressed: () => openInApp(context, AppConfig.web('admin/')),
            icon: Icon(CupertinoIcons.globe, color: Tx.text),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: Tx.accentSoft,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: [
            if (me != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Tx.alpha(Tx.accentSoft, .18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Tx.alpha(Tx.accentSoft, .35)),
                    ),
                    child: Text(isAdmin ? tr('Administrador') : tr('Moderador'), style: Tx.body(12.5, weight: FontWeight.w700, color: Tx.accentSoft)),
                  ),
                  const Spacer(),
                  Text(tr('TREVIX Admin'), style: Tx.body(12.5, color: Tx.subtle)),
                ]),
              ),
            TextField(
              controller: _search,
              style: Tx.body(15),
              decoration: InputDecoration(
                hintText: tr('Buscar sección…'),
                prefixIcon: Icon(CupertinoIcons.search, color: Tx.muted, size: 20),
                filled: true,
                fillColor: Tx.surface1,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Tx.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorState(error: _error!, onRetry: _load),
            ],
            if (stats != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 88,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _StatChip(icon: CupertinoIcons.person_2_fill, label: tr('Usuarios'), value: compact(asInt(stats['users']))),
                    _StatChip(icon: CupertinoIcons.bolt_fill, label: tr('Activos (24 h)'), value: compact(asInt(stats['active_users']))),
                    _StatChip(icon: CupertinoIcons.square_grid_2x2_fill, label: tr('Publicaciones'), value: compact(asInt(stats['posts']))),
                    _StatChip(icon: CupertinoIcons.flag_fill, label: tr('Reportes'), value: compact(asInt(stats['open_reports']))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            ...teamSectionGroups.expand((group) {
              final items = visible.where((s) => s.group == group).toList();
              if (items.isEmpty) return <Widget>[];
              return [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                child: Text(tr(group).toUpperCase(), style: Tx.body(11.5, weight: FontWeight.w700, color: Tx.subtle).copyWith(letterSpacing: .85)),
              ),
              Container(
                decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tx.border)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Tx.border, indent: 56),
                      _SectionRow(
                        section: items[i],
                        badge: items[i].badgeKey == null ? 0 : (badges[items[i].badgeKey!] ?? 0),
                        onTap: () => _open(items[i]),
                      ),
                    ],
                  ],
                ),
              ),
              ];
            }),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: EmptyState(icon: CupertinoIcons.search, title: tr('Sin resultados'), message: tr('Prueba otro término.')),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Tx.surface1, borderRadius: BorderRadius.circular(16), border: Border.all(color: Tx.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Icon(icon, size: 18, color: Tx.accentSoft),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Tx.display(20)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, color: Tx.muted)),
        ]),
      ]),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section, required this.badge, required this.onTap});
  final TeamSection section;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final web = section.kind == TeamNative.web;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: Tx.alpha(section.color, .16), borderRadius: BorderRadius.circular(10)),
              child: Icon(section.icon, size: 18, color: section.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(section.label), style: Tx.body(15, weight: FontWeight.w600)),
                if (web) Text(tr('Completo en el panel web'), style: Tx.body(12, color: Tx.subtle)),
              ]),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Tx.alpha(Tx.accentSoft, .22), borderRadius: BorderRadius.circular(999)),
                child: Text(badge > 99 ? '99+' : '$badge', style: Tx.body(12, weight: FontWeight.w700, color: Tx.accentSoft)),
              ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: Tx.subtle),
          ]),
        ),
      ),
    );
  }
}