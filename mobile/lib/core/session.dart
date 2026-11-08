import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api.dart';
import 'device.dart';

enum BootState { loading, failed, ready }

/// Estado global: sesión, cuenta propia, contadores de avisos y configuración del servidor.
class AppState extends ChangeNotifier {
  static const _tokenKey = 'trevix_token';
  static const _introKey = 'trevix_intro_seen';
  static const deviceName = 'iPhone · App TREVIX';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  BootState boot = BootState.loading;
  String? bootError;
  bool introSeen = true;
  Me? me;
  Json config = {};
  Timer? _poll;

  bool get signedIn => me != null;
  Counts get counts => me?.counts ?? Counts();
  String get announcement => asStr(config['announcement']).trim();
  bool get registrationOpen => config['registration_open'] == null || asBool(config['registration_open']);
  bool get maintenance => asBool(config['maintenance']);
  int get passwordMin => asInt(config['password_min_length'], 8);
  int limit(String key, int fallback) => asInt(asMap(config['limits'])[key], fallback);
  Map<String, String> get countries => asMap(config['countries']).map((k, v) => MapEntry(k, '$v'));
  String countryName(String code) => countries[code] ?? code;

  /// Funciones que el servidor tiene activas (gifs, voice_notes).
  bool feature(String key) => asBool(asMap(config['features'])[key]);

  Future<void> start() async {
    boot = BootState.loading;
    bootError = null;
    notifyListeners();
    api.onUnauthorized = _expired;
    try {
      final prefs = await SharedPreferences.getInstance();
      introSeen = prefs.getBool(_introKey) ?? false;
      try {
        config = (await api.get('app/config')).map;
      } on ApiException catch (e) {
        if (e.status == 0) rethrow;
      }
      final token = await _storage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        api.token = token;
        try {
          me = Me.fromJson((await api.get('me')).map);
          _startPolling();
        } on ApiException catch (e) {
          if (e.status == 401) {
            await _clear();
          } else if (e.status == 0) {
            rethrow;
          } else {
            await _clear();
          }
        }
      }
      boot = BootState.ready;
    } catch (e) {
      bootError = errorText(e);
      boot = BootState.failed;
    }
    notifyListeners();
  }

  Future<void> finishIntro() async {
    introSeen = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introKey, true);
  }

  Future<void> replayIntro() async {
    introSeen = false;
    notifyListeners();
  }

  Future<Json> login(String identifier, String password) async {
    final res = await api.post('auth/login', {'identifier': identifier, 'password': password, 'device_name': deviceName});
    await _signIn(res.map);
    return res.map;
  }

  Future<Json> register(Json fields) async {
    final res = await api.post('auth/register', {...fields, 'terms': true, 'device_name': deviceName});
    await _signIn(res.map);
    return res.map;
  }

  Future<void> _signIn(Json data) async {
    final token = asStr(data['token']);
    api.token = token;
    await _storage.write(key: _tokenKey, value: token);
    me = Me.fromJson(asMap(data['user']));
    _startPolling();
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('auth/logout');
    } catch (_) {}
    await _clear();
    notifyListeners();
  }

  /// Sesión cerrada desde el servidor (401): vuelve al inicio de sesión.
  void signedOutRemotely() {
    _clear().then((_) => notifyListeners());
  }

  void _expired() {
    if (me != null) signedOutRemotely();
  }

  Future<void> _clear() async {
    _poll?.cancel();
    _poll = null;
    api.token = null;
    me = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> refreshMe() async {
    try {
      me = Me.fromJson((await api.get('me')).map);
      notifyListeners();
    } catch (_) {}
  }

  void setMe(Json data) {
    me = Me.fromJson(data);
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    if (me == null) return;
    try {
      final before = me!.counts;
      me!.counts = Counts.fromJson((await api.get('me/counts')).map);
      _alertNew(before, me!.counts);
      notifyListeners();
    } catch (_) {}
  }

  /// Aviso del sistema cuando llegan mensajes o notificaciones nuevas (si el usuario dio permiso).
  void _alertNew(Counts before, Counts after) {
    if (after.messages > before.messages) {
      DeviceAccess.notify(1, 'Mensajes nuevos',
          after.messages == 1 ? 'Tienes 1 conversación sin leer.' : 'Tienes ${after.messages} conversaciones sin leer.');
    }
    final pending = after.notifications + after.followRequests;
    if (pending > before.notifications + before.followRequests) {
      DeviceAccess.notify(2, 'TREVIX', pending == 1 ? 'Tienes 1 notificación nueva.' : 'Tienes $pending notificaciones nuevas.');
    }
  }

  void setCounts(Json data) {
    if (me == null) return;
    me!.counts = Counts.fromJson(data);
    notifyListeners();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => refreshCounts());
  }

  void pausePolling() {
    _poll?.cancel();
    _poll = null;
  }

  void resumePolling() {
    if (me == null) return;
    refreshCounts();
    _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
