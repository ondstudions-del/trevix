import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/e2ee.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/private_chats.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/settings_tiles.dart';
import 'chat_screen.dart';
import 'inbox_screen.dart';

final _pinPattern = RegExp(r'^\d{4,8}$');

/// Campo de las hojas de PIN; [key] es el nombre del campo en la API (para mostrar ahí su error).
class _Field {
  const _Field(this.key, this.label, {this.pin = true});

  final String key;
  final String label;
  final bool pin;
}

/// Hoja con uno o varios PIN (o la contraseña). [submit] recibe lo escrito; si lanza un error, se muestra en la hoja
/// sin cerrarla. Devuelve lo que devolvió [submit], o null si se cerró.
Future<T?> _secretSheet<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<_Field> fields,
  required String action,
  bool destructive = false,
  required Future<T> Function(Map<String, String> values) submit,
}) =>
    showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SecretSheet<T>(title: title, message: message, fields: fields, action: action, destructive: destructive, submit: submit),
    );

class _SecretSheet<T> extends StatefulWidget {
  const _SecretSheet({
    required this.title,
    required this.message,
    required this.fields,
    required this.action,
    required this.destructive,
    required this.submit,
  });

  final String title;
  final String? message;
  final List<_Field> fields;
  final String action;
  final bool destructive;
  final Future<T> Function(Map<String, String> values) submit;

  @override
  State<_SecretSheet<T>> createState() => _SecretSheetState<T>();
}

class _SecretSheetState<T> extends State<_SecretSheet<T>> {
  late final Map<String, TextEditingController> _controllers = {for (final f in widget.fields) f.key: TextEditingController()};
  Map<String, String> _errors = {};
  String? _error;
  bool _busy = false;

  bool get _valid => widget.fields.every((f) {
        final v = _controllers[f.key]!.text;
        return f.pin ? _pinPattern.hasMatch(v) : v.isNotEmpty;
      });

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _errors = {};
      _error = null;
    });
    try {
      final result = await widget.submit({for (final e in _controllers.entries) e.key: e.value.text});
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      final fields = e is ApiException ? {for (final f in widget.fields) if (e.field(f.key) != null) f.key: e.field(f.key)!} : <String, String>{};
      setState(() {
        _busy = false;
        _errors = fields;
        _error = fields.isEmpty ? errorText(e) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.fields;
    return SheetFrame(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.title, style: Tx.display(18)),
          if (widget.message != null) ...[
            const SizedBox(height: 6),
            Text(widget.message!, style: Tx.body(14, color: Tx.muted, height: 1.35)),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            TextField(
              controller: _controllers[fields[i].key],
              autofocus: i == 0,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              keyboardType: fields[i].pin ? TextInputType.number : TextInputType.visiblePassword,
              inputFormatters: fields[i].pin ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)] : [LengthLimitingTextInputFormatter(200)],
              textInputAction: i == fields.length - 1 ? TextInputAction.done : TextInputAction.next,
              onChanged: (_) => setState(() {}),
              onSubmitted: i == fields.length - 1 ? (_) => _submit() : null,
              style: Tx.body(16, weight: fields[i].pin ? FontWeight.w700 : FontWeight.w400).copyWith(letterSpacing: fields[i].pin ? 4 : 0),
              decoration: fieldDecoration(fields[i].label, error: _errors[fields[i].key]),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: Tx.body(13.5, color: Tx.danger)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _valid && !_busy ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: widget.destructive ? Tx.danger : Tx.purple,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(widget.action, style: Tx.body(16, weight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Pide el PIN y desbloquea los chats privados (abrir un chat privado desde un aviso o un perfil, ajustes).
Future<bool> unlockPrivateChats(BuildContext context, {String? message}) async {
  final token = await _secretSheet<String>(
    context,
    title: tr('Chats privados'),
    message: message ?? tr('Escribe tu PIN para abrir tus chats privados.'),
    fields: [_Field('pin', tr('PIN'))],
    action: tr('Abrir'),
    submit: (v) async => asStr((await api.post('me/private-chats/unlock', {'pin': v['pin']})).map['token']),
  );
  if (token == null || token.isEmpty) return false;
  privateChats.unlock(token);
  return true;
}

/// Crea el PIN de los chats privados. true si se creó.
Future<bool> createPrivatePin(BuildContext context) async {
  final message = await _secretSheet<String>(
    context,
    title: tr('Crea el PIN de tus chats privados'),
    message: tr('De 4 a 8 números. Para ver tus chats privados, escríbelo en el buscador de los chats.'),
    fields: [_Field('pin', tr('PIN nuevo')), _Field('pin_confirmation', tr('Repite el PIN'))],
    action: tr('Crear PIN'),
    submit: (v) async => asStr((await api.put('me/private-chats/pin', v)).map['message']),
  );
  if (message == null) return false;
  if (context.mounted) toast(context, message);
  return true;
}

/// Antes de pasar un chat a privados: si aún no hay PIN, lo crea. true si ya hay PIN.
Future<bool> ensurePrivatePin(BuildContext context) async {
  final res = await api.get('me/private-chats');
  if (asBool(res.map['has_pin'])) return true;
  if (!context.mounted) return false;
  return createPrivatePin(context);
}

/// Los chats privados, abiertos con el PIN escrito en el buscador. Al salir se vuelven a bloquear.
class PrivateChatsScreen extends StatefulWidget {
  const PrivateChatsScreen({super.key, this.initial = const []});

  final List<Conversation> initial;

  @override
  State<PrivateChatsScreen> createState() => _PrivateChatsScreenState();
}

class _PrivateChatsScreenState extends State<PrivateChatsScreen> {
  late List<Conversation> _items = widget.initial;
  late bool _loaded = widget.initial.isNotEmpty;
  Object? _error;
  Timer? _poll;
  bool _loading = false;
  bool _closed = false;
  final Set<int> _selected = {};
  bool _busy = false;
  ModalRoute<dynamic>? _route;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    privateChats.unlocked.addListener(_onLockChanged);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _refresh(silent: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    _poll?.cancel();
    privateChats.unlocked.removeListener(_onLockChanged);
    privateChats.lock();
    super.dispose();
  }

  void _onLockChanged() {
    if (!privateChats.unlocked.value) _close();
  }

  /// Se bloquearon (segundo plano, cambio de PIN, cuenta): cierra esta lista y lo que se abrió encima.
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    final route = _route;
    final nav = Navigator.of(context);
    if (route != null && route.isActive) {
      nav.popUntil((r) => r == route);
      nav.pop();
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_loading || _closed) return;
    _loading = true;
    try {
      final res = await api.get('conversations', {'private': 1});
      if (!mounted) return;
      final renewed = asStrOrNull(res.meta['private_token']);
      if (renewed != null && renewed.isNotEmpty) api.privateToken = renewed;
      setState(() {
        _items = res.list.map(Conversation.fromJson).toList();
        _selected.retainAll(_items.map((c) => c.id));
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (e is ApiException && e.status == 423) {
        privateChats.lock();
      } else if (mounted && !silent) {
        setState(() => _error = e);
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _open(Conversation c) async {
    await push(context, ChatScreen(conversationId: c.id, user: c.user, conversation: c));
    _refresh(silent: true);
  }

  void _toggle(Conversation c) => setState(() => _selected.contains(c.id) ? _selected.remove(c.id) : _selected.add(c.id));

  Future<void> _bulk(String action) async {
    final chosen = _items.where((c) => _selected.contains(c.id)).toList();
    if (chosen.isEmpty || _busy) return;
    final many = chosen.length > 1;
    if (action == 'delete') {
      final ok = await confirm(
        context,
        many ? tr('¿Eliminar {n} chats?', {'n': chosen.length}) : tr('¿Eliminar este chat?'),
        tr('Se borrarán sus mensajes solo para ti. Si te vuelven a escribir, aparecerá de nuevo entre tus chats privados.'),
        action: tr('Eliminar'),
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final res = await api.post('conversations/bulk', {'ids': chosen.map((c) => c.id).toList(), 'action': action});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Listo.')}');
      setState(_selected.clear);
      await _refresh(silent: true);
      if (mounted) context.read<AppState>().refreshCounts();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _selectionBar() {
    final chosen = _items.where((c) => _selected.contains(c.id)).toList();
    final allMuted = chosen.isNotEmpty && chosen.every((c) => c.muted);
    final enabled = chosen.isNotEmpty && !_busy;
    Widget item(IconData icon, String label, String action, {bool danger = false}) => Expanded(
          child: InboxBarAction(icon: icon, label: label, danger: danger, onTap: enabled ? () => _bulk(action) : null),
        );
    return Container(
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            item(CupertinoIcons.lock_open, tr('Quitar de privados'), 'unprivate'),
            item(allMuted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, allMuted ? tr('Reactivar') : tr('Silenciar'), allMuted ? 'unmute' : 'mute'),
            item(CupertinoIcons.checkmark_circle, tr('Leído'), 'read'),
            item(CupertinoIcons.trash, tr('Eliminar'), 'delete', danger: true),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting
            ? GlassBar(
                leading: CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onPressed: () => setState(_selected.clear),
                  child: Icon(CupertinoIcons.xmark, color: Tx.text, size: 24),
                ),
                titleWidget:
                    Text(_selected.length == 1 ? tr('1 seleccionado') : tr('{n} seleccionados', {'n': _selected.length}), style: Tx.display(18, weight: FontWeight.w700)),
              )
            : GlassBar(
                title: tr('Chats privados'),
                actions: [
                  IconButton(
                    tooltip: tr('Ajustes de los chats privados'),
                    onPressed: () => push(context, const PrivateChatSettingsScreen()),
                    icon: Icon(CupertinoIcons.gear, color: Tx.text),
                  ),
                ],
              ),
        bottomNavigationBar: _selecting ? _selectionBar() : null,
        body: _error != null && !_loaded
            ? ErrorState(error: _error!, onRetry: _refresh)
            : !_loaded
                ? const Loading()
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: _items.isEmpty
                        ? ListView(children: [
                            SizedBox(
                              height: 420,
                              child: EmptyState(
                                icon: CupertinoIcons.lock,
                                title: tr('Sin chats privados'),
                                message: tr('Mantén pulsado un chat en tu bandeja y toca «Privado» para esconderlo aquí.'),
                              ),
                            ),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 6, bottom: 30),
                            itemCount: _items.length,
                            itemBuilder: (context, i) {
                              final c = _items[i];
                              return ConversationTile(
                                conversation: c,
                                term: '',
                                selecting: _selecting,
                                selected: _selected.contains(c.id),
                                onTap: () => _selecting ? _toggle(c) : _open(c),
                                onLongPress: () {
                                  HapticFeedback.selectionClick();
                                  _toggle(c);
                                },
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}

/// Ajustes › Chats privados: PIN, exportar, vaciar, olvidé mi PIN y desactivar.
class PrivateChatSettingsScreen extends StatefulWidget {
  const PrivateChatSettingsScreen({super.key});

  @override
  State<PrivateChatSettingsScreen> createState() => _PrivateChatSettingsScreenState();
}

class _PrivateChatSettingsScreenState extends State<PrivateChatSettingsScreen> {
  bool? _hasPin;
  Object? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final res = await api.get('me/private-chats');
      if (mounted) setState(() => _hasPin = asBool(res.map['has_pin']));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    if (await createPrivatePin(context)) _load();
  }

  Future<void> _changePin() async {
    final result = await _secretSheet<ApiResponse>(
      context,
      title: tr('Cambiar PIN'),
      message: tr('Tus chats privados se abrirán con el PIN nuevo.'),
      fields: [_Field('current_pin', tr('PIN actual')), _Field('pin', tr('PIN nuevo')), _Field('pin_confirmation', tr('Repite el PIN'))],
      action: tr('Cambiar PIN'),
      submit: (v) => api.put('me/private-chats/pin', v),
    );
    if (result == null || !mounted) return;
    if (privateChats.unlocked.value) privateChats.unlock(asStr(result.map['token']));
    toast(context, asStr(result.map['message']));
  }

  /// Acciones que piden los chats desbloqueados: si no lo están, pide el PIN y los vuelve a bloquear al terminar.
  Future<T?> _withUnlock<T>(Future<T> Function() run) async {
    final wasUnlocked = privateChats.unlocked.value;
    if (!wasUnlocked && !await unlockPrivateChats(context)) return null;
    try {
      return await run();
    } finally {
      if (!wasUnlocked) privateChats.lock();
    }
  }

  Future<void> _export() async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final path = await _withUnlock(() async => _writeExport(await api.post('me/private-chats/export')));
      if (path != null && mounted) await _share(path);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _empty() async {
    final ok = await confirm(
      context,
      tr('¿Vaciar tus chats privados?'),
      tr('Se borrarán todos sus mensajes solo para ti y desaparecerán de la lista. Si te vuelven a escribir, aparecerán de nuevo entre tus chats privados.'),
      action: tr('Vaciar'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final res = await _withUnlock(() => api.post('me/private-chats/empty'));
      if (res != null && mounted) {
        toast(context, asStr(res.map['message']));
        context.read<AppState>().refreshCounts();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _disable() async {
    final ok = await confirm(
      context,
      tr('¿Desactivar los chats privados?'),
      tr('Tus chats privados volverán a la bandeja con todos sus mensajes y se borrará el PIN.'),
      action: tr('Desactivar'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final res = await _withUnlock(() => api.delete('me/private-chats'));
      if (res == null || !mounted) return;
      privateChats.lock();
      toast(context, asStr(res.map['message']));
      context.read<AppState>().refreshCounts();
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  /// Olvidé mi PIN: con la contraseña de la cuenta se pueden exportar; después se vacían y se crea un PIN nuevo.
  Future<void> _forgot() async {
    final ok = await confirm(
      context,
      tr('¿Olvidaste tu PIN?'),
      tr('Con la contraseña de tu cuenta puedes exportar tus chats privados. Después se vaciarán y crearás un PIN nuevo, como en los chats ocultos de WhatsApp.'),
      action: tr('Continuar'),
    );
    if (!ok || !mounted) return;
    String? password;
    bool? exportFirst;
    await actionSheet(context, title: tr('¿Exportar antes de vaciar?'), [
      SheetAction(tr('Exportar y después vaciar'), CupertinoIcons.square_arrow_up, () => exportFirst = true),
      SheetAction(tr('Vaciar sin exportar'), CupertinoIcons.trash, () => exportFirst = false, destructive: true),
    ]);
    if (exportFirst == null || !mounted) return;
    if (exportFirst!) {
      final exported = await _secretSheet<(String, String)>(
        context,
        title: tr('Exportar chats privados'),
        message: tr('Escribe la contraseña de tu cuenta.'),
        fields: [_Field('password', tr('Contraseña'), pin: false)],
        action: tr('Exportar'),
        submit: (v) async {
          final path = await _writeExport(await api.post('me/private-chats/export', {'password': v['password']}));
          return (v['password']!, path);
        },
      );
      if (exported == null || !mounted) return;
      password = exported.$1;
      await _share(exported.$2);
      if (!mounted) return;
    }
    final known = password;
    final res = await _secretSheet<ApiResponse>(
      context,
      title: tr('Vaciar y crear un PIN nuevo'),
      message: tr('Se borrarán todos los mensajes de tus chats privados solo para ti. Esto no se puede deshacer.'),
      fields: [
        if (known == null) _Field('password', tr('Contraseña de tu cuenta'), pin: false),
        _Field('pin', tr('PIN nuevo')),
        _Field('pin_confirmation', tr('Repite el PIN')),
      ],
      action: tr('Vaciar y crear PIN'),
      destructive: true,
      submit: (v) => api.post('me/private-chats/reset', {...v, 'password': known ?? v['password']}),
    );
    if (res == null || !mounted) return;
    if (privateChats.unlocked.value) privateChats.unlock(asStr(res.map['token']));
    toast(context, asStr(res.map['message']));
    context.read<AppState>().refreshCounts();
    _load();
  }

  /// Escribe la exportación en un .txt temporal; los mensajes cifrados se descifran aquí con la clave del teléfono.
  Future<String> _writeExport(ApiResponse res) async {
    final chats = res.list;
    final uid = context.read<AppState>().me?.user.id ?? 0;
    if (!e2ee.ready && uid > 0 && chats.any((c) => asList(c['messages'], (m) => m).any((m) => m['e2ee'] is Map))) {
      try {
        await e2ee.load(uid);
      } catch (_) {}
    }
    final out = StringBuffer()
      ..writeln(tr('Chats privados de TREVIX · exportados el {date}', {'date': _date(DateTime.now())}))
      ..writeln();
    for (final chat in chats) {
      final cid = asInt(chat['id']);
      out.writeln('== ${asStr(chat['title'])} ==');
      for (final m in asList(chat['messages'], (m) => m)) {
        final who = asBool(m['mine']) ? tr('Tú') : (asStrOrNull(m['sender_name']) ?? tr('Cuenta no disponible'));
        var text = asStr(m['text']);
        final sealed = m['e2ee'];
        if (sealed is Map) {
          final p = e2ee.ready
              ? await e2ee.open(cid, asInt(m['id']), asInt(sealed['epoch']), asInt(m['sender_id']), asStr(sealed['ciphertext']))
              : null;
          text = p?.summary ?? tr('Mensaje cifrado que no se pudo leer en este teléfono');
        }
        final url = asStrOrNull(m['media_url']);
        final at = asDate(m['created_at']);
        out.writeln('[${at != null ? _date(at) : ''}] $who: $text${url != null ? ' $url' : ''}');
      }
      out.writeln();
    }
    if (chats.isEmpty) out.writeln(tr('No tienes mensajes en tus chats privados.'));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/trevix-chats-privados-${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString('\uFEFF${out.toString().replaceAll('\n', '\r\n')}');
    return file.path;
  }

  Future<void> _share(String path) async {
    await Share.shareXFiles([XFile(path, mimeType: 'text/plain')], subject: tr('Chats privados de TREVIX'));
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasPin = _hasPin;
    return Scaffold(
      appBar: GlassBar(title: tr('Chats privados')),
      body: _error != null && hasPin == null
          ? ErrorState(error: _error!, onRetry: _load)
          : hasPin == null
              ? const Loading()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(gradient: hasPin ? Tx.brand : null, color: hasPin ? null : Tx.surface3, shape: BoxShape.circle),
                          child: Icon(CupertinoIcons.lock_fill, color: hasPin ? Colors.white : Tx.muted, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            tr('Esconde los chats que quieras detrás de un PIN. No salen en tu bandeja ni en la búsqueda, y sus avisos no dicen quién escribió. Para verlos, escribe tu PIN en el buscador de los chats.'),
                            style: Tx.body(13.5, color: Tx.muted, height: 1.4),
                          ),
                        ),
                      ]),
                    ),
                    if (!hasPin)
                      SettingsGroup(children: [
                        SettingsRow(icon: CupertinoIcons.number_circle_fill, color: Tx.purple, label: tr('Crear PIN'), onTap: _create),
                      ])
                    else ...[
                      SettingsGroup(children: [
                        SettingsRow(icon: CupertinoIcons.number_circle_fill, color: Tx.purple, label: tr('Cambiar PIN'), onTap: _changePin),
                        SettingsRow(
                          icon: CupertinoIcons.square_arrow_up_fill,
                          color: Tx.blue400,
                          label: tr('Exportar chats privados'),
                          subtitle: tr('Un archivo de texto con todos sus mensajes, también los cifrados.'),
                          trailing: _working ? const CupertinoActivityIndicator() : null,
                          onTap: _export,
                        ),
                        SettingsRow(icon: CupertinoIcons.text_badge_xmark, color: Tx.warning, label: tr('Vaciar chats privados'), onTap: _empty),
                      ]),
                      SettingsGroup(
                        footer: tr('Si olvidaste el PIN, con la contraseña de tu cuenta puedes exportarlos; después se vacían y creas uno nuevo.'),
                        children: [
                          SettingsRow(icon: CupertinoIcons.question_circle_fill, color: Tx.cyan, label: tr('Olvidé mi PIN'), onTap: _forgot),
                          SettingsRow(icon: CupertinoIcons.lock_open_fill, color: Tx.danger, label: tr('Desactivar chats privados'), destructive: true, onTap: _disable),
                        ],
                      ),
                    ],
                  ],
                ),
    );
  }
}
