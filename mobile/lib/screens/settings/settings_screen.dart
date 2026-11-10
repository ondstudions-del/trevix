import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/appearance.dart';
import '../../core/catalog.dart';
import '../../core/config.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/logo.dart';
import '../../widgets/settings_tiles.dart';
import '../admin/admin_screen.dart';
import '../communities/communities_screen.dart';
import '../music/artist_screen.dart';
import '../music/music_screen.dart';
import '../notes/close_friends_screen.dart';
import '../notifications/follow_requests_screen.dart';
import '../profile/edit_profile_screen.dart';
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

class _SettingsScreenState extends State<SettingsScreen> {
  final Set<String> _saving = {};
  final Map<String, Object> _pending = {};

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
      if (message.isNotEmpty && message != 'No hiciste cambios.') toast(context, message);
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
      if (mounted) toast(context, '${res.map['message'] ?? 'Te enviamos el enlace.'}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _messagePrivacy(Me me) {
    actionSheet(context, [
      for (final e in messagePrivacy.entries)
        SheetAction(
          e.value,
          me.messagePrivacy == e.key ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          () => _patch('me/privacy', 'message_privacy', e.key),
        ),
    ], title: '¿Quién puede escribirte?');
  }

  Future<void> _logout() async {
    if (!await confirm(context, 'Cerrar sesión', '¿Quieres cerrar sesión en este dispositivo?', action: 'Cerrar sesión', destructive: true)) return;
    if (mounted) await context.read<AppState>().logout();
  }

  Future<void> _deactivate() async {
    final state = context.read<AppState>();
    if (!await confirm(context, 'Desactivar cuenta',
        'Tu perfil y tu contenido dejarán de verse hasta que vuelvas a iniciar sesión. Se cerrarán todas tus sesiones.',
        action: 'Continuar', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final password = await prompt(context, 'Confirma con tu contraseña', hint: 'Contraseña', action: 'Desactivar', obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.post('me/deactivate', {'password': password});
      if (mounted) toast(context, '${res.map['message'] ?? 'Tu cuenta quedó desactivada.'}');
      state.signedOutRemotely();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _delete(Me me) async {
    final state = context.read<AppState>();
    if (!await confirm(context, 'Eliminar cuenta',
        'Se borrarán para siempre tu perfil, publicaciones, comentarios, mensajes e historias. Esta acción no se puede deshacer.',
        action: 'Continuar', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final username = await prompt(context, 'Escribe tu usuario', hint: me.username, action: 'Continuar', maxLength: 30,
        message: 'Para confirmar, escribe «${me.username}».');
    if (username == null || !mounted) return;
    final password = await prompt(context, 'Confirma con tu contraseña', hint: 'Contraseña', action: 'Eliminar para siempre', obscure: true, maxLength: 200);
    if (password == null || !mounted) return;
    try {
      final res = await api.delete('me', {'password': password, 'confirm_username': username.replaceFirst('@', '')});
      if (mounted) toast(context, '${res.map['message'] ?? 'Tu cuenta se eliminó.'}');
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
      appBar: const GlassBar(title: 'Ajustes'),
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
              Expanded(child: Text('Confirma tu correo para proteger tu cuenta.', style: Tx.body(13.5, height: 1.35))),
              const SizedBox(width: 8),
              SoftButton(label: 'Reenviar', height: 36, onPressed: _resendVerification),
            ]),
          ),
        ],
        SettingsGroup(title: 'Cuenta', children: [
          SettingsRow(icon: CupertinoIcons.person_crop_circle, color: Tx.accentSoft, label: 'Editar perfil', onTap: () => push(context, const EditProfileScreen())),
          SettingsRow(icon: CupertinoIcons.at, color: Tx.blue400, label: 'Usuario y correo', onTap: () => push(context, const AccountPage())),
          SettingsRow(icon: CupertinoIcons.lock_rotation, color: Tx.cyan, label: 'Contraseña', onTap: () => push(context, const PasswordPage())),
          SettingsRow(icon: CupertinoIcons.device_phone_portrait, color: Tx.success, label: 'Sesiones activas', onTap: () => push(context, const SessionsPage())),
          SettingsRow(
            icon: CupertinoIcons.checkmark_seal_fill,
            color: Tx.blue400,
            label: 'Verificación',
            value: u.isVerified ? 'Verificada' : null,
            onTap: () async {
              await push(context, const VerificationScreen());
              if (context.mounted) context.read<AppState>().refreshMe();
            },
          ),
          SettingsRow(icon: CupertinoIcons.checkmark_shield_fill, color: Tx.warning, label: 'Estado de la cuenta', onTap: () => push(context, const AccountStatusScreen())),
        ]),
        SettingsGroup(title: 'Privacidad', children: [
          SettingsRow(
            icon: CupertinoIcons.lock_fill,
            color: Tx.accentSoft,
            label: 'Cuenta privada',
            subtitle: 'Solo tus seguidores aprobados ven tu contenido.',
            trailing: _saving.contains('is_private')
                ? const CupertinoActivityIndicator()
                : TxSwitch(value: _flag(me, 'is_private'), onChanged: (v) => _patch('me/privacy', 'is_private', v)),
          ),
          SettingsRow(
            icon: CupertinoIcons.circle_fill,
            color: Tx.success,
            label: 'Mostrar actividad',
            subtitle: 'Deja que vean cuándo estás en línea.',
            trailing: _saving.contains('show_activity')
                ? const CupertinoActivityIndicator()
                : TxSwitch(value: _flag(me, 'show_activity'), onChanged: (v) => _patch('me/privacy', 'show_activity', v)),
          ),
          SettingsRow(
            icon: CupertinoIcons.chat_bubble_2_fill,
            color: Tx.blue400,
            label: 'Quién puede escribirte',
            value: messagePrivacy[me.messagePrivacy] ?? '',
            onTap: () => _messagePrivacy(me),
          ),
          SettingsRow(
            icon: CupertinoIcons.star_fill,
            color: const Color(0xFF22C55E),
            label: 'Mejores amigos',
            onTap: () => push(context, const CloseFriendsScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.nosign, color: Tx.danger, label: 'Cuentas bloqueadas', onTap: () => push(context, const BlockedPage())),
          SettingsRow(
            icon: CupertinoIcons.person_badge_plus,
            color: Tx.pink,
            label: 'Solicitudes de seguimiento',
            value: state.counts.followRequests > 0 ? '${state.counts.followRequests}' : null,
            onTap: () => push(context, const FollowRequestsScreen()),
          ),
        ]),
        SettingsGroup(title: 'Notificaciones', children: [
          for (final e in const {
            'notify_follows': ('Nuevos seguidores', CupertinoIcons.person_add_solid),
            'notify_likes': ('Me gusta', CupertinoIcons.heart_fill),
            'notify_comments': ('Comentarios', CupertinoIcons.chat_bubble_fill),
            'notify_mentions': ('Menciones', CupertinoIcons.at_circle_fill),
          }.entries)
            SettingsRow(
              icon: e.value.$2,
              color: Tx.like,
              label: e.value.$1,
              trailing: _saving.contains(e.key)
                  ? const CupertinoActivityIndicator()
                  : TxSwitch(value: _flag(me, e.key), onChanged: (v) => _patch('me/notification-settings', e.key, v)),
            ),
        ]),
        SettingsGroup(title: 'Apariencia', children: [
          ListenableBuilder(
            listenable: Appearance.instance,
            builder: (context, _) => SettingsRow(
              icon: CupertinoIcons.circle_lefthalf_fill,
              color: Tx.accentSoft,
              label: 'Apariencia y accesibilidad',
              value: const {ThemeChoice.system: 'Sistema', ThemeChoice.light: 'Claro', ThemeChoice.dark: 'Oscuro'}[Appearance.instance.choice],
              onTap: () => push(context, const AppearanceScreen()),
            ),
          ),
        ]),
        SettingsGroup(title: 'Dispositivo', children: [
          SettingsRow(
            icon: CupertinoIcons.checkmark_shield_fill,
            color: Tx.success,
            label: 'Permisos',
            subtitle: 'Notificaciones, micrófono, fotos, ubicación y contactos.',
            onTap: () => push(context, const PermissionsScreen()),
          ),
          SettingsRow(icon: CupertinoIcons.person_2_fill, color: Tx.blue400, label: 'Invitar contactos', onTap: () => push(context, const InviteContactsScreen())),
        ]),
        SettingsGroup(title: 'Tu contenido', children: [
          SettingsRow(icon: CupertinoIcons.bookmark_fill, color: Tx.warning, label: 'Guardados', onTap: () => push(context, const SavedPage())),
          SettingsRow(icon: CupertinoIcons.person_3_fill, color: Tx.accentSoft, label: 'Comunidades', onTap: () => push(context, const CommunitiesScreen())),
          SettingsRow(icon: CupertinoIcons.music_note_2, color: Tx.pink, label: 'Biblioteca de música', onTap: () => push(context, const MusicScreen())),
          SettingsRow(icon: CupertinoIcons.music_mic, color: Tx.cyan, label: 'Panel de artista', onTap: () => push(context, const ArtistScreen())),
        ]),
        if (me.isStaff)
          SettingsGroup(title: 'Equipo', children: [
            SettingsRow(
              icon: CupertinoIcons.shield_lefthalf_fill,
              color: Tx.accentSoft,
              label: 'Moderación',
              subtitle: me.isAdmin ? 'Administrador' : 'Moderador',
              onTap: () => push(context, const AdminScreen()),
            ),
          ]),
        SettingsGroup(title: 'Información', children: [
          SettingsRow(icon: CupertinoIcons.doc_text, color: Tx.muted, label: 'Términos y condiciones', onTap: () => openInApp(context, AppConfig.web('legal.php?doc=terminos'))),
          SettingsRow(icon: CupertinoIcons.hand_raised_fill, color: Tx.muted, label: 'Política de privacidad', onTap: () => openInApp(context, AppConfig.web('legal.php?doc=privacidad'))),
          SettingsRow(icon: CupertinoIcons.info_circle, color: Tx.muted, label: 'Política de cookies', onTap: () => openInApp(context, AppConfig.web('legal.php?doc=cookies'))),
          SettingsRow(icon: CupertinoIcons.sparkles, color: Tx.accent, label: 'Ver la bienvenida otra vez', onTap: () => context.read<AppState>().replayIntro()),
        ]),
        SettingsGroup(children: [
          SettingsRow(icon: CupertinoIcons.square_arrow_right, color: Tx.danger, label: 'Cerrar sesión', destructive: true, onTap: _logout),
        ]),
        SettingsGroup(title: 'Zona delicada', children: [
          SettingsRow(icon: CupertinoIcons.pause_circle, color: Tx.warning, label: 'Desactivar cuenta', onTap: _deactivate),
          if (!me.isAdmin) SettingsRow(icon: CupertinoIcons.trash_fill, color: Tx.danger, label: 'Eliminar cuenta', destructive: true, onTap: () => _delete(me)),
        ]),
        const SizedBox(height: 28),
        const Center(child: TrevixLogo(size: 34)),
        const SizedBox(height: 8),
        Center(child: Text('TREVIX para ${Platform.isIOS ? 'iOS' : 'Android'} · versión 1.0', style: Tx.body(12, color: Tx.subtle))),
      ]),
    );
  }
}
