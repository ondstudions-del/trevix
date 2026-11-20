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
      videoCalls: raw.containsKey('video_calls') ? asBool(raw['video_calls']) : true,
      live: raw.containsKey('live') ? asBool(raw['live']) : true,
    );
  }

  static LiveKitConfig? of(BuildContext context) => fromAppConfig(context.read<AppState>().config);
}

class LiveKitSession {
  LiveKitSession({required this.id, required this.room, required this.kind, required this.status, this.hostName});

  final int id;
  final String room;
  final String kind;
  final String status;
  final String? hostName;

  factory LiveKitSession.fromJson(Json j) {
    final host = asMap(j['host']);
    final name = asStr(host['display_name']).isNotEmpty ? asStr(host['display_name']) : asStr(host['username']);
    return LiveKitSession(
      id: asInt(j['id']),
      room: asStr(j['room']),
      kind: asStr(j['kind']),
      status: asStr(j['status']),
      hostName: name.isNotEmpty ? name : null,
    );
  }
}

Future<void> liveKitDecline(int sessionId) async {
  await api.post('livekit/calls/$sessionId/decline', {});
}

Future<({LiveKitSession session, LiveKitJoin join})> liveKitStartCallBundle(int userId, String kind) async {
  final res = await api.post('livekit/calls', {'user_id': userId, 'kind': kind});
  final join = LiveKitJoin.fromJson(asMap(res.map['join']));
  return (session: LiveKitSession.fromJson(res.map), join: join);
}

class LiveKitJoin {
  LiveKitJoin({required this.url, required this.token, required this.session});

  final String url;
  final String token;
  final LiveKitSession session;

  factory LiveKitJoin.fromJson(Json j) => LiveKitJoin(
        url: asStr(j['url']),
        token: asStr(j['token']),
        session: LiveKitSession.fromJson(asMap(j['session'])),
      );
}

Future<LiveKitSession> liveKitStartCall(int userId, String kind) async {
  final res = await api.post('livekit/calls', {'user_id': userId, 'kind': kind});
  return LiveKitSession.fromJson(res.map);
}

Future<LiveKitJoin> liveKitJoinToken(int sessionId) async {
  final res = await api.post('livekit/sessions/$sessionId/token', {});
  return LiveKitJoin.fromJson(res.map);
}

Future<LiveKitSession> liveKitStartLive({String? title}) async {
  final body = <String, dynamic>{};
  if (title != null && title.trim().isNotEmpty) body['title'] = title.trim();
  final res = await api.post('livekit/live', body);
  return LiveKitSession.fromJson(res.map);
}

Future<void> liveKitEnd(int sessionId) async {
  await api.post('livekit/sessions/$sessionId/end', {});
}