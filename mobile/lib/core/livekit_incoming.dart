import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import 'api.dart';
import 'livekit_api.dart';
import 'session.dart';

/// Detecta llamadas entrantes (poll + despertar por Firebase).
class LiveKitIncoming extends ChangeNotifier {
  LiveKitIncoming._();

  static final instance = LiveKitIncoming._();

  LiveKitSession? _ringing;
  Timer? _timer;
  int _lastSeenId = 0;

  LiveKitSession? get ringing => _ringing;

  void bind(AppState state) {
    _timer?.cancel();
    _ringing = null;
    if (!state.signedIn) return;
    final lk = LiveKitConfig.fromAppConfig(state.config);
    if (lk == null || !lk.ready) return;
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    _poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _ringing = null;
    notifyListeners();
  }

  /// Llamada explícita desde Firebase (datos `livekit_call`).
  void hint(int sessionId) {
    if (sessionId < 1) return;
    hintFromPush({'session_id': '$sessionId'});
  }

  /// Datos push / notificación: muestra la UI al momento y confirma con la API.
  void hintFromPush(Map<String, dynamic> data) {
    final session = LiveKitSession.fromPush(data);
    if (session.id < 1) return;
    if (session.id == _lastSeenId) return;
    _ringing = session;
    notifyListeners();
    _poll(preferId: session.id);
  }

  void clear() {
    _ringing = null;
    notifyListeners();
  }

  Future<void> _poll({int? preferId}) async {
    if (api.token == null || api.token!.isEmpty) return;
    try {
      LiveKitSession? session;
      if (preferId != null && preferId > 0) {
        try {
          final shown = await liveKitShow(preferId);
          if (shown.status == 'ringing' && (shown.kind == 'audio' || shown.kind == 'video')) {
            session = shown;
          }
        } catch (_) {}
      }
      if (session == null) {
        final res = await api.get('livekit/incoming');
        final call = asMap(res.map['call']);
        if (call.isEmpty) {
          if (preferId != null && preferId > 0 && _ringing?.id == preferId) {
            return;
          }
          if (_ringing != null) {
            _ringing = null;
            notifyListeners();
          }
          return;
        }
        session = LiveKitSession.fromJson(call);
      }
      if (session.id != _lastSeenId || _ringing?.id != session.id) {
        _ringing = session;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> dismissed(int sessionId) async {
    if (_ringing?.id == sessionId) {
      _lastSeenId = sessionId;
      _ringing = null;
      notifyListeners();
    }
  }
}
