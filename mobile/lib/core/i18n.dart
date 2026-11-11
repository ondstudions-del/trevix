import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/en.dart';

/// Idioma de la app. Los textos se escriben en español en el código y [tr] los busca en el diccionario inglés
/// (`lib/l10n/`). Orden: el elegido en este teléfono, el de la cuenta (el mismo que en la web) y el del sistema.
class Lang extends ChangeNotifier {
  Lang._();

  static final instance = Lang._();

  static const _key = 'trevix_locale';
  static const codes = ['es', 'en'];
  static const names = {'es': 'Español', 'en': 'English'};

  /// null = el del sistema.
  String? choice;
  String? _account;
  String code = 'es';

  bool get en => code == 'en';
  Locale get locale => Locale(code);

  static String get system => PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'es';

  Future<void> load() async {
    final saved = (await SharedPreferences.getInstance()).getString(_key);
    choice = codes.contains(saved) ? saved : null;
    code = _resolve();
  }

  String _resolve() => choice ?? _account ?? system;

  void _update() {
    final next = _resolve();
    if (next == code) return;
    code = next;
    notifyListeners();
  }

  /// Elegido en Ajustes (null vuelve al del sistema).
  Future<void> set(String? c) async {
    choice = codes.contains(c) ? c : null;
    final p = await SharedPreferences.getInstance();
    choice == null ? await p.remove(_key) : await p.setString(_key, choice!);
    if (choice != null) _account = choice;
    _update();
  }

  /// Idioma guardado en la cuenta que acaba de entrar (solo cuenta si este teléfono no tiene uno elegido).
  void account(String? c) {
    _account = codes.contains(c) ? c : null;
    _update();
  }

  void systemChanged() => _update();
}

/// Texto en el idioma de la app. [es] es el texto en español (y la clave del diccionario); `{nombre}` se reemplaza
/// con [args]: `tr('Hola, {name}', {'name': u.displayName})`.
String tr(String es, [Map<String, Object?> args = const {}]) {
  var s = Lang.instance.en ? (en[es] ?? es) : es;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}
