import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'fcm.dart';

/// Avisos al instante en Android (android_overrides/.../Push*.kt): GET me/push se muestra como notificaciones del
/// sistema, con foto, «Responder» y «Marcar como leído». Lo despierta Firebase (core/fcm.dart) o, en teléfonos sin
/// Firebase, un servicio en primer plano con un aviso fijo y silencioso. En iOS no hace nada (allí están los avisos
/// push de Apple o BackgroundNotices).
class AndroidPush {
  AndroidPush._();

  static const _channel = MethodChannel('trevix/push');
  static const _enabledKey = 'trevix_push_instant';

  static bool get supported => Platform.isAndroid;

  /// Preferencia «Avisos al instante» (activada salvo que la persona la apague).
  static Future<bool> wanted() async {
    if (!supported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setWanted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  static Future<bool> start(String token) async {
    if (!supported || token.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('start', {'token': token, 'api': AppConfig.apiBase}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [forget]: al cerrar sesión borra el token guardado y quita los avisos mostrados.
  static Future<void> stop({bool forget = false}) => _call('stop', {'forget': forget});

  /// Chat abierto en pantalla (0 = ninguno): sus mensajes no se avisan y se quitan los avisos que tenía.
  static Future<void> activeChat(int id) async {
    await FcmPush.activeChat(id);
    await _call('activeChat', {'id': id});
  }

  /// Clave privada de los chats cifrados para que las notificaciones muestren el mensaje y se pueda responder
  /// cifrado desde ellas. Android la guarda cifrada con el Keystore del teléfono (E2ee.kt).
  static Future<void> shareKey(int uid, int keyId, String seed) => _call('e2eeKey', {'uid': uid, 'keyId': keyId, 'seed': seed});

  static Future<void> forgetKey() => _call('e2eeForget');

  /// Al abrir la pestaña de notificaciones se quitan los avisos de actividad del sistema.
  static Future<void> clearActivity() => _call('clearActivity');

  /// Si Android aplica la optimización de batería a TREVIX (los avisos pueden retrasarse con el teléfono en reposo).
  static Future<bool> batteryRestricted() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('batteryRestricted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openBatterySettings() => _call('openBatterySettings');

  static Future<void> openChannelSettings() => _call('openChannelSettings');

  static Future<void> _call(String method, [Map<String, Object>? args]) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {}
  }
}
