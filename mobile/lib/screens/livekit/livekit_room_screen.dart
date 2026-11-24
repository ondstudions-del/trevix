import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/livekit_api.dart';
import '../../core/nav.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/report_sheet.dart';
import '../../widgets/share_sheet.dart';
import '../wallet/gifts_screen.dart';
import 'call_presentation.dart';
import 'live_end_summary_screen.dart';
import 'live_obs_sheet.dart';

enum LiveKitRoomMode { call, live }

/// Conecta a una sala LiveKit (llamada 1:1 o live estilo TikTok).
class LiveKitRoomScreen extends StatefulWidget {
  const LiveKitRoomScreen({
    super.key,
    required this.join,
    required this.title,
    required this.video,
    this.mode = LiveKitRoomMode.call,
  });

  final LiveKitJoin join;
  final String title;
  final bool video;
  final LiveKitRoomMode mode;

  @override
  State<LiveKitRoomScreen> createState() => _LiveKitRoomScreenState();
}

class _LiveKitRoomScreenState extends State<LiveKitRoomScreen> {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  String? _error;
  bool _busy = true;
  bool _micOn = true;
  bool _camOn = true;

  final _messages = <LiveKitChatMessage>[];
  final _chatCtrl = TextEditingController();
  final _chatFocus = FocusNode();
  int _likes = 0;
  int _lastMsgId = 0;
  Timer? _msgPoll;
  final _hearts = <_Heart>[];
  String? _giftBanner;
  Timer? _giftTimer;
  final _giftQueue = <String>[];
  int _viewers = 0;
  String? _joinToast;
  Timer? _joinToastTimer;
  LiveKitChatMessage? _replyTo;
  String? _giftBurstUrl;
  String? _giftBurstLabel;
  Timer? _giftBurstTimer;
  Timer? _callStatusPoll;
  Timer? _callDurationTick;
  DateTime? _callStartedAt;
  bool _speakerOn = true;
  bool _ending = false;
  Timer? _speakerPoll;
  bool _speakerInviteOpen = false;
  String? _speakerStatus;

  bool get _isLive => widget.mode == LiveKitRoomMode.live;
  bool get _isHost => widget.join.session.isHost;
  bool get _voiceChat => widget.join.session.isVoiceChat;
  bool get _isObs => widget.join.session.isObs;

  @override
  void initState() {
    super.initState();
    _likes = widget.join.session.likes;
    _speakerStatus = widget.join.session.speakerStatus;
    _connect();
  }

  Future<void> _connect() async {
    try {
      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: CameraCaptureOptions(),
          defaultAudioPublishOptions: AudioPublishOptions(),
          defaultVideoPublishOptions: VideoPublishOptions(simulcast: true),
        ),
      );
      _listener = room.createListener();
      _listener!.on<RoomDisconnectedEvent>((_) {
        if (mounted && !_isLive) _finishCall(remoteEnded: true);
      });
      _listener!.on<ParticipantConnectedEvent>((e) {
        if (!_isLive && mounted) {
          setState(() => _callStartedAt ??= DateTime.now());
          return;
        }
        if (!_isLive || !mounted) return;
        final name = e.participant.name.isNotEmpty ? e.participant.name : tr('Alguien');
        setState(() {
          _viewers = _countViewers(room);
          _flashJoinToast(name);
        });
      });
      _listener!.on<ParticipantDisconnectedEvent>((_) {
        if (!_isLive && mounted) {
          _finishCall(remoteEnded: true);
          return;
        }
        if (!_isLive || !mounted) return;
        setState(() => _viewers = _countViewers(room));
      });
      _listener!.on<ActiveSpeakersChangedEvent>((_) {
        if (mounted && _voiceChat) setState(() {});
      });
      _listener!.on<LocalTrackPublishedEvent>((_) {
        if (mounted && _isLive && !_voiceChat) setState(() {});
      });
      _listener!.on<TrackSubscribedEvent>((_) {
        if (mounted && _isLive && !_voiceChat) setState(() {});
      });
      _listener!.on<DataReceivedEvent>((e) {
        try {
          final raw = utf8.decode(e.data);
          final map = jsonDecode(raw);
          if (map is! Map) return;
          final type = '${map['type'] ?? ''}';
          if (type == 'chat') {
            final msg = LiveKitChatMessage.fromJson(Map<String, dynamic>.from(map['message'] as Map? ?? {}));
            if (msg.id > 0 && !_messages.any((m) => m.id == msg.id)) {
              setState(() {
                _messages.add(msg);
                _lastMsgId = math.max(_lastMsgId, msg.id);
              });
            }
          } else if (type == 'like') {
            setState(() {
              _likes = asInt(map['likes'], _likes + 1);
              _spawnHeart();
            });
          } else if (type == 'call_end' && !_isLive) {
            if (mounted) _finishCall(remoteEnded: true);
          } else if (type == 'speaker_invite' && _isLive && _voiceChat) {
            final targetId = asInt(map['user_id']);
            final meId = context.read<AppState>().me?.user.id;
            if (meId != null && meId == targetId) {
              setState(() => _speakerStatus = 'invited');
              _showSpeakerInvite();
            }
          } else if (type == 'gift') {
            final name = '${map['gift'] ?? ''}';
            final from = '${map['from'] ?? ''}';
            final mediaUrl = asStrOrNull(map['media_url']);
            final line = asStrOrNull(map['line']) ??
                (from.isEmpty ? name : (from + ' te regaló 1 ' + (name.isNotEmpty ? name : tr('Regalo'))));
            setState(() {
              _giftBanner = line;
              _giftQueue.insert(0, line);
              if (_giftQueue.length > 5) _giftQueue.removeLast();
            });
            _showGiftBurst(mediaUrl, line);
            _giftTimer?.cancel();
            _giftTimer = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _giftBanner = null);
            });
          }
        } catch (_) {}
      });
      await room.connect(widget.join.url, widget.join.token);
      if (!mounted) return;
      setState(() {
        _room = room;
        _busy = false;
        if (_isLive) _viewers = _countViewers(room);
      });
      if (_isLive) {
        // ignore: unawaited_futures
        _loadMessages();
        _msgPoll = Timer.periodic(const Duration(seconds: 4), (_) => _pollMessages());
        if (_voiceChat && !_isHost) {
          _speakerPoll = Timer.periodic(const Duration(seconds: 5), (_) => _checkSpeakerStatus());
          if (_speakerStatus == 'invited') {
            WidgetsBinding.instance.addPostFrameCallback((_) => _showSpeakerInvite());
          }
        }
      } else {
        _callStartedAt ??= DateTime.now();
        _callStatusPoll = Timer.periodic(const Duration(seconds: 2), (_) => _pollCallSession());
        _callDurationTick = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
      // ignore: unawaited_futures
      _enableLocalPublish(room);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e);
        _busy = false;
      });
    }
  }

  Future<void> _enableLocalPublish(Room room) async {
    final local = room.localParticipant;
    if (local == null) return;
    if (_isLive && _isHost && _isObs) {
      try {
        await local.setMicrophoneEnabled(false);
        await local.setCameraEnabled(false);
        if (mounted) setState(() {
          _micOn = false;
          _camOn = false;
        });
      } catch (_) {}
      return;
    }
    if (_isLive && !_isHost && _voiceChat) {
      if (_speakerStatus == 'active') {
        try {
          await local.setMicrophoneEnabled(true);
          if (mounted) setState(() => _micOn = true);
        } catch (_) {}
      }
      return;
    }
    if (_isLive && !_isHost) return;
    try {
      await local.setMicrophoneEnabled(true);
      if (mounted) setState(() => _micOn = true);
    } catch (_) {}
    if (widget.video && _isLive && !_isObs) {
      try {
        await local.setCameraEnabled(true).timeout(const Duration(seconds: 15));
        if (mounted) setState(() => _camOn = true);
      } catch (_) {
        if (mounted) toast(context, tr('No se pudo abrir la cámara. Revisa el permiso.'));
      }
    }
  }

  Future<void> _loadMessages() async {
    try {
      final list = await liveKitMessages(widget.join.session.id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(list);
        if (list.isNotEmpty) _lastMsgId = list.last.id;
      });
    } catch (_) {}
  }

  Future<void> _pollMessages() async {
    try {
      final list = await liveKitMessages(widget.join.session.id, after: _lastMsgId);
      if (!mounted || list.isEmpty) return;
      setState(() {
        for (final m in list) {
          if (!_messages.any((x) => x.id == m.id)) _messages.add(m);
        }
        _lastMsgId = math.max(_lastMsgId, list.last.id);
      });
    } catch (_) {}
  }

  Future<void> _publishData(Map<String, dynamic> payload) async {
    final bytes = utf8.encode(jsonEncode(payload));
    await _room?.localParticipant?.publishData(bytes, reliable: true);
  }

  int _countViewers(Room room) => room.remoteParticipants.length + 1;

  void _flashJoinToast(String name) {
    _joinToast = tr('{name} se unió', {'name': name});
    _joinToastTimer?.cancel();
    _joinToastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _joinToast = null);
    });
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    if (text.isEmpty) return;
    final replyId = _replyTo?.id;
    _chatCtrl.clear();
    setState(() => _replyTo = null);
    try {
      final msg = await liveKitPostMessage(widget.join.session.id, text, replyToId: replyId);
      setState(() {
        if (!_messages.any((m) => m.id == msg.id)) _messages.add(msg);
        _lastMsgId = math.max(_lastMsgId, msg.id);
      });
      await _publishData({'type': 'chat', 'message': {
        'id': msg.id,
        'body': msg.body,
        'user': {
          'id': msg.user.id,
          'username': msg.user.username,
          'display_name': msg.user.displayName,
          'avatar_url': msg.user.avatarUrl,
          'is_verified': msg.user.isVerified,
        },
      }});
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _like() async {
    _spawnHeart();
    try {
      final n = await liveKitLike(widget.join.session.id);
      setState(() => _likes = n);
      await _publishData({'type': 'like', 'likes': n});
    } catch (_) {}
  }

  void _showGiftBurst(String? url, String label) {
    if (url == null || url.isEmpty) return;
    setState(() {
      _giftBurstUrl = url;
      _giftBurstLabel = label;
    });
    _giftBurstTimer?.cancel();
    _giftBurstTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) {
        setState(() {
          _giftBurstUrl = null;
          _giftBurstLabel = null;
        });
      }
    });
  }

  void _spawnHeart() {
    final id = DateTime.now().microsecondsSinceEpoch;
    setState(() => _hearts.add(_Heart(id: id, x: 0.55 + math.Random().nextDouble() * 0.35)));
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _hearts.removeWhere((h) => h.id == id));
    });
  }

  Future<void> _sendGift() async {
    final host = widget.join.session.hostUser;
    if (host == null) return;
    final res = await sendGift(context, host, where: 'live', refId: widget.join.session.id);
    if (res == null || !mounted) return;
    final send = asMap(res['send']);
    final gift = asMap(send['gift']);
    final giftName = asStr(gift['name'], tr('Regalo'));
    final mediaUrl = asStrOrNull(gift['media_url']);
    final from = asStr(send['user']?['display_name'] ?? '', '');
    final line = from.isEmpty ? giftName : '$from te regaló 1 $giftName';
    setState(() {
      _giftBanner = line;
      _giftQueue.insert(0, line);
      if (_giftQueue.length > 5) _giftQueue.removeLast();
    });
    _showGiftBurst(mediaUrl, line);
    await _publishData({
      'type': 'gift',
      'gift': giftName,
      'from': from,
      'line': line,
      if (mediaUrl != null) 'media_url': mediaUrl,
    });
  }

  void _liveMenu() {
    final s = widget.join.session;
    final shareUrl = AppConfig.web('livekit-live.php?id=${s.id}');
    actionSheet(context, [
      SheetAction(tr('Compartir'), CupertinoIcons.share, () => showShareSheet(context, url: shareUrl, title: s.title ?? tr('En vivo'))),
      if (!_isHost) SheetAction(tr('Reportar'), CupertinoIcons.flag, () => showReportSheet(context, 'live', s.id), destructive: true),
      if (_isHost && _voiceChat) SheetAction(tr('Invitar a hablar'), CupertinoIcons.person_add, () => _inviteSpeaker()),
    ]);
  }

  Future<void> _inviteSpeaker() async {
    if (!_isHost || !_voiceChat) return;
    try {
      final rows = await liveKitListViewers(widget.join.session.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF14141C),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
        builder: (ctx) {
          final eligible = rows.where((r) {
            final st = r.speakerStatus ?? '';
            return st != 'active' && st != 'invited';
          }).toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            maxChildSize: 0.85,
            minChildSize: 0.35,
            builder: (_, scroll) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(tr('Invitar a hablar'), style: Tx.display(18, color: Colors.white)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    tr('Elige a alguien que esté viendo el live (máx. 8 en micrófono).'),
                    style: Tx.body(13, color: Colors.white60, height: 1.35),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: eligible.isEmpty
                      ? Center(child: Text(tr('Nadie disponible para invitar.'), style: Tx.body(14, color: Colors.white54)))
                      : ListView.builder(
                          controller: scroll,
                          itemCount: eligible.length,
                          itemBuilder: (_, i) {
                            final row = eligible[i];
                            final u = row.user;
                            return ListTile(
                              leading: Avatar(user: u, size: 44),
                              title: Text(u.displayName, style: Tx.body(15, weight: FontWeight.w700, color: Colors.white)),
                              subtitle: Text('@${u.username}', style: Tx.body(12, color: Colors.white54)),
                              trailing: SoftButton(
                                label: tr('Invitar'),
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  try {
                                    await liveKitInviteSpeaker(widget.join.session.id, u.id);
                                    await _publishData({'type': 'speaker_invite', 'user_id': u.id});
                                    if (mounted) toast(context, tr('Invitación enviada a {name}', {'name': u.displayName}));
                                  } catch (e) {
                                    if (mounted) toastError(context, e);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                ),
                SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _checkSpeakerStatus() async {
    if (_isHost || !_voiceChat || _speakerInviteOpen) return;
    try {
      final s = await liveKitShow(widget.join.session.id);
      if (!mounted) return;
      final st = s.speakerStatus;
      if (st == 'invited' && _speakerStatus != 'invited') {
        setState(() => _speakerStatus = 'invited');
        _showSpeakerInvite();
      }
    } catch (_) {}
  }

  Future<void> _showSpeakerInvite() async {
    if (!_isLive || _isHost || !_voiceChat || _speakerInviteOpen || _speakerStatus != 'invited') return;
    _speakerInviteOpen = true;
    final join = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(tr('Invitación al micrófono')),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(tr('El host te invitó a hablar en el live. ¿Aceptas?'), style: Tx.body(14, height: 1.35)),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Rechazar'))),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Aceptar')),
          ),
        ],
      ),
    );
    _speakerInviteOpen = false;
    if (!mounted || join != true) return;
    try {
      await liveKitAcceptSpeaker(widget.join.session.id);
      final fresh = await liveKitJoinToken(widget.join.session.id);
      await _room?.disconnect();
      await _room?.connect(fresh.url, fresh.token);
      await _room?.localParticipant?.setMicrophoneEnabled(true);
      if (mounted) {
        setState(() {
          _speakerStatus = 'active';
          _micOn = true;
        });
        toast(context, tr('Ya puedes hablar en el live.'));
      }
    } catch (e) {
      if (mounted) toastError(context, e);
    }
  }

  Future<void> _showLiveEndSummary(LiveKitSession s) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => LiveEndSummaryScreen(session: s),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _toggleMic() async {
    if (_isLive && _isHost && _isObs) return;
    final next = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(next);
    setState(() => _micOn = next);
  }

  void _showObsConfig() {
    final j = widget.join;
    if (!j.hasObs) {
      toast(context, tr('No hay datos RTMP para OBS.'), error: true);
      return;
    }
    showLiveObsSheet(
      context,
      LiveObsCredentials(
        rtmpUrl: j.obsRtmpUrl!,
        streamKey: j.obsStreamKey!,
        overlayCommentsUrl: j.obsOverlayCommentsUrl,
        overlayGiftsUrl: j.obsOverlayGiftsUrl,
      ),
    );
  }

  Future<void> _toggleCam() async {
    final next = !_camOn;
    await _room?.localParticipant?.setCameraEnabled(next);
    setState(() => _camOn = next);
  }

  Future<void> _pollCallSession() async {
    if (_ending || _isLive) return;
    try {
      final s = await liveKitShow(widget.join.session.id);
      if (s.status == 'ended' || s.status == 'declined' || s.status == 'missed') {
        if (mounted) _finishCall(remoteEnded: true);
      }
    } catch (_) {}
  }

  User? _remoteCallUser() {
    final room = _room;
    final counterparty = widget.join.session.counterpartyFor(widget.join.session.isHost);
    if (counterparty != null) return counterparty;
    if (room != null) {
      for (final p in room.remoteParticipants.values) {
        final n = p.name;
        if (n.isNotEmpty) {
          return User(id: 0, username: n, displayName: n);
        }
      }
    }
    return null;
  }

  String _callDurationLabel() {
    final start = _callStartedAt;
    if (start == null) return tr('Conectando…');
    return formatCallDuration(DateTime.now().difference(start));
  }

  Future<void> _finishCall({bool remoteEnded = false}) async {
    if (_ending) return;
    _ending = true;
    _callStatusPoll?.cancel();
    _callDurationTick?.cancel();
    LiveKitSession? ended;
    try {
      if (_isLive && _isHost) {
        ended = await liveKitEnd(widget.join.session.id);
      } else if (!_isLive) {
        if (!remoteEnded) {
          try {
            await _publishData({'type': 'call_end'});
          } catch (_) {}
          await liveKitEnd(widget.join.session.id);
        }
      }
    } catch (_) {}
    try {
      await _room?.disconnect();
    } catch (_) {}
    if (!mounted) return;
    if (ended != null && _isLive) await _showLiveEndSummary(ended);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _hangUp() => _finishCall(remoteEnded: false);

  @override
  void dispose() {
    _msgPoll?.cancel();
    _giftTimer?.cancel();
    _joinToastTimer?.cancel();
    _giftBurstTimer?.cancel();
    _callStatusPoll?.cancel();
    _callDurationTick?.cancel();
    _speakerPoll?.cancel();
    _chatCtrl.dispose();
    _chatFocus.dispose();
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLive) return _buildLiveScaffold();
    return _buildCallScaffold();
  }

  Widget _buildCallScaffold() {
    final remote = _remoteCallUser();
    final name = remote?.displayName ?? widget.title;
    final duration = _callDurationLabel();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CallBlurBackdrop(user: remote, avatarUrl: remote?.avatarUrl),
          SafeArea(
            child: Column(
              children: [
                CallConnectedBar(title: name, subtitle: duration),
                Expanded(child: _buildCallCenter(remote, name)),
                CallOutgoingDock(
                  video: false,
                  micOn: _micOn,
                  speakerOn: _speakerOn,
                  onToggleMic: _toggleMic,
                  onToggleSpeaker: () => setState(() => _speakerOn = !_speakerOn),
                  onEnd: _ending ? () {} : _hangUp,
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          if (_busy) const ColoredBox(color: Colors.black54, child: Center(child: CupertinoActivityIndicator(color: Colors.white))),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: Tx.body(15, color: Colors.white), textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCallCenter(User? remote, String name) {
    if (_busy) return const SizedBox.shrink();
    return Center(
      child: CallCallerBlock(
        user: remote,
        nameOverride: name,
        subtitle: _callDurationLabel(),
        avatarSize: 148,
      ),
    );
  }

  Widget _buildVideoCallStage() {
    if (_busy) return const ColoredBox(color: Color(0xFF1C1C1E));
    final room = _room;
    if (room == null) return const ColoredBox(color: Color(0xFF1C1C1E));
    Participant? remote;
    for (final p in room.remoteParticipants.values) {
      remote = p;
      break;
    }
    final local = room.localParticipant;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (remote != null)
          _ParticipantTile(participant: remote, local: false, video: true, fullBleed: true)
        else
          ColoredBox(
            color: const Color(0xFF1C1C1E),
            child: Center(
              child: Text(tr('Conectando videollamada…'), style: Tx.body(15, color: Colors.white70)),
            ),
          ),
        if (local != null && widget.video)
          Positioned(
            top: 64,
            right: 14,
            width: 108,
            height: 156,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(140), blurRadius: 12)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _ParticipantTile(participant: local, local: true, video: _camOn),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLiveScaffold() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onDoubleTap: _isLive ? () { HapticFeedback.lightImpact(); _like(); } : null,
            child: _liveVideo(),
          ),
          if (_giftBurstUrl != null) _GiftBurstOverlay(url: _giftBurstUrl!, label: _giftBurstLabel ?? ''),
          if (_giftQueue.isNotEmpty)
            Positioned(
              left: 12,
              top: MediaQuery.paddingOf(context).top + 72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final g in _giftQueue.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Tx.accent.withAlpha(120)),
                        ),
                        child: Text(g, style: Tx.body(12, weight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                ],
              ),
            ),
          if (_joinToast != null)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 56,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                  child: Text(_joinToast!, style: Tx.body(13, weight: FontWeight.w600, color: Colors.white)),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withAlpha(140), Colors.transparent, Colors.transparent, Colors.black.withAlpha(200)],
                  stops: const [0, 0.22, 0.55, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _liveTopBar(),
                    const Spacer(),
                    if (_isHost) _liveHostChips(),
                    const SizedBox(height: 8),
                    _chatList(),
                    _liveBottomDock(),
                  ],
                ),
                if (_giftBanner != null)
                  Positioned(
                    left: 14,
                    top: MediaQuery.paddingOf(context).top + 78,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 280),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [const Color(0xFFFBBF24).withAlpha(180), Colors.black.withAlpha(140)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(_giftBanner!, style: Tx.body(12.5, weight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
          ..._hearts.map((h) => _HeartFly(key: ValueKey(h.id), x: h.x)),
          if (_busy) const Center(child: CupertinoActivityIndicator(color: Colors.white)),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: Tx.body(15, color: Colors.white70), textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }

  static const double _obsAspectRatio = 16 / 9;

  /// Vídeo OBS en 16:9 centrado (letterbox), no pantalla completa vertical como la cámara.
  Widget _obsVideoStage(Widget videoChild) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: _obsAspectRatio,
          child: videoChild,
        ),
      ),
    );
  }

  Widget _liveWaitingPlaceholder() {
    final cover = widget.join.session.coverUrl;
    return ColoredBox(
      color: const Color(0xFF14141F),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null) Opacity(opacity: .25, child: NetImage(cover, fit: BoxFit.cover)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_isObs ? CupertinoIcons.tv : CupertinoIcons.dot_radiowaves_left_right, color: Colors.white24, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    _isObs && _isHost
                        ? tr('Conecta OBS y pulsa «Iniciar transmisión».')
                        : tr('Esperando señal de video…'),
                    textAlign: TextAlign.center,
                    style: Tx.body(14, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  VideoTrack? _findBroadcastVideo(Room room) {
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t is VideoTrack && !pub.muted) return t;
      }
    }
    if (!_isObs && _isHost) {
      final local = room.localParticipant;
      if (local != null) {
        for (final pub in local.videoTrackPublications) {
          final t = pub.track;
          if (t is VideoTrack) return t;
        }
      }
    }
    return null;
  }

  Widget _liveVideo() {
    final room = _room;
    if (room == null) return const ColoredBox(color: Colors.black);
    if (_voiceChat) return _voiceChatGrid(room);
    final track = _findBroadcastVideo(room);
    if (track == null) {
      final waiting = _liveWaitingPlaceholder();
      return _isObs ? _obsVideoStage(waiting) : waiting;
    }
    if (_isObs) {
      return _obsVideoStage(
        ColoredBox(
          color: Colors.black,
          child: VideoTrackRenderer(track, fit: VideoViewFit.contain),
        ),
      );
    }
    return VideoTrackRenderer(track, fit: VideoViewFit.cover);
  }

  Widget _voiceChatGrid(Room room) {
    final tiles = <Widget>[];
    final local = room.localParticipant;
    if (local != null) {
      tiles.add(_VoiceChatTile(participant: local, local: true, user: widget.join.session.isHost ? widget.join.session.hostUser : null));
    }
    for (final p in room.remoteParticipants.values) {
      tiles.add(_VoiceChatTile(participant: p, local: false));
    }
    if (tiles.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF0B0B10),
        child: Center(child: Icon(CupertinoIcons.mic_fill, color: Colors.white24, size: 40)),
      );
    }
    final cover = widget.join.session.coverUrl;
    return ColoredBox(
      color: const Color(0xFF0B0B10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null) Opacity(opacity: 0.12, child: NetImage(cover, fit: BoxFit.cover)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 96),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: tiles,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCommentTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $h:$m';
  }

  List<InlineSpan> _liveChatSpans(String name, String body) {
    final spans = <InlineSpan>[];
    if (name.isNotEmpty) {
      spans.add(TextSpan(text: '$name ', style: Tx.body(12.5, weight: FontWeight.w800, color: const Color(0xFFFBBF24))));
    }
    final re = RegExp(r'@([A-Za-z0-9_]{2,30})');
    var start = 0;
    for (final m in re.allMatches(body)) {
      if (m.start > start) {
        spans.add(TextSpan(text: body.substring(start, m.start), style: Tx.body(12.5, color: Colors.white.withAlpha(235))));
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: Tx.body(12.5, weight: FontWeight.w800, color: const Color(0xFF60A5FA)),
      ));
      start = m.end;
    }
    if (start < body.length) {
      spans.add(TextSpan(text: body.substring(start), style: Tx.body(12.5, color: Colors.white.withAlpha(235))));
    }
    return spans;
  }

  Widget _livePill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }

  Widget _liveTopBar() {
    final host = widget.join.session.hostUser;
    final name = widget.join.session.hostName ?? widget.title;
    final title = widget.join.session.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _livePill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (host != null) Avatar(user: host, size: 34, liveRing: true),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name, style: Tx.body(13.5, weight: FontWeight.w800, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            const Icon(CupertinoIcons.heart_fill, size: 12, color: Color(0xFFF43F5E)),
                            const SizedBox(width: 2),
                            Text('$_likes', style: Tx.body(11, weight: FontWeight.w700, color: Colors.white)),
                          ],
                        ),
                        if (title != null && title.isNotEmpty)
                          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Tx.body(11, color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _livePill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.person_fill, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Text('$_viewers', style: Tx.body(12, weight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _hangUp,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: Color(0xFF2A2A30), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.power, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveHostChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _liveChip(tr('EN VIVO'), CupertinoIcons.flame_fill, const Color(0xFFFF6B6B)),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: _liveMenu,
              child: _liveChip(tr('Compartir LIVE'), CupertinoIcons.arrow_2_circlepath, Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveChip(String label, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.black.withAlpha(130), borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: Tx.body(11.5, weight: FontWeight.w600, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _chatList() {
    return SizedBox(
      height: 200,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 96, 4),
        reverse: true,
        itemCount: _messages.length + (_isHost ? 1 : 0),
        itemBuilder: (_, i) {
          if (_isHost && i == _messages.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(gradient: Tx.brand, borderRadius: BorderRadius.circular(6)),
                    child: const Center(child: Text('T', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('Estamos avisando a tus seguidores que estás en LIVE. Mantén las normas de la comunidad.'),
                      style: Tx.body(12.5, color: Colors.white.withAlpha(220), height: 1.3),
                    ),
                  ),
                ],
              ),
            );
          }
          final m = _messages[_messages.length - 1 - i];
          final when = _formatCommentTime(m.createdAt);
          return GestureDetector(
            onLongPress: () => setState(() => _replyTo = m),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Avatar(user: m.user, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                m.user.displayName,
                                style: Tx.body(12.5, weight: FontWeight.w800, color: const Color(0xFFFBBF24)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (when.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(when, style: Tx.body(10.5, color: Colors.white54)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        RichText(text: TextSpan(children: _liveChatSpans('', m.body))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _liveBottomDock() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _livePill(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr('Respondiendo a {name}', {'name': _replyTo!.user.displayName}), style: Tx.body(11, color: Colors.white70)),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setState(() => _replyTo = null),
                        child: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.white54, size: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (_isHost && _voiceChat)
                _LiveDockIcon(icon: CupertinoIcons.person_2_fill, label: tr('Invitar'), onTap: _inviteSpeaker)
              else if (_isHost && _isObs)
                _LiveDockIcon(icon: CupertinoIcons.tv, label: 'OBS', onTap: _showObsConfig)
              else if (_isHost)
                _LiveDockIcon(icon: CupertinoIcons.camera_rotate, label: tr('Cámara'), onTap: _toggleCam),
              _LiveDockIcon(icon: CupertinoIcons.chat_bubble_text, label: tr('Comentar'), onTap: () => _chatFocus.requestFocus()),
              _LiveDockIcon(icon: CupertinoIcons.arrowshape_turn_up_right, label: tr('Compartir'), onTap: () {
                final s = widget.join.session;
                showShareSheet(context, url: AppConfig.web('livekit-live.php?id=${s.id}'), title: s.title ?? tr('En vivo'));
              }),
              _LiveDockIcon(icon: CupertinoIcons.sparkles, label: tr('Regalo'), onTap: _sendGift),
              _LiveDockIcon(icon: CupertinoIcons.ellipsis, label: tr('Más'), onTap: _liveMenu),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white.withAlpha(35)),
                  ),
                  child: TextField(
                    controller: _chatCtrl,
                    focusNode: _chatFocus,
                    style: Tx.body(14, color: Colors.white),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                          hintText: tr('Di algo… (@usuario para mencionar)'),
                          hintStyle: Tx.body(14, color: Colors.white54),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendChat(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _LiveIconBtn(icon: CupertinoIcons.heart_fill, color: const Color(0xFFF43F5E), onTap: _like),
              if (_isHost || (_voiceChat && _speakerStatus == 'active'))
                _LiveIconBtn(icon: _micOn ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill, onTap: _toggleMic),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveDockIcon extends StatelessWidget {
  const _LiveDockIcon({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Tx.body(10, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _VoiceChatTile extends StatefulWidget {
  const _VoiceChatTile({required this.participant, required this.local, this.user});

  final Participant participant;
  final bool local;
  final User? user;

  @override
  State<_VoiceChatTile> createState() => _VoiceChatTileState();
}

class _VoiceChatTileState extends State<_VoiceChatTile> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _VoiceChatTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWave();
  }

  void _syncWave() {
    final speaking = widget.participant.isSpeaking && widget.participant.isMicrophoneEnabled();
    if (speaking) {
      if (!_wave.isAnimating) _wave.repeat();
    } else {
      _wave.stop();
      _wave.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncWave();
    final micOn = widget.participant.isMicrophoneEnabled();
    final speaking = widget.participant.isSpeaking && micOn;
    final name = widget.user?.displayName ??
        (widget.participant.name.isNotEmpty ? widget.participant.name : (widget.local ? tr('Tú') : tr('Participante')));
    final avatarUser = widget.user ??
        User(
          id: 0,
          username: '',
          displayName: name,
        );
    return SizedBox(
      width: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (speaking)
                  AnimatedBuilder(
                    animation: _wave,
                    builder: (_, __) {
                      final t = _wave.value;
                      final scale = 1.0 + t * 0.55;
                      final alpha = ((1 - t) * 0.85 * 255).round().clamp(0, 255);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Tx.accent.withAlpha(alpha), width: 2.5),
                          ),
                        ),
                      );
                    },
                  ),
                if (speaking)
                  AnimatedBuilder(
                    animation: _wave,
                    builder: (_, __) {
                      final t = (_wave.value + 0.45) % 1.0;
                      final scale = 1.0 + t * 0.55;
                      final alpha = ((1 - t) * 0.6 * 255).round().clamp(0, 255);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Tx.cyan.withAlpha(alpha), width: 1.5),
                          ),
                        ),
                      );
                    },
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: speaking ? Tx.accent : (micOn ? Colors.white.withAlpha(70) : Colors.white.withAlpha(35)),
                      width: speaking ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Avatar(user: avatarUser, size: 44),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Tx.body(11, weight: FontWeight.w600, color: Colors.white.withAlpha(230)),
          ),
          const SizedBox(height: 2),
          Icon(micOn ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill, color: micOn ? Tx.accent : Colors.white38, size: 14),
        ],
      ),
    );
  }
}

class _CallBtn extends StatelessWidget {
  const _CallBtn({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 58, height: 58, child: Icon(icon, color: Colors.white, size: 26)),
      ),
    );
  }
}

class _LiveIconBtn extends StatelessWidget {
  const _LiveIconBtn({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(onPressed: onTap, icon: Icon(icon, color: color ?? Colors.white, size: 26));
  }
}

class _Heart {
  _Heart({required this.id, required this.x});
  final int id;
  final double x;
}

class _HeartFly extends StatefulWidget {
  const _HeartFly({super.key, required this.x});
  final double x;

  @override
  State<_HeartFly> createState() => _HeartFlyState();
}

class _HeartFlyState extends State<_HeartFly> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeOut.transform(_c.value);
        return Positioned(
          left: size.width * widget.x,
          bottom: 90 + t * (size.height * 0.45),
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Icon(CupertinoIcons.heart_fill, color: Color.lerp(const Color(0xFFF43F5E), const Color(0xFFFBBF24), t), size: 28 + 10 * (1 - t)),
          ),
        );
      },
    );
  }
}

class _GiftBurstOverlay extends StatefulWidget {
  const _GiftBurstOverlay({required this.url, required this.label});

  final String url;
  final String label;

  @override
  State<_GiftBurstOverlay> createState() => _GiftBurstOverlayState();
}

class _GiftBurstOverlayState extends State<_GiftBurstOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = Curves.elasticOut.transform(_c.value.clamp(0.0, 1.0));
            final scale = 0.35 + t * 0.85;
            final opacity = _c.value < 0.82 ? 1.0 : (1 - ((_c.value - 0.82) / 0.18)).clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(color: const Color(0xFFFBBF24).withAlpha(120), blurRadius: 32, spreadRadius: 8)],
                      ),
                      child: NetImage(widget.url, fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                    child: Text(widget.label, style: Tx.body(14, weight: FontWeight.w800, color: Colors.white)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({required this.participant, required this.local, this.video = true, this.fullBleed = false});

  final Participant participant;
  final bool local;
  final bool video;
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    VideoTrack? track;
    if (video) {
      for (final pub in participant.videoTrackPublications) {
        if (pub.track != null && !pub.muted) {
          track = pub.track as VideoTrack?;
          break;
        }
      }
    }
    final name = participant.name.isNotEmpty ? participant.name : (local ? tr('Tú') : tr('Participante'));
    final body = ColoredBox(
      color: const Color(0xFF1a1a1a),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track != null) VideoTrackRenderer(track) else Center(child: Icon(CupertinoIcons.person_fill, color: Colors.white24, size: 48)),
          if (!fullBleed)
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                child: Text(name, style: Tx.body(12, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
    if (fullBleed) return body;
    return ClipRRect(borderRadius: BorderRadius.circular(12), child: body);
  }
}
