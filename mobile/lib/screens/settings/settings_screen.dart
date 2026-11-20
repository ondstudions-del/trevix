import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/account_switcher.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/settings_tiles.dart';
import '../admin/team_hub_screen.dart';
import '../auth/device_link_screens.dart';
import '../communities/communities_screen.dart';
import '../messages/e2ee_screens.dart';
import '../messages/private_chats_screens.dart';
import '../music/music_screen.dart';
import '../notes/close_friends_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../wallet/collaborator_screen.dart'; // SubscriptionsScreen
import '../wallet/gifts_screen.dart';
import '../wallet/wallet_screen.dart';
import 'account_status_screen.dart';
import 'app_lock_screen.dart';
import 'appearance_screen.dart';
import 'permissions_screen.dart';
import 'settings_catalog.dart';
import 'settings_category_screen.dart';
import 'settings_pages.dart';
import 'verification_screen.dart';

/// Hub de Ajustes: lista limpia con grupos que se despliegan al tocar.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _search = TextEditingController();
  final Set<SettingsCategory> _expanded = {};
  String _query = '';
  bool _sendingMail = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(SettingsCategory id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  void _openCategory(SettingsCategory id) {
    HapticFeedback.selectionClick();
    push(context, SettingsCategoryScreen(category: id));
  }

  Future<void> _resendVerification() async {
    if (_sendingMail) return;
    setState(() => _sendingMail = true);
    try {
      final res = await api.post('me/email/verification');
      if (mounted) toast(context, '${res.map['message'] ?? tr('Te enviamos el enlace.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sendingMail = false);
  }

  void _language() {
    final lang = Lang.instance;
    Future<void> pick(String? code) async {
      await lang.set(code);
      try {
        await api.put('me/locale', {'locale': lang.code});
      } catch (_) {}
    }

    actionSheet(context, [
      SheetAction(tr('Del sistema'), lang.choice == null ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, () => pick(null)),
      for (final e in Lang.names.entries)
        SheetAction(e.value, lang.choice == e.key ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, () => pick(e.key)),
    ], title: tr('Idioma'));
  }

  List<_HubSection> _sections(List<SettingsCategoryMeta> cats) {
    SettingsCategoryMeta? of(SettingsCategory id) {
      for (final c in cats) {
        if (c.id == id) return c;
      }
      return null;
    }

    return [
      _HubSection(tr('Tu cuenta'), [
        of(SettingsCategory.account),
        of(SettingsCategory.security),
        of(SettingsCategory.session),
      ].whereType<SettingsCategoryMeta>().toList()),
      _HubSection(tr('Pagos'), [
        of(SettingsCategory.payments),
      ].whereType<SettingsCategoryMeta>().toList()),
      _HubSection(tr('App'), [
        of(SettingsCategory.chats),
        of(SettingsCategory.notifications),
        of(SettingsCategory.appearance),
        of(SettingsCategory.devices),
        of(SettingsCategory.content),
      ].whereType<SettingsCategoryMeta>().toList()),
      _HubSection(tr('Más'), [
        of(SettingsCategory.team),
        of(SettingsCategory.info),
      ].whereType<SettingsCategoryMeta>().toList()),
    ].where((s) => s.items.isNotEmpty).toList();
  }

  List<_ChildItem> _children(SettingsCategory id, AppState state) {
    switch (id) {
      case SettingsCategory.account:
        return [
          _ChildItem(CupertinoIcons.person_crop_circle, Tx.accentSoft, tr('Editar perfil'), () => push(context, const EditProfileScreen())),
          _ChildItem(CupertinoIcons.at, Tx.blue400, tr('Usuario y correo'), () => push(context, const AccountPage())),
          _ChildItem(CupertinoIcons.link, Tx.cyan, tr('VINCRIPTAR'), () => push(context, const LinkHostScreen())),
          _ChildItem(CupertinoIcons.checkmark_seal_fill, Tx.blue400, tr('Verificación'), () async {
            await push(context, const VerificationScreen());
            if (mounted) state.refreshMe();
          }),
        ];
      case SettingsCategory.security:
        return [
          _ChildItem(CupertinoIcons.lock_rotation, Tx.cyan, tr('Contraseña'), () => push(context, const PasswordPage())),
          _ChildItem(CupertinoIcons.device_phone_portrait, Tx.success, tr('Sesiones activas'), () => push(context, const SessionsPage())),
          _ChildItem(CupertinoIcons.checkmark_shield_fill, Tx.warning, tr('Estado de la cuenta'), () => push(context, const AccountStatusScreen())),
          _ChildItem(CupertinoIcons.lock_shield_fill, Tx.accentSoft, tr('Bloqueo de app'), () => push(context, const AppLockSettingsScreen())),
          _ChildItem(CupertinoIcons.star_fill, const Color(0xFF22C55E), tr('Mejores amigos'), () => push(context, const CloseFriendsScreen())),
          _ChildItem(CupertinoIcons.nosign, Tx.danger, tr('Cuentas bloqueadas'), () => push(context, const BlockedPage())),
          _ChildItem(CupertinoIcons.slider_horizontal_3, Tx.cyan, tr('Más privacidad'), () => _openCategory(SettingsCategory.security)),
        ];
      case SettingsCategory.payments:
        return [
          _ChildItem(CupertinoIcons.star_circle_fill, Tx.warning, tr('Colaborador'), () => push(context, const CollaboratorScreen())),
          _ChildItem(CupertinoIcons.creditcard_fill, Tx.success, tr('Monedero'), () => push(context, const WalletScreen())),
          _ChildItem(CupertinoIcons.gift_fill, const Color(0xFFF59E0B), tr('Regalos'), () => push(context, const GiftsScreen())),
          _ChildItem(CupertinoIcons.star_fill, Tx.accentSoft, tr('Mis suscripciones'), () => push(context, const SubscriptionsScreen())),
        ];
      case SettingsCategory.chats:
        return [
          _ChildItem(CupertinoIcons.lock_shield_fill, Tx.success, tr('Cifrado de los chats'), () => push(context, const E2eeSettingsScreen())),
          _ChildItem(CupertinoIcons.lock_fill, Tx.purple, tr('Chats privados'), () => push(context, const PrivateChatSettingsScreen())),
          _ChildItem(CupertinoIcons.slider_horizontal_3, Tx.blue400, tr('Más opciones de chats'), () => _openCategory(SettingsCategory.chats)),
        ];
      case SettingsCategory.notifications:
        return [
          _ChildItem(CupertinoIcons.bell_fill, Tx.warning, tr('Preferencias de avisos'), () => _openCategory(SettingsCategory.notifications)),
        ];
      case SettingsCategory.appearance:
        return [
          _ChildItem(CupertinoIcons.circle_lefthalf_fill, Tx.accentSoft, tr('Apariencia y accesibilidad'), () => push(context, const AppearanceScreen())),
          _ChildItem(CupertinoIcons.globe, Tx.blue400, tr('Idioma'), _language),
        ];
      case SettingsCategory.devices:
        return [
          _ChildItem(CupertinoIcons.checkmark_shield_fill, Tx.success, tr('Permisos'), () => push(context, const PermissionsScreen())),
          _ChildItem(CupertinoIcons.person_2_fill, Tx.blue400, tr('Invitar contactos'), () => push(context, const InviteContactsScreen())),
        ];
      case SettingsCategory.content:
        return [
          _ChildItem(CupertinoIcons.bookmark_fill, Tx.warning, tr('Guardados'), () => push(context, const SavedPage())),
          _ChildItem(CupertinoIcons.person_3_fill, Tx.accentSoft, tr('Comunidades'), () => push(context, const CommunitiesScreen())),
          _ChildItem(CupertinoIcons.music_note_2, Tx.pink, tr('Biblioteca de música'), () => push(context, const MusicScreen())),
          _ChildItem(CupertinoIcons.slider_horizontal_3, Tx.cyan, tr('Más contenido'), () => _openCategory(SettingsCategory.content)),
        ];
      case SettingsCategory.team:
        return [
          _ChildItem(CupertinoIcons.shield_lefthalf_fill, Tx.accentSoft, tr('Panel del equipo'), () => push(context, const TeamHubScreen())),
        ];
      case SettingsCategory.info:
        return [
          _ChildItem(CupertinoIcons.doc_text, Tx.muted, tr('Términos y condiciones'), () => openInApp(context, AppConfig.web('legal.php?doc=terminos'))),
          _ChildItem(CupertinoIcons.hand_raised_fill, Tx.muted, tr('Política de privacidad'), () => openInApp(context, AppConfig.web('legal.php?doc=privacidad'))),
          _ChildItem(CupertinoIcons.info_circle, Tx.muted, tr('Política de cookies'), () => openInApp(context, AppConfig.web('legal.php?doc=cookies'))),
          _ChildItem(CupertinoIcons.arrow_uturn_left_circle, Tx.muted, tr('Política de reembolsos'), () => openInApp(context, AppConfig.web('legal.php?doc=reembolsos'))),
          _ChildItem(CupertinoIcons.sparkles, Tx.accent, tr('Ver la bienvenida otra vez'), () => state.replayIntro()),
        ];
      case SettingsCategory.session:
        return [
          _ChildItem(
            CupertinoIcons.person_2_square_stack,
            Tx.accent,
            state.otherAccounts.isEmpty ? tr('Agregar cuenta') : tr('Cambiar de cuenta'),
            () => showAccountSwitcher(context),
          ),
          _ChildItem(CupertinoIcons.square_arrow_right, Tx.danger, tr('Cerrar sesión'), () => _openCategory(SettingsCategory.session)),
          _ChildItem(CupertinoIcons.pause_circle, Tx.warning, tr('Zona delicada'), () => _openCategory(SettingsCategory.session)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    if (me == null) return const Scaffold(body: Loading());
    final u = me.user;
    final cats = settingsCategories(isStaff: me.isStaff);
    final q = _query.trim().toLowerCase();
    final searching = q.isNotEmpty;
    final hits = searching
        ? settingsSearchIndex()
            .where((h) {
              final blob = '${h.label} ${h.keywords}'.toLowerCase();
              return blob.contains(q) && cats.any((c) => c.id == h.category);
            })
            .toList()
        : const <SettingsSearchHit>[];
    final sections = _sections(cats);

    return Scaffold(
      backgroundColor: Tx.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          floating: true,
          backgroundColor: Tx.bg.withAlpha(235),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: Icon(CupertinoIcons.back, color: Tx.text),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(tr('Ajustes'), style: Tx.display(20)),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => push(context, const EditProfileScreen()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(children: [
                    Avatar(user: u, size: 52),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        NameLine(user: u, size: 16),
                        const SizedBox(height: 2),
                        Text('@${u.username}', style: Tx.body(13, color: Tx.muted)),
                        Text(me.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: Tx.subtle)),
                      ]),
                    ),
                    Text(tr('Editar'), style: Tx.body(13.5, weight: FontWeight.w600, color: Tx.accent)),
                    const SizedBox(width: 2),
                    Icon(CupertinoIcons.chevron_right, size: 14, color: Tx.subtle),
                  ]),
                ),
              ),
            ),
          ),
        ),
        if (!me.emailVerified)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Material(
                color: Tx.alpha(Tx.warning, .12),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _sendingMail ? null : _resendVerification,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Tx.alpha(Tx.warning, .32)),
                    ),
                    child: Row(children: [
                      Icon(CupertinoIcons.envelope_badge, color: Tx.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('Confirmar correo'), style: Tx.body(14, weight: FontWeight.w700)),
                          Text(tr('Confirma tu correo para proteger tu cuenta.'), style: Tx.body(12.5, color: Tx.muted, height: 1.3)),
                        ]),
                      ),
                      if (_sendingMail)
                        const SizedBox(width: 18, height: 18, child: CupertinoActivityIndicator())
                      else
                        Text(tr('Enviar'), style: Tx.body(13, weight: FontWeight.w700, color: Tx.warning)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              style: Tx.body(15),
              decoration: InputDecoration(
                hintText: tr('Buscar en ajustes…'),
                hintStyle: Tx.body(15, color: Tx.subtle),
                prefixIcon: Icon(CupertinoIcons.search, color: Tx.muted, size: 18),
                suffixIcon: q.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.subtle, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                filled: true,
                fillColor: Tx.surface2,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Tx.accent.withAlpha(140), width: 1.2),
                ),
              ),
            ),
          ),
        ),
        if (!searching)
          // Accesos rápidos (altura fija para no recortar el texto)
          SliverToBoxAdapter(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(children: [
                _QuickPill(icon: CupertinoIcons.creditcard_fill, color: Tx.success, label: tr('Monedero'), onTap: () => push(context, const WalletScreen())),
                _QuickPill(icon: CupertinoIcons.lock_shield_fill, color: Tx.cyan, label: tr('Privacidad'), onTap: () {
                  setState(() => _expanded.add(SettingsCategory.security));
                }),
                _QuickPill(icon: CupertinoIcons.bell_fill, color: Tx.warning, label: tr('Avisos'), onTap: () {
                  setState(() => _expanded.add(SettingsCategory.notifications));
                }),
                _QuickPill(icon: CupertinoIcons.lock_rotation, color: Tx.accentSoft, label: tr('Bloqueo'), onTap: () => push(context, const AppLockSettingsScreen())),
              ]),
            ),
          ),
        if (searching)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: hits.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: Text(tr('Nada coincide con tu búsqueda.'), style: Tx.body(14.5, color: Tx.muted))),
                    )
                  : SettingsGroup(
                      title: tr('Resultados'),
                      children: [
                        for (final h in hits)
                          SettingsRow(
                            icon: cats.firstWhere((c) => c.id == h.category).icon,
                            color: cats.firstWhere((c) => c.id == h.category).color,
                            label: h.label,
                            subtitle: cats.firstWhere((c) => c.id == h.category).title,
                            onTap: () => _openCategory(h.category),
                          ),
                      ],
                    ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final section = sections[i];
                  return _ExpandableSection(
                    title: section.title,
                    items: section.items,
                    expanded: _expanded,
                    onToggle: _toggle,
                    childrenOf: (id) => _children(id, state),
                  );
                },
                childCount: sections.length,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
            child: Column(children: [
              const TrevixLogo(size: 28),
              const SizedBox(height: 8),
              Text(
                tr('TREVIX para {platform} · versión {version}', {
                  'platform': Platform.isIOS ? 'iOS' : 'Android',
                  'version': AppConfig.version,
                }),
                style: Tx.body(12, color: Tx.subtle),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _HubSection {
  const _HubSection(this.title, this.items);
  final String title;
  final List<SettingsCategoryMeta> items;
}

class _ChildItem {
  const _ChildItem(this.icon, this.color, this.label, this.onTap);
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

class _ExpandableSection extends StatelessWidget {
  const _ExpandableSection({
    required this.title,
    required this.items,
    required this.expanded,
    required this.onToggle,
    required this.childrenOf,
  });

  final String title;
  final List<SettingsCategoryMeta> items;
  final Set<SettingsCategory> expanded;
  final void Function(SettingsCategory) onToggle;
  final List<_ChildItem> Function(SettingsCategory) childrenOf;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
        child: Text(title.toUpperCase(), style: Tx.body(12, weight: FontWeight.w700, color: Tx.subtle).copyWith(letterSpacing: .8)),
      ),
      Container(
        decoration: BoxDecoration(
          color: Tx.surface1,
          borderRadius: BorderRadius.circular(Tx.radiusLg),
          border: Border.all(color: Tx.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: Tx.border),
            _ExpandableGroup(
              meta: items[i],
              open: expanded.contains(items[i].id),
              onToggle: () => onToggle(items[i].id),
              children: childrenOf(items[i].id),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _ExpandableGroup extends StatelessWidget {
  const _ExpandableGroup({
    required this.meta,
    required this.open,
    required this.onToggle,
    required this.children,
  });

  final SettingsCategoryMeta meta;
  final bool open;
  final VoidCallback onToggle;
  final List<_ChildItem> children;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: Tx.alpha(meta.color, .16), borderRadius: BorderRadius.circular(9)),
                child: Icon(meta.icon, size: 17, color: meta.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(meta.title, style: Tx.body(15.5, weight: FontWeight.w600)),
                  Text(meta.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted)),
                ]),
              ),
              AnimatedRotation(
                turns: open ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: Icon(CupertinoIcons.chevron_right, size: 15, color: open ? meta.color : Tx.subtle),
              ),
            ]),
          ),
        ),
      ),
      AnimatedCrossFade(
        firstChild: const SizedBox(width: double.infinity),
        secondChild: Column(children: [
          Divider(height: 1, thickness: 1, indent: 58, color: Tx.border),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, indent: 70, color: Tx.border),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: children[i].onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(26, 11, 14, 11),
                  child: Row(children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Tx.alpha(children[i].color, .14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(children[i].icon, size: 15, color: children[i].color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(children[i].label, style: Tx.body(15, weight: FontWeight.w500))),
                    Icon(CupertinoIcons.chevron_right, size: 14, color: Tx.subtle),
                  ]),
                ),
              ),
            ),
          ],
        ]),
        crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 220),
        sizeCurve: Curves.easeOutCubic,
      ),
    ]);
  }
}

class _QuickPill extends StatelessWidget {
  const _QuickPill({required this.icon, required this.color, required this.label, required this.onTap});

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Tx.surface1,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Tx.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: Tx.body(13, weight: FontWeight.w600, height: 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}
