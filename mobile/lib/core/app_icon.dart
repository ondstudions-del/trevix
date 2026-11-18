import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'i18n.dart';

/// Iconos de la app que el usuario puede elegir (Ajustes › Apariencia).
enum AppIconChoice {
  original,
  wave,
  heart,
  messages,
  mark;

  String get label => switch (this) {
        AppIconChoice.original => tr('Original'),
        AppIconChoice.wave => tr('Onda'),
        AppIconChoice.heart => tr('Corazón'),
        AppIconChoice.messages => tr('Mensajes'),
        AppIconChoice.mark => tr('Marca'),
      };

  /// Vista previa en los ajustes (assets/icon/).
  String get previewAsset => switch (this) {
        AppIconChoice.original => 'assets/icon/icon_original.png',
        AppIconChoice.wave => 'assets/icon/icon_wave.png',
        AppIconChoice.heart => 'assets/icon/icon_heart.png',
        AppIconChoice.messages => 'assets/icon/icon_messages.png',
        AppIconChoice.mark => 'assets/icon/icon_mark.png',
      };

  /// Nombre de icono alternativo en iOS (`null` = el predeterminado del bundle).
  String? get iosName => switch (this) {
        AppIconChoice.original => null,
        AppIconChoice.wave => 'AppIconWave',
        AppIconChoice.heart => 'AppIconHeart',
        AppIconChoice.messages => 'AppIconMessages',
        AppIconChoice.mark => 'AppIconMark',
      };

  /// Activity-alias de Android (siempre un alias; nunca se desactiva MainActivity).
  String get androidAlias => switch (this) {
        AppIconChoice.original => 'MainActivityDefault',
        AppIconChoice.wave => 'MainActivityWave',
        AppIconChoice.heart => 'MainActivityHeart',
        AppIconChoice.messages => 'MainActivityMessages',
        AppIconChoice.mark => 'MainActivityMark',
      };
}

/// Cambia el icono del lanzador (iOS: iconos alternativos; Android: activity-alias).
class AppIcons {
  AppIcons._();

  static const _channel = MethodChannel('trevix/app_icon');

  static Future<void> set(AppIconChoice icon) async {
    if (Platform.isIOS) {
      await _channel.invokeMethod<void>('set', {'name': icon.iosName});
      return;
    }
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('set', {'alias': icon.androidAlias});
    }
  }

  /// Nombre actual en iOS (`null` = primario); en Android el alias activo o null.
  static Future<String?> current() async {
    try {
      return await _channel.invokeMethod<String?>('current');
    } catch (e, st) {
      developer.log('AppIcons.current failed', error: e, stackTrace: st, name: 'trevix.icon');
      return null;
    }
  }

  static Future<bool> supported() async {
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } catch (e, st) {
      developer.log('AppIcons.supported failed', error: e, stackTrace: st, name: 'trevix.icon');
      return false;
    }
  }
}
