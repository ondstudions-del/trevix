import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/paged.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_view.dart';
import '../../widgets/user_tile.dart';

/// Cambiar el usuario o el correo (pide la contraseña actual).
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  late final Me _me = context.read<AppState>().me!;
  late final _username = TextEditingController(text: _me.username);
  late final _email = TextEditingController(text: _me.email);
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final state = context.read<AppState>();
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final res = await api.patch('me/account', {
        'username': _username.text.trim().replaceFirst('@', '').toLowerCase(),
        'email': _email.text.trim(),
        'current_password': _password.text,
      });
      if (!mounted) return;
      if (res.map['user'] is Map) state.setMe(asMap(res.map['user']));
      final warning = asStrOrNull(res.map['warning']);
      toast(context, warning ?? '${res.map['message'] ?? 'Guardado.'}', error: warning != null);
      if (asBool(res.map['changed'])) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors = e.fields.isEmpty ? {'form': e.message} : e.fields);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassBar(title: 'Usuario y correo'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 60), children: [
        if (_errors['form'] != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger))),
        TextField(
          controller: _username,
          autocorrect: false,
          maxLength: 30,
          style: Tx.body(16),
          decoration: fieldDecoration('usuario', label: 'Nombre de usuario', error: _errors['username'], prefix: Icon(CupertinoIcons.at, color: Tx.subtle, size: 19)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _email,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          style: Tx.body(16),
          decoration: fieldDecoration('tu@correo.com', label: 'Correo electrónico', error: _errors['email'], prefix: Icon(CupertinoIcons.envelope, color: Tx.subtle, size: 19)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
          child: Text('Si cambias el correo, te enviaremos un enlace para confirmarlo.', style: Tx.body(12.5, color: Tx.subtle)),
        ),
        TextField(
          controller: _password,
          obscureText: !_show,
          style: Tx.body(16),
          decoration: fieldDecoration(
            'Contraseña actual',
            label: 'Contraseña actual',
            error: _errors['current_password'],
            suffix: IconButton(
              onPressed: () => setState(() => _show = !_show),
              icon: Icon(_show ? CupertinoIcons.eye_slash : CupertinoIcons.eye, color: Tx.subtle, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 22),
        GradientButton(label: 'Guardar cambios', loading: _busy, onPressed: _save),
      ]),
    );
  }
}

/// Cambiar la contraseña (cierra las demás sesiones).
class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final min = context.read<AppState>().passwordMin;
    final local = <String, String>{};
    if (_password.text.length < min) local['password'] = 'Usa al menos $min caracteres.';
    if (_password.text != _confirm.text) local['password_confirmation'] = 'Las contraseñas no coinciden.';
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final res = await api.put('me/password', {
        'current_password': _current.text,
        'password': _password.text,
        'password_confirmation': _confirm.text,
      });
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Tu contraseña se actualizó.'}');
      Navigator.pop(context);
      return;
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors = e.fields.isEmpty ? {'form': e.message} : e.fields);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final min = context.read<AppState>().passwordMin;
    final eye = IconButton(
      onPressed: () => setState(() => _show = !_show),
      icon: Icon(_show ? CupertinoIcons.eye_slash : CupertinoIcons.eye, color: Tx.subtle, size: 20),
    );
    return Scaffold(
      appBar: const GlassBar(title: 'Contraseña'),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 60), children: [
        if (_errors['form'] != null)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_errors['form']!, style: Tx.body(14, color: Tx.danger))),
        TextField(
          controller: _current,
          obscureText: !_show,
          style: Tx.body(16),
          decoration: fieldDecoration('Contraseña actual', label: 'Contraseña actual', error: _errors['current_password'], suffix: eye),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: !_show,
          style: Tx.body(16),
          decoration: fieldDecoration('Mínimo $min caracteres', label: 'Nueva contraseña', error: _errors['password']),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirm,
          obscureText: !_show,
          style: Tx.body(16),
          decoration: fieldDecoration('Repite la contraseña', label: 'Confirmar contraseña', error: _errors['password_confirmation']),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 22),
          child: Text('Al cambiarla cerraremos la sesión en tus otros dispositivos.', style: Tx.body(12.5, color: Tx.subtle)),
        ),
        GradientButton(label: 'Cambiar contraseña', loading: _busy, onPressed: _save),
      ]),
    );
  }
}

/// Dispositivos con la sesión abierta en la app.
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  List<SessionItem>? _items;
  Object? _error;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('auth/sessions');
      if (mounted) {
        setState(() {
          _items = res.list.map(SessionItem.fromJson).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _revoke(SessionItem s) async {
    if (!await confirm(context, 'Cerrar sesión en «${s.name}»', s.current ? 'Es este dispositivo: volverás al inicio de sesión.' : 'Tendrá que volver a iniciar sesión.',
        action: 'Cerrar', destructive: true)) {
      return;
    }
    if (!mounted) return;
    final state = context.read<AppState>();
    setState(() => _busy = s.id);
    try {
      final res = await api.delete('auth/sessions/${s.id}');
      if (asBool(res.map['current'])) {
        state.signedOutRemotely();
        return;
      }
      if (mounted) toast(context, '${res.map['message'] ?? 'Cerraste esa sesión.'}');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _logoutOthers() async {
    final password = await prompt(context, 'Cerrar las demás sesiones', hint: 'Contraseña', action: 'Cerrar sesiones', obscure: true, maxLength: 200,
        message: 'Se cerrará la sesión en todos tus otros dispositivos, en la web y en la app.');
    if (password == null || !mounted) return;
    try {
      final res = await api.post('auth/sessions/logout-others', {'password': password});
      if (mounted) toast(context, '${res.map['message'] ?? 'Listo.'}');
      await _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: const GlassBar(title: 'Sesiones activas'),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : items == null
              ? const Loading()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Tx.accentSoft,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 60), children: [
                    for (final s in items)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Tx.surface1,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: s.current ? Tx.alpha(Tx.purple500, .5) : Tx.border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(gradient: s.current ? Tx.brand : null, color: s.current ? null : Tx.surface3, shape: BoxShape.circle),
                            child: Icon(CupertinoIcons.device_phone_portrait, color: s.current ? Colors.white : Tx.muted, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600))),
                                if (s.current) ...[
                                  const SizedBox(width: 6),
                                  Text('· Este dispositivo', style: Tx.body(12.5, weight: FontWeight.w600, color: Tx.accent)),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (s.lastUsedAt != null) 'Activa ${timeAgo(s.lastUsedAt)}',
                                  if (s.lastIp != null) s.lastIp!,
                                  if (s.createdAt != null) 'desde ${fullDate(s.createdAt)}',
                                ].join(' · '),
                                style: Tx.body(12.5, color: Tx.muted),
                              ),
                            ]),
                          ),
                          if (_busy == s.id)
                            const CupertinoActivityIndicator()
                          else
                            IconButton(onPressed: () => _revoke(s), icon: Icon(CupertinoIcons.xmark_circle, color: Tx.muted)),
                        ]),
                      ),
                    const SizedBox(height: 10),
                    SoftButton(label: 'Cerrar las demás sesiones', icon: CupertinoIcons.square_arrow_right, color: Tx.danger, expand: true, height: 46, onPressed: _logoutOthers),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('Esta lista muestra las sesiones de la app. Las sesiones de la web también se cierran con el botón.',
                          textAlign: TextAlign.center, style: Tx.body(12, color: Tx.subtle)),
                    ),
                  ]),
                ),
    );
  }
}

/// Cuentas bloqueadas.
class BlockedPage extends StatefulWidget {
  const BlockedPage({super.key});

  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  List<User>? _users;
  Object? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('me/blocked');
      if (mounted) {
        setState(() {
          _users = res.list.map(User.fromJson).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _unblock(User u) async {
    setState(() => _busy.add(u.id));
    try {
      final res = await api.delete('users/${u.id}/block');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? 'Desbloqueaste a @${u.username}.'}');
      setState(() => _users?.removeWhere((x) => x.id == u.id));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(u.id));
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: const GlassBar(title: 'Cuentas bloqueadas'),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : users == null
              ? const Loading()
              : users.isEmpty
                  ? const EmptyState(icon: CupertinoIcons.nosign, title: 'No bloqueaste a nadie', message: 'Las cuentas que bloquees aparecerán aquí.')
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 60),
                      itemCount: users.length,
                      itemBuilder: (_, i) {
                        final u = users[i];
                        return UserTile(
                          user: u,
                          subtitle: u.extraDate != null ? '@${u.username} · desde ${timeAgo(u.extraDate)}' : '@${u.username}',
                          trailing: _busy.contains(u.id)
                              ? const CupertinoActivityIndicator()
                              : SoftButton(label: 'Desbloquear', height: 36, onPressed: () => _unblock(u)),
                        );
                      },
                    ),
    );
  }
}

/// Publicaciones guardadas (solo las ve su dueño).
class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends State<SavedPage> {
  final Paged<Post> _list = Paged<Post>('me/saved', Post.fromJson);

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassBar(title: 'Guardados'),
      body: PagedView<Post>(
        paged: _list,
        header: const [SliverToBoxAdapter(child: SizedBox(height: 10))],
        empty: const EmptyState(icon: CupertinoIcons.bookmark, title: 'Nada guardado', message: 'Toca el marcador de una publicación para guardarla aquí.'),
        itemBuilder: postBuilder(_list),
      ),
    );
  }
}
