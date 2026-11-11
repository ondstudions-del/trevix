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
import '../../core/chat_sender.dart';
import '../../core/device.dart';
import '../../core/e2ee.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/nav.dart';
import '../../core/push.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/chat_wallpaper.dart';
import '../../widgets/common.dart';
import '../../widgets/emoji_picker.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/song_chip.dart';
import '../../widgets/report_sheet.dart';
import 'chat_bubble.dart';
import 'chat_info_screen.dart';
import 'chat_search_screen.dart';
import 'chat_style.dart';
import 'chat_video.dart';
import 'e2ee_screens.dart';
import 'forward_screen.dart';
import 'message_info_screen.dart';
import 'photo_editor.dart';
import 'view_once_viewer.dart';

/// Conversación privada o de grupo. Sin [conversationId], el primer mensaje abre la conversación con [user].
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.conversationId, this.user, this.conversation});

  final int? conversationId;
  final User? user;

  /// Datos que ya se tienen (bandeja), para pintar la cabecera mientras carga.
  final Conversation? conversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  late int? _id = widget.conversationId ?? widget.conversation?.id;
  late Conversation? _conversation = widget.conversation;
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
  String _since = '';

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Gif? _gif;
  Message? _replyTo;
  bool _sending = false;
  bool _locating = false;
  bool _typing = false;
  DateTime? _typingSent;
  List<String> _othersTyping = const [];

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
  bool get _isGroup => _conversation?.isGroup ?? false;
  bool get _canWrite => _conversation?.blockedReason == null;
  ChatPalette get _palette => ChatPalette.of(_conversation?.theme);
  int get _myId => context.read<AppState>().me?.user.id ?? 0;

  /// El chat tiene mensajes cifrados y este teléfono aún no tiene la clave.
  bool get _locked => !e2ee.ready && ((_conversation?.e2ee ?? false) || _messages.any((m) => m.encrypted));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() {
      final typing = _input.text.trim().isNotEmpty;
      if (typing != _typing) setState(() => _typing = typing);
      _signalTyping(typing);
    });
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadOlder();
    });
    _expiry = Timer.periodic(const Duration(seconds: 10), (_) => _dropExpired());
    if (_id != null) {
      AndroidPush.activeChat(_id!);
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    if (_id != null) AndroidPush.activeChat(0);
    _signalTyping(false);
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
      _signalTyping(false);
      if (_recording) _stopRecording();
    }
  }

  /// Mientras alguien escribe se consulta más seguido para que «escribiendo…» y su mensaje lleguen antes.
  void _startPolling() {
    _poll?.cancel();
    if (_id == null) return;
    _poll = Timer.periodic(Duration(seconds: _othersTyping.isEmpty ? 4 : 2), (_) => _pollOnce());
  }

  /// Avisa que escribes (como mucho cada 3 s; el servidor lo olvida a los 6 s) o que dejaste de hacerlo.
  void _signalTyping(bool typing) {
    final id = _id;
    if (id == null) return;
    final now = DateTime.now();
    if (typing) {
      final sent = _typingSent;
      if (!_canWrite || (sent != null && now.difference(sent) < const Duration(seconds: 3))) return;
      _typingSent = now;
    } else {
      if (_typingSent == null) return;
      _typingSent = null;
    }
    () async {
      try {
        await api.post('conversations/$id/typing', {'typing': typing});
      } catch (_) {}
    }();
  }

  Future<void> _load() async {
    try {
      final uid = _myId;
      if (e2ee.status == null && uid > 0) {
        try {
          await e2ee.load(uid);
        } catch (_) {}
      }
      final results = await Future.wait([
        api.get('conversations/$_id'),
        api.get('conversations/$_id/messages', {'read': 1}),
      ]);
      if (!mounted) return;
      final conv = Conversation.fromJson(results[0].map);
      final history = results[1];
      final list = history.list.map(Message.fromJson).where((m) => !m.expired).toList();
      setState(() {
        _conversation = conv;
        _online = conv.online;
        _messages
          ..clear()
          ..addAll(list);
        _older = history.next;
        _seenId = asInt(history.meta['seen_id'], conv.partnerLastReadId);
        _since = asStr(history.meta['now']);
        _loading = false;
        _error = null;
      });
      _decrypt([...list, ...conv.pinned]);
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
      if (!mounted) return;
      final conv = Conversation.fromJson(res.map);
      setState(() => _conversation = conv);
      _decrypt(conv.pinned);
    } catch (_) {}
  }

  /// Descifra los mensajes (y las respuestas citadas) que aún no lo están.
  Future<void> _decrypt(Iterable<Message> list) async {
    final id = _id;
    if (id == null || !e2ee.ready) return;
    var changed = false;
    for (final m in list.toList()) {
      final c = m.cipher;
      if (c != null && m.payload == null && !m.undecryptable) {
        final p = await e2ee.open(id, m.id, c.epoch, m.senderId ?? 0, c.ciphertext);
        if (p != null) {
          m.payload = p;
        } else {
          m.undecryptable = true;
        }
        changed = true;
      }
      final r = m.reply;
      final rc = r?.cipher;
      if (r != null && rc != null && const {'Mensaje cifrado', 'Encrypted message'}.contains(r.text)) {
        final p = await e2ee.open(id, r.id, rc.epoch, r.senderId ?? (r.isMine ? _myId : 0), rc.ciphertext);
        if (p != null) {
          r.text = p.summary;
          changed = true;
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _unlock() async {
    if (await ensureE2ee(context) && mounted) {
      for (final m in _messages) {
        m.undecryptable = false;
      }
      setState(() {});
      _decrypt([..._messages, ...?_conversation?.pinned]);
    }
  }

  Future<void> _loadOlder() async {
    final older = _older;
    if (older == null || _loadingOlder || _id == null) return;
    _loadingOlder = true;
    try {
      final res = await api.get('conversations/$_id/messages', older);
      if (mounted) {
        final known = _messages.map((m) => m.id).toSet();
        final list = res.list.map(Message.fromJson).where((m) => !known.contains(m.id) && !m.expired).toList();
        setState(() {
          _messages.insertAll(0, list);
          _older = res.next;
        });
        _decrypt(list);
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
      final c = _conversation;
      final keyChanged = c != null && asInt(res.meta['key_epoch'], c.keyEpoch) != c.keyEpoch;
      final typing = res.meta['typing'] is List ? (res.meta['typing'] as List).map((e) => asStr(e)).where((n) => n.isNotEmpty).toList() : <String>[];
      final typingChanged = typing.isEmpty != _othersTyping.isEmpty;
      setState(() {
        _othersTyping = typing;
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
        if (c != null) {
          c.pinned = pinned;
          if (res.meta.containsKey('disappear_seconds')) c.disappearSeconds = asInt(res.meta['disappear_seconds']);
          if (res.meta['theme'] is String) c.theme = res.meta['theme'] as String;
          if (res.meta['wallpaper'] is String) c.wallpaper = res.meta['wallpaper'] as String;
          if (res.meta.containsKey('e2ee')) c.e2ee = asBool(res.meta['e2ee']);
          c.keyEpoch = asInt(res.meta['key_epoch'], c.keyEpoch);
          if (res.meta['read_states'] is List) c.readStates = asList(res.meta['read_states'], ReadState.fromJson);
        }
        _seenId = asInt(res.meta['seen_id'], _seenId);
        _online = asBool(res.meta['online']);
        final now = asStr(res.meta['now']);
        if (now.isNotEmpty) _since = now;
      });
      if (keyChanged) e2ee.invalidate(_id!);
      if (typingChanged) _startPolling();
      _decrypt([...fresh, ...pinned]);
      if (fresh.any((m) => !m.isMine)) HapticFeedback.selectionClick();
      if (fresh.any((m) => m.isSystem) && _isGroup) _reloadConversation();
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
          toast(context, tr('Ese mensaje ya no está disponible.'), error: true);
          return;
        }
        setState(() {
          _messages
            ..clear()
            ..addAll(list);
          _older = res.next;
        });
        _decrypt(list);
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

  Future<void> _pickPhoto(ImageSource source) async {
    XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, imageQuality: 90, maxWidth: 2000);
    } catch (_) {
      if (mounted) {
        toast(context,
            source == ImageSource.camera ? tr('No se pudo abrir la cámara. Revisa el permiso.') : tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'),
            error: true);
      }
      return;
    }
    if (file == null || !mounted) return;
    final edited = await editPhoto(context, file.path, viewSeconds: _options.viewSeconds, stickers: context.read<AppState>().feature('gifs'));
    if (edited == null || !mounted) return;
    await _deliver(
        Outgoing(text: edited.viewSeconds == null ? edited.caption : '', imagePath: edited.path, viewSeconds: edited.viewSeconds, replyTo: _replyTo?.id));
  }

  Future<void> _pickVideo(ImageSource source) async {
    XFile? file;
    try {
      file = await ImagePicker().pickVideo(
        source: source,
        maxDuration: source == ImageSource.camera ? const Duration(seconds: chatVideoMaxSeconds) : null,
      );
    } catch (_) {
      if (mounted) {
        toast(context,
            source == ImageSource.camera ? tr('No se pudo abrir la cámara. Revisa el permiso.') : tr('No se pudo abrir la galería. Revisa el permiso de Fotos.'),
            error: true);
      }
      return;
    }
    if (file == null || !mounted) return;
    final video = await prepareVideo(context, file.path, viewSeconds: _options.viewSeconds);
    if (video == null || !mounted) return;
    try {
      await _deliver(Outgoing(
        text: video.caption,
        videoPath: video.path,
        videoSeconds: video.seconds,
        videoWidth: video.width,
        videoHeight: video.height,
        posterPath: video.poster,
        viewSeconds: video.viewSeconds,
        replyTo: _replyTo?.id,
      ));
    } finally {
      final poster = video.poster;
      if (poster != null) {
        try {
          await File(poster).delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _pickGif() async {
    final gif = await pickGif(context);
    if (gif != null && mounted) setState(() => _gif = gif);
  }

  Future<void> _pickEmoji() async {
    final emoji = await pickEmoji(context);
    if (emoji == null || !mounted) return;
    final sel = _input.selection;
    final text = _input.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _input.value = TextEditingValue(text: text.replaceRange(start, end, emoji), selection: TextSelection.collapsed(offset: start + emoji.length));
  }

  void _attachMenu() {
    final state = context.read<AppState>();
    actionSheet(context, [
      SheetAction(tr('Cámara'), CupertinoIcons.camera, () => _pickPhoto(ImageSource.camera)),
      SheetAction(tr('Foto de la galería'), CupertinoIcons.photo, () => _pickPhoto(ImageSource.gallery)),
      SheetAction(tr('Grabar video'), CupertinoIcons.videocam, () => _pickVideo(ImageSource.camera)),
      SheetAction(tr('Video de la galería'), CupertinoIcons.film, () => _pickVideo(ImageSource.gallery)),
      if (state.feature('gifs')) SheetAction(tr('GIF y stickers'), CupertinoIcons.smiley, _pickGif),
      SheetAction(tr('Ubicación actual'), CupertinoIcons.location, _sendLocation),
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
        tr('Enviar ubicación'),
        '${p.name ?? tr('Tu ubicación actual')}\n${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}\n\n'
            '${_isGroup ? tr('El grupo verá tu ubicación exacta.') : tr('{name} verá tu ubicación exacta.', {'name': _partnerName})}',
        action: tr('Enviar'),
      );
      if (ok) {
        await _deliver(Outgoing(location: {'lat': p.lat, 'lng': p.lng, if (p.name != null) 'name': p.name}, replyTo: _replyTo?.id));
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
      if (mounted) toast(context, tr('Permite el micrófono en Ajustes › TREVIX para grabar notas de voz.'), error: true);
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
      if (mounted) toast(context, tr('No se pudo iniciar la grabación.'), error: true);
      return;
    }
    _deleteVoiceFile();
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recordStart = DateTime.now();
      _recordSeconds = 0;
      _voicePath = null;
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
      toast(context, tr('La nota de voz debe durar al menos {n} s. Mantén la grabación un poco más.', {'n': _voiceMin}), error: true);
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
    final gif = _gif;
    final voice = _voicePath;
    if ((text.isEmpty && gif == null && voice == null) || _sending || _recording) return;
    if (voice != null) await songPlayer.stop('voice-draft');
    final ok = await _deliver(Outgoing(
      text: voice != null ? '' : text,
      gif: gif,
      voicePath: voice,
      voiceSeconds: _voiceSeconds,
      replyTo: _replyTo?.id,
    ));
    if (!ok || !mounted) return;
    if (voice == null) _input.clear();
    if (voice != null) _deleteFile(voice);
    setState(() {
      _gif = null;
      _voicePath = null;
    });
  }

  Future<void> _quickLike() => _deliver(Outgoing(text: '👍', replyTo: _replyTo?.id));

  /// Envía el mensaje (cifrado si el chat lo permite) y lo añade al chat. Devuelve false si falló.
  Future<bool> _deliver(Outgoing out, {bool retried = false}) async {
    if (_sending && !retried) return false;
    setState(() => _sending = true);
    var ok = false;
    try {
      final sent = await ChatSender.send(
        conversationId: _id,
        to: _id == null ? _user?.username : null,
        chatEncrypted: _conversation?.e2ee ?? false,
        myId: _myId,
        out: out,
      );
      final message = sent.message;
      ok = true;
      if (mounted) {
        setState(() {
          _replyTo = null;
          if (message != null && !_messages.any((m) => m.id == message.id)) _messages.add(message);
        });
        if (message != null) _decrypt([message]);
      }
      if (_id == null && sent.conversationId > 0) {
        _id = sent.conversationId;
        AndroidPush.activeChat(sent.conversationId);
        _startPolling();
        _reloadConversation();
      }
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } on E2eeLocked {
      if (mounted) setState(() => _sending = false);
      if (!retried && mounted && await ensureE2ee(context)) return _deliver(out, retried: true);
      return false;
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
    return ok;
  }

  // ---------- Acciones sobre un mensaje ----------

  bool _forwardable(Message m) {
    if (m.deleted || m.viewOnce != null || m.isSystem) return false;
    if (m.encrypted) return m.payload != null && !m.mediaCleared;
    return (m.body ?? '').isNotEmpty || m.imageUrl != null || m.video != null || m.voice != null || m.gif != null || m.location != null;
  }

  bool _canDeleteForAll(Message m) => !m.deleted && (m.isMine || (_isGroup && (_conversation?.group?.isAdmin ?? false)));

  String _nameOf(Message m) => m.isMine ? tr('Tú') : (_isGroup ? (m.sender?.displayName ?? tr('Alguien')) : _partnerName);

  void _reply(Message m) {
    if (m.deleted || !_canWrite || m.isSystem) return;
    setState(() => _replyTo = m);
    _focus.requestFocus();
  }

  void _messageMenu(Message m) {
    if (m.isSystem || _id == null) return;
    HapticFeedback.selectionClick();
    final text = m.text;
    final pinLabel = _isGroup ? (m.pinned ? tr('Quitar de destacados') : tr('Destacar')) : (m.pinned ? tr('Dejar de fijar') : tr('Fijar'));
    final actions = <SheetAction>[
      if (!m.deleted && _canWrite) SheetAction(tr('Responder'), CupertinoIcons.reply, () => _reply(m)),
      if (_forwardable(m))
        SheetAction(tr('Reenviar…'), CupertinoIcons.arrowshape_turn_up_right, () => push(context, ForwardScreen(message: m, max: _options.maxForward))),
      if (text.isNotEmpty && m.viewOnce == null)
        SheetAction(tr('Copiar'), CupertinoIcons.doc_on_doc, () {
          Clipboard.setData(ClipboardData(text: text));
          toast(context, tr('Mensaje copiado.'));
        }),
      if (!m.deleted) SheetAction(pinLabel, m.pinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin, () => _pin(m, !m.pinned)),
      if (m.isMine && !m.deleted) SheetAction(tr('Info'), CupertinoIcons.info_circle, () => push(context, MessageInfoScreen(message: m, isGroup: _isGroup))),
      SheetAction(tr('Eliminar para mí'), CupertinoIcons.eye_slash, () => _hide(m)),
      if (_canDeleteForAll(m)) SheetAction(tr('Eliminar para todos'), CupertinoIcons.trash, () => _deleteForAll(m), destructive: true),
      if (!m.isMine && !m.deleted) SheetAction(tr('Reportar mensaje'), CupertinoIcons.flag, () => showReportSheet(context, 'message', m.id), destructive: true),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SheetFrame(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!m.deleted)
              Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(30)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final e in _options.reactions)
                    ReactionOption(
                      emoji: e,
                      selected: m.myReaction == e,
                      onTap: () {
                        Navigator.pop(ctx);
                        _react(m, e);
                      },
                    ),
                  ReactionOption(
                    icon: CupertinoIcons.add,
                    onTap: () async {
                      Navigator.pop(ctx);
                      final emoji = await pickEmoji(context);
                      if (emoji != null) _react(m, emoji);
                    },
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text('${_nameOf(m)}: ${m.summary}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(13, color: Tx.subtle)),
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
      _decrypt(pinned);
      toast(context, '${res.map['message'] ?? (pin ? tr('Mensaje fijado.') : tr('Mensaje desfijado.'))}');
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _hide(Message m) async {
    if (!await confirm(
        context,
        tr('Eliminar para mí'),
        _isGroup
            ? tr('El mensaje dejará de verse en tu chat. Los demás lo seguirán viendo.')
            : tr('El mensaje dejará de verse en tu chat. {name} lo seguirá viendo.', {'name': _partnerName}),
        action: tr('Eliminar'),
        destructive: true)) {
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
    final other = !m.isMine;
    if (!await confirm(
      context,
      tr('Eliminar para todos'),
      other
          ? tr('Como administrador, eliminarás este mensaje de {name} para todo el grupo.', {'name': m.sender?.displayName ?? tr('esta persona')})
          : tr('Se mostrará como «Mensaje eliminado» para todos.'),
      action: tr('Eliminar'),
      destructive: true,
    )) {
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

  Future<void> _openViewOnce(Message m) async {
    await pushFade<bool>(context, ViewOnceViewer(message: m));
    if (!mounted) return;
    setState(() {
      m.viewOnce?.viewed = true;
      m.viewOnce?.views = (m.viewOnce?.views ?? 0) + 1;
    });
  }

  Future<void> _openLocation(MessageLocation loc) async {
    final label = Uri.encodeComponent(loc.name ?? tr('Ubicación'));
    final ll = '${loc.lat},${loc.lng}';
    final uris = Platform.isIOS
        ? [Uri.parse('https://maps.apple.com/?ll=$ll&q=$label')]
        : [Uri.parse('geo:$ll?q=$ll($label)'), Uri.parse('https://www.google.com/maps/search/?api=1&query=$ll')];
    for (final uri in uris) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (mounted) toast(context, tr('No se pudo abrir la aplicación de mapas.'), error: true);
  }

  // ---------- Información del chat ----------

  Future<void> _openInfo() async {
    final c = _conversation;
    if (c == null) return;
    final result = await push<ChatInfoResult>(context, ChatInfoScreen(conversation: c));
    if (!mounted) return;
    if (result?.left == true) {
      Navigator.of(context).pop();
      return;
    }
    if (result?.search == true) {
      _openSearch();
    } else if (result?.jumpTo != null) {
      _jumpTo(result!.jumpTo!);
    }
    await _reloadConversation();
    _pollOnce();
  }

  Future<void> _openSearch() async {
    final id = _id;
    if (id == null) return;
    final messageId = await push<int>(context, ChatSearchScreen(conversationId: id, partnerName: _partnerName));
    if (messageId != null && mounted) _jumpTo(messageId);
  }

  Future<void> _unblock() async {
    final c = _conversation;
    if (c == null) return;
    try {
      final res = await api.delete('users/${c.user.id}/block');
      if (mounted) toast(context, '${res.map['message'] ?? tr('Desbloqueaste la cuenta.')}');
      await _reloadConversation();
    } catch (e) {
      if (mounted) toastError(context, e);
    }
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
          Text(_isGroup ? tr('Mensajes destacados') : tr('Mensajes fijados'), style: Tx.display(17), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          for (final p in pinned)
            ListTile(
              leading: Icon(CupertinoIcons.pin_fill, color: _palette.accent, size: 18),
              title: Text(p.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: Tx.body(15)),
              subtitle: Text(_nameOf(p), style: Tx.body(12, color: Tx.subtle)),
              onTap: () {
                Navigator.pop(ctx);
                _jumpTo(p.id);
              },
              trailing: IconButton(
                tooltip: tr('Quitar'),
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

  /// «escribiendo…» en los chats privados; en los grupos, quién escribe.
  String? _typingText() {
    final names = _othersTyping;
    if (names.isEmpty) return null;
    if (!_isGroup) return tr('escribiendo…');
    if (names.length == 1) return tr('{name} está escribiendo…', {'name': names.first});
    if (names.length == 2) return tr('{name1} y {name2} están escribiendo…', {'name1': names[0], 'name2': names[1]});
    return tr('Varias personas están escribiendo…');
  }

  String _subtitle() {
    final c = _conversation;
    if (c == null) return '';
    final typing = _typingText();
    if (typing != null) return typing;
    if (c.isGroup) {
      final n = c.group?.membersCount ?? 0;
      return plural(n, 'miembro', 'miembros');
    }
    if (_online) return tr('Activo ahora');
    return '@${c.user.username}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _conversation;
    final blocked = c?.blockedReason;
    final accent = _palette.accent;
    return Scaffold(
      appBar: GlassBar(
        titleWidget: c == null && _user == null
            ? const SizedBox.shrink()
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: c != null ? _openInfo : null,
                child: Row(children: [
                  if (c != null) ChatAvatar(conversation: c, size: 38, online: _online && !c.isGroup) else Avatar(user: _user!, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Row(children: [
                        Flexible(
                          child: Text(_partnerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(16, weight: FontWeight.w700)),
                        ),
                        if (!(c?.isGroup ?? true) && (_user?.isVerified ?? false)) ...[const SizedBox(width: 4), const VerifiedBadge(size: 14)],
                      ]),
                      Row(children: [
                        if (c?.e2ee ?? false) ...[Icon(CupertinoIcons.lock_fill, size: 10, color: Tx.subtle), const SizedBox(width: 3)],
                        if ((c?.disappearSeconds ?? 0) > 0) ...[Icon(CupertinoIcons.timer, size: 11, color: accent), const SizedBox(width: 3)],
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _subtitle(),
                              key: ValueKey(_othersTyping.isNotEmpty),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Tx.body(12,
                                  weight: _othersTyping.isNotEmpty ? FontWeight.w600 : FontWeight.w400,
                                  color: _othersTyping.isNotEmpty ? accent : (_online && !_isGroup ? Tx.success : Tx.subtle)),
                            ),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
        actions: [
          if (c != null)
            IconButton(
              onPressed: _openInfo,
              tooltip: tr('Información del chat'),
              icon: Icon(CupertinoIcons.info_circle_fill, color: accent, size: 26),
            ),
        ],
      ),
      body: Column(children: [
        if ((c?.pinned ?? const []).isNotEmpty) _pinnedBanner(c!.pinned),
        if (_locked) _lockedBanner(),
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
              if (c?.blockedByMe ?? false)
                TextButton(onPressed: _unblock, child: Text(tr('Desbloquear'), style: Tx.body(14, weight: FontWeight.w600, color: Tx.accent))),
            ]),
          )
        else
          _composer(),
      ]),
    );
  }

  Widget _lockedBanner() {
    return Material(
      color: Tx.surface1,
      child: InkWell(
        onTap: _unlock,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tx.border))),
          child: Row(children: [
            Icon(CupertinoIcons.lock_shield_fill, color: _palette.accent, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('Este chat está cifrado. Escribe tu PIN para leer y enviar mensajes.'), style: Tx.body(13.5))),
            Text('PIN', style: Tx.body(14, weight: FontWeight.w700, color: _palette.accent)),
          ]),
        ),
      ),
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
            Container(width: 3, height: 32, decoration: BoxDecoration(gradient: _palette.gradient, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  '${_isGroup ? tr('Mensaje destacado') : tr('Mensaje fijado')}${pinned.length > 1 ? ' ${tr('{n} de {total}', {'n': index + 1, 'total': pinned.length})}' : ''}',
                  style: Tx.body(12, weight: FontWeight.w700, color: _palette.accent),
                ),
                Text(p.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13.5, color: Tx.text)),
              ]),
            ),
            IconButton(onPressed: _pinnedList, tooltip: tr('Ver todos'), icon: Icon(CupertinoIcons.pin, color: Tx.muted, size: 20)),
          ]),
        ),
      ),
    );
  }

  /// Quién vio cada mensaje: en los chats privados, la foto de la otra persona bajo el último que leyó; en los
  /// grupos, la de cada participante bajo el último que leyó.
  Map<int, List<User>> _seenMap() {
    final out = <int, List<User>>{};
    final visible = _messages.where((m) => !m.isSystem).toList();
    if (visible.isEmpty) return out;
    final c = _conversation;
    if (c == null) return out;
    if (c.isGroup) {
      final me = _myId;
      for (final r in c.readStates) {
        if (r.userId == me || r.lastReadId <= 0) continue;
        final target = visible.lastWhere((m) => m.id <= r.lastReadId, orElse: () => Message(id: 0, conversationId: 0));
        if (target.id > 0) out.putIfAbsent(target.id, () => []).add(r.user);
      }
    } else if (_seenId > 0) {
      final target = visible.lastWhere((m) => m.isMine && m.id <= _seenId, orElse: () => Message(id: 0, conversationId: 0));
      if (target.id > 0) out[target.id] = [c.user];
    }
    return out;
  }

  bool _sameCluster(Message a, Message b) =>
      !a.isSystem &&
      !b.isSystem &&
      a.senderId == b.senderId &&
      a.createdAt != null &&
      b.createdAt != null &&
      b.createdAt!.difference(a.createdAt!).inMinutes.abs() < 5;

  Widget _body() {
    if (_loading) return const Loading();
    if (_error != null) {
      return ErrorState(
          error: _error!,
          onRetry: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _load();
          });
    }
    if (_messages.isEmpty) {
      final c = _conversation;
      final user = _user;
      return Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (c != null) ChatAvatar(conversation: c, size: 90) else if (user != null) Avatar(user: user, size: 90),
            const SizedBox(height: 14),
            Text(_partnerName, style: Tx.display(20)),
            const SizedBox(height: 6),
            Text(_isGroup ? tr('Escribe el primer mensaje del grupo.') : tr('Saluda y empieza la conversación.'), style: Tx.body(14, color: Tx.muted)),
            if (e2ee.ready) ...[
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.lock_fill, size: 12, color: Tx.subtle),
                const SizedBox(width: 5),
                Text(tr('Cifrado de extremo a extremo cuando todos usan la app'), style: Tx.body(12, color: Tx.subtle)),
              ]),
            ],
          ]),
        ),
      );
    }
    final lastMine = _messages.lastWhere((m) => m.isMine && !m.isSystem, orElse: () => Message(id: 0, conversationId: 0)).id;
    final onWallpaper = (_conversation?.wallpaper ?? 'default') != 'default';
    final seen = _seenMap();
    final palette = _palette;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        itemCount: _messages.length + (_older != null ? 1 : 0) + (_othersTyping.isNotEmpty ? 1 : 0),
        itemBuilder: (context, row) {
          if (_othersTyping.isNotEmpty && row == 0) return _TypingBubble(label: _isGroup ? _typingText() : null);
          final i = _othersTyping.isNotEmpty ? row - 1 : row;
          if (i >= _messages.length) return const Loading(padding: 16);
          final index = _messages.length - 1 - i;
          final m = _messages[index];
          final prev = index > 0 ? _messages[index - 1] : null;
          final next = index < _messages.length - 1 ? _messages[index + 1] : null;
          final showDate = prev == null || m.createdAt == null || prev.createdAt == null || m.createdAt!.difference(prev.createdAt!).inMinutes > 30;
          final nextDate = next != null && next.createdAt != null && m.createdAt != null && next.createdAt!.difference(m.createdAt!).inMinutes > 30;
          final first = showDate || !_sameCluster(prev, m);
          final last = next == null || nextDate || !_sameCluster(m, next);
          final dateStyle = Tx.body(11.5, weight: FontWeight.w600, color: onWallpaper ? Colors.white : Tx.subtle);
          final seenBy = seen[m.id];
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
                SystemNote(text: m.systemText ?? '', onWallpaper: onWallpaper)
              else
                SwipeToReply(
                  enabled: !m.deleted && _canWrite,
                  onReply: () => _reply(m),
                  child: ChatBubble(
                    message: m,
                    palette: palette,
                    first: first,
                    last: last,
                    highlight: _highlight == m.id,
                    showName: _isGroup && first,
                    avatarSlot: true,
                    showAvatar: last && (m.sender != null || !_isGroup),
                    replyName: (r) => r.isMine ? tr('Tú') : (_isGroup ? r.senderName : _partnerName),
                    onAvatarTap: m.sender != null ? () => openProfile(context, m.sender!.username) : null,
                    onLongPress: () => _messageMenu(m),
                    onDoubleTap: m.deleted || m.viewOnce != null ? null : () => _react(m, _options.reactions.isEmpty ? '❤️' : _options.reactions.first),
                    onReplyTap: m.reply != null && m.reply!.available ? () => _jumpTo(m.reply!.id) : null,
                    onLocationTap: () {
                      final loc = m.location ?? MessageLocation.maybe(m.payload?.location);
                      if (loc != null) _openLocation(loc);
                    },
                    onViewOnce: () => _openViewOnce(m),
                    onUnlock: m.encrypted && !e2ee.ready ? _unlock : null,
                  ),
                ),
              if (seenBy != null && seenBy.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(padding: const EdgeInsets.only(top: 3, right: 2), child: SeenAvatars(users: seenBy, size: 15)),
                )
              else if (m.id == lastMine && m.isMine && !m.deleted && !_isGroup && m.id > _seenId)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3, right: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.checkmark_alt_circle, size: 13, color: onWallpaper ? Colors.white70 : Tx.subtle),
                      const SizedBox(width: 3),
                      Text(tr('Enviado'), style: Tx.body(11, color: onWallpaper ? Colors.white70 : Tx.subtle)),
                    ]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }

  Widget _composer() {
    final gif = _gif;
    final reply = _replyTo;
    final state = context.read<AppState>();
    final accent = _palette.accent;
    return Container(
      decoration: BoxDecoration(color: Tx.bg, border: Border(top: BorderSide(color: Tx.border))),
      padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : MediaQuery.of(context).padding.bottom)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (reply != null)
          Container(
            margin: const EdgeInsets.fromLTRB(8, 0, 4, 6),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(reply.isMine ? tr('Respondiéndote a ti') : tr('Respondiendo a {name}', {'name': _nameOf(reply)}), style: Tx.body(12.5, weight: FontWeight.w700)),
                  Text(reply.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(13, color: Tx.muted)),
                ]),
              ),
              IconButton(onPressed: () => setState(() => _replyTo = null), icon: Icon(CupertinoIcons.xmark, color: Tx.muted, size: 18)),
            ]),
          ),
        if (_recording)
          _recordingBar()
        else if (_voicePath != null)
          _voiceDraftBar()
        else ...[
          if (gif != null) GifAttachment(gif: gif, onRemove: () => setState(() => _gif = null)),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (_typing)
              _ComposerIcon(icon: CupertinoIcons.chevron_right, color: accent, onTap: () => setState(() => _typing = false))
            else ...[
              _ComposerIcon(
                icon: CupertinoIcons.add_circled_solid,
                color: accent,
                busy: _locating,
                onTap: _attachMenu,
              ),
              _ComposerIcon(icon: CupertinoIcons.camera_fill, color: accent, onTap: () => _pickPhoto(ImageSource.camera)),
              _ComposerIcon(icon: CupertinoIcons.photo_fill, color: accent, onTap: () => _pickPhoto(ImageSource.gallery)),
              if (state.feature('voice_notes')) _ComposerIcon(icon: CupertinoIcons.mic_fill, color: accent, onTap: _startRecording),
            ],
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                decoration: BoxDecoration(color: Tx.surface2, borderRadius: BorderRadius.circular(22)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: state.limit('message_body', 2000),
                      textCapitalization: TextCapitalization.sentences,
                      style: Tx.body(15.5),
                      onTap: () => setState(() => _typing = _input.text.trim().isNotEmpty),
                      decoration: InputDecoration(
                        hintText: tr('Mensaje'),
                        hintStyle: Tx.body(15.5, color: Tx.subtle),
                        counterText: '',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _pickEmoji,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
                      child: Icon(CupertinoIcons.smiley_fill, color: accent, size: 24),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (_, value, __) {
                final hasContent = value.text.trim().isNotEmpty || _gif != null;
                if (_sending) {
                  return const SizedBox(width: 44, height: 40, child: Center(child: CupertinoActivityIndicator()));
                }
                if (!hasContent) {
                  return GestureDetector(
                    onTap: _quickLike,
                    child: const SizedBox(width: 44, height: 40, child: Center(child: Text('👍', style: TextStyle(fontSize: 26)))),
                  );
                }
                return _ComposerIcon(icon: CupertinoIcons.paperplane_fill, color: accent, onTap: _send);
              },
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _recordingBar() {
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(onPressed: _cancelVoice, tooltip: tr('Descartar nota de voz'), icon: const Icon(CupertinoIcons.trash, color: Tx.danger)),
        const _RecDot(),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tr('Grabando… {time} / {max}', {'time': clock(_recordSeconds), 'max': clock(_voiceMax)}), style: Tx.body(15, weight: FontWeight.w600)),
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
    final draft = Song(id: 0, title: tr('Nota de voz'), duration: _voiceSeconds, audioUrl: Uri.file(_voicePath!).toString());
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(onPressed: _sending ? null : _cancelVoice, tooltip: tr('Descartar nota de voz'), icon: const Icon(CupertinoIcons.trash, color: Tx.danger)),
        PlayButton(playKey: 'voice-draft', song: draft, size: 38),
        const SizedBox(width: 12),
        Expanded(child: Text(tr('Nota de voz · {time}', {'time': clock(_voiceSeconds)}), style: Tx.body(15, weight: FontWeight.w600))),
        _sending
            ? const SizedBox(width: 44, height: 44, child: Center(child: CupertinoActivityIndicator()))
            : GestureDetector(
                onTap: _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: _palette.gradient, shape: BoxShape.circle),
                  child: const Icon(CupertinoIcons.paperplane_fill, color: Colors.white, size: 19),
                ),
              ),
      ]),
    );
  }
}

class _ComposerIcon extends StatelessWidget {
  const _ComposerIcon({required this.icon, required this.color, required this.onTap, this.busy = false});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 38,
        height: 40,
        child: Center(child: busy ? const CupertinoActivityIndicator() : Icon(icon, color: color, size: 25)),
      ),
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

/// Burbuja con tres puntos que saltan mientras la otra persona (o alguien del grupo) escribe.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble({this.label});

  /// En los grupos, quién escribe.
  final String? label;

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bubble = Tx.isDark ? const Color(0xFF26262B) : const Color(0xFFEDEDF1);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 36, top: 6, bottom: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (widget.label != null)
            Padding(padding: const EdgeInsets.only(left: 12, bottom: 3), child: Text(widget.label!, style: Tx.body(11.5, color: Tx.subtle))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: bubble, borderRadius: BorderRadius.circular(20)),
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  _dot(i),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dot(int i) {
    final t = (_c.value - i * .16) % 1.0;
    final wave = t < .5 ? math.sin(t * 2 * math.pi) : 0.0;
    return Transform.translate(
      offset: Offset(0, -4 * wave),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: Tx.alpha(Tx.muted, .55 + .45 * wave), shape: BoxShape.circle),
      ),
    );
  }
}
