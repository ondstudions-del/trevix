import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';

/// Cómo desbloquea el usuario la app cuando el bloqueo está activo.
enum AppLockMethod { biometrics, pin, pattern }

/// Bloqueo de la app (Ajustes › Privacidad). Al activarlo, pide verificación al abrir o volver.
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock._();

  static final instance = AppLock._();

  static const _grace = Duration(seconds: 2);
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  final _auth = LocalAuthentication();

  bool enabled = false;
  AppLockMethod method = AppLockMethod.biometrics;
  bool locked = false;
  bool biometricsAvailable = false;
  String biometricLabel = 'Face ID';

  DateTime? _pausedAt;
  bool _ready = false;

  bool get ready => _ready;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('trevix_app_lock') ?? false;
    method = AppLockMethod.values.firstWhere(
      (m) => m.name == p.getString('trevix_app_lock_method'),
      orElse: () => AppLockMethod.biometrics,
    );
    await _refreshBiometrics();
    locked = enabled;
    _ready = true;
    notifyListeners();
  }

  void install() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _pausedAt;
      _pausedAt = null;
      if (since != null && DateTime.now().difference(since) > _grace) {
        lock();
      }
    }
  }

  Future<void> refreshBiometrics() async {
    try {
      biometricsAvailable = await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) {
        biometricLabel = 'Face ID';
      } else if (types.contains(BiometricType.fingerprint) || types.contains(BiometricType.strong) || types.contains(BiometricType.weak)) {
        biometricLabel = tr('Huella');
      } else {
        biometricLabel = tr('Biometría');
      }
    } catch (_) {
      biometricsAvailable = false;
      biometricLabel = tr('Biometría');
    }
    notifyListeners();
  }

  Future<void> _refreshBiometrics() => refreshBiometrics();

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('trevix_app_lock', enabled);
    await p.setString('trevix_app_lock_method', method.name);
  }

  void lock() {
    if (!enabled || locked) return;
    locked = true;
    notifyListeners();
  }

  void _unlock() {
    locked = false;
    _pausedAt = null;
    notifyListeners();
  }

  Future<bool> authenticateBiometrics() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: tr('Desbloquea TREVIX para continuar.'),
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) _unlock();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<String> _hash(String secret, String salt) async {
    final digest = await Sha256().hash(utf8.encode('$salt::$secret'));
    return base64Url.encode(digest.bytes);
  }

  Future<void> setPin(String pin) async {
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final hash = await _hash(pin, salt);
    await _storage.write(key: 'trevix_app_lock_pin_salt', value: salt);
    await _storage.write(key: 'trevix_app_lock_pin_hash', value: hash);
    await _storage.delete(key: 'trevix_app_lock_pattern_salt');
    await _storage.delete(key: 'trevix_app_lock_pattern_hash');
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _storage.read(key: 'trevix_app_lock_pin_salt');
    final hash = await _storage.read(key: 'trevix_app_lock_pin_hash');
    if (salt == null || hash == null) return false;
    final ok = await _hash(pin, salt) == hash;
    if (ok) _unlock();
    return ok;
  }

  Future<void> setPattern(List<int> dots) async {
    final secret = dots.join(',');
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final hash = await _hash(secret, salt);
    await _storage.write(key: 'trevix_app_lock_pattern_salt', value: salt);
    await _storage.write(key: 'trevix_app_lock_pattern_hash', value: hash);
    await _storage.delete(key: 'trevix_app_lock_pin_salt');
    await _storage.delete(key: 'trevix_app_lock_pin_hash');
  }

  Future<bool> verifyPattern(List<int> dots) async {
    final salt = await _storage.read(key: 'trevix_app_lock_pattern_salt');
    final hash = await _storage.read(key: 'trevix_app_lock_pattern_hash');
    if (salt == null || hash == null) return false;
    final ok = await _hash(dots.join(','), salt) == hash;
    if (ok) _unlock();
    return ok;
  }

  Future<bool> hasPin() async => (await _storage.read(key: 'trevix_app_lock_pin_hash')) != null;
  Future<bool> hasPattern() async => (await _storage.read(key: 'trevix_app_lock_pattern_hash')) != null;

  Future<void> enable(AppLockMethod m) async {
    await _refreshBiometrics();
    if (m == AppLockMethod.biometrics && !biometricsAvailable) {
      throw StateError('biometrics');
    }
    if (m == AppLockMethod.pin && !await hasPin()) throw StateError('pin');
    if (m == AppLockMethod.pattern && !await hasPattern()) throw StateError('pattern');
    method = m;
    enabled = true;
    locked = false;
    await _persist();
    notifyListeners();
  }

  Future<void> disable({required Future<bool> Function() confirm}) async {
    if (!await confirm()) return;
    enabled = false;
    locked = false;
    await _persist();
    notifyListeners();
  }

  Future<void> clearSecrets() async {
    await _storage.delete(key: 'trevix_app_lock_pin_salt');
    await _storage.delete(key: 'trevix_app_lock_pin_hash');
    await _storage.delete(key: 'trevix_app_lock_pattern_salt');
    await _storage.delete(key: 'trevix_app_lock_pattern_hash');
  }

  String methodLabel() => switch (method) {
        AppLockMethod.biometrics => biometricLabel,
        AppLockMethod.pin => tr('PIN'),
        AppLockMethod.pattern => tr('Patrón'),
      };
}
