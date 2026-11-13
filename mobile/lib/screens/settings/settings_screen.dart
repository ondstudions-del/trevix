import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/appearance.dart';
import '../../core/background.dart';
import '../../core/catalog.dart';
import '../../core/config.dart';
import '../../core/device.dart';
import '../../core/fcm.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/push.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/account_switcher.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/settings_tiles.dart';
import '../admin/admin_screen.dart';
import '../communities/communities_screen.dart';
import '../messages/chat_storage_screens.dart';
import '../messages/e2ee_screens.dart';
import '../messages/group_screens.dart';
import '../music/artist_screen.dart';
import '../music/music_screen.dart';
import '../notes/close_friends_screen.dart';
import '../notifications/follow_requests_screen.dart';
import '../profile/edit_profile_screen.dart';
import '../wallet/collaborator_screen.dart';
import '../wallet/gifts_screen.dart';
import '../wallet/wallet_screen.dart';
import 'account_status_screen.dart';
import 'appearance_screen.dart';
import 'permissions_screen.dart';
import 'settings_pages.dart';
import 'verification_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  final Set<String> _saving = {};
  final Map<String, Object> _pending = {};
  bool? _instant;
  bool _batteryRestricted = false;

  @override
  void initState() {
    super.initState();
    if (AndroidPush.supported) {
      WidgetsBinding.instance.addObserver(this);
      _loadPush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadPush();
  }

  Future<void> _loadPush() async {
    final wanted = await AndroidPush.wanted();
    final restricted = await AndroidPush.batteryRestricted();
    if (mounted) {
      setState(() {
        _instant = wanted;
        _batteryRestricted = restricted;
      });
    }
  }

  Future<void> _setInstant(bool value) async {
    setState(() => _instant = value);
    await AndroidPush.setWanted(value);
    if (value && await DeviceAccess.state(Access.notifications) != AccessState.granted) {
      if (!await DeviceAccess.request(Access.notifications)) {
        if (mounted) toast(context, tr('Activa las notificaciones de TREVIX en los ajustes del teléfono.'), error: true);
      }
    }
    await BackgroundNotices.start();
    if (!mounted) return;
    toast(context, value && BackgroundNotices.instant ? tr('Recibirás los avisos al instante.') : tr('Los avisos se revisarán cada cierto tiempo.'));
  }

  Future<void> _patch(String path, String key, Object value) async {
    final state = context.read<AppState>();
    setState(() {
      _saving.add(key);
      _pending[key] = value;
    });
    try {
      final res = await api.patch(path, {key: value});
      if (!mounted) return;
      if (res.map['user'] is Map) state.setMe(asMap(res.map['user']));
      final message = '${res.map['message'] ?? ''}';
      if (message.isNotEmpty && message != 'No hiciste cambios.' && message != "You didn't make any changes.") toast(context, message);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) {
      setState(() {
        _saving.remove(key);
        _pending.remove(key);
      });
    }
  }

  bool _flag(Me me, String key) => (_pending[key] as bool?) ?? me.setting(key);

  Future<void> _resendVerification() async {
    try {
      final res = await api.post('me/email/verification');
      if (mounted) toast(context, '${res.map['message'] ?? tr('Te enviamos el enlace.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _messagePrivacy(Me me) {
    actionSheet(context, [
      for (final e in messagePrivacy.entries)
        SheetAction(
          tr(e.value),
          me.messagePrivacy == e.key ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          () => _patch('me/privacy', 'message_privacy', e.key),
        ),
    ], title: tr('¿Quién puede escribirte?'));
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

  Future<void> _logout() async {
    final others = context.read<AppState>().otherAccounts;
    final message = others.isEmpty
        ? tr('¿Quieres cerrar sesión en este dispositivo?')
        : tr('¿Quieres cerrar sesión en este dispositivo? Pasarás a @{username}.', {'username': others.first.username});
    if (!await confirm(context, tr('Cerrar sesión'), message, action: tr('Cerrar sesión'), destructive: true)) return;
    if (mounted) await context.read<AppState>().logout();
  }

  Future<void> _deactivate() async {
    final state = context.read<AppState>();
    if (!await confirm(context, tr('Desactivar cuenta'),
        tr('Tu perfil y tu contenido dejarán de verse hasta que vuelvas a iniciar sesión. Se cerrarán todas tus sesiones.'),
        action: tr('Continuar'), destructive: true)) {
      return;
    }
    if (!mounted) return;
    final password = await prompt(context, tr('Confirma con tu contraseña'), hint: tr('Contraseña'), action: tr('Desactivar'), obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.post('me/deactivate', {'password': password});
      if (mounted) toast(context, '${res.map['message'] ?? tr('Tu cuenta quedó desactivada.')}');
      state.signedOutRemotely();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete(Me me) async {
    final state = context.read<AppState>();
    if (!await confirm(context, tr('Eliminar cuenta'),
        tr('Se borrarán para siempre tu perfil, publicaciones, comentarios, mensajes e historias. Esta acción no se puede deshacer.'),
        action: tr('Continuar'), destructive: true)) {
      return;
    }
    if (!mounted) return;
    final username = await prompt(context, tr('Escribe tu usuario'), hint: me.username, action: tr('Continuar'), maxLength: 30,
        message: tr('Para confirmar, escribe «{username}».', {'username': me.username}));
    if (username == null || !mounted) return;
    final password = await prompt(context, tr('Confirma con tu contraseña'), hint: tr('Contraseña'), action: tr('Eliminar para siempre'), obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.delete('me', {'password': password, 'confirm_username': username.replaceFirst('@', '')});
      if (mounted) toast(context, '${res.map['message'] ?? tr('Tu cuenta se eliminó.')}');
      state.signedOutRemotely();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.me;
    if (me == null) return const Scaffold(body: Loading());
    final u = me.user;
    return Scaffold(
      appBar: GlassBar(title: tr('Ajustes')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
        Panel(
          onTap: () => push(context, const EditProfileScreen()),
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Avatar(user: u, size: 58),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NameLine(user: u, size: 17),
                const SizedBox(height: 2),
                Text('@${u.username}', style: Tx.body(13.5, color: Tx.muted)),
                Text(me.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.subtle)),
              ]),
            ),
            Icon(CupertinoIcons.chevron_right, size: 16, color: Tx.subtle),
          ]),
        ),
        if (!me.emailVerified) ...[
          const SizedBox(height: 12),
          Panel(
            gradient: true,
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const Icon(CupertinoIcons.envelope_badge, color: Tx.warning),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Confirma tu correo para proteger tu cuenta.'), style: Tx.body(13.5, height: 1.35))),
              const SizedBox(width: 8),
              SoftButton(label: tr('Reenviar'), height: 36, onPressed: _resendVerification),
            ]),
          ),
        ],
        SettingsGroup(title: tr('Cuenta'), children: [
          SettingsRow(icon: CupertinoIcons.person_crop_circle, color: Tx.accentSoft, label: tr('Editar perfil'), onTap: () => push(context, const EditProfileScreen())),
          SettingsRow(icon: CupertinoIcons.at, color: Tx.blue400, label: tr('Usuario y correo'), onTap: () => push(context, const AccountPage())),
          SettingsRow(icon: CupertinoIcons.lock_rotation, color: Tx.cyan, label: tr('Contraseña'), onTap: () => push(context, const PasswordPage())),
          SettingsRow(icon: CupertinoIcons.device_phone_portrait, color: Tx.success, label: tr('Sesiones activas'), onTap: () => push(context, const SessionsPage())),
          SettingsRow(
            icon: CupertinoIcons.checkmark_seal_fill,
            color: Tx.blue400,
            label: tr('Verificación'),
            value: u.isVerified ? tr('Verificada') : null,
            onTap: () async {
              await push(context, const VerificationScreen());
              if (context.mounted) context.read<AppState>().refreshMe();
            },
          ),
          SettingsRow(icon: CupertinoIcons.checkmark_shield_fill, color: Tx.warning, label: tr('Estado de la cuenta'), onTap: () => push(context, const AccountStatusScreen())),
        ]),
        SettingsGroup(title: tr('Colaborador y monedero'), children: [
          SettingsRow(
            icon: CupertinoIcons.star_circle_fill,
            color: Tx.warning,
            label: tr('Colaborador'),
            value: me.collaboratorActive ? tr('Activo') : null,
            onTap: () => push(context, const CollaboratorScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.creditcard_fill, color: Tx.success, label: tr('Monedero'), onTap: () => push(context, const WalletScreen())),
          SettingsRow(icon: CupertinoIcons.gift_fill, color: const Color(0xFFF59E0B), label: tr('Regalos'), onTap: () => push(context, const GiftsScreen())),
          SettingsRow(icon: CupertinoIcons.star_fill, color: Tx.accentSoft, label: tr('Mis suscripciones'), onTap: () => push(context, const SubscriptionsScreen())),
        ]),
        SettingsGroup(title: tr('Privacidad'), children: [
          SettingsRow(
            icon: CupertinoIcons.lock_fill,
            color: Tx.accentSoft,
            label: tr('Cuenta privada'),
            subtitle: tr('Solo tus seguidores aprobados ven tu contenido.'),
            trailing: _saving.contains('is_private')
                ? const CupertinoActivityIndicator()
                : TxSwitch(value: _flag(me, 'is_private'), onChanged: (v) => _patch('me/privacy', 'is_private', v)),
          ),
          SettingsRow(
            icon: CupertinoIcons.circle_fill,
            color: Tx.success,
            label: tr('Mostrar actividad'),
            subtitle: tr('Deja que vean cuándo estás en línea.'),
            trailing: _saving.contains('show_activity')
                ? const CupertinoActivityIndicator()
                : TxSwitch(value: _flag(me, 'show_activity'), onChanged: (v) => _patch('me/privacy', 'show_activity', v)),
          ),
          SettingsRow(
            icon: CupertinoIcons.chat_bubble_2_fill,
            color: Tx.blue400,
            label: tr('Quién puede escribirte'),
            value: tr(messagePrivacy[me.messagePrivacy] ?? ''),
            onTap: () => _messagePrivacy(me),
          ),
          SettingsRow(
            icon: CupertinoIcons.star_fill,
            color: const Color(0xFF22C55E),
            label: tr('Mejores amigos'),
            onTap: () => push(context, const CloseFriendsScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.nosign, color: Tx.danger, label: tr('Cuentas bloqueadas'), onTap: () => push(context, const BlockedPage())),
          SettingsRow(
            icon: CupertinoIcons.person_badge_plus,
            color: Tx.pink,
            label: tr('Solicitudes de seguimiento'),
            value: state.counts.followRequests > 0 ? '${state.counts.followRequests}' : null,
            onTap: () => push(context, const FollowRequestsScreen()),
          ),
        ]),
        SettingsGroup(title: tr('Chats'), children: [
          SettingsRow(
            icon: CupertinoIcons.eye_fill,
            color: Tx.accentSoft,
            label: tr('Confirmación de lectura'),
            subtitle: tr('Los demás verán cuándo leíste sus mensajes y abriste sus fotos o videos de una vez. Si la desactivas, tampoco verás quién leyó los tuyos.'),
            trailing: _saving.contains('read_receipts')
                ? const CupertinoActivityIndicator()
                : TxSwitch(
                    value: (_pending['read_receipts'] as bool?) ?? me.settings['read_receipts'] != false,
                    onChanged: (v) => _patch('me/privacy', 'read_receipts', v),
                  ),
          ),
          SettingsRow(icon: CupertinoIcons.lock_shield_fill, color: Tx.success, label: tr('Cifrado de los chats'), onTap: () => push(context, const E2eeSettingsScreen())),
          SettingsRow(
            icon: CupertinoIcons.trash_circle_fill,
            color: Tx.warning,
            label: tr('Eliminar almacenamiento del chat'),
            onTap: () => push(context, const ChatStorageSettingsScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.globe, color: Tx.cyan, label: tr('Grupos públicos'), onTap: () => push(context, const PublicGroupsScreen())),
        ]),
        SettingsGroup(title: tr('Notificaciones'), children: [
          if (FcmPush.active)
            SettingsRow(
              icon: CupertinoIcons.bolt_fill,
              color: Tx.warning,
              label: tr('Avisos push'),
              subtitle: tr('Mensajes, reacciones, comentarios, menciones y más al instante aunque la app esté cerrada, sin aviso fijo ni gasto extra de batería.'),
              value: tr('Activos'),
            ),
          if (AndroidPush.supported && _instant != null) ...[
            if (!FcmPush.active)
              SettingsRow(
                icon: CupertinoIcons.bolt_fill,
                color: Tx.warning,
                label: tr('Avisos al instante'),
                subtitle: tr('Mensajes, reacciones, comentarios, menciones y más aunque la app esté cerrada. Android muestra un aviso fijo y silencioso mientras está activo.'),
                trailing: TxSwitch(value: _instant!, onChanged: _setInstant),
              ),
            if (!FcmPush.active && _instant! && _batteryRestricted)
              SettingsRow(
                icon: CupertinoIcons.battery_25,
                color: Tx.success,
                label: tr('Uso de batería'),
                subtitle: tr('Con la optimización de batería, Android puede retrasar los avisos con el teléfono en reposo. Elige «Todas las apps», busca TREVIX y marca «No optimizar».'),
                value: tr('Optimizado'),
                onTap: AndroidPush.openBatterySettings,
              ),
            SettingsRow(
              icon: CupertinoIcons.speaker_2_fill,
              color: Tx.blue400,
              label: tr('Sonido y estilo de los avisos'),
              subtitle: tr('Mensajes, Actividad y Conexión en segundo plano, en los ajustes del teléfono.'),
              onTap: AndroidPush.openChannelSettings,
            ),
          ],
          for (final e in const {
            'notify_follows': ('Nuevos seguidores', CupertinoIcons.person_add_solid),
            'notify_likes': ('Me gusta', CupertinoIcons.heart_fill),
            'notify_comments': ('Comentarios', CupertinoIcons.chat_bubble_fill),
            'notify_mentions': ('Menciones', CupertinoIcons.at_circle_fill),
          }.entries)
            SettingsRow(
              icon: e.value.$2,
              color: Tx.like,
              label: tr(e.value.$1),
              trailing: _saving.contains(e.key)
                  ? const CupertinoActivityIndicator()
                  : TxSwitch(value: _flag(me, e.key), onChanged: (v) => _patch('me/notification-settings', e.key, v)),
            ),
        ]),
        SettingsGroup(title: tr('Apariencia'), children: [
          ListenableBuilder(
            listenable: Appearance.instance,
            builder: (context, _) => SettingsRow(
              icon: CupertinoIcons.circle_lefthalf_fill,
              color: Tx.accentSoft,
              label: tr('Apariencia y accesibilidad'),
              value: {ThemeChoice.system: tr('Sistema'), ThemeChoice.light: tr('Claro'), ThemeChoice.dark: tr('Oscuro')}[Appearance.instance.choice],
              onTap: () => push(context, const AppearanceScreen()),
            ),
          ),
          ListenableBuilder(
            listenable: Lang.instance,
            builder: (context, _) => SettingsRow(
              icon: CupertinoIcons.globe,
              color: Tx.blue400,
              label: tr('Idioma'),
              value: Lang.instance.choice == null ? tr('Del sistema') : Lang.names[Lang.instance.code],
              onTap: _language,
            ),
          ),
        ]),
        SettingsGroup(title: tr('Dispositivo'), children: [
          SettingsRow(
            icon: CupertinoIcons.checkmark_shield_fill,
            color: Tx.success,
            label: tr('Permisos'),
            subtitle: tr('Notificaciones, micrófono, fotos, ubicación y contactos.'),
            onTap: () => push(context, const PermissionsScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.person_2_fill, color: Tx.blue400, label: tr('Invitar contactos'), onTap: () => push(context, const InviteContactsScreen())),
        ]),
        SettingsGroup(title: tr('Tu contenido'), children: [
          SettingsRow(icon: CupertinoIcons.bookmark_fill, color: Tx.warning, label: tr('Guardados'), onTap: () => push(context, const SavedPage())),
          SettingsRow(icon: CupertinoIcons.person_3_fill, color: Tx.accentSoft, label: tr('Comunidades'), onTap: () => push(context, const CommunitiesScreen())),
          SettingsRow(icon: CupertinoIcons.music_note_2, color: Tx.pink, label: tr('Biblioteca de música'), onTap: () => push(context, const MusicScreen())),
          SettingsRow(icon: CupertinoIcons.music_mic, color: Tx.cyan, label: tr('Panel de artista'), onTap: () => push(context, const ArtistScreen())),
        ]),
        if (me.isStaff)
          SettingsGroup(title: tr('Equipo'), children: [
            SettingsRow(
              icon: CupertinoIcons.shield_lefthalf_fill,
              color: Tx.accentSoft,
              label: tr('Moderación'),
              subtitle: me.isAdmin ? tr('Administrador') : tr('Moderador'),
              onTap: () => push(context, const AdminScreen()),
            ),
          ]),
        SettingsGroup(title: tr('Información'), children: [
          SettingsRow(icon: CupertinoIcons.doc_text, color: Tx.muted, label: tr('Términos y condiciones'), onTap: () => openInApp(context, AppConfig.web('legal.php?doc=terminos'))),
          SettingsRow(icon: CupertinoIcons.hand_raised_fill, color: Tx.muted, label: tr('Política de privacidad'), onTap: () => openInApp(context, AppConfig.web('legal.php?doc=privacidad'))),
          SettingsRow(icon: CupertinoIcons.info_circle, color: Tx.muted, label: tr('Política de cookies'), onTap: () => openInApp(context, AppConfig.web('legal.php?doc=cookies'))),
          SettingsRow(icon: CupertinoIcons.arrow_uturn_left_circle, color: Tx.muted, label: tr('Política de reembolsos'), onTap: () => openInApp(context, AppConfig.web('legal.php?doc=reembolsos'))),
          SettingsRow(icon: CupertinoIcons.sparkles, color: Tx.accent, label: tr('Ver la bienvenida otra vez'), onTap: () => context.read<AppState>().replayIntro()),
        ]),
        SettingsGroup(children: [
          SettingsRow(
            icon: CupertinoIcons.person_2_square_stack,
            color: Tx.accent,
            label: state.otherAccounts.isEmpty ? tr('Agregar cuenta') : tr('Cambiar de cuenta'),
            value: state.accounts.length > 1 ? tr('{n} cuentas', {'n': state.accounts.length}) : null,
            onTap: () => showAccountSwitcher(context),
          ),
          SettingsRow(icon: CupertinoIcons.square_arrow_right, color: Tx.danger, label: tr('Cerrar sesión'), destructive: true, onTap: _logout),
        ]),
        SettingsGroup(title: tr('Zona delicada'), children: [
          SettingsRow(icon: CupertinoIcons.pause_circle, color: Tx.warning, label: tr('Desactivar cuenta'), onTap: _deactivate),
          if (!me.isAdmin) SettingsRow(icon: CupertinoIcons.trash_fill, color: Tx.danger, label: tr('Eliminar cuenta'), destructive: true, onTap: () => _delete(me)),
        ]),
        const SizedBox(height: 28),
        const Center(child: TrevixLogo(size: 34)),
        const SizedBox(height: 8),
        Center(child: Text(tr('TREVIX para {platform} · versión {version}', {'platform': Platform.isIOS ? 'iOS' : 'Android', 'version': AppConfig.version}), style: Tx.body(12, color: Tx.subtle))),
      ]),
    );
  }
}
