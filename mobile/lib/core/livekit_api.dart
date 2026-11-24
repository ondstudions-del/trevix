import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import 'api.dart';
import 'session.dart';

/// Configuración pública de LiveKit (`app/config → features.livekit`).
class LiveKitConfig {
  LiveKitConfig({required this.url, required this.audioCalls, required this.videoCalls, required this.live});

  final String url;
  final bool audioCalls;
  final bool videoCalls;
  final bool live;

  bool get ready => url.isNotEmpty;

  static LiveKitConfig? fromAppConfig(Json config) {
    final raw = asMap(asMap(config['features'])['livekit']);
    final url = asStr(raw['url']);
    if (url.isEmpty) return null;
    return LiveKitConfig(
      url: url,
      audioCalls: raw.containsKey('audio_calls') ? asBool(raw['audio_calls']) : true,
      videoCalls: raw.containsKey('video_calls') ? asBool(raw['video_calls']) : false,
      live: raw.containsKey('live') ? asBool(raw['live']) : true,
    );
  }

  static LiveKitConfig? of(BuildContext context) => fromAppConfig(context.read<AppState>().config);
}

class LiveKitSession {
  LiveKitSession({
    required this.id,
    required this.room,
    required this.kind,
    required this.status,
    this.hostName,
    this.hostUsername,
    this.hostAvatar,
    this.hostId,
    this.title,
    this.description,
    this.hashtags,
    this.category,
    this.coverUrl,
    this.liveMode = 'camera',
    this.isAdult = false,
    this.speakerStatus,
    this.likes = 0,
    this.viewersPeak = 0,
    this.uniqueViewers = 0,
    this.joinCount = 0,
    this.giftsTotalCents = 0,
    this.durationSeconds,
    this.isHost = false,
    this.peerUser,
  });

  final int id;
  final String room;
  final String kind;
  final String status;
  final String? hostName;
  final String? hostUsername;
  final String? hostAvatar;
  final int? hostId;
  final String? title;
  final String? description;
  final String? hashtags;
  final String? category;
  final String? coverUrl;
  final String liveMode;
  final bool isAdult;
  final String? speakerStatus;
  final int likes;
  final int viewersPeak;
  final int uniqueViewers;
  final int joinCount;
  final int giftsTotalCents;
  final int? durationSeconds;
  final bool isHost;
  final User? peerUser;

  bool get isLive => kind == 'live';
  bool get isVideoCall => kind == 'video';
  bool get isVoiceChat => liveMode == 'voice_chat';
  bool get isObs => liveMode == 'obs';

  User? get hostUser {
    if (hostId == null || (hostUsername ?? '').isEmpty) return null;
    return User(
      id: hostId!,
      username: hostUsername!,
      displayName: hostName ?? hostUsername!,
      avatarUrl: hostAvatar,
    );
  }

  /// La otra persona en una llamada 1:1 (según quien mira).
  User? counterpartyFor(bool viewerIsHost) => viewerIsHost ? peerUser : hostUser;

  /// Desde FCM / notificación Android (antes de confirmar con la API).
  factory LiveKitSession.fromPush(Map<String, dynamic> data) {
    final id = asInt(data['session_id']);
    final kind = asStr(data['kind'], 'audio');
    final name = asStr(data['caller_name']);
    return LiveKitSession(
      id: id,
      room: '',
      kind: kind == 'video' ? 'video' : 'audio',
      status: 'ringing',
      hostName: name.isNotEmpty ? name : null,
      hostUsername: asStrOrNull(data['caller_username']),
      hostAvatar: asStrOrNull(data['caller_avatar']),
    );
  }

  factory LiveKitSession.fromJson(Json j) {
    final host = asMap(j['host']);
    final peerRaw = asMap(j['peer']);
    final name = asStr(host['display_name']).isNotEmpty ? asStr(host['display_name']) : asStr(host['username']);
    final User? peer = peerRaw.isEmpty ? null : User.fromJson(peerRaw);
    return LiveKitSession(
      id: asInt(j['id']),
      room: asStr(j['room']),
      kind: asStr(j['kind']),
      status: asStr(j['status']),
      hostName: name.isNotEmpty ? name : null,
      hostUsername: asStrOrNull(host['username']),
      hostAvatar: asStrOrNull(host['avatar_url']),
      hostId: asIntOrNull(host['id']),
      title: asStrOrNull(j['title']),
      description: asStrOrNull(j['description']),
      hashtags: asStrOrNull(j['hashtags']),
      category: asStrOrNull(j['category']),
      coverUrl: asStrOrNull(j['cover_url']),
      liveMode: asStr(j['live_mode'], 'camera'),
      isAdult: asBool(j['is_adult']),
      speakerStatus: asStrOrNull(j['speaker_status']),
      likes: asInt(j['likes']),
      viewersPeak: asInt(j['viewers_peak']),
      uniqueViewers: asInt(j['unique_viewers']),
      joinCount: asInt(j['join_count']),
      giftsTotalCents: asInt(j['gifts_total_cents']),
      durationSeconds: asIntOrNull(j['duration_seconds']),
      isHost: asBool(j['is_host']),
      peerUser: peer,
    );
  }
}

/// RTMP + overlay URLs para OBS Studio.
class LiveObsCredentials {
  const LiveObsCredentials({
    required this.rtmpUrl,
    required this.streamKey,
    this.overlayCommentsUrl,
    this.overlayGiftsUrl,
  });

  final String rtmpUrl;
  final String streamKey;
  final String? overlayCommentsUrl;
  final String? overlayGiftsUrl;

  factory LiveObsCredentials.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const LiveObsCredentials(rtmpUrl: '', streamKey: '');
    final legacy = j['overlay_url']?.toString();
    return LiveObsCredentials(
      rtmpUrl: j['rtmp_url']?.toString() ?? '',
      streamKey: j['stream_key']?.toString() ?? '',
      overlayCommentsUrl: j['overlay_comments_url']?.toString() ?? legacy,
      overlayGiftsUrl: j['overlay_gifts_url']?.toString(),
    );
  }

  bool get valid => rtmpUrl.trim().isNotEmpty && streamKey.trim().isNotEmpty;
  bool get hasOverlayComments => (overlayCommentsUrl ?? '').trim().isNotEmpty;
  bool get hasOverlayGifts => (overlayGiftsUrl ?? '').trim().isNotEmpty;
}

class LiveKitJoin {
  LiveKitJoin({
    required this.url,
    required this.token,
    required this.session,
    this.obsRtmpUrl,
    this.obsStreamKey,
    this.obsOverlayCommentsUrl,
    this.obsOverlayGiftsUrl,
  });

  final String url;
  final String token;
  final LiveKitSession session;
  final String? obsRtmpUrl;
  final String? obsStreamKey;
  final String? obsOverlayCommentsUrl;
  final String? obsOverlayGiftsUrl;

  bool get hasObs => (obsRtmpUrl ?? '').isNotEmpty && (obsStreamKey ?? '').isNotEmpty;

  factory LiveKitJoin.fromJson(Json j) {
    final obs = asMap(j['obs']);
    final legacy = asStrOrNull(obs['overlay_url']);
    return LiveKitJoin(
      url: asStr(j['url']),
      token: asStr(j['token']),
      session: LiveKitSession.fromJson(asMap(j['session'])),
      obsRtmpUrl: asStrOrNull(obs['rtmp_url']),
      obsStreamKey: asStrOrNull(obs['stream_key']),
      obsOverlayCommentsUrl: asStrOrNull(obs['overlay_comments_url']) ?? legacy,
      obsOverlayGiftsUrl: asStrOrNull(obs['overlay_gifts_url']),
    );
  }
}

Future<LiveObsCredentials> liveKitPrepareObs() async {
  final res = await api.post('livekit/live/obs/prepare', {});
  return LiveObsCredentials.fromJson(res.map);
}

class LiveKitChatMessage {
  LiveKitChatMessage({required this.id, required this.body, required this.user, this.createdAt, this.replyToId});

  final int id;
  final String body;
  final User user;
  final String? createdAt;
  final int? replyToId;

  factory LiveKitChatMessage.fromJson(Json j) => LiveKitChatMessage(
        id: asInt(j['id']),
        body: asStr(j['body']),
        user: User.fromJson(asMap(j['user'])),
        createdAt: asStrOrNull(j['created_at']),
        replyToId: asIntOrNull(j['reply_to_id']),
      );
}

Future<void> liveKitDecline(int sessionId) async {
  await api.post('livekit/calls/$sessionId/decline', {});
}

Future<LiveKitJoin> liveKitAcceptCall(int sessionId) async {
  final res = await api.post('livekit/calls/$sessionId/accept', {});
  final joinRaw = asMap(res.map['join']);
  if (joinRaw.isNotEmpty) return LiveKitJoin.fromJson(joinRaw);
  return liveKitJoinToken(sessionId);
}

Future<({LiveKitSession session, LiveKitJoin join})> liveKitStartCallBundle(int userId, String kind) async {
  final res = await api.post('livekit/calls', {'user_id': userId, 'kind': kind});
  final join = LiveKitJoin.fromJson(asMap(res.map['join']));
  return (session: LiveKitSession.fromJson(res.map), join: join);
}

Future<LiveKitSession> liveKitStartCall(int userId, String kind) async {
  final res = await api.post('livekit/calls', {'user_id': userId, 'kind': kind});
  return LiveKitSession.fromJson(res.map);
}

Future<LiveKitJoin> liveKitJoinToken(int sessionId) async {
  final res = await api.post('livekit/sessions/$sessionId/token', {});
  return LiveKitJoin.fromJson(res.map);
}

class LiveKitViewerRow {
  LiveKitViewerRow({required this.user, this.speakerStatus});

  final User user;
  final String? speakerStatus;

  factory LiveKitViewerRow.fromJson(Json j) => LiveKitViewerRow(
        user: User.fromJson(asMap(j['user'])),
        speakerStatus: asStrOrNull(j['speaker_status']),
      );
}

Future<LiveKitJoin> liveKitStartLiveJoin({
  String? title,
  String? description,
  String? hashtags,
  String? category,
  String? coverUrl,
  String liveMode = 'camera',
  bool isAdult = false,
}) async {
  final body = <String, dynamic>{
    'live_mode': liveMode,
    if (isAdult) 'is_adult': '1',
    if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    if (hashtags != null && hashtags.trim().isNotEmpty) 'hashtags': hashtags.trim(),
    if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
    if (coverUrl != null && coverUrl.trim().isNotEmpty) 'cover_url': coverUrl.trim(),
  };
  final res = await api.post('livekit/live', body);
  final joinRaw = asMap(res.map['join']);
  if (joinRaw.isNotEmpty) return LiveKitJoin.fromJson(joinRaw);
  final session = LiveKitSession.fromJson(res.map);
  return liveKitJoinToken(session.id);
}

Future<List<LiveKitSession>> liveKitListLives() async {
  final res = await api.get('livekit/lives');
  return res.list.map(LiveKitSession.fromJson).toList();
}

Future<LiveKitSession> liveKitShow(int sessionId) async {
  final res = await api.get('livekit/sessions/$sessionId');
  return LiveKitSession.fromJson(res.map);
}

Future<int> liveKitLike(int sessionId) async {
  final res = await api.post('livekit/sessions/$sessionId/like', {});
  return asInt(res.map['likes']);
}

Future<List<LiveKitChatMessage>> liveKitMessages(int sessionId, {int after = 0}) async {
  final res = await api.get('livekit/sessions/$sessionId/messages', {if (after > 0) 'after': '$after'});
  return res.list.map(LiveKitChatMessage.fromJson).toList();
}

Future<LiveKitChatMessage> liveKitPostMessage(int sessionId, String body, {int? replyToId}) async {
  final res = await api.post('livekit/sessions/$sessionId/messages', {
    'body': body,
    if (replyToId != null) 'reply_to_id': replyToId,
  });
  return LiveKitChatMessage.fromJson(res.map);
}

Future<LiveKitSession> liveKitEnd(int sessionId) async {
  final res = await api.post('livekit/sessions/$sessionId/end', {});
  return LiveKitSession.fromJson(res.map);
}

Future<List<LiveKitViewerRow>> liveKitListViewers(int sessionId) async {
  final res = await api.get('livekit/sessions/$sessionId/viewers');
  return res.list.map(LiveKitViewerRow.fromJson).toList();
}

Future<void> liveKitInviteSpeaker(int sessionId, int userId) async {
  await api.post('livekit/sessions/$sessionId/speakers/invite', {'user_id': userId});
}

Future<void> liveKitAcceptSpeaker(int sessionId) async {
  await api.post('livekit/sessions/$sessionId/speakers/accept', {});
}

Future<void> liveKitRemoveSpeaker(int sessionId, int userId) async {
  await api.post('livekit/sessions/$sessionId/speakers/remove', {'user_id': userId});
}
