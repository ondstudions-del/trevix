import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/chat_wallpaper.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/song_chip.dart';
import 'chat_search_screen.dart';
import 'forward_screen.dart';

/// Conversación privada. Sin [conversationId], el primer mensaje abre la conversación con [user].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.conversationId, this.user});

  final int? conversationId;
  final User? user;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late int? _id = widget.conversationId;
  Conversation? _conversation;
  final List<Message> _messages = [];
  Map<String, dynamic>? _older;
  bool _loading = true;
  bool _loadingOlder = false;
  Object? _error;
  int _seenId = 0;
  bool _online = false;
  Timer? _poll;
  Timer? _expiry;
  bool _polling = false;

  /// Hora del servidor del último sondeo: pide los mensajes ya cargados que cambiaron desde entonces.
  String _since = '';

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  XFile? _image;
  Gif? _gif;
  Message? _replyTo;
  bool _sending = false;
  bool _locating = false;

  final Map<int, GlobalKey> _keys = {};
  int? _highlight;
  int _pinIndex = 0;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  DateTime? _recordStart;
  Timer? _recordTimer;
  int _recordSeconds = 0;
  String? _voicePath;
  int _voiceSeconds = 0;

  User? get _user => _conversation?.user ?? widget.user;
  ChatOptions get _options => _conversation?.options ?? ChatOptions();
  String get _partnerName => _conversation?.title ?? _user?.displayName ?? '';
  bool get _canWrite => _conversation?.blockedReason == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadOlder();
    });
    _expiry = Timer.periodic(const Duration(seconds: 10), (_) => _dropExpired());
    if (_id != null) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _expiry?.cancel();
    _recordTimer?.cancel();
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _deleteVoiceFile();
    songPlayer.stop('voice-draft');
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
      _pollOnce();
    } else if (state == AppLifecycleState.paused) {
      _poll?.cancel();
      if (_recording) _stopRecording();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    if (_id == null) return;
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _pollOnce());
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        api.get('conversations/$_id'),
        api.get('conversations/$_id/messages', {'read': 1}),
      ]);
      if (!mounted) return;
      final conv = Conversation.fromJson(results[0].map);
      final history = results[1];
      setState(() {
        _conversation = conv;
        _online = conv.online;
        _messages
          ..clear()
          ..addAll(history.list.map(Message.fromJson).where((m) => !m.expired));
        _older = history.next;
        _seenId = asInt(history.meta['seen_id'], conv.partnerLastReadId);
        _since = asStr(history.meta['now']);
        _loading = false;
        _error = null;
      });
      _startPolling();
      if (mounted) context.read<AppState>().refreshCounts();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _reloadConversation() async {
    if (_id == null) return;
    try {
      final res = await api.get('conversations/$_id');
      if (mounted) setState(() => _conversation = Conversation.fromJson(res.map));
    } catch (_) {}
  }

  Future<void> _loadOlder() async {
    final older = _older;
    if (older == null || _loadingOlder || _id == null) return;
    _loadingOlder = true;
    try {
      final res = await api.get('conversations/$_id/messages', older);
      if (mounted) {
        setState(() {
          final known = _messages.map((m) => m.id).toSet();
          _messages.insertAll(0, res.list.map(Message.fromJson).where((m) => !known.contains(m.id) && !m.expired));
          _older = res.next;
        });
      }
    } catch (_) {}
    _loadingOlder = false;
  }

  Future<void> _pollOnce() async {
    if (_polling || _id == null || !mounted) return;
    _polling = true;
    try {
      final last = _messages.isEmpty ? 0 : _messages.last.id;
      final first = _messages.isEmpty ? 0 : _messages.first.id;
      final res = await api.get('conversations/$_id/messages', {
        'after': last,
        'from': first,
        'read': 1,
        if (_since.isNotEmpty) 'since': _since,
      });
      if (!mounted) return;
      final fresh = res.list.map(Message.fromJson).where((m) => !_messages.any((x) => x.id == m.id)).toList();
      final deleted = res.meta['deleted'] is List ? (res.meta['deleted'] as List).map((e) => asInt(e)).toSet() : <int>{};
      final updated = {for (final m in asList(res.meta['updated'], Message.fromJson)) m.id: m};
      final pinned = asList(res.meta['pinned'], Message.fromJson);
      setState(() {
        _messages.addAll(fresh);
        for (final m in _messages) {
          final change = updated[m.id];
          if (change != null) m.updateFrom(change);
          if (deleted.contains(m.id) && !m.deleted) m.markDeleted();
        }
        final pinnedIds = pinned.map((m) => m.id).toSet();
        for (final m in _messages) {
          m.pinned = pinnedIds.contains(m.id);
        }
        _conversation?.pinned = pinned;
        if (res.meta.containsKey('disappear_seconds')) _conversation?.disappearSeconds = asInt(res.meta['disappear_seconds']);
        _seenId = asInt(res.meta['seen_id'], _seenId);
        _online = asBool(res.meta['online']);
        final now = asStr(res.meta['now']);
        if (now.isNotEmpty) _since = now;
      });
      if (fresh.any((m) => !m.isMine)) HapticFeedback.selectionClick();
    } catch (_) {}
    _polling = false;
  }

  void _dropExpired() {
    if (!mounted || !_messages.any((m) => m.expired)) return;
    setState(() => _messages.removeWhere((m) => m.expired));
  }

  // ---------- Saltar a un mensaje (búsqueda, respuestas y fijados) ----------

  GlobalKey _keyFor(int id) => _keys.putIfAbsent(id, () => GlobalKey());

  Future<void> _jumpTo(int id) async {
    if (_id == null) return;
    if (!_messages.any((m) => m.id == id)) {
      try {
        final res = await api.get('conversations/$_id/messages', {'around': id});
        if (!mounted) return;
        final list = res.list.map(Message.fromJson).where((m) => !m.expired).toList();
        if (!list.any((m) => m.id == id)) {
          toast(context, 'Ese mensaje ya no está disponible.', error: true);
          return;
        }
        setState(() {
          _messages
            ..clear()
            ..addAll(list);
          _older = res.next;
        });
        await WidgetsBinding.instance.endOfFrame;
      } catch (e) {
        if (mounted) toastError(context, e);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _highlight = id);
    await _ensureVisible(id);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted && _highlight == id) setState(() => _highlight = null);
    });
  }

  Future<void> _ensureVisible(int id) async {
    if (!_scroll.hasClients) return;
    final key = _keyFor(id);
    if (key.currentContext == null) {
      _scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
    for (var i = 0; i < 80 && key.currentContext == null && _scroll.hasClients; i++) {
      final pos = _scroll.position;
      if (pos.pixels >= pos.maxScrollExtent) break;
      _scroll.jumpTo(math.min(pos.pixels + pos.viewportDimension * .7, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
    final ctx = key.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(ctx, alignment: .5, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    }
  }

  // ---------- Adjuntos ----------

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2000);
      if (file != null) {
        setState(() {
          _image = file;
          _gif = null;
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'No se pudo abrir la galería. Revisa el permiso de Fotos.', error: true);
    }
  }

  Future<void> _pickGif() async {
    final gif = await pickGif(context);
    if (gif != null && mounted) {
      setState(() {
        _gif = gif;
        _image = null;
      });
    }
  }

  void _attachMenu() {
    final state = context.read<AppState>();
    actionSheet(context, [
      SheetAction('Foto de la galería', CupertinoIcons.photo, _pickImage),
      if (state.feature('gifs')) SheetAction('GIF y stickers', CupertinoIcons.smiley, _pickGif),
      SheetAction('Ubicación actual', CupertinoIcons.location, _sendLocation),
    ]);
  }

  Future<void> _sendLocation() async {
    if (_sending || _locating) return;
    setState(() => _locating = true);
    try {
      final p = await DeviceAccess.exactPosition();
      if (!mounted) return;
      final ok = await confirm(
        context,
        'Enviar ubicación',
        '${p.name ?? 'Tu ubicación actual'}\n${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}\n\n$_partnerName verá tu ubicación exacta.',
        action: 'Enviar',
      );
      if (ok) {
        await _deliver({
          'location': {'lat': p.lat, 'lng': p.lng, if (p.name != null) 'name': p.name},
        });
      }
    } on DeviceException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _locating = false);
  }

  // ---------- Notas de voz ----------

  int get _voiceMax => context.read<AppState>().limit('voice_max_seconds', 120);
  int get _voiceMin => context.read<AppState>().limit('voice_min_seconds', 1);

  Future<void> _startRecording() async {
    if (_recording || _sending) return;
    await songPlayer.stop();
    if (!await DeviceAccess.request(Access.microphone)) {
      if (mounted) toast(context, 'Permite el micrófono en Ajustes › TREVIX para grabar notas de voz.', error: true);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1),
        path: path,
      );
    } catch (_) {
      if (mounted) toast(context, 'No se pudo iniciar la grabación.', error: true);
      return;
    }
    _deleteVoiceFile();
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recordStart = DateTime.now();
      _recordSeconds = 0;
      _voicePath = null;
      _image = null;
      _gif = null;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final start = _recordStart;
      if (!mounted || start == null) return;
      final seconds = DateTime.now().difference(start).inSeconds;
      if (seconds != _recordSeconds) setState(() => _recordSeconds = seconds);
      if (seconds >= _voiceMax) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recordTimer?.cancel();
    final start = _recordStart ?? DateTime.now();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    final seconds = DateTime.now().difference(start).inMilliseconds / 1000;
    await songPlayer.restoreSession();
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null || seconds < _voiceMin) {
      if (path != null) _deleteFile(path);
      toast(context, 'La nota de voz debe durar al menos $_voiceMin s. Mantén la grabación un poco más.', error: true);
      return;
    }
    setState(() {
      _voicePath = path;
      _voiceSeconds = seconds.round().clamp(1, _voiceMax);
    });
  }

  Future<void> _cancelVoice() async {
    _recordTimer?.cancel();
    if (_recording) {
      try {
        await _recorder.cancel();
      } catch (_) {}
      await songPlayer.restoreSession();
    }
    await songPlayer.stop('voice-draft');
    _deleteVoiceFile();
    if (mounted) {
      setState(() {
        _recording = false;
        _voicePath = null;
      });
    }
  }

  void _deleteVoiceFile() {
    final path = _voicePath;
    if (path != null) _deleteFile(path);
  }

  void _deleteFile(String path) {
    final file = File(path);
    file.exists().then((exists) {
      if (exists) file.delete();
    }).catchError((_) {});
  }

  // ---------- Enviar ----------

  Future<void> _send() async {
    final text = _input.text.trim();
    final image = _image;
    final gif = _gif;
    final voice = _voicePath;
    if ((text.isEmpty && image == null && gif == null && voice == null) || _sending || _recording) return;
    final fields = <String, String>{
      'body': voice != null ? '' : text,
      if (gif != null) 'gif_id': gif.id,
      if (gif != null) 'gif_kind': gif.kind,
    };
    final ok = await _deliver(
      fields,
      upload: voice != null
          ? Upload('voice', voice, filename: 'nota.m4a')
          : image != null
              ? Upload('image', image.path, filename: image.name)
              : null,
    );
    if (!ok || !mounted) return;
    if (voice == null) _input.clear();
    if (voice != null) _deleteFile(voice);
    setState(() {
      _image = null;
      _gif = null;
      _voicePath = null;
    });
  }

  /// Envía el mensaje (con la respuesta elegida) y lo añade al chat. Devuelve false si falló.
  Future<bool> _deliver(Map<String, dynamic> fields, {Upload? upload}) async {
    if (_sending) return false;
    setState(() => _sending = true);
    final reply = _replyTo;
    final payload = <String, dynamic>{
      ...fields,
      if (reply != null) 'reply_to': '${reply.id}',
      if (_id == null) 'to': _user!.username,
    };
    var ok = false;
    try {
      final path = _id == null ? 'messages' : 'conversations/$_id/messages';
      final ApiResponse res;
      if (upload != null) {
        if (upload.field == 'voice') await songPlayer.stop('voice-draft');
        res = await api.upload(path, fields: payload.map((k, v) => MapEntry(k, '$v')), files: [upload]);
      } else {
        res = await api.post(path, payload);
      }
      final data = res.map;
      final message = data['message'] is Map ? Message.fromJson(asMap(data['message'])) : null;
      final newId = asInt(data['conversation_id']);
      ok = true;
      if (mounted) {
        setState(() {
          _replyTo = null;
          if (message != null && !_messages.any((m) => m.id == message.id)) _messages.add(message);
        });
      }
      if (_id == null && newId > 0) {
        _id = newId;
        _startPolling();
        _reloadConversation();
      }
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
    return ok;
  }

  // ---------- Acciones sobre un mensaje ----------

  bool _forwardable(Message m) =>
      !m.deleted && ((m.body ?? '').isNotEmpty || m.imageUrl != null || m.voice != null || m.gif != null || m.location != null);

  void _messageMenu(Message m) {
    if (m.isSystem || _id == null) return;
    HapticFeedback.selectionClick();
    final actions = <SheetAction>[
      if (!m.deleted && _canWrite)
        SheetAction('Responder', CupertinoIcons.reply, () {
          setState(() => _replyTo = m);
          _focus.requestFocus();
        }),
      if (_forwardable(m))
        SheetAction('Reenviar', CupertinoIcons.arrowshape_turn_up_right, () => push(context, ForwardScreen(message: m, max: _options.maxForward))),
      if ((m.body ?? '').isNotEmpty)
        SheetAction('Copiar', CupertinoIcons.doc_on_doc, () {
          Clipboard.setData(ClipboardData(text: m.body!));
          toast(context, 'Mensaje copiado.');
        }),
      if (!m.deleted) SheetAction(m.pinned ? 'Dejar de fijar' : 'Fijar', m.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin, () => _pin(m, !m.pinned)),
      SheetAction('Eliminar para mí', CupertinoIcons.eye_slash, () => _hide(m)),
      if (m.isMine && !m.deleted) SheetAction('Eliminar para todos', CupertinoIcons.trash, () => _deleteForAll(m), destructive: true),
      if (!m.isMine && !m.deleted) SheetAction('Reportar mensaje', CupertinoIcons.flag, () => showReportSheet(context, 'message', m.id), destructive: true),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!m.deleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final e in _options.reactions)
                    _ReactionOption(
                      emoji: e,
                      selected: m.myReaction == e,
                      onTap: () {
                        Navigator.pop(ctx);
                        _react(m, e);
                      },
                    ),
                  _ReactionOption(
                    icon: CupertinoIcons.add,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final emoji = await prompt(context, 'Reaccionar', hint: 'Escribe un emoji', action: 'Reaccionar', maxLength: 8);
                      if (emoji != null && emoji.isNotEmpty) _react(m, emoji);
                    },
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(m.summary, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(13, color: Tx.subtle)),
            ),
            for (final a in actions)
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  a.onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(children: [
                    Icon(a.icon, size: 22, color: a.destructive ? Tx.danger : Tx.text),
                    const SizedBox(width: 14),
                    Expanded(child: Text(a.label, style: Tx.body(16, weight: FontWeight.w500, color: a.destructive ? Tx.danger : Tx.text))),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _applyReaction(Message m, String? emoji) {
    final counts = <String, int>{for (final r in m.reactions) r.emoji: r.count};
    final mine = m.myReaction;
    if (mine != null) {
      final left = (counts[mine] ?? 1) - 1;
      if (left <= 0) {
        counts.remove(mine);
      } else {
        counts[mine] = left;
      }
    }
    if (emoji != null) counts[emoji] = (counts[emoji] ?? 0) + 1;
    m.reactions = [for (final e in counts.entries) Reaction(e.key, e.value)];
    m.myReaction = emoji;
  }

  Future<void> _react(Message m, String emoji) async {
    if (m.deleted || m.isSystem) return;
    final remove = m.myReaction == emoji;
    final before = (m.reactions, m.myReaction);
    HapticFeedback.lightImpact();
    setState(() => _applyReaction(m, remove ? null : emoji));
    try {
      final res = remove ? await api.delete('messages/${m.id}/reaction') : await api.post('messages/${m.id}/reaction', {'emoji': emoji});
      if (mounted) setState(() => m.updateFrom(Message.fromJson(res.map)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        m.reactions = before.$1;
        m.myReaction = before.$2;
      });
      toastError(context, e);
    }
  }

  Future<void> _pin(Message m, bool pin) async {
    try {
      final res = pin ? await api.post('messages/${m.id}/pin') : await api.delete('messages/${m.id}/pin');
      final pinned = asList(res.map['pinned'], Message.fromJson);
      if (!mounted) return;
      setState(() {
        _conversation?.pinned = pinned;
        _pinIndex = 0;
        final ids = pinned.map((p) => p.id).toSet();
        for (final x in _messages) {
          x.pinned = ids.contains(x.id);
        }
      });
      toast(context, '${res.map['message'] ?? (pin ? 'Mensaje fijado.' : 'Mensaje desfijado.')}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _hide(Message m) async {
    if (!await confirm(context, 'Eliminar para mí', 'El mensaje dejará de verse en tu chat. $_partnerName lo seguirá viendo.',
        action: 'Eliminar', destructive: true)) {
      return;
    }
    try {
      await api.post('messages/${m.id}/hide');
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((x) => x.id == m.id);
        _conversation?.pinned = [...?_conversation?.pinned.where((p) => p.id != m.id)];
        if (_replyTo?.id == m.id) _replyTo = null;
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _deleteForAll(Message m) async {
    if (!await confirm(context, 'Eliminar para todos', 'Se mostrará como «Mensaje eliminado» para los dos.', action: 'Eliminar', destructive: true)) {
      return;
    }
    try {
      await api.delete('messages/${m.id}');
      if (!mounted) return;
      setState(() {
        m.markDeleted();
        _conversation?.pinned = [...?_conversation?.pinned.where((p) => p.id != m.id)];
      });
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _openLocation(MessageLocation loc) async {
    final label = Uri.encodeComponent(loc.name ?? 'Ubicación');
    final ll = '${loc.lat},${loc.lng}';
    final uris = Platform.isIOS
        ? [Uri.parse('https://maps.apple.com/?ll=$ll&q=$label')]
        : [Uri.parse('geo:$ll?q=$ll($label)'), Uri.parse('https://www.google.com/maps/search/?api=1&query=$ll')];
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (mounted) toast(context, 'No se pudo abrir la aplicación de mapas.', error: true);
  }

  // ---------- Ajustes de la conversación ----------

  Future<bool> _patch(Map<String, dynamic> body) async {
    final c = _conversation;
    if (c == null) return false;
    try {
      final res = await api.patch('conversations/${c.id}', body);
      final fresh = res.map;
      if (!mounted) return true;
      setState(() {
        c.muted = asBool(fresh['muted']);
        c.nickname = asStrOrNull(fresh['nickname']);
        c.wallpaper = asStrOrNull(fresh['wallpaper']) ?? 'default';
        c.disappearSeconds = asInt(fresh['disappear_seconds']);
      });
      toast(context, '${fresh['message'] ?? 'Guardado.'}');
      return true;
    } catch (e) {
      if (mounted) toastError(context, e);
      return false;
    }
  }

  Future<void> _toggleMute() async {
    final c = _conversation;
    if (c == null) return;
    if (await _patch({'muted': !c.muted}) && mounted) context.read<AppState>().refreshCounts();
  }

  Future<void> _editNickname() async {
    final c = _conversation;
    if (c == null) return;
    final value = await prompt(
      context,
      'Apodo',
      message: 'Solo tú verás el apodo de @${c.user.username} en este chat. Déjalo vacío para quitarlo.',
      hint: c.user.displayName,
      initial: c.nickname ?? '',
      maxLength: _options.nicknameMax,
      required: false,
    );
    if (value != null) _patch({'nickname': value});
  }

  void _chooseWallpaper() {
    final c = _conversation;
    if (c == null) return;
    final wallpapers = _options.wallpapers.isEmpty ? [const MapEntry('default', 'Predeterminado')] : _options.wallpapers;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Estilo del chat', style: Tx.display(18), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Solo tú ves el fondo que elijas.', style: Tx.body(13, color: Tx.muted), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Wrap(spacing: 12, runSpacing: 14, alignment: WrapAlignment.center, children: [
              for (final w in wallpapers)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (w.key != c.wallpaper) _patch({'wallpaper': w.key});
                  },
                  child: SizedBox(
                    width: 72,
                    child: Column(children: [
                      ChatWallpaper.swatch(w.key, size: 66, selected: w.key == c.wallpaper),
                      const SizedBox(height: 5),
                      Text(w.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(12, color: w.key == c.wallpaper ? Tx.accent : Tx.muted)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _chooseDisappear() {
    final c = _conversation;
    if (c == null) return;
    final options = _options.disappear.isEmpty ? [const MapEntry(0, 'Desactivados'), const MapEntry(86400, '24 horas')] : _options.disappear;
    actionSheet(
      context,
      [
        for (final o in options)
          SheetAction(o.value, o.key == c.disappearSeconds ? CupertinoIcons.checkmark_alt : CupertinoIcons.timer, () {
            if (o.key != c.disappearSeconds) _patch({'disappear_seconds': o.key}).then((ok) => ok ? _pollOnce() : null);
          }),
      ],
      title: 'Mensajes temporales',
    );
  }

  Future<void> _toggleBlock() async {
    final c = _conversation;
    if (c == null || !c.available) return;
    final blocking = !c.blockedByMe;
    if (blocking &&
        !await confirm(context, 'Bloquear a @${c.user.username}',
            'No podrá escribirte, ver tu perfil ni encontrarte. No le avisaremos.', action: 'Bloquear', destructive: true)) {
      return;
    }
    try {
      final res = blocking ? await api.post('users/${c.user.id}/block') : await api.delete('users/${c.user.id}/block');
      if (mounted) toast(context, '${res.map['message'] ?? (blocking ? 'Bloqueaste la cuenta.' : 'Desbloqueaste la cuenta.')}');
      await _reloadConversation();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  void _chatMenu() {
    final c = _conversation;
    final user = _user;
    if (c == null || user == null) return;
    final disappear = _options.disappear.where((o) => o.key == c.disappearSeconds).map((o) => o.value).firstOrNull;
    actionSheet(context, [
      if (c.available) SheetAction('Ver perfil', CupertinoIcons.person, () => openProfile(context, user.username)),
      SheetAction('Buscar en el chat', CupertinoIcons.search, _openSearch),
      SheetAction(c.nickname == null ? 'Poner apodo' : 'Cambiar apodo', CupertinoIcons.tag, _editNickname),
      SheetAction('Estilo del chat', CupertinoIcons.paintbrush, _chooseWallpaper),
      if (c.available && !c.blocked)
        SheetAction(
          c.disappearSeconds > 0 ? 'Mensajes temporales: ${disappear ?? 'activados'}' : 'Mensajes temporales',
          CupertinoIcons.timer,
          _chooseDisappear,
        ),
      SheetAction(c.muted ? 'Reactivar avisos' : 'Silenciar conversación', c.muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, _toggleMute),
      if (c.available)
        SheetAction(c.blockedByMe ? 'Desbloquear a @${user.username}' : 'Bloquear a @${user.username}', CupertinoIcons.nosign, _toggleBlock,
            destructive: !c.blockedByMe),
      if (c.available) SheetAction('Reportar cuenta', CupertinoIcons.flag, () => showReportSheet(context, 'user', user.id), destructive: true),
    ]);
  }

  Future<void> _openSearch() async {
    final id = _id;
    if (id == null) return;
    final messageId = await push<int>(context, ChatSearchScreen(conversationId: id, partnerName: _partnerName));
    if (messageId != null && mounted) _jumpTo(messageId);
  }

  void _pinnedList() {
    final pinned = _conversation?.pinned ?? const <Message>[];
    if (pinned.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Mensajes fijados', style: Tx.display(17), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          for (final p in pinned)
            ListTile(
              leading: Icon(CupertinoIcons.pin_fill, color: Tx.accent, size: 18),
              title: Text(p.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(15)),
              subtitle: Text(p.isMine ? 'Tú' : _partnerName, style: Tx.body(12, color: Tx.subtle)),
              onTap: () {
                Navigator.pop(ctx);
                _jumpTo(p.id);
              },
              trailing: IconButton(
                tooltip: 'Dejar de fijar',
                icon: Icon(CupertinoIcons.pin_slash, color: Tx.muted, size: 20),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pin(p, false);
                },
              ),
            ),
        ]),
      ),
    );
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final c = _conversation;
    final blocked = c?.blockedReason;
    final disappear = c != null && c.disappearSeconds > 0
        ? (_options.disappear.where((o) => o.key == c.disappearSeconds).map((o) => o.value).firstOrNull ?? 'activados')
        : null;
    return Scaffold(
      appBar: GlassBar(
        titleWidget: user == null
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: () => c == null || c.available ? openProfile(context, user.username) : null,
                child: Row(children: [
                  Avatar(user: user, size: 38, online: _online),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      if ((c?.nickname ?? '').isNotEmpty)
                        Text(c!.nickname!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(15.5, weight: FontWeight.w700))
                      else
                        NameLine(user: user, size: 15.5),
                      Row(children: [
                        if (disappear != null) ...[
                          Icon(CupertinoIcons.timer, size: 12, color: Tx.accent),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            _online ? 'En línea' : (disappear != null ? 'Temporales: $disappear' : '@${user.username}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Tx.body(12, color: _online ? Tx.success : Tx.subtle),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
        actions: [
          if (c != null) ...[
            IconButton(onPressed: _openSearch, tooltip: 'Buscar en el chat', icon: Icon(CupertinoIcons.search, color: Tx.text)),
            IconButton(onPressed: _chatMenu, icon: Icon(CupertinoIcons.ellipsis_circle, color: Tx.text)),
          ],
        ],
      ),
      body: Column(children: [
        if ((c?.pinned ?? const []).isNotEmpty) _pinnedBanner(c!.pinned),
        Expanded(child: ChatWallpaper(name: c?.wallpaper ?? 'default', child: _body())),
        if (blocked != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
            child: Row(children: [
              Icon(CupertinoIcons.lock_fill, size: 16, color: Tx.subtle),
              const SizedBox(width: 10),
              Expanded(child: Text(blocked, style: Tx.body(13.5, color: Tx.muted))),
              if (c?.blockedByMe ?? false) TextButton(onPressed: _toggleBlock, child: Text('Desbloquear', style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent))),
            ]),
          )
        else
          _composer(),
      ]),
    );
  }

  Widget _pinnedBanner(List<Message> pinned) {
    final index = _pinIndex % pinned.length;
    final p = pinned[index];
    return Material(
      color: Tx.surface1,
      child: InkWell(
        onTap: () {
          _jumpTo(p.id);
          if (pinned.length > 1) setState(() => _pinIndex = index + 1);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tx.border))),
          child: Row(children: [
            Container(width: 3, height: 32, decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(pinned.length > 1 ? 'Mensaje fijado ${index + 1} de ${pinned.length}' : 'Mensaje fijado',
                    style: Tx.body(12, weight: FontWeight.w700, color: Tx.accent)),
                Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.text)),
              ]),
            ),
            IconButton(onPressed: _pinnedList, tooltip: 'Ver fijados', icon: Icon(CupertinoIcons.pin, color: Tx.muted, size: 20)),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Loading();
    if (_error != null) {
      return ErrorState(error: _error!, onRetry: () {
        setState(() {
          _loading = true;
          _error = null;
        });
        _load();
      });
    }
    if (_messages.isEmpty) {
      final user = _user;
      return Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (user != null) Avatar(user: user, size: 86),
            const SizedBox(height: 14),
            if (user != null) NameLine(user: user, size: 19),
            const SizedBox(height: 6),
            Text('Saluda y empieza la conversación.', style: Tx.body(14, color: Tx.muted)),
          ]),
        ),
      );
    }
    final lastMine = _messages.lastWhere((m) => m.isMine && !m.isSystem, orElse: () => Message(id: 0, conversationId: 0)).id;
    final onWallpaper = (_conversation?.wallpaper ?? 'default') != 'default';
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: _messages.length + (_older != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _messages.length) return const Loading(padding: 16);
          final index = _messages.length - 1 - i;
          final m = _messages[index];
          final prev = index > 0 ? _messages[index - 1] : null;
          final showDate = prev == null || m.createdAt == null || prev.createdAt == null || m.createdAt!.difference(prev.createdAt!).inMinutes > 30;
          final grouped = prev != null && !prev.isSystem && prev.isMine == m.isMine && !showDate;
          final dateStyle = Tx.body(11.5, weight: FontWeight.w600, color: onWallpaper ? Colors.white : Tx.subtle);
          return KeyedSubtree(
            key: _keyFor(m.id),
            child: Column(children: [
              if (showDate)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: onWallpaper
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withAlpha(70), borderRadius: BorderRadius.circular(10)),
                          child: Text(fullDate(m.createdAt), style: dateStyle),
                        )
                      : Text(fullDate(m.createdAt), style: dateStyle),
                ),
              if (m.isSystem)
                _SystemNote(text: m.systemText ?? '', onWallpaper: onWallpaper)
              else ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    color: _highlight == m.id ? Tx.alpha(Tx.accent, .18) : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _Bubble(
                    message: m,
                    grouped: grouped,
                    partnerName: _partnerName,
                    onLongPress: () => _messageMenu(m),
                    onDoubleTap: m.deleted || m.voice != null ? null : () => _react(m, _options.reactions.isEmpty ? '❤️' : _options.reactions.first),
                    onReplyTap: m.reply != null && m.reply!.available ? () => _jumpTo(m.reply!.id) : null,
                    onLocationTap: m.location != null ? () => _openLocation(m.location!) : null,
                  ),
                ),
                if (m.reactions.isNotEmpty)
                  _ReactionChips(message: m, onTap: (emoji) => _react(m, emoji)),
                if (m.id == lastMine && m.isMine && !m.deleted)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3, right: 4),
                      child: Text(m.id <= _seenId ? 'Visto' : 'Enviado',
                          style: Tx.body(11, color: m.id <= _seenId ? Tx.accent : (onWallpaper ? Colors.white70 : Tx.subtle))),
                    ),
                  ),
              ],
            ]),
          );
        },
      ),
    );
  }

  Widget _composer() {
    final image = _image;
    final gif = _gif;
    final reply = _replyTo;
    final state = context.read<AppState>();
    return Container(
      decoration: BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : MediaQuery.of(context).padding.bottom)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (reply != null)
          Container(
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              color: Tx.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border(left: BorderSide(color: Tx.accent, width: 3)),
            ),
            child: Row(children: [
              Icon(CupertinoIcons.reply, size: 16, color: Tx.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(reply.isMine ? 'Respondiéndote a ti' : 'Respondiendo a $_partnerName', style: Tx.body(12, weight: FontWeight.w700, color: Tx.accent)),
                  Text(reply.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
                ]),
              ),
              IconButton(onPressed: () => setState(() => _replyTo = null), icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted, size: 20)),
            ]),
          ),
        if (_recording)
          _recordingBar()
        else if (_voicePath != null)
          _voiceDraftBar()
        else ...[
          if (image != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(image.path), width: 64, height: 64, fit: BoxFit.cover)),
                const SizedBox(width: 10),
                Expanded(child: Text('Imagen adjunta', style: Tx.body(13.5, color: Tx.muted))),
                IconButton(onPressed: () => setState(() => _image = null), icon: Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted)),
              ]),
            ),
          if (gif != null) GifAttachment(gif: gif, onRemove: () => setState(() => _gif = null)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton(
              onPressed: _locating ? null : _attachMenu,
              tooltip: 'Adjuntar',
              icon: _locating ? const CupertinoActivityIndicator() : Icon(CupertinoIcons.add_circled, color: Tx.accent, size: 26),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                minLines: 1,
                maxLines: 5,
                maxLength: state.limit('message_body', 2000),
                textCapitalization: TextCapitalization.sentences,
                style: Tx.body(15.5),
                decoration: fieldDecoration('Mensaje…').copyWith(counterText: '', contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11)),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, value, __) {
                final hasContent = value.text.trim().isNotEmpty || _image != null || _gif != null;
                if (!hasContent && !_sending && state.feature('voice_notes')) {
                  return GestureDetector(
                    onTap: _startRecording,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(gradient: Tx.brand, shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.mic_fill, color: Colors.white, size: 21),
                    ),
                  );
                }
                return _sendButton(hasContent && !_sending);
              },
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _sendButton(bool enabled) {
    return GestureDetector(
      onTap: enabled ? _send : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        decoration: BoxDecoration(gradient: enabled || _sending ? Tx.brand : null, color: enabled || _sending ? null : Tx.surface3, shape: BoxShape.circle),
        child: _sending
            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(CupertinoIcons.arrow_up, color: enabled ? Colors.white : Tx.subtle, size: 21),
      ),
    );
  }

  Widget _recordingBar() {
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(onPressed: _cancelVoice, tooltip: 'Descartar', icon: const Icon(CupertinoIcons.trash, color: Tx.danger)),
        const _RecDot(),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Grabando… ${clock(_recordSeconds)} / ${clock(_voiceMax)}', style: Tx.body(15, weight: FontWeight.w600)),
        ),
        GestureDetector(
          onTap: _stopRecording,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(color: Tx.danger, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.stop_fill, color: Colors.white, size: 19),
          ),
        ),
      ]),
    );
  }

  Widget _voiceDraftBar() {
    final draft = Song(id: 0, title: 'Nota de voz', duration: _voiceSeconds, audioUrl: Uri.file(_voicePath!).toString());
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(onPressed: _sending ? null : _cancelVoice, tooltip: 'Descartar', icon: const Icon(CupertinoIcons.trash, color: Tx.danger)),
        PlayButton(playKey: 'voice-draft', song: draft, size: 38),
        const SizedBox(width: 12),
        Expanded(child: Text('Nota de voz · ${clock(_voiceSeconds)}', style: Tx.body(15, weight: FontWeight.w600))),
        _sendButton(!_sending),
      ]),
    );
  }
}

/// Punto rojo que late mientras se graba.
class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: .35, end: 1).animate(_c),
      child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Tx.danger, shape: BoxShape.circle)),
    );
  }
}

/// Aviso centrado dentro del chat (p. ej. «activó los mensajes temporales»).
class _SystemNote extends StatelessWidget {
  const _SystemNote({required this.text, required this.onWallpaper});

  final String text;
  final bool onWallpaper;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: onWallpaper ? Colors.black.withAlpha(80) : Tx.surface2,
          borderRadius: BorderRadius.circular(14),
          border: onWallpaper ? null : Border.all(color: Tx.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.timer, size: 14, color: onWallpaper ? Colors.white : Tx.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, textAlign: TextAlign.center, style: Tx.body(12.5, color: onWallpaper ? Colors.white : Tx.muted)),
          ),
        ]),
      ),
    );
  }
}

/// Emoji (o el botón «+») de la barra de reacciones.
class _ReactionOption extends StatelessWidget {
  const _ReactionOption({this.emoji, this.icon, this.selected = false, required this.onTap});

  final String? emoji;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Tx.alpha(Tx.accent, .25) : Tx.surface3,
          border: Border.all(color: selected ? Tx.accent : Tx.border),
        ),
        child: emoji != null ? Text(emoji!, style: const TextStyle(fontSize: 22)) : Icon(icon, color: Tx.muted, size: 20),
      ),
    );
  }
}

/// Reacciones bajo la burbuja; tocar una pone o quita la tuya.
class _ReactionChips extends StatelessWidget {
  const _ReactionChips({required this.message, required this.onTap});

  final Message message;
  final void Function(String emoji) onTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    return Align(
      alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: 3, left: m.isMine ? 0 : 8, right: m.isMine ? 8 : 0),
        child: Wrap(spacing: 4, children: [
          for (final r in m.reactions)
            GestureDetector(
              onTap: () => onTap(r.emoji),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: m.myReaction == r.emoji ? Tx.alpha(Tx.accent, .3) : Tx.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: m.myReaction == r.emoji ? Tx.accent : Tx.border),
                ),
                child: Text(r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji, style: Tx.body(13)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Reproductor de una nota de voz dentro de la burbuja.
class _VoicePlayer extends StatelessWidget {
  const _VoicePlayer({required this.voice, required this.playKey, required this.mine});

  final VoiceNote voice;
  final String playKey;
  final bool mine;

  Future<void> _toggle(BuildContext context) async {
    final song = Song(id: 0, title: 'Nota de voz', duration: voice.duration, audioUrl: voice.url);
    await songPlayer.toggle(playKey, song);
    final error = songPlayer.error;
    if (error != null && songPlayer.currentKey == null && context.mounted) toast(context, error, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : Tx.text;
    return SizedBox(
      width: 220,
      child: ListenableBuilder(
        listenable: songPlayer,
        builder: (context, _) {
          final active = songPlayer.currentKey == playKey;
          final playing = songPlayer.isPlaying(playKey);
          final loading = songPlayer.isLoading(playKey);
          return Row(children: [
            GestureDetector(
              onTap: () => _toggle(context),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? Colors.white.withAlpha(45) : Tx.alpha(Tx.purple500, .22)),
                child: loading
                    ? Padding(padding: const EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                    : Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, color: fg, size: 18),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: StreamBuilder<Duration>(
                stream: active ? songPlayer.position : null,
                builder: (context, snap) {
                  final total = (songPlayer.duration?.inMilliseconds ?? voice.duration * 1000).toDouble();
                  final pos = active ? (snap.data?.inMilliseconds ?? 0).toDouble() : 0.0;
                  final progress = total <= 0 ? 0.0 : (pos / total).clamp(0.0, 1.0).toDouble();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: mine ? Colors.white.withAlpha(60) : Tx.surface4,
                        valueColor: AlwaysStoppedAnimation(mine ? Colors.white : Tx.accentSoft),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      active && pos > 0 ? '${clock(pos / 1000)} / ${clock(voice.duration)}' : 'Nota de voz · ${clock(voice.duration)}',
                      style: Tx.body(12, color: mine ? Colors.white.withAlpha(215) : Tx.muted),
                    ),
                  ]);
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// Tarjeta de una ubicación enviada; al tocarla se abre en la app de mapas.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.mine, this.onTap});

  final MessageLocation location;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = mine ? Colors.white : Tx.text;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 230,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0EA5E9), Color(0xFF10B981)]),
            ),
            child: Stack(children: [
              Positioned.fill(child: CustomPaint(painter: _GridPainter())),
              const Center(child: Icon(CupertinoIcons.location_solid, color: Colors.white, size: 38)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(location.name ?? 'Ubicación', maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(14.5, weight: FontWeight.w600, color: fg)),
          const SizedBox(height: 2),
          Text('${location.lat.toStringAsFixed(5)}, ${location.lng.toStringAsFixed(5)}',
              style: Tx.body(12, color: mine ? Colors.white.withAlpha(200) : Tx.muted)),
          const SizedBox(height: 4),
          Text('Abrir en Mapas', style: Tx.body(13, weight: FontWeight.w600, color: mine ? Colors.white : Tx.accent)),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(45)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.grouped,
    required this.partnerName,
    required this.onLongPress,
    this.onDoubleTap,
    this.onReplyTap,
    this.onLocationTap,
  });

  final Message message;
  final bool grouped;
  final String partnerName;
  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onReplyTap;
  final VoidCallback? onLocationTap;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final mine = m.isMine;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(!mine && grouped ? 8 : 22),
      topRight: Radius.circular(mine && grouped ? 8 : 22),
      bottomLeft: Radius.circular(mine ? 22 : 8),
      bottomRight: Radius.circular(mine ? 8 : 22),
    );
    final soft = mine ? Colors.white.withAlpha(200) : Tx.muted;
    final children = <Widget>[];
    if (m.forwarded && !m.deleted) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.arrowshape_turn_up_right, size: 12, color: soft),
          const SizedBox(width: 4),
          Text('Reenviado', style: Tx.body(12, color: soft).copyWith(fontStyle: FontStyle.italic)),
        ]),
      ));
    }
    final reply = m.reply;
    if (reply != null && !m.deleted) {
      children.add(GestureDetector(
        onTap: onReplyTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          constraints: const BoxConstraints(minWidth: 120),
          decoration: BoxDecoration(
            color: mine ? Colors.white.withAlpha(38) : Tx.alpha(Tx.purple500, .12),
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: mine ? Colors.white : Tx.accent, width: 3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(reply.isMine ? 'Tú' : partnerName, style: Tx.body(12, weight: FontWeight.w700, color: mine ? Colors.white : Tx.accent)),
            Text(reply.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: soft)),
          ]),
        ),
      ));
    }
    final story = m.story;
    if (story != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!story.expired && story.type == 'text')
            Container(
              width: 34,
              height: 50,
              decoration: BoxDecoration(gradient: Tx.storyBackground(story.background), borderRadius: BorderRadius.circular(8)),
            )
          else if (!story.expired && story.mediaUrl != null && story.type == 'image')
            NetImage(story.mediaUrl, width: 34, height: 50, radius: 8)
          else
            Container(
              width: 34,
              height: 50,
              decoration: BoxDecoration(color: Colors.white.withAlpha(30), borderRadius: BorderRadius.circular(8)),
              child: const Icon(CupertinoIcons.time, size: 14, color: Colors.white70),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              story.expired ? 'Historia no disponible' : (mine ? 'Respondiste a su historia' : 'Respondió a tu historia'),
              style: Tx.body(12, color: soft),
            ),
          ),
        ]),
      ));
    }
    if (m.deleted) {
      children.add(Text('Mensaje eliminado', style: Tx.body(14.5, color: mine ? Colors.white70 : Tx.subtle).copyWith(fontStyle: FontStyle.italic)));
    } else {
      if (m.imageUrl != null) {
        children.add(Padding(
          padding: EdgeInsets.only(bottom: (m.body ?? '').isNotEmpty ? 6 : 0),
          child: GestureDetector(
            onTap: () => pushFade(context, MediaViewer(media: [Media(type: 'image', url: m.imageUrl!)])),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 240),
              child: NetImage(m.imageUrl, radius: 16, fit: BoxFit.cover),
            ),
          ),
        ));
      }
      if (m.gif != null) {
        children.add(Padding(
          padding: EdgeInsets.only(bottom: (m.body ?? '').isNotEmpty ? 6 : 0),
          child: GifView(gif: m.gif!, maxWidth: 200, maxHeight: 200),
        ));
      }
      if (m.location != null) {
        children.add(_LocationCard(location: m.location!, mine: mine, onTap: onLocationTap));
      }
      if (m.voice != null) {
        children.add(_VoicePlayer(voice: m.voice!, playKey: 'voice:${m.id}', mine: mine));
      }
      if (m.song != null) {
        children.add(Padding(
          padding: EdgeInsets.only(bottom: (m.body ?? '').isNotEmpty ? 6 : 0),
          child: SizedBox(width: 250, child: SongChip(song: m.song!, playKey: 'msg:${m.id}', compact: true)),
        ));
      }
      if ((m.body ?? '').isNotEmpty) {
        children.add(Text(m.body!, style: Tx.body(15.5, color: mine ? Colors.white : Tx.text, height: 1.35)));
      }
    }
    if (!m.deleted && (m.pinned || m.expiresAt != null)) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (m.pinned) Icon(CupertinoIcons.pin_fill, size: 11, color: soft),
          if (m.pinned && m.expiresAt != null) const SizedBox(width: 6),
          if (m.expiresAt != null) Icon(CupertinoIcons.timer, size: 11, color: soft),
        ]),
      ));
    }
    final mediaOnly = !m.deleted &&
        (m.body ?? '').isEmpty &&
        (m.imageUrl != null || m.gif != null) &&
        m.reply == null &&
        !m.forwarded &&
        !m.pinned &&
        m.expiresAt == null;
    final bare = mediaOnly && m.gif != null && m.gif!.isSticker && m.story == null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Container(
          margin: EdgeInsets.only(top: grouped ? 2 : 8, left: mine ? 60 : 0, right: mine ? 0 : 60),
          padding: mediaOnly ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: bare
              ? null
              : BoxDecoration(
                  gradient: mine ? Tx.brand : null,
                  color: mine ? null : Tx.surface3,
                  borderRadius: radius,
                  border: mine ? null : Border.all(color: Tx.border),
                ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    );
  }
}
