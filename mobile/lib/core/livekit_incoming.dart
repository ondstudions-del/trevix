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
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
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
    if (sessionId == _lastSeenId) return;
    _poll();
  }

  void clear() {
    _ringing = null;
    notifyListeners();
  }

  Future<void> _poll() async {
    if (api.token == null || api.token!.isEmpty) return;
    try {
      final res = await api.get('livekit/incoming');
      final call = asMap(res.map['call']);
      if (call.isEmpty) {
        if (_ringing != null) {
          _ringing = null;
          notifyListeners();
        }
        return;
      }
      final session = LiveKitSession.fromJson(call);
      if (session.id == _lastSeenId && _ringing?.id == session.id) return;
      _ringing = session;
      notifyListeners();
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