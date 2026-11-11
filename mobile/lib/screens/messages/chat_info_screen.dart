import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/e2ee.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/chat_wallpaper.dart';
import '../../widgets/common.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/settings_tiles.dart';
import 'chat_storage_screens.dart';
import 'chat_style.dart';
import 'e2ee_screens.dart';
import 'group_screens.dart';

/// Lo que el chat debe hacer al volver de la información.
class ChatInfoResult {
  const ChatInfoResult({this.search = false, this.jumpTo, this.left = false});

  final bool search;
  final int? jumpTo;
  final bool left;
}

/// Información del chat (como en Messenger): personalizar, mensajes temporales, cifrado, contenido,
/// almacenamiento y, en los grupos, miembros, enlace, solicitudes y ajustes del administrador.
class ChatInfoScreen extends StatefulWidget {
  const ChatInfoScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late Conversation _c = widget.conversation;
  int _requests = 0;

  ChatOptions get _options => _c.options ?? ChatOptions();
  GroupInfo? get _g => _c.group;
  bool get _admin => _g?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final res = await api.get('conversations/${_c.id}');
      if (!mounted) return;
      setState(() => _c = Conversation.fromJson(res.map));
      if (_c.isGroup && _admin) {
        final members = await api.get('groups/${_c.id}/members');
        if (mounted) setState(() => _requests = asInt(members.meta['requests']));
      }
    } catch (_) {}
  }

  /// Respuesta {message, conversation} de las rutas de grupos: avisa y vuelve a cargar (con las opciones del chat).
  void _applyGroup(ApiResponse res) {
    final message = res.map['message'];
    if (message != null) toast(context, '$message');
    _reload();
  }

  Future<void> _patchConversation(Map<String, dynamic> body) async {
    try {
      final res = await api.patch('conversations/${_c.id}', body);
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Guardado.')}');
      _reload();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _patchGroup(Map<String, dynamic> body) async {
    try {
      final res = await api.patch('groups/${_c.id}', body);
      if (mounted) _applyGroup(res);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  // ---- Personalizar ----

  void _chooseTheme() {
    if (_c.isGroup && !_admin) {
      toast(context, tr('Solo los administradores cambian el estilo del grupo.'), error: true);
      return;
    }
    final themes = _options.themes.isEmpty ? const [MapEntry('trevix', 'TREVIX')] : _options.themes;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('Tema del chat'), style: Tx.display(18), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(_c.isGroup ? tr('Lo verán todos los miembros del grupo.') : tr('Lo verán los dos en este chat.'),
              style: Tx.body(13, color: Tx.muted), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(spacing: 14, runSpacing: 16, alignment: WrapAlignment.center, children: [
            for (final t in themes)
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  if (t.key == _c.theme) return;
                  _c.isGroup ? _patchGroup({'theme': t.key}) : _patchConversation({'theme': t.key});
                },
                child: SizedBox(
                  width: 70,
                  child: Column(children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: ChatPalette.of(t.key).gradient,
                        border: Border.all(color: t.key == _c.theme ? Tx.text : Colors.transparent, width: 3),
                      ),
                      child: t.key == _c.theme ? const Icon(CupertinoIcons.checkmark_alt, color: Colors.white) : null,
                    ),
                    const SizedBox(height: 6),
                    Text(t.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: t.key == _c.theme ? Tx.text : Tx.muted)),
                  ]),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  void _chooseWallpaper() {
    if (_c.isGroup && !_admin) {
      toast(context, tr('Solo los administradores cambian el fondo del grupo.'), error: true);
      return;
    }
    final wallpapers = _options.wallpapers.isEmpty ? [MapEntry('default', tr('Predeterminado'))] : _options.wallpapers;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr('Fondo del chat'), style: Tx.display(18), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(_c.isGroup ? tr('Lo verán todos los miembros del grupo.') : tr('Lo verán los dos en este chat.'),
                style: Tx.body(13, color: Tx.muted), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 14, alignment: WrapAlignment.center, children: [
              for (final w in wallpapers)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (w.key != _c.wallpaper) _patchConversation({'wallpaper': w.key});
                  },
                  child: SizedBox(
                    width: 72,
                    child: Column(children: [
                      ChatWallpaper.swatch(w.key, size: 66, selected: w.key == _c.wallpaper),
                      const SizedBox(height: 5),
                      Text(w.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: w.key == _c.wallpaper ? Tx.accent : Tx.muted)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _editNickname() async {
    final value = await prompt(
      context,
      tr('Apodo'),
      message: tr('Solo tú verás el apodo de @{username} en este chat. Déjalo vacío para quitarlo.', {'username': _c.user.username}),
      hint: _c.user.displayName,
      initial: _c.nickname ?? '',
      maxLength: _options.nicknameMax,
      required: false,
    );
    if (value != null) _patchConversation({'nickname': value});
  }

  void _chooseDisappear() {
    if (_c.isGroup && !_admin) {
      toast(context, tr('Solo los administradores cambian los mensajes temporales del grupo.'), error: true);
      return;
    }
    final options = _options.disappear.isEmpty ? [MapEntry(0, tr('Desactivados')), MapEntry(86400, tr('24 horas'))] : _options.disappear;
    actionSheet(
      context,
      [
        for (final o in options)
          SheetAction(o.value, o.key == _c.disappearSeconds ? CupertinoIcons.checkmark_alt : CupertinoIcons.timer, () {
            if (o.key == _c.disappearSeconds) return;
            _c.isGroup ? _patchGroup({'disappear_seconds': o.key}) : _patchConversation({'disappear_seconds': o.key});
          }),
      ],
      title: tr('Mensajes temporales: los nuevos mensajes desaparecen después del tiempo elegido.'),
    );
  }

  Future<void> _toggleMute() => _patchConversation({'muted': !_c.muted});

  // ---- Privado ----

  Future<void> _toggleBlock() async {
    if (!_c.available) return;
    final blocking = !_c.blockedByMe;
    if (blocking &&
        !await confirm(context, tr('Bloquear a @{username}', {'username': _c.user.username}), tr('No podrá escribirte, ver tu perfil ni encontrarte. No le avisaremos.'),
            action: tr('Bloquear'), destructive: true)) {
      return;
    }
    try {
      final res = blocking ? await api.post('users/${_c.user.id}/block') : await api.delete('users/${_c.user.id}/block');
      if (mounted) toast(context, '${res.map['message'] ?? (blocking ? tr('Bloqueaste la cuenta.') : tr('Desbloqueaste la cuenta.'))}');
      _reload();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  // ---- Grupo ----

  void _shareInvite() {
    final url = _g?.inviteUrl;
    if (url == null) return;
    actionSheet(
        context,
        [
          SheetAction(tr('Copiar enlace'), CupertinoIcons.doc_on_doc, () {
            Clipboard.setData(ClipboardData(text: url));
            toast(context, tr('Enlace copiado.'));
          }),
          SheetAction(tr('Compartir enlace'), CupertinoIcons.share, () => Share.share(tr('Únete a «{group}» en TREVIX: {url}', {'group': _c.title, 'url': url}))),
          if (_admin)
            SheetAction(tr('Restablecer enlace'), CupertinoIcons.arrow_2_circlepath, () async {
              if (!await confirm(context, tr('Restablecer enlace'), tr('El enlace actual dejará de funcionar.'), action: tr('Restablecer'), destructive: true)) return;
              try {
                final res = await api.post('groups/${_c.id}/invite');
                if (mounted) _applyGroup(res);
              } catch (e) {
                if (mounted) toastError(context, e);
              }
            }, destructive: true),
        ],
        title: url);
  }

  Future<void> _addMembers() async {
    final people = await pickPeople(context, title: tr('Añadir al grupo'));
    if (people == null || people.isEmpty || !mounted) return;
    try {
      final res = await api.post('groups/${_c.id}/members', {'members': people.map((u) => u.username).toList()});
      if (!mounted) return;
      _applyGroup(res);
      final failed = asMap(res.map['failed']);
      if (failed.isNotEmpty) toast(context, tr('No se añadió a @{user}: {error}', {'user': failed.keys.first, 'error': failed.values.first}), error: true);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _leave() async {
    final owner = _g?.isOwner ?? false;
    if (!await confirm(
      context,
      tr('Salir del grupo'),
      owner
          ? tr('Eres el creador: otro administrador (o el miembro más antiguo) quedará a cargo del grupo.')
          : tr('Dejarás de recibir los mensajes de «{group}».', {'group': _c.title}),
      action: tr('Salir del grupo'),
      destructive: true,
    )) {
      return;
    }
    try {
      final res = await api.delete('groups/${_c.id}/membership');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Saliste del grupo.')}');
      Navigator.of(context).pop(const ChatInfoResult(left: true));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  // ---- Interfaz ----

  Widget _quick(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Column(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Tx.surface2, shape: BoxShape.circle),
              child: Icon(icon, color: Tx.text, size: 21),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final g = _g;
    final palette = ChatPalette.of(c.theme);
    final disappear = _options.disappear.where((o) => o.key == c.disappearSeconds).map((o) => o.value).firstOrNull;
    final themeName = _options.themes.where((t) => t.key == c.theme).map((t) => t.value).firstOrNull ?? 'TREVIX';
    return Scaffold(
      appBar: const GlassBar(title: ''),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
          if (g?.coverUrl != null) NetImage(g!.coverUrl, height: 150, width: double.infinity),
          SizedBox(height: g?.coverUrl != null ? 0 : 18),
          Transform.translate(
            offset: Offset(0, g?.coverUrl != null ? -44 : 0),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Tx.bg, shape: BoxShape.circle),
                child: ChatAvatar(conversation: c, size: 92),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(c.title, textAlign: TextAlign.center, style: Tx.display(22)),
              ),
              const SizedBox(height: 4),
              Text(
                c.isGroup ? '${g?.isPublic == true ? tr('Grupo público') : tr('Grupo privado')} · ${plural(g?.membersCount ?? 0, 'miembro', 'miembros')}' : '@${c.user.username}',
                style: Tx.body(13.5, color: Tx.muted),
              ),
              if (c.e2ee || e2ee.ready) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => push(context, SecurityCodeScreen(conversationId: c.id, title: c.title)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(c.e2ee ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open, size: 13, color: c.e2ee ? palette.accent : Tx.subtle),
                      const SizedBox(width: 6),
                      Text(c.e2ee ? tr('Cifrado de extremo a extremo') : tr('Aún sin cifrar'), style: Tx.body(12.5, weight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  if (!c.isGroup && c.available) _quick(CupertinoIcons.person_fill, tr('Perfil'), () => openProfile(context, c.user.username)),
                  if (c.isGroup && _admin) _quick(CupertinoIcons.person_add_solid, tr('Añadir'), _addMembers),
                  _quick(c.muted ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash_fill, c.muted ? tr('Reactivar') : tr('Silenciar'), _toggleMute),
                  _quick(CupertinoIcons.search, tr('Buscar'), () => Navigator.of(context).pop(const ChatInfoResult(search: true))),
                  if (c.isGroup && g?.inviteUrl != null) _quick(CupertinoIcons.link, tr('Invitar'), _shareInvite),
                ]),
              ),
              if (c.isGroup && (g?.description ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Text(g!.description, textAlign: TextAlign.center, style: Tx.body(14.5, color: Tx.text, height: 1.4)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SettingsGroup(title: tr('Personalizar'), children: [
                SettingsRow(
                  icon: CupertinoIcons.circle_lefthalf_fill,
                  color: palette.accent,
                  label: tr('Tema'),
                  value: themeName,
                  onTap: _chooseTheme,
                ),
                SettingsRow(
                  icon: CupertinoIcons.photo_fill_on_rectangle_fill,
                  color: Tx.blue,
                  label: tr('Fondo'),
                  value: _options.wallpapers.where((w) => w.key == c.wallpaper).map((w) => w.value).firstOrNull ?? '',
                  onTap: _chooseWallpaper,
                ),
                if (!c.isGroup) SettingsRow(icon: CupertinoIcons.textformat, color: Tx.pink, label: tr('Apodo'), value: c.nickname ?? '', onTap: _editNickname),
              ]),
              SettingsGroup(title: tr('Privacidad y ayuda'), children: [
                SettingsRow(
                  icon: CupertinoIcons.timer,
                  color: Tx.purple,
                  label: tr('Mensajes temporales'),
                  value: c.disappearSeconds > 0 ? (disappear ?? tr('Activados')) : tr('Desactivados'),
                  onTap: c.available && !c.blocked ? _chooseDisappear : null,
                ),
                SettingsRow(
                  icon: CupertinoIcons.lock_shield_fill,
                  color: Tx.success,
                  label: tr('Cifrado de extremo a extremo'),
                  subtitle: c.e2ee ? tr('Ver código de seguridad') : tr('Se activa cuando todos usan la app'),
                  onTap: () => push(context, SecurityCodeScreen(conversationId: c.id, title: c.title)),
                ),
              ]),
              if (c.isGroup)
                SettingsGroup(title: tr('Grupo'), children: [
                  SettingsRow(
                    icon: CupertinoIcons.person_3_fill,
                    color: Tx.blue,
                    label: tr('Miembros'),
                    value: '${g?.membersCount ?? 0}',
                    onTap: () async {
                      await push(context, GroupMembersScreen(conversation: c));
                      _reload();
                    },
                  ),
                  if (_admin)
                    SettingsRow(
                      icon: CupertinoIcons.person_crop_circle_badge_plus,
                      color: Tx.warning,
                      label: tr('Solicitudes para unirse'),
                      trailing: _requests > 0 ? CountBadge(_requests) : null,
                      value: _requests > 0 ? null : tr('Ninguna'),
                      onTap: () async {
                        await push(context, GroupRequestsScreen(conversationId: c.id));
                        _reload();
                      },
                    ),
                  if (g?.inviteUrl != null) SettingsRow(icon: CupertinoIcons.link, color: Tx.cyan, label: tr('Enlace de invitación'), onTap: _shareInvite),
                  if (_admin)
                    SettingsRow(
                      icon: CupertinoIcons.slider_horizontal_3,
                      color: Tx.purple,
                      label: tr('Ajustes del grupo'),
                      subtitle: tr('Nombre, descripción, foto, portada y privacidad'),
                      onTap: () async {
                        await push(context, GroupEditScreen(conversation: c));
                        _reload();
                      },
                    ),
                ]),
              SettingsGroup(title: tr('Contenido'), children: [
                SettingsRow(
                  icon: CupertinoIcons.photo_on_rectangle,
                  color: Tx.pink,
                  label: tr('Contenido enviado'),
                  subtitle: tr('Fotos, notas de voz, GIF y enlaces'),
                  onTap: () async {
                    final jump = await push<int>(context, SharedContentScreen(conversation: c));
                    if (jump != null && context.mounted) Navigator.of(context).pop(ChatInfoResult(jumpTo: jump));
                  },
                ),
                SettingsRow(
                  icon: CupertinoIcons.archivebox_fill,
                  color: Tx.warning,
                  label: tr('Almacenamiento del chat'),
                  onTap: () => push(context, ConversationStorageScreen(conversation: c)),
                ),
              ]),
              SettingsGroup(children: [
                if (c.isGroup)
                  SettingsRow(icon: CupertinoIcons.square_arrow_left, color: Tx.danger, label: tr('Salir del grupo'), destructive: true, onTap: _leave)
                else if (c.available) ...[
                  SettingsRow(
                    icon: CupertinoIcons.nosign,
                    color: Tx.danger,
                    label: c.blockedByMe ? tr('Desbloquear a @{username}', {'username': c.user.username}) : tr('Bloquear'),
                    destructive: !c.blockedByMe,
                    onTap: _toggleBlock,
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.flag_fill,
                    color: Tx.danger,
                    label: tr('Reportar'),
                    destructive: true,
                    onTap: () => showReportSheet(context, 'user', c.user.id),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
