import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/api.dart';
import '../../core/audio.dart';
import '../../core/device.dart';
import '../../core/format.dart';
import '../../core/nav.dart';
import '../../core/routes.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/gif_picker.dart';
import '../../widgets/media.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/song_chip.dart';

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
  bool _polling = false;

  final _input = TextEditingController();
  final _scroll = ScrollController();
  XFile? _image;
  Gif? _gif;
  bool _sending = false;

  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  DateTime? _recordStart;
  Timer? _recordTimer;
  int _recordSeconds = 0;
  String? _voicePath;
  int _voiceSeconds = 0;

  User? get _user => _conversation?.user ?? widget.user;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 300) _loadOlder();
    });
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
    _recordTimer?.cancel();
    if (_recording) _recorder.cancel();
    _recorder.dispose();
    _deleteVoiceFile();
    songPlayer.stop('voice-draft');
    _input.dispose();
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
          ..addAll(history.list.map(Message.fromJson));
        _older = history.next;
        _seenId = asInt(history.meta['seen_id'], conv.partnerLastReadId);
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

  Future<void> _loadOlder() async {
    final older = _older;
    if (older == null || _loadingOlder || _id == null) return;
    _loadingOlder = true;
    try {
      final res = await api.get('conversations/$_id/messages', older);
      if (mounted) {
        setState(() {
          _messages.insertAll(0, res.list.map(Message.fromJson));
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
      final res = await api.get('conversations/$_id/messages', {'after': last, 'from': first, 'read': 1});
      if (!mounted) return;
      final fresh = res.list.map(Message.fromJson).where((m) => !_messages.any((x) => x.id == m.id)).toList();
      final deleted = res.meta['deleted'] is List ? (res.meta['deleted'] as List).map((e) => asInt(e)).toSet() : <int>{};
      setState(() {
        _messages.addAll(fresh);
        for (final m in _messages) {
          if (deleted.contains(m.id) && !m.deleted) m.markDeleted();
        }
        _seenId = asInt(res.meta['seen_id'], _seenId);
        _online = asBool(res.meta['online']);
      });
      if (fresh.any((m) => !m.isMine)) HapticFeedback.selectionClick();
    } catch (_) {}
    _polling = false;
  }

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

  Future<void> _send() async {
    final text = _input.text.trim();
    final image = _image;
    final gif = _gif;
    final voice = _voicePath;
    if ((text.isEmpty && image == null && gif == null && voice == null) || _sending || _recording) return;
    setState(() => _sending = true);
    try {
      final fields = <String, String>{
        'body': voice != null ? '' : text,
        if (gif != null) 'gif_id': gif.id,
        if (gif != null) 'gif_kind': gif.kind,
        if (_id == null) 'to': _user!.username,
      };
      final path = _id == null ? 'messages' : 'conversations/$_id/messages';
      final ApiResponse res;
      if (voice != null) {
        await songPlayer.stop('voice-draft');
        res = await api.upload(path, fields: fields, files: [Upload('voice', voice, filename: 'nota.m4a')]);
      } else if (image != null) {
        res = await api.upload(path, fields: fields, files: [Upload('image', image.path, filename: image.name)]);
      } else {
        res = await api.post(path, fields);
      }
      final data = res.map;
      final message = data['message'] is Map ? Message.fromJson(asMap(data['message'])) : null;
      final newId = asInt(data['conversation_id']);
      if (voice == null) _input.clear();
      if (voice != null) _deleteFile(voice);
      setState(() {
        _image = null;
        _gif = null;
        _voicePath = null;
        if (message != null && !_messages.any((m) => m.id == message.id)) _messages.add(message);
      });
      if (_id == null && newId > 0) {
        _id = newId;
        _startPolling();
        api.get('conversations/$newId').then((r) {
          if (mounted) setState(() => _conversation = Conversation.fromJson(r.map));
        }).catchError((_) {});
      }
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    } catch (e) {
      if (mounted) toastError(context, e);
    }
    if (mounted) setState(() => _sending = false);
  }

  void _messageMenu(Message m) {
    if (m.deleted) return;
    actionSheet(context, [
      if ((m.body ?? '').isNotEmpty)
        SheetAction('Copiar', CupertinoIcons.doc_on_doc, () {
          Clipboard.setData(ClipboardData(text: m.body!));
          toast(context, 'Mensaje copiado.');
        }),
      if (m.isMine)
        SheetAction('Eliminar para todos', CupertinoIcons.trash, () async {
          if (!await confirm(context, 'Eliminar mensaje', 'Se mostrará como «Mensaje eliminado».', action: 'Eliminar', destructive: true)) return;
          try {
            await api.delete('messages/${m.id}');
            if (mounted) setState(m.markDeleted);
          } catch (e) {
            if (mounted) toastError(context, e);
          }
        }, destructive: true),
      if (!m.isMine) SheetAction('Reportar mensaje', CupertinoIcons.flag, () => showReportSheet(context, 'message', m.id), destructive: true),
    ]);
  }

  Future<void> _toggleMute() async {
    final c = _conversation;
    if (c == null) return;
    try {
      final res = await api.patch('conversations/${c.id}', {'muted': !c.muted});
      setState(() => c.muted = asBool(res.map['muted']));
      if (mounted) {
        toast(context, '${res.map['message'] ?? ''}');
        context.read<AppState>().refreshCounts();
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final blocked = _conversation?.blockedReason;
    return Scaffold(
      appBar: GlassBar(
        titleWidget: user == null
            ? const SizedBox.shrink()
            : GestureDetector(
                onTap: () => openProfile(context, user.username),
                child: Row(children: [
                  Avatar(user: user, size: 38, online: _online),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      NameLine(user: user, size: 15.5),
                      Text(_online ? 'En línea' : '@${user.username}', style: Tx.body(12, color: _online ? Tx.success : Tx.subtle)),
                    ]),
                  ),
                ]),
              ),
        actions: [
          if (_conversation != null)
            IconButton(
              onPressed: () => actionSheet(context, [
                SheetAction('Ver perfil', CupertinoIcons.person, () => openProfile(context, user!.username)),
                SheetAction(_conversation!.muted ? 'Reactivar avisos' : 'Silenciar conversación',
                    _conversation!.muted ? CupertinoIcons.bell : CupertinoIcons.bell_slash, _toggleMute),
              ]),
              icon: const Icon(CupertinoIcons.ellipsis_circle, color: Tx.text),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(child: _body()),
        if (blocked != null)
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + MediaQuery.of(context).padding.bottom),
            decoration: const BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
            child: Row(children: [
              const Icon(CupertinoIcons.lock_fill, size: 16, color: Tx.subtle),
              const SizedBox(width: 10),
              Expanded(child: Text(blocked, style: Tx.body(13.5, color: Tx.muted))),
            ]),
          )
        else
          _composer(),
      ]),
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
    final lastMine = _messages.lastWhere((m) => m.isMine, orElse: () => Message(id: 0, conversationId: 0)).id;
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
          final grouped = prev != null && prev.isMine == m.isMine && !showDate;
          return Column(children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(fullDate(m.createdAt), style: Tx.body(11.5, weight: FontWeight.w600, color: Tx.subtle)),
              ),
            _Bubble(
              message: m,
              grouped: grouped,
              onLongPress: () => _messageMenu(m),
            ),
            if (m.id == lastMine && m.isMine && !m.deleted)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4),
                  child: Text(m.id <= _seenId ? 'Visto' : 'Enviado', style: Tx.body(11, color: m.id <= _seenId ? Tx.purple300 : Tx.subtle)),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _composer() {
    final image = _image;
    final gif = _gif;
    final state = context.read<AppState>();
    return Container(
      decoration: const BoxDecoration(color: Tx.surface1, border: Border(top: BorderSide(color: Tx.border))),
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + (MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : MediaQuery.of(context).padding.bottom)),
      child: _recording
          ? _recordingBar()
          : _voicePath != null
              ? _voiceDraftBar()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  if (image != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Row(children: [
                        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(image.path), width: 64, height: 64, fit: BoxFit.cover)),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Imagen adjunta', style: Tx.body(13.5, color: Tx.muted))),
                        IconButton(onPressed: () => setState(() => _image = null), icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Tx.muted)),
                      ]),
                    ),
                  if (gif != null) GifAttachment(gif: gif, onRemove: () => setState(() => _gif = null)),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(onPressed: _pickImage, icon: const Icon(CupertinoIcons.photo, color: Tx.purple300)),
                    if (state.feature('gifs'))
                      IconButton(onPressed: _pickGif, tooltip: 'GIF y stickers', icon: const Icon(CupertinoIcons.smiley, color: Tx.purple300)),
                    Expanded(
                      child: TextField(
                        controller: _input,
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

/// Reproductor de una nota de voz dentro de la burbuja.
class _VoicePlayer extends StatelessWidget {
  const _VoicePlayer({required this.voice, required this.playKey, required this.mine});

  final VoiceNote voice;
  final String playKey;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final song = Song(id: 0, title: 'Nota de voz', duration: voice.duration, audioUrl: voice.url);
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
              onTap: () => songPlayer.toggle(playKey, song),
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
                        valueColor: AlwaysStoppedAnimation(mine ? Colors.white : Tx.purple400),
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

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.grouped, required this.onLongPress});

  final Message message;
  final bool grouped;
  final VoidCallback onLongPress;

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
    final children = <Widget>[];
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
              style: Tx.body(12, color: mine ? Colors.white.withAlpha(200) : Tx.muted),
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
    final mediaOnly = !m.deleted && (m.body ?? '').isEmpty && (m.imageUrl != null || m.gif != null);
    final bare = mediaOnly && m.gif != null && m.gif!.isSticker && m.story == null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
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
