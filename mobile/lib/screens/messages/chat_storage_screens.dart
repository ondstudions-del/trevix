import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/chat_media.dart';
import '../../core/e2ee.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/media.dart';
import '../../widgets/settings_tiles.dart';
final _urlPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

// ---------------------------------------------------------------------------------------------------------------
// Contenido enviado
// ---------------------------------------------------------------------------------------------------------------

/// Fotos, notas de voz, GIF y archivos cifrados del chat, y enlaces. Tocar algo que no es foto vuelve al chat en
/// ese mensaje (devuelve su id).
class SharedContentScreen extends StatefulWidget {
  const SharedContentScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<SharedContentScreen> createState() => _SharedContentScreenState();
}

class _SharedContentScreenState extends State<SharedContentScreen> {
  String _type = 'media';
  final Map<String, List<Message>> _items = {'media': [], 'links': []};
  final Map<String, Map<String, dynamic>?> _next = {};
  final Map<String, bool> _loaded = {};
  bool _loading = false;
  Object? _error;

  int get _id => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    final type = _type;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await api.get('conversations/$_id/shared', {'type': type, if (more) ...?_next[type]});
      final list = res.list.map(Message.fromJson).toList();
      for (final m in list) {
        final c = m.cipher;
        if (c != null && e2ee.ready) m.payload = await e2ee.open(_id, m.id, c.epoch, m.senderId ?? 0, c.ciphertext);
      }
      if (!mounted) return;
      setState(() {
        if (!more) _items[type]!.clear();
        _items[type]!.addAll(list);
        _next[type] = res.next;
        _loaded[type] = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _switch(String type) {
    if (type == _type) return;
    setState(() => _type = type);
    if (_loaded[type] != true) _load();
  }

  Widget _tile(Message m) {
    Widget child;
    VoidCallback? onTap = () => Navigator.of(context).pop(m.id);
    final p = m.payload;
    if (m.mediaCleared) {
      child = _iconTile(CupertinoIcons.trash_slash, tr('Eliminado'));
    } else if (m.viewOnce != null) {
      child = _iconTile(CupertinoIcons.eye, tr('Una vez'));
    } else if (m.imageUrl != null) {
      child = NetImage(m.imageUrl);
      onTap = () => pushFade(context, MediaViewer(media: [Media(type: 'image', url: m.imageUrl!)]));
    } else if (m.gif != null) {
      child = NetImage(m.gif!.url, fit: BoxFit.cover);
    } else if (m.voice != null) {
      child = _iconTile(CupertinoIcons.mic_fill, clock(m.voice!.duration));
    } else if (m.encrypted && p == null) {
      child = _iconTile(CupertinoIcons.lock_fill, tr('Archivo cifrado'));
    } else if (p?.type == 'image') {
      child = FutureBuilder<File>(
        future: ChatMedia.load(m),
        builder: (_, snap) => snap.data != null ? Image.file(snap.data!, fit: BoxFit.cover) : Container(color: Tx.surface3, child: const Center(child: CupertinoActivityIndicator())),
      );
      onTap = () async {
        final file = await ChatMedia.load(m);
        if (mounted) pushFade(context, MediaViewer.file(file));
      };
    } else if (p?.type == 'voice') {
      child = _iconTile(CupertinoIcons.mic_fill, clock(p!.duration));
    } else if (p?.type == 'gif' && p?.gif?['url'] != null) {
      child = NetImage('${p!.gif!['url']}');
    } else {
      child = _iconTile(CupertinoIcons.doc, tr('Archivo'));
    }
    return GestureDetector(onTap: onTap, child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child));
  }

  Widget _iconTile(IconData icon, String label) => Container(
        color: Tx.surface2,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Tx.muted, size: 26),
          const SizedBox(height: 6),
          Text(label, style: Tx.body(12, color: Tx.muted)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final items = _items[_type]!;
    final more = _next[_type] != null;
    Widget body;
    if (_error != null && items.isEmpty) {
      body = ErrorState(error: _error!, onRetry: _load);
    } else if (_loaded[_type] != true) {
      body = const Loading();
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: _type == 'media' ? CupertinoIcons.photo_on_rectangle : CupertinoIcons.link,
        title: _type == 'media' ? tr('Sin contenido') : tr('Sin enlaces'),
        message: _type == 'media' ? tr('Aquí aparecerán las fotos, notas de voz y GIF del chat.') : tr('Aquí aparecerán los enlaces que se envíen en el chat.'),
      );
    } else if (_type == 'media') {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (more && n.metrics.extentAfter < 400) _load(more: true);
          return false;
        },
        child: GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
          itemCount: items.length,
          itemBuilder: (_, i) => _tile(items[i]),
        ),
      );
    } else {
      final links = <(Message, String)>[
        for (final m in items)
          for (final url in _urlPattern.allMatches(m.text).map((e) => e.group(0)!)) (m, url),
      ];
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (more && n.metrics.extentAfter < 400) _load(more: true);
          return false;
        },
        child: ListView.separated(
          itemCount: links.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Tx.border, indent: 70),
          itemBuilder: (_, i) {
            final (m, url) = links[i];
            final host = Uri.tryParse(url)?.host ?? url;
            return ListTile(
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(10)),
                child: Icon(CupertinoIcons.link, color: Tx.accent),
              ),
              title: Text(host, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15, weight: FontWeight.w600)),
              subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12.5, color: Tx.muted)),
              trailing: Text(timeAgo(m.createdAt), style: Tx.body(12, color: Tx.subtle)),
              onTap: () => openInApp(context, url),
              onLongPress: () => Navigator.of(context).pop(m.id),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: GlassBar(
        title: tr('Contenido enviado'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _type,
              children: {
                'media': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(tr('Fotos y archivos'), style: Tx.body(13.5, weight: FontWeight.w600))),
                'links': Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(tr('Enlaces'), style: Tx.body(13.5, weight: FontWeight.w600))),
              },
              onValueChanged: (v) => v != null ? _switch(v) : null,
            ),
          ),
        ),
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Almacenamiento de un chat
// ---------------------------------------------------------------------------------------------------------------

class ConversationStorageScreen extends StatefulWidget {
  const ConversationStorageScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ConversationStorageScreen> createState() => _ConversationStorageScreenState();
}

class _ConversationStorageScreenState extends State<ConversationStorageScreen> {
  Json? _server;
  int _phone = 0;
  Object? _error;
  bool _busy = false;

  int get _id => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([api.get('conversations/$_id/storage'), ChatMedia.size(_id)]);
      if (!mounted) return;
      setState(() {
        _server = (results[0] as ApiResponse).map;
        _phone = results[1] as int;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _clearPhone() async {
    if (!await confirm(context, tr('Borrar del teléfono'), tr('Se borrarán las fotos y notas de voz de este chat guardadas en el teléfono. Se volverán a descargar si las abres.'),
        action: tr('Borrar'), destructive: true)) {
      return;
    }
    await ChatMedia.clear(_id);
    if (!mounted) return;
    toast(context, tr('Liberaste {size} del teléfono.', {'size': fileSize(_phone)}));
    _load();
  }

  Future<void> _clean(int days) async {
    if (!await confirm(
      context,
      tr('Eliminar archivos de más de {days} días', {'days': days}),
      tr('Se borrarán del servidor las fotos, notas de voz y archivos que enviaste en este chat hace más de {days} días. Los mensajes se quedan, pero en lugar del archivo se verá «Archivo eliminado». No se puede deshacer.', {'days': days}),
      action: tr('Eliminar'),
      destructive: true,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await api.post('me/chat-storage/clean', {'older_than_days': days, 'conversation_id': _id});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Listo.')}');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      appBar: GlassBar(title: tr('Almacenamiento del chat')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : s == null
              ? const Loading()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    SettingsGroup(title: tr('En este teléfono'), children: [
                      SettingsRow(icon: CupertinoIcons.device_phone_portrait, color: Tx.blue, label: tr('Guardado en el teléfono'), value: fileSize(_phone)),
                      SettingsRow(
                        icon: CupertinoIcons.trash,
                        color: Tx.danger,
                        label: tr('Borrar del teléfono'),
                        destructive: true,
                        onTap: _phone > 0 ? _clearPhone : null,
                      ),
                    ]),
                    SettingsGroup(
                      title: tr('En el servidor'),
                      footer: tr('Cada persona puede eliminar solo los archivos que envió.'),
                      children: [
                        SettingsRow(
                          icon: CupertinoIcons.cloud_fill,
                          color: Tx.purple,
                          label: tr('Total del chat'),
                          value: '${fileSize(asInt(s['bytes']))} · ${plural(asInt(s['files']), 'archivo', 'archivos')}',
                        ),
                        for (final k in asList(s['kinds'], (e) => e))
                          SettingsRow(
                            icon: switch (asStr(k['kind'])) { 'voice' => CupertinoIcons.mic_fill, 'encrypted' => CupertinoIcons.lock_fill, _ => CupertinoIcons.photo_fill },
                            color: Tx.subtle,
                            label: asStr(k['label']),
                            value: '${fileSize(asInt(k['bytes']))} · ${asInt(k['files'])}',
                          ),
                      ],
                    ),
                    if (asList(s['people'], (e) => e).isNotEmpty)
                      SettingsGroup(title: tr('Por persona'), children: [
                        for (final p in asList(s['people'], (e) => e))
                          ListTile(
                            leading: Avatar(user: User.fromJson(p), size: 34),
                            title: Text(asStr(p['display_name'], asStr(p['username'])), style: Tx.body(15)),
                            trailing: Text('${fileSize(asInt(p['bytes']))} · ${asInt(p['files'])}', style: Tx.body(13, color: Tx.muted)),
                          ),
                      ]),
                    SettingsGroup(title: tr('Eliminar mis archivos viejos'), children: [
                      for (final days in const [30, 90])
                        SettingsRow(
                          icon: CupertinoIcons.clock_fill,
                          color: Tx.warning,
                          label: tr('De más de {days} días', {'days': days}),
                          trailing: _busy ? const CupertinoActivityIndicator() : null,
                          onTap: _busy ? null : () => _clean(days),
                        ),
                    ]),
                  ]),
                ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Ajustes › Almacenamiento del chat
// ---------------------------------------------------------------------------------------------------------------

/// Eliminar almacenamiento del chat: lo guardado en el teléfono (por chat) y tus archivos enviados viejos en el
/// servidor (de más de 30 o 90 días).
class ChatStorageSettingsScreen extends StatefulWidget {
  const ChatStorageSettingsScreen({super.key});

  @override
  State<ChatStorageSettingsScreen> createState() => _ChatStorageSettingsScreenState();
}

class _ChatStorageSettingsScreenState extends State<ChatStorageSettingsScreen> {
  Json? _server;
  Map<int, int> _phone = {};
  Map<int, String> _titles = {};
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([api.get('me/chat-storage'), ChatMedia.sizes(), api.get('conversations')]);
      if (!mounted) return;
      final inbox = (results[2] as ApiResponse).list.map(Conversation.fromJson);
      final server = (results[0] as ApiResponse).map;
      setState(() {
        _server = server;
        _phone = results[1] as Map<int, int>;
        _titles = {
          for (final c in inbox) c.id: c.title,
          for (final c in asList(server['conversations'], (e) => e)) asInt(c['conversation_id']): asStr(c['title']),
        };
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _clearPhone([int? conversationId]) async {
    final bytes = conversationId == null ? _phone.values.fold<int>(0, (a, b) => a + b) : (_phone[conversationId] ?? 0);
    if (!await confirm(
      context,
      conversationId == null ? tr('Borrar todo del teléfono') : tr('Borrar «{chat}»', {'chat': _titles[conversationId] ?? tr('chat')}),
      tr('Se borrarán {size} de fotos y notas de voz guardadas en el teléfono. Si las vuelves a abrir, se descargarán otra vez.', {'size': fileSize(bytes)}),
      action: tr('Borrar'),
      destructive: true,
    )) {
      return;
    }
    await ChatMedia.clear(conversationId);
    if (!mounted) return;
    toast(context, tr('Liberaste {size} del teléfono.', {'size': fileSize(bytes)}));
    _load();
  }

  Future<void> _clean(int days, int bytes) async {
    if (!await confirm(
      context,
      tr('Eliminar archivos de más de {days} días', {'days': days}),
      tr('Se borrarán del servidor {size} de fotos, notas de voz y archivos que enviaste en todos tus chats hace más de {days} días. Los mensajes se quedan, pero se verá «Archivo eliminado». No se puede deshacer.', {'size': fileSize(bytes), 'days': days}),
      action: tr('Eliminar'),
      destructive: true,
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await api.post('me/chat-storage/clean', {'older_than_days': days});
      if (!mounted) return;
      toast(context, '${res.map['message'] ?? tr('Listo.')}');
      _load();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    final phoneTotal = _phone.values.fold<int>(0, (a, b) => a + b);
    final phoneChats = _phone.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: GlassBar(title: tr('Almacenamiento del chat')),
      body: _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : s == null
              ? const Loading()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
                    SettingsGroup(
                      title: tr('En este teléfono'),
                      footer: tr('Fotos y notas de voz de los chats (las cifradas ya descifradas). Borrarlas libera espacio; se descargan de nuevo al abrirlas.'),
                      children: [
                        SettingsRow(icon: CupertinoIcons.device_phone_portrait, color: Tx.blue, label: tr('Total'), value: fileSize(phoneTotal)),
                        for (final e in phoneChats.take(20))
                          SettingsRow(
                            icon: CupertinoIcons.chat_bubble_2_fill,
                            color: Tx.subtle,
                            label: _titles[e.key] ?? tr('Chat'),
                            value: fileSize(e.value),
                            onTap: () => _clearPhone(e.key),
                          ),
                        SettingsRow(
                          icon: CupertinoIcons.trash,
                          color: Tx.danger,
                          label: tr('Borrar todo del teléfono'),
                          destructive: true,
                          onTap: phoneTotal > 0 ? () => _clearPhone() : null,
                        ),
                      ],
                    ),
                    SettingsGroup(
                      title: tr('Tus archivos en el servidor'),
                      footer: tr('Elimina el contenido viejo que ya no usas. Los mensajes se quedan en los chats sin el archivo.'),
                      children: [
                        SettingsRow(
                          icon: CupertinoIcons.cloud_fill,
                          color: Tx.purple,
                          label: tr('Enviados por ti'),
                          value: '${fileSize(asInt(s['bytes']))} · ${plural(asInt(s['files']), 'archivo', 'archivos')}',
                        ),
                        for (final o in asList(s['older'], (e) => e))
                          SettingsRow(
                            icon: CupertinoIcons.clock_fill,
                            color: Tx.warning,
                            label: tr('Eliminar los de más de {days} días', {'days': asInt(o['days'])}),
                            value: asInt(o['files']) > 0 ? '${fileSize(asInt(o['bytes']))} · ${asInt(o['files'])}' : tr('Nada'),
                            trailing: _busy ? const CupertinoActivityIndicator() : null,
                            destructive: asInt(o['files']) > 0,
                            onTap: _busy || asInt(o['files']) == 0 ? null : () => _clean(asInt(o['days']), asInt(o['bytes'])),
                          ),
                      ],
                    ),
                    if (asList(s['conversations'], (e) => e).isNotEmpty)
                      SettingsGroup(title: tr('Por chat'), children: [
                        for (final c in asList(s['conversations'], (e) => e))
                          SettingsRow(
                            icon: asStr(c['type']) == 'group' ? CupertinoIcons.person_3_fill : CupertinoIcons.person_fill,
                            color: Tx.subtle,
                            label: asStr(c['title']),
                            value: '${fileSize(asInt(c['bytes']))} · ${asInt(c['files'])}',
                          ),
                      ]),
                  ]),
                ),
    );
  }
}
