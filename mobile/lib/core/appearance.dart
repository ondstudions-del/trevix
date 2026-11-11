import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'theme.dart';

/// Modo de color: el del sistema, claro u oscuro.
enum ThemeChoice { system, light, dark }

/// Apariencia y accesibilidad. Se guardan en el teléfono (son del dispositivo, no de la cuenta).
class Appearance extends ChangeNotifier {
  Appearance._();

  static final instance = Appearance._();

  static const textScales = <double>[0, .9, 1, 1.15, 1.3];
  static List<String> get textScaleLabels => [tr('Del sistema'), tr('Pequeño'), tr('Mediano'), tr('Grande'), tr('Muy grande')];

  ThemeChoice choice = ThemeChoice.system;

  /// 0 = tamaño del sistema; el resto multiplica el tamaño base.
  double textScale = 0;
  bool boldText = false;
  bool reduceMotion = false;
  bool highContrast = false;

  Brightness _platform = Brightness.dark;

  Brightness get brightness => switch (choice) {
        ThemeChoice.light => Brightness.light,
        ThemeChoice.dark => Brightness.dark,
        ThemeChoice.system => _platform,
      };

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    choice = ThemeChoice.values.firstWhere((c) => c.name == p.getString('trevix_theme'), orElse: () => ThemeChoice.system);
    final scale = p.getDouble('trevix_text_scale') ?? 0;
    textScale = textScales.contains(scale) ? scale : 0;
    boldText = p.getBool('trevix_bold_text') ?? false;
    reduceMotion = p.getBool('trevix_reduce_motion') ?? false;
    highContrast = p.getBool('trevix_high_contrast') ?? false;
    _platform = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    _apply();
  }

  /// El sistema cambió entre claro y oscuro (solo importa en «Del sistema»).
  void platformChanged(Brightness b) {
    if (b == _platform) return;
    _platform = b;
    if (choice == ThemeChoice.system) _changed();
  }

  Future<void> setChoice(ThemeChoice c) async {
    choice = c;
    _changed();
    (await SharedPreferences.getInstance()).setString('trevix_theme', c.name);
  }

  Future<void> setTextScale(double s) async {
    textScale = s;
    _changed();
    (await SharedPreferences.getInstance()).setDouble('trevix_text_scale', s);
  }

  Future<void> setBoldText(bool v) async {
    boldText = v;
    _changed();
    (await SharedPreferences.getInstance()).setBool('trevix_bold_text', v);
  }

  Future<void> setReduceMotion(bool v) async {
    reduceMotion = v;
    _changed();
    (await SharedPreferences.getInstance()).setBool('trevix_reduce_motion', v);
  }

  Future<void> setHighContrast(bool v) async {
    highContrast = v;
    _changed();
    (await SharedPreferences.getInstance()).setBool('trevix_high_contrast', v);
  }

  void _apply() => Tx.use(TxPalette.resolve(brightness, highContrast: highContrast));

  void _changed() {
    _apply();
    notifyListeners();
  }

  /// Ajustes de accesibilidad sobre los del sistema (tamaño, negrita, movimiento y contraste).
  MediaQueryData apply(MediaQueryData m) => m.copyWith(
        textScaler: textScale == 0 ? m.textScaler.clamp(maxScaleFactor: 1.6) : TextScaler.linear(textScale),
        boldText: boldText || m.boldText,
        disableAnimations: reduceMotion || m.disableAnimations,
        highContrast: highContrast || m.highContrast,
      );

  /// «Reducir movimiento» de la app o del sistema.
  static bool motionReduced(BuildContext context) => instance.reduceMotion || MediaQuery.of(context).disableAnimations;
}
