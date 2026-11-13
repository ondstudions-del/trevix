import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'api.dart';
import 'config.dart';

/// Avisos push con Firebase Cloud Messaging (plan gratuito), con la app abierta, en segundo plano o cerrada.
/// Android (android_overrides/.../Fcm.kt): el aviso despierta la app, que consulta GET me/push y muestra lo nuevo con
/// foto, «Responder» y «Marcar como leído», sin aviso fijo. iPhone (packages/trevix_fcm): el servidor arma los avisos y
/// Apple los entrega por APNs. Los datos de Firebase llegan del servidor (app/config → push); sin ellos, o si el
/// teléfono no puede usar Firebase, siguen los avisos propios de TREVIX (core/push.dart y core/background.dart).
class FcmPush {
  FcmPush._();

  static const _channel = MethodChannel('trevix/fcm');
  static const activeKey = 'trevix_fcm_active';

  /// Datos públicos de Firebase que entrega el servidor (AppState los guarda al leer app/config).
  static Json config = {};

  /// Los avisos llegan por Firebase en este teléfono.
  static bool active = false;
  static bool _listening = false;

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  static bool get supported => (Platform.isAndroid || Platform.isIOS) && asMap(config[_platform]).isNotEmpty;

  /// Registra el teléfono en Firebase y en TREVIX. Devuelve true si los avisos ya llegan por Firebase.
  static Future<bool> start() async {
    final app = asMap(config[_platform]);
    final token = api.token;
    if (app.isEmpty || token == null || token.isEmpty) return _deactivate();
    _listen();
    String? fcmToken;
    try {
      fcmToken = await _channel.invokeMethod<String>('register', {
        'app_id': asStr(app['app_id']),
        'api_key': asStr(app['api_key']),
        'project_id': asStr(config['project_id']),
        'sender_id': asStr(config['sender_id']),
        'token': token,
        'api': AppConfig.apiBase,
      }).timeout(const Duration(seconds: 20));
    } catch (_) {}
    if (fcmToken == null || fcmToken.isEmpty || !await _register(fcmToken)) return _deactivate();
    try {
      await _channel.invokeMethod<void>('activate');
    } catch (_) {}
    active = true;
    await (await SharedPreferences.getInstance()).setBool(activeKey, true);
    return true;
  }

  /// Guarda el token en TREVIX. false si no se pudo o si los últimos envíos a este teléfono fallaron (entonces la app
  /// sigue revisando por su cuenta para no perder avisos).
  static Future<bool> _register(String fcmToken) async {
    try {
      final res = await api.post('me/push/devices', {'token': fcmToken, 'platform': _platform, 'app_version': AppConfig.version});
      return asStr(res.map['delivery']) != 'failing';
    } catch (_) {
      return false;
    }
  }

  /// Firebase renovó el token (iPhone; en Android lo registra el servicio nativo).
  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'token' && active && api.token != null && call.arguments is String) {
        await _register(call.arguments as String);
      }
    });
  }

  static Future<bool> _deactivate() async {
    active = false;
    await (await SharedPreferences.getInstance()).setBool(activeKey, false);
    return false;
  }

  /// Al salir de la cuenta: el token de este teléfono deja de valer (cerrar sesión ya lo borra en el servidor).
  static Future<void> stop() async {
    final was = active;
    await _deactivate();
    if (!was || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _channel.invokeMethod<void>('delete').timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  /// Chat abierto en pantalla en iPhone (0 = ninguno): sus avisos no se muestran con la app abierta.
  static Future<void> activeChat(int id) async {
    if (!Platform.isIOS || !active) return;
    try {
      await _channel.invokeMethod<void>('activeChat', {'id': id});
    } catch (_) {}
  }
}
