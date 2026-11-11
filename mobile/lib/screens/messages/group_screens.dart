import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/user_tile.dart';
import 'chat_screen.dart';
import 'chat_style.dart';

// ---------------------------------------------------------------------------------------------------------------
// Elegir personas
// ---------------------------------------------------------------------------------------------------------------

/// Elegir varias personas (las que sigues o por búsqueda). Devuelve null si se cancela.
Future<List<User>?> pickPeople(BuildContext context, {String? title, String? action, Set<int> exclude = const {}}) =>
    push<List<User>>(context, _PeoplePicker(title: title ?? tr('Elegir personas'), action: action ?? tr('Listo'), exclude: exclude), fullscreen: true);

class _PeoplePicker extends StatefulWidget {
  const _PeoplePicker({required this.title, required this.action, required this.exclude});

  final String title;
  final String action;
  final Set<int> exclude;

  @override
  State<_PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<_PeoplePicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<User>? _users;
  Object? _error;
  int _request = 0;
  final Map<int, User> _selected = {};

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    try {
      final res = await api.get('messages/recipients', {if (q.isNotEmpty) 'q': q});
      final users = res.list.map(User.fromJson).where((u) => !widget.exclude.contains(u.id)).toList();
      if (id == _request && mounted) {
        setState(() {
          _users = users;
          _error = null;
        });
      }
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Scaffold(
      appBar: GlassBar(
        title: widget.title,
        leading: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar'), style: Tx.body(16, color: Tx.text)),
        ),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty ? null : () => Navigator.of(context).pop(_selected.values.toList()),
            child: Text(_selected.isEmpty ? widget.action : '${widget.action} (${_selected.length})',
                style: Tx.body(16, weight: FontWeight.w700, color: _selected.isEmpty ? Tx.subtle : Tx.accent)),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _load(v.trim()));
            },
            style: Tx.body(15),
            decoration: fieldDecoration(tr('Buscar personas'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 84,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final u in _selected.values)
                  GestureDetector(
                    onTap: () => setState(() => _selected.remove(u.id)),
                    child: SizedBox(
                      width: 66,
                      child: Column(children: [
                        Stack(clipBehavior: Clip.none, children: [
                          Avatar(user: u, size: 50),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              decoration: BoxDecoration(color: Tx.surface4, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2)),
                              child: Icon(CupertinoIcons.xmark, size: 12, color: Tx.text),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(u.displayName.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11.5, color: Tx.muted)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : users == null
                  ? const Loading()
                  : users.isEmpty
                      ? EmptyState(icon: CupertinoIcons.person_crop_circle_badge_xmark, title: tr('Sin resultados'), message: tr('Busca por nombre o usuario.'))
                      : ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (_, i) {
                            final u = users[i];
                            final on = _selected.containsKey(u.id);
                            return UserTile(
                              user: u,
                              showFollow: false,
                              onTap: () => setState(() => on ? _selected.remove(u.id) : _selected[u.id] = u),
                              trailing: Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: on ? Tx.accent : Tx.subtle, size: 24),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

Future<XFile?> _pickImage(BuildContext context) async {
  try {
    return await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 2000);
  } catch (_) {
    if (context.mounted) toast(context, tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'), error: true);
    return null;
  }
}

Widget _visibilityPicker(String value, ValueChanged<String> onChanged) {
  Widget option(String key, IconData icon, String title, String subtitle) {
    final on = value == key;
    return GestureDetector(
      onTap: () => onChanged(key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: on ? Tx.alpha(Tx.accent, .12) : Tx.surface1,
          borderRadius: BorderRadius.circular(Tx.radiusMd),
          border: Border.all(color: on ? Tx.accent : Tx.border),
        ),
        child: Row(children: [
          Icon(icon, color: on ? Tx.accent : Tx.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Tx.body(15, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: Tx.body(12.5, color: Tx.muted, height: 1.3)),
            ]),
          ),
          Icon(on ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle, color: on ? Tx.accent : Tx.subtle),
        ]),
      ),
    );
  }

  return Column(children: [
    option('private', CupertinoIcons.lock_fill, tr('Privado'), tr('Con el enlace, las personas piden unirse y un administrador las aprueba.')),
    option('public', CupertinoIcons.globe, tr('Público'), tr('Aparece en la búsqueda y cualquiera con el enlace entra directamente.')),
  ]);
}

// ---------------------------------------------------------------------------------------------------------------
// Crear grupo
// ---------------------------------------------------------------------------------------------------------------

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final List<User> _members = [];
  String _visibility = 'private';
  XFile? _avatar;
  bool _saving = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _addPeople() async {
    final people = await pickPeople(context, title: tr('Añadir personas'), exclude: _members.map((u) => u.id).toSet());
    if (people != null && mounted) setState(() => _members.addAll(people));
  }

  Future<void> _create() async {
    if (_saving) return;
    final title = _title.text.trim();
    setState(() {
      _errors.clear();
      if (title.isEmpty) _errors['title'] = tr('Ponle un nombre al grupo.');
    });
    if (_errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final usernames = _members.map((u) => u.username).toList();
      final ApiResponse res = _avatar != null
          ? await api.upload('groups', fields: {
              'title': title,
              'description': _description.text.trim(),
              'visibility': _visibility,
              'members': usernames.join(','),
            }, files: [
              Upload('avatar', _avatar!.path, filename: _avatar!.name)
            ])
          : await api.post('groups', {'title': title, 'description': _description.text.trim(), 'visibility': _visibility, 'members': usernames});
      if (!mounted) return;
      final conv = Conversation.fromJson(asMap(res.map['conversation']));
      final failed = asMap(res.map['failed']);
      toast(context, failed.isEmpty
          ? tr('Creaste el grupo.')
          : tr('Creaste el grupo. No se añadió a @{user}: {error}', {'user': failed.keys.first, 'error': failed.values.first}), error: failed.isNotEmpty);
      Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (_) => ChatScreen(conversationId: conv.id, conversation: conv)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors.addAll(e.fields);
      });
      if (e.fields.isEmpty) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = _avatar;
    final state = context.read<AppState>();
    return Scaffold(
      appBar: GlassBar(
        title: tr('Nuevo grupo'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _create,
            child: _saving ? const CupertinoActivityIndicator() : Text(tr('Crear'), style: Tx.body(16, weight: FontWeight.w700, color: Tx.accent)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 18, 16, 40), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final file = await _pickImage(context);
              if (file != null && mounted) setState(() => _avatar = file);
            },
            child: Stack(children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(shape: BoxShape.circle, gradient: avatar == null ? Tx.brand : null),
                clipBehavior: Clip.antiAlias,
                child: avatar != null ? Image.file(File(avatar.path), fit: BoxFit.cover) : const Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 44),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Tx.surface4, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2)),
                  child: Icon(CupertinoIcons.camera_fill, size: 16, color: Tx.text),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _title,
          maxLength: state.limit('group_title_max', 80),
          style: Tx.body(16),
          decoration: fieldDecoration(tr('Nombre del grupo')).copyWith(errorText: _errors['title'], counterText: ''),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLength: 500,
          minLines: 2,
          maxLines: 4,
          style: Tx.body(15),
          decoration: fieldDecoration(tr('Descripción (opcional)')).copyWith(errorText: _errors['description']),
        ),
        const SizedBox(height: 10),
        _visibilityPicker(_visibility, (v) => setState(() => _visibility = v)),
        const SizedBox(height: 8),
        Row(children: [
          Text(tr('Miembros ({n})', {'n': _members.length}), style: Tx.body(15, weight: FontWeight.w700)),
          const Spacer(),
          SoftButton(label: tr('Añadir'), icon: CupertinoIcons.person_add, onPressed: _addPeople),
        ]),
        if (_errors['members'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_errors['members']!, style: Tx.body(13, color: Tx.danger))),
        const SizedBox(height: 8),
        if (_members.isEmpty)
          Text(tr('Puedes añadir personas ahora o compartir el enlace del grupo después.'), style: Tx.body(13.5, color: Tx.muted))
        else
          for (final u in _members)
            UserTile(
              user: u,
              showFollow: false,
              trailing: IconButton(
                onPressed: () => setState(() => _members.remove(u)),
                icon: Icon(CupertinoIcons.minus_circle_fill, color: Tx.danger),
              ),
            ),
        const SizedBox(height: 16),
        Row(children: [
          Icon(CupertinoIcons.lock_fill, size: 13, color: Tx.subtle),
          const SizedBox(width: 6),
          Expanded(
            child: Text(tr('Los mensajes del grupo se cifran de extremo a extremo cuando todos los miembros usan la app.'),
                style: Tx.body(12.5, color: Tx.subtle, height: 1.35)),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Ajustes del grupo (administradores)
// ---------------------------------------------------------------------------------------------------------------

class GroupEditScreen extends StatefulWidget {
  const GroupEditScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  late Conversation _c = widget.conversation;
  late final _title = TextEditingController(text: _c.group?.title ?? _c.title);
  late final _description = TextEditingController(text: _c.group?.description ?? '');
  late String _visibility = _c.group?.visibility ?? 'private';
  bool _saving = false;
  String? _busyImage;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _apply(ApiResponse res) {
    final data = res.map;
    if (data['conversation'] is Map) setState(() => _c = Conversation.fromJson(asMap(data['conversation'])));
    if (data['message'] != null) toast(context, '${data['message']}');
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errors.clear();
    });
    try {
      final res = await api.patch('groups/${_c.id}', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'visibility': _visibility,
      });
      if (!mounted) return;
      _apply(res);
      Navigator.of(context).pop();
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors.addAll(e.fields));
      if (e.fields.isEmpty) toastError(context, e);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _image(String kind) async {
    final has = kind == 'avatar' ? _c.group?.avatarUrl != null : _c.group?.coverUrl != null;
    final avatar = kind == 'avatar';
    await actionSheet(context, [
      SheetAction(has ? (avatar ? tr('Cambiar foto') : tr('Cambiar portada')) : (avatar ? tr('Subir foto') : tr('Subir portada')), CupertinoIcons.photo, () async {
        final file = await _pickImage(context);
        if (file == null || !mounted) return;
        setState(() => _busyImage = kind);
        try {
          _apply(await api.upload('groups/${_c.id}/$kind', files: [Upload(kind, file.path, filename: file.name)]));
        } catch (e) {
          if (mounted) toastError(context, e);
        }
        if (mounted) setState(() => _busyImage = null);
      }),
      if (has)
        SheetAction(avatar ? tr('Quitar foto') : tr('Quitar portada'), CupertinoIcons.trash, () async {
          setState(() => _busyImage = kind);
          try {
            _apply(await api.delete('groups/${_c.id}/$kind'));
          } catch (e) {
            if (mounted) toastError(context, e);
          }
          if (mounted) setState(() => _busyImage = null);
        }, destructive: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = _c.group;
    final state = context.read<AppState>();
    return Scaffold(
      appBar: GlassBar(
        title: tr('Ajustes del grupo'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const CupertinoActivityIndicator() : Text(tr('Guardar'), style: Tx.body(16, weight: FontWeight.w700, color: Tx.accent)),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        GestureDetector(
          onTap: () => _image('cover'),
          child: SizedBox(
            height: 150,
            child: Stack(fit: StackFit.expand, children: [
              if (g?.coverUrl != null)
                NetImage(g!.coverUrl)
              else
                DecoratedBox(decoration: BoxDecoration(gradient: ChatPalette.of(_c.theme).gradient)),
              Container(color: Colors.black26),
              Center(
                child: _busyImage == 'cover'
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(CupertinoIcons.camera_fill, color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(g?.coverUrl != null ? tr('Cambiar portada') : tr('Añadir portada'), style: Tx.body(14, weight: FontWeight.w600, color: Colors.white)),
                      ]),
              ),
            ]),
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -42),
          child: Center(
            child: GestureDetector(
              onTap: () => _image('avatar'),
              child: Stack(children: [
                Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Tx.bg, shape: BoxShape.circle), child: ChatAvatar(conversation: _c, size: 84)),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: Tx.surface4, shape: BoxShape.circle, border: Border.all(color: Tx.bg, width: 2)),
                    child: _busyImage == 'avatar'
                        ? const SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator(radius: 7))
                        : Icon(CupertinoIcons.camera_fill, size: 16, color: Tx.text),
                  ),
                ),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _title,
              maxLength: state.limit('group_title_max', 80),
              style: Tx.body(16),
              decoration: fieldDecoration(tr('Nombre del grupo')).copyWith(errorText: _errors['title'], counterText: ''),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              style: Tx.body(15),
              decoration: fieldDecoration(tr('Descripción')).copyWith(errorText: _errors['description']),
            ),
            const SizedBox(height: 10),
            _visibilityPicker(_visibility, (v) => setState(() => _visibility = v)),
            if (_errors['visibility'] != null) Text(_errors['visibility']!, style: Tx.body(13, color: Tx.danger)),
            const SizedBox(height: 8),
            Text(tr('El estilo del grupo y los mensajes temporales se cambian desde la información del chat.'), style: Tx.body(12.5, color: Tx.subtle)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Miembros
// ---------------------------------------------------------------------------------------------------------------

class GroupMembersScreen extends StatefulWidget {
  const GroupMembersScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<GroupMembersScreen> createState() => _GroupMembersScreenState();
}

class _GroupMembersScreenState extends State<GroupMembersScreen> {
  late Conversation _c = widget.conversation;
  final List<GroupMember> _members = [];
  Map<String, dynamic>? _next;
  bool _loading = true;
  Object? _error;
  int _count = 0;

  bool get _admin => _c.group?.isAdmin ?? false;
  bool get _owner => _c.group?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _fetching = false;

  Future<void> _load({bool more = false}) async {
    if (more && _fetching) return;
    _fetching = true;
    try {
      final res = await api.get('groups/${_c.id}/members', more ? _next : null);
      _fetching = false;
      if (!mounted) return;
      setState(() {
        if (!more) _members.clear();
        _members.addAll(res.list.map(GroupMember.fromJson));
        _next = res.next;
        _count = asInt(res.meta['count'], _members.length);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      _fetching = false;
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _apply(ApiResponse res) {
    final data = res.map;
    if (data['conversation'] is Map) _c = Conversation.fromJson(asMap(data['conversation']));
    if (data['message'] != null) toast(context, '${data['message']}');
    _load();
  }

  Future<void> _add() async {
    final people = await pickPeople(context, title: tr('Añadir al grupo'), exclude: _members.map((m) => m.user.id).toSet());
    if (people == null || people.isEmpty || !mounted) return;
    try {
      final res = await api.post('groups/${_c.id}/members', {'members': people.map((u) => u.username).toList()});
      if (!mounted) return;
      _apply(res);
      final failed = asMap(res.map['failed']);
      if (failed.isNotEmpty) toast(context, tr('No se añadió a @{user}: {error}', {'user': failed.keys.first, 'error': failed.values.first}), error: true);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _memberMenu(GroupMember m) {
    final actions = <SheetAction>[
      SheetAction(tr('Ver perfil'), CupertinoIcons.person, () => openProfile(context, m.user.username)),
      if (_owner && m.role == 'member')
        SheetAction(tr('Nombrar administrador'), CupertinoIcons.star, () async {
          try {
            _apply(await api.post('groups/${_c.id}/admins/${m.user.id}'));
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }),
      if (_owner && m.role == 'admin')
        SheetAction(tr('Quitar como administrador'), CupertinoIcons.star_slash, () async {
          try {
            _apply(await api.delete('groups/${_c.id}/admins/${m.user.id}'));
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }),
      if (_admin && m.role != 'owner' && !(m.role == 'admin' && !_owner))
        SheetAction(tr('Eliminar del grupo'), CupertinoIcons.person_badge_minus, () async {
          if (!await confirm(context, tr('Eliminar del grupo'), tr('{name} dejará de recibir los mensajes del grupo.', {'name': m.user.displayName}), action: tr('Eliminar'), destructive: true)) {
            return;
          }
          try {
            _apply(await api.delete('groups/${_c.id}/members/${m.user.id}'));
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }, destructive: true),
    ];
    actionSheet(context, actions, title: m.user.displayName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassBar(
        title: _count > 0 ? tr('Miembros ({n})', {'n': _count}) : tr('Miembros'),
        actions: [
          if (_admin) IconButton(onPressed: _add, tooltip: tr('Añadir'), icon: Icon(CupertinoIcons.person_add, color: Tx.text)),
        ],
      ),
      body: _loading
          ? const Loading()
          : _error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _members.length + (_next != null ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _members.length) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _load(more: true));
                        return const Loading(padding: 16);
                      }
                      final m = _members[i];
                      final parts = [
                        if (m.isMe) tr('Tú'),
                        if (m.roleLabel.isNotEmpty) tr(m.roleLabel),
                        if (!m.hasKey) tr('Sin cifrado en la app'),
                      ];
                      return UserTile(
                        user: m.user,
                        showFollow: false,
                        subtitle: parts.isEmpty ? '@${m.user.username}' : parts.join(' · '),
                        onTap: m.isMe ? null : () => _memberMenu(m),
                        trailing: m.isManager ? Icon(CupertinoIcons.star_fill, size: 16, color: Tx.warning) : null,
                      );
                    },
                  ),
                ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Solicitudes
// ---------------------------------------------------------------------------------------------------------------

class GroupRequestsScreen extends StatefulWidget {
  const GroupRequestsScreen({super.key, required this.conversationId});

  final int conversationId;

  @override
  State<GroupRequestsScreen> createState() => _GroupRequestsScreenState();
}

class _GroupRequestsScreenState extends State<GroupRequestsScreen> {
  List<(User, DateTime?)>? _items;
  Object? _error;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('groups/${widget.conversationId}/requests');
      if (mounted) setState(() => _items = [for (final j in res.list) (User.fromJson(j), asDate(j['requested_at']))]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _resolve(User u, bool approve) async {
    setState(() => _busy.add(u.id));
    try {
      final res = await api.post('groups/${widget.conversationId}/requests/${u.id}/${approve ? 'approve' : 'reject'}');
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? (approve ? tr('Solicitud aprobada.') : tr('Solicitud rechazada.'))}');
      setState(() => _items?.removeWhere((e) => e.$1.id == u.id));
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy.remove(u.id));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: GlassBar(title: tr('Solicitudes')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : items == null
              ? const Loading()
              : items.isEmpty
                  ? EmptyState(icon: CupertinoIcons.person_crop_circle_badge_checkmark, title: tr('Sin solicitudes'), message: tr('Cuando alguien pida unirse con el enlace aparecerá aquí.'))
                  : ListView(children: [
                      for (final (u, at) in items)
                        UserTile(
                          user: u,
                          showFollow: false,
                          subtitle: at != null ? tr('Pidió unirse {time}', {'time': timeAgo(at)}) : '@${u.username}',
                          trailing: _busy.contains(u.id)
                              ? const CupertinoActivityIndicator()
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(onPressed: () => _resolve(u, false), icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Tx.danger)),
                                  IconButton(onPressed: () => _resolve(u, true), icon: const Icon(CupertinoIcons.checkmark_circle_fill, color: Tx.success)),
                                ]),
                        ),
                    ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Unirse por enlace
// ---------------------------------------------------------------------------------------------------------------

class InvitePreviewScreen extends StatefulWidget {
  const InvitePreviewScreen({super.key, required this.code});

  final String code;

  @override
  State<InvitePreviewScreen> createState() => _InvitePreviewScreenState();
}

class _InvitePreviewScreenState extends State<InvitePreviewScreen> {
  Json? _group;
  Object? _error;
  bool _joining = false;

  String get _code => widget.code.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await api.get('invites/${Uri.encodeComponent(_code)}');
      if (mounted) setState(() => _group = res.map);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _open(int id) {
    Navigator.of(context).pushReplacement(CupertinoPageRoute(builder: (_) => ChatScreen(conversationId: id)));
  }

  Future<void> _join() async {
    final g = _group;
    if (g == null || _joining) return;
    if (g['state'] == 'member') return _open(asInt(g['id']));
    setState(() => _joining = true);
    try {
      final res = await api.post('invites/${Uri.encodeComponent(_code)}/join');
      if (!mounted) return;
      final data = res.map;
      toast(context, '${data['message'] ?? tr('Listo.')}');
      if (data['state'] == 'member') {
        _open(asInt(data['conversation_id'], asInt(g['id'])));
        return;
      }
      setState(() => _group = {...g, 'state': data['state']});
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _joining = false);
  }

  @override
  Widget build(BuildContext context) {
    final g = _group;
    return Scaffold(
      appBar: GlassBar(title: tr('Invitación')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : g == null
              ? const Loading()
              : ListView(padding: const EdgeInsets.only(bottom: 40), children: [
                  SizedBox(
                    height: 150,
                    child: asStrOrNull(g['cover_url']) != null ? NetImage(asStr(g['cover_url'])) : const DecoratedBox(decoration: BoxDecoration(gradient: Tx.brand)),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -44),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: Tx.bg, shape: BoxShape.circle),
                        child: asStrOrNull(g['avatar_url']) != null
                            ? ClipOval(child: NetImage(asStr(g['avatar_url']), width: 88, height: 88))
                            : Container(
                                width: 88,
                                height: 88,
                                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
                                child: const Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 40),
                              ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(asStr(g['title']), textAlign: TextAlign.center, style: Tx.display(22)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${g['visibility'] == 'public' ? tr('Grupo público') : tr('Grupo privado')} · ${plural(asInt(g['members_count']), 'miembro', 'miembros')}',
                        style: Tx.body(13.5, color: Tx.muted),
                      ),
                      if (asStr(g['description']).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
                          child: Text(asStr(g['description']), textAlign: TextAlign.center, style: Tx.body(14.5, height: 1.4)),
                        ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: g['state'] == 'requested'
                            ? Text(tr('Pediste unirte. Un administrador revisará tu solicitud.'), textAlign: TextAlign.center, style: Tx.body(14, color: Tx.muted))
                            : GradientButton(
                                label: g['state'] == 'member' ? tr('Abrir el grupo') : (g['visibility'] == 'public' ? tr('Unirme al grupo') : tr('Pedir unirme')),
                                loading: _joining,
                                onPressed: _join,
                              ),
                      ),
                    ]),
                  ),
                ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Buscar grupos públicos
// ---------------------------------------------------------------------------------------------------------------

class PublicGroupsScreen extends StatefulWidget {
  const PublicGroupsScreen({super.key});

  @override
  State<PublicGroupsScreen> createState() => _PublicGroupsScreenState();
}

class _PublicGroupsScreenState extends State<PublicGroupsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Json>? _items;
  Object? _error;
  int _request = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final id = ++_request;
    if (q.length < 2) {
      setState(() => _items = null);
      return;
    }
    try {
      final res = await api.get('groups', {'q': q});
      if (id == _request && mounted) {
        setState(() {
          _items = res.list;
          _error = null;
        });
      }
    } catch (e) {
      if (id == _request && mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: GlassBar(title: tr('Grupos públicos')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: TextField(
            controller: _search,
            autofocus: true,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => _load(v.trim()));
            },
            style: Tx.body(15),
            decoration: fieldDecoration(tr('Buscar grupos por nombre'), prefix: Icon(CupertinoIcons.search, color: Tx.subtle, size: 20)),
          ),
        ),
        Expanded(
          child: _error != null
              ? ErrorState(error: _error!, onRetry: () => _load(_search.text.trim()))
              : items == null
                  ? EmptyState(icon: CupertinoIcons.person_3, title: tr('Encuentra grupos'), message: tr('Escribe al menos 2 letras para buscar grupos públicos.'))
                  : items.isEmpty
                      ? EmptyState(icon: CupertinoIcons.search, title: tr('Sin resultados'), message: tr('Ningún grupo público coincide.'))
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => PublicGroupTile(group: items[i]),
                        ),
        ),
      ]),
    );
  }
}

/// Grupo público en una búsqueda (groups o search?type=groups): quien es miembro abre el chat; el resto, la invitación.
class PublicGroupTile extends StatelessWidget {
  const PublicGroupTile({super.key, required this.group});

  final Json group;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final member = asBool(g['is_member']);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: asStrOrNull(g['avatar_url']) != null
          ? ClipOval(child: NetImage(asStr(g['avatar_url']), width: 48, height: 48))
          : Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Tx.brand),
              child: const Icon(CupertinoIcons.person_3_fill, color: Colors.white, size: 22),
            ),
      title: Text(asStr(g['title']), style: Tx.body(15.5, weight: FontWeight.w600)),
      subtitle: Text(
        '${plural(asInt(g['members_count']), 'miembro', 'miembros')}${asStr(g['description']).isNotEmpty ? ' · ${asStr(g['description'])}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tx.body(13, color: Tx.muted),
      ),
      trailing: member ? Text(tr('Miembro'), style: Tx.body(12.5, color: Tx.accent)) : null,
      onTap: () => member
          ? push(context, ChatScreen(conversationId: asInt(g['id'])))
          : push(context, InvitePreviewScreen(code: asStr(g['invite_code']))),
    );
  }
}
