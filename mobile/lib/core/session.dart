import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'accounts.dart';
import 'api.dart';
import 'background.dart';
import 'device.dart';
import 'e2ee.dart';
import 'fcm.dart';
import 'i18n.dart';
import 'private_chats.dart';
import 'push.dart';
import 'recent_searches.dart';

enum BootState { loading, failed, ready }

/// Estado global: sesión, cuenta propia, contadores de avisos y configuración del servidor.
class AppState extends ChangeNotifier {
  static const _tokenKey = 'trevix_token';
  static const _introKey = 'trevix_intro_seen';
  static String get deviceName => Platform.isIOS ? 'iPhone · App TREVIX' : 'Android · App TREVIX';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  late final AccountStore _accounts = AccountStore(_storage);

  BootState boot = BootState.loading;
  String? bootError;
  bool introSeen = true;
  Me? _me;
  Json config = {};

  Me? get me => _me;

  /// La cuenta activa también trae su idioma (el que eligió en la web o en otro teléfono).
  set me(Me? value) {
    _me = value;
    Lang.instance.account(value?.locale);
  }
  Timer? _poll;

  /// Cuentas con sesión abierta en este teléfono (la activa incluida).
  List<SavedAccount> accounts = [];

  /// Iniciando sesión en otra cuenta sin cerrar la actual («Agregar cuenta»).
  bool addingAccount = false;
  String? _tokenBeforeAdding;

  List<SavedAccount> get otherAccounts => [for (final a in accounts) if (a.id != me?.id) a];

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
        FcmPush.config = asMap(config['push']);
      } on ApiException catch (e) {
        if (e.status == 0) rethrow;
      }
      accounts = await _accounts.read();
      final token = await _storage.read(key: _tokenKey);
      if (token != null && token.isNotEmpty) {
        api.token = token;
        try {
          me = Me.fromJson((await api.get('me')).map);
          await _remember(token);
          _startPolling();
        } on ApiException catch (e) {
          if (e.status == 0) rethrow;
          await _forgetToken(token);
          await _clear();
          await _fallback();
        }
      } else if (accounts.isNotEmpty) {
        await _fallback();
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
    final previous = me;
    final next = Me.fromJson(asMap(data['user']));
    if (previous != null && previous.id != next.id) await _leaveAccount();
    // Volver a entrar en una cuenta ya guardada deja su sesión anterior sin uso: se cierra en el servidor.
    final stale = {
      for (final a in accounts)
        if (a.id == next.id) a.token,
      if (previous != null && previous.id == next.id && _tokenBeforeAdding != null) _tokenBeforeAdding!,
    }..remove(token);
    addingAccount = false;
    _tokenBeforeAdding = null;
    api.token = token;
    await _storage.write(key: _tokenKey, value: token);
    me = next;
    await _remember(token);
    _startPolling();
    notifyListeners();
    for (final t in stale) {
      api.request('POST', 'auth/logout', body: {}, asToken: t).then<void>((_) {}, onError: (_) {});
    }
  }

  /// Guarda (o actualiza) la cuenta activa en la lista de cuentas del teléfono.
  Future<void> _remember(String token) async {
    final current = me;
    if (current == null) return;
    final list = [SavedAccount.of(current.user, token), ...accounts.where((a) => a.id != current.id)];
    accounts = list.take(AccountStore.max).toList();
    await _accounts.write(accounts);
  }

  Future<void> _forgetToken(String token) async {
    accounts = accounts.where((a) => a.token != token).toList();
    await _accounts.write(accounts);
  }

  /// Lo que es de la cuenta que se deja (cifrado en memoria, búsquedas, avisos) antes de entrar en otra.
  Future<void> _leaveAccount() async {
    _poll?.cancel();
    _poll = null;
    e2ee.forget();
    privateChats.lock();
    await recentSearches.clear();
    await BackgroundNotices.reset();
    BackgroundNotices.instant = false;
    await AndroidPush.stop(forget: true);
    await FcmPush.stop();
  }

  /// «Agregar cuenta»: muestra el inicio de sesión sin cerrar la cuenta actual.
  void beginAddAccount() {
    if (me == null || addingAccount) return;
    if (accounts.length >= AccountStore.max) throw ApiException(0, 'limit', tr('Puedes tener hasta {max} cuentas en este teléfono.', {'max': AccountStore.max}));
    pausePolling();
    privateChats.lock();
    _tokenBeforeAdding = api.token;
    api.token = null;
    addingAccount = true;
    notifyListeners();
  }

  void cancelAddAccount() {
    if (!addingAccount) return;
    api.token = _tokenBeforeAdding;
    _tokenBeforeAdding = null;
    addingAccount = false;
    _startPolling();
    notifyListeners();
  }

  /// Cambia a otra cuenta guardada. Si su sesión ya no vale, la quita de la lista y lanza el error.
  Future<void> switchTo(SavedAccount account) async {
    if (account.id == me?.id) return;
    final Me next;
    try {
      next = Me.fromJson((await api.request('GET', 'me', asToken: account.token)).map);
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _forgetToken(account.token);
        notifyListeners();
        throw ApiException(e.status, 'expired', tr('La sesión de @{username} se cerró. Agrégala de nuevo con tu contraseña.', {'username': account.username}));
      }
      rethrow;
    }
    await _leaveAccount();
    api.token = account.token;
    await _storage.write(key: _tokenKey, value: account.token);
    me = next;
    await _remember(account.token);
    _startPolling();
    notifyListeners();
  }

  /// Quita una cuenta guardada que no es la activa (y cierra su sesión en el servidor).
  Future<void> removeAccount(SavedAccount account) async {
    if (account.id == me?.id) return logout();
    try {
      await api.request('POST', 'auth/logout', body: {}, asToken: account.token);
    } catch (_) {}
    await _forgetToken(account.token);
    notifyListeners();
  }

  /// Entra en la primera cuenta guardada cuya sesión siga abierta.
  Future<void> _fallback() async {
    for (final a in List.of(accounts)) {
      try {
        final next = Me.fromJson((await api.request('GET', 'me', asToken: a.token)).map);
        api.token = a.token;
        await _storage.write(key: _tokenKey, value: a.token);
        me = next;
        await _remember(a.token);
        _startPolling();
        return;
      } on ApiException catch (e) {
        if (e.status == 0) return;
        await _forgetToken(a.token);
      }
    }
  }

  Future<void> logout() async {
    final token = api.token;
    try {
      await api.post('auth/logout');
    } catch (_) {}
    if (token != null) await _forgetToken(token);
    await _clear();
    await _fallback();
    notifyListeners();
  }

  /// Sesión cerrada desde el servidor (401, cuenta desactivada o eliminada): pasa a otra cuenta guardada o al inicio de sesión.
  void signedOutRemotely() {
    final token = api.token;
    () async {
      if (token != null) await _forgetToken(token);
      await _clear();
      await _fallback();
      notifyListeners();
    }();
  }

  void _expired() {
    if (me != null && !addingAccount) signedOutRemotely();
  }

  Future<void> _clear() async {
    await _leaveAccount();
    api.token = null;
    me = null;
    addingAccount = false;
    _tokenBeforeAdding = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<void> refreshMe() async {
    try {
      me = Me.fromJson((await api.get('me')).map);
      _syncSaved();
      notifyListeners();
    } catch (_) {}
  }

  void setMe(Json data) {
    me = Me.fromJson(data);
    _syncSaved();
    notifyListeners();
  }

  /// Nombre, usuario y foto de la cuenta activa al día en la lista de cuentas.
  void _syncSaved() {
    final u = me?.user;
    final token = api.token;
    if (u == null || token == null) return;
    final saved = accounts.where((a) => a.id == u.id).firstOrNull;
    if (saved != null && saved.username == u.username && saved.displayName == u.displayName && saved.avatarUrl == u.avatarUrl) return;
    _remember(token);
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
    if (BackgroundNotices.instant) return;
    if (after.messages > before.messages) {
      DeviceAccess.notify(1, tr('Mensajes nuevos'),
          after.messages == 1 ? tr('Tienes 1 conversación sin leer.') : tr('Tienes {n} conversaciones sin leer.', {'n': after.messages}));
    }
    final pending = after.notifications + after.followRequests;
    if (pending > before.notifications + before.followRequests) {
      DeviceAccess.notify(2, 'TREVIX', pending == 1 ? tr('Tienes 1 notificación nueva.') : tr('Tienes {n} notificaciones nuevas.', {'n': pending}));
    }
  }

  void setCounts(Json data) {
    if (me == null) return;
    me!.counts = Counts.fromJson(data);
    notifyListeners();
  }

  /// Con la app abierta, cada consulta de contadores también te mantiene «en línea» (el servidor lo anota a los 20 s
  /// y te muestra desconectado a los 75 s sin actividad).
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 25), (_) => refreshCounts());
  }

  /// Al salir de la app se avisa al servidor para que deje de mostrarte en línea al momento.
  void pausePolling() {
    _poll?.cancel();
    _poll = null;
    if (me != null) api.post('me/presence', {'state': 'away'}).then((_) {}, onError: (_) {});
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
