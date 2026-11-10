import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores que cambian entre el modo claro y el oscuro (y sus versiones de alto contraste).
class TxPalette {
  const TxPalette({
    required this.brightness,
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surface4,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.glass,
    required this.scrim,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color surface4;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color muted;
  final Color subtle;

  /// Fondo translúcido de las barras y hojas de vidrio.
  final Color glass;

  /// Velo sobre el contenido detrás de hojas y diálogos.
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  static const dark = TxPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF09090B),
    surface1: Color(0xFF0F0F12),
    surface2: Color(0xFF18181B),
    surface3: Color(0xFF202024),
    surface4: Color(0xFF27272A),
    border: Color(0x12FFFFFF),
    borderStrong: Color(0x1FFFFFFF),
    text: Color(0xFFFAFAFA),
    muted: Color(0xFFA1A1AA),
    subtle: Color(0xFF71717A),
    glass: Color(0xB8101014),
    scrim: Color(0x99000000),
  );

  static const darkContrast = TxPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface1: Color(0xFF0A0A0C),
    surface2: Color(0xFF16161A),
    surface3: Color(0xFF222228),
    surface4: Color(0xFF2E2E35),
    border: Color(0x33FFFFFF),
    borderStrong: Color(0x59FFFFFF),
    text: Color(0xFFFFFFFF),
    muted: Color(0xFFD4D4D8),
    subtle: Color(0xFFA1A1AA),
    glass: Color(0xF0000000),
    scrim: Color(0xB3000000),
  );

  static const light = TxPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF6F6F9),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFEFEFF4),
    surface4: Color(0xFFE4E4EB),
    border: Color(0x14000000),
    borderStrong: Color(0x24000000),
    text: Color(0xFF0B0B10),
    muted: Color(0xFF55555F),
    subtle: Color(0xFF85858F),
    glass: Color(0xD9FFFFFF),
    scrim: Color(0x66000000),
  );

  static const lightContrast = TxPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    surface1: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFE9E9EF),
    surface4: Color(0xFFD9D9E1),
    border: Color(0x33000000),
    borderStrong: Color(0x59000000),
    text: Color(0xFF000000),
    muted: Color(0xFF2E2E36),
    subtle: Color(0xFF55555F),
    glass: Color(0xF5FFFFFF),
    scrim: Color(0x80000000),
  );

  static TxPalette resolve(Brightness brightness, {bool highContrast = false}) => brightness == Brightness.dark
      ? (highContrast ? darkContrast : dark)
      : (highContrast ? lightContrast : light);
}

/// Sistema visual de TREVIX (mismos tokens que la web: assets/css/tokens.css).
///
/// Las superficies y los textos dependen del modo activo ([use]); los colores de marca son fijos.
class Tx {
  Tx._();

  static TxPalette _p = TxPalette.dark;

  static TxPalette get palette => _p;
  static bool get isDark => _p.isDark;

  /// Cambia la paleta activa. Quien la cambie debe reconstruir la app (lo hace [Appearance]).
  static void use(TxPalette p) => _p = p;

  static Color get bg => _p.bg;
  static Color get surface1 => _p.surface1;
  static Color get surface2 => _p.surface2;
  static Color get surface3 => _p.surface3;
  static Color get surface4 => _p.surface4;
  static Color get border => _p.border;
  static Color get borderStrong => _p.borderStrong;
  static Color get text => _p.text;
  static Color get muted => _p.muted;
  static Color get subtle => _p.subtle;
  static Color get glass => _p.glass;
  static Color get scrim => _p.scrim;

  static const purple = Color(0xFF7C3AED);
  static const purple300 = Color(0xFFC4B5FD);
  static const purple400 = Color(0xFFA78BFA);
  static const purple500 = Color(0xFF8B5CF6);
  static const purple700 = Color(0xFF6D28D9);
  static const blue = Color(0xFF2563EB);
  static const blue400 = Color(0xFF60A5FA);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFDB2777);

  /// Morado legible sobre el fondo activo (el claro de la marca se pierde sobre blanco).
  static Color get accent => _p.isDark ? purple300 : purple700;
  static Color get accentSoft => _p.isDark ? purple400 : purple;

  static const danger = Color(0xFFF43F5E);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const like = danger;

  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple500, purple, blue],
    stops: [0, .45, 1],
  );

  static const _brandTextDark = LinearGradient(colors: [purple300, purple400, blue400]);
  static const _brandTextLight = LinearGradient(colors: [purple, purple700, blue]);

  static LinearGradient get brandText => _p.isDark ? _brandTextDark : _brandTextLight;

  static const ring = SweepGradient(
    startAngle: 0,
    endAngle: 6.2832,
    colors: [purple500, blue, cyan, Color(0xFFA855F7), purple500],
  );

  static const brandSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x297C3AED), Color(0x292563EB)],
  );

  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 20.0;
  static const radiusXl = 28.0;

  static Color alpha(Color c, double opacity) => c.withAlpha((opacity * 255).round().clamp(0, 255));

  static TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color? color, double? height}) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color ?? text, letterSpacing: -0.4, height: height);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color ?? text, height: height);

  /// Barras del sistema transparentes con iconos según el fondo activo. Los estilos predefinidos de Flutter pintan
  /// de negro la barra de navegación de Android (antes de Android 15), incluso en el tema claro.
  static SystemUiOverlayStyle get overlay => _p.isDark ? immersive : _lightBars;

  /// Pantallas oscuras a pantalla completa (historias, reels, visores): iconos claros en ambas barras.
  static const immersive = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  static const _lightBars = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  /// Fondos de las historias de texto (mismos que la web).
  static Gradient storyBackground(String? key) {
    switch (key) {
      case 'blue':
        return const LinearGradient(
            begin: Alignment(-0.4, -1), end: Alignment(0.4, 1), colors: [Color(0xFF1D4ED8), Color(0xFF0EA5E9), Color(0xFF7C3AED)], stops: [0, .6, 1]);
      case 'midnight':
        return const RadialGradient(center: Alignment(-0.4, -0.6), radius: 1.2, colors: [Color(0xFF4C1D95), Color(0xFF09090B)], stops: [0, .7]);
      case 'sunset':
        return const LinearGradient(
            begin: Alignment(-0.4, -1), end: Alignment(0.4, 1), colors: [Color(0xFFDB2777), Color(0xFF7C3AED)], stops: [0, .7]);
      case 'ocean':
        return const LinearGradient(begin: Alignment(-0.4, -1), end: Alignment(0.4, 1), colors: [Color(0xFF0EA5E9), Color(0xFF0F766E)]);
      case 'graphite':
        return const LinearGradient(begin: Alignment(-0.4, -1), end: Alignment(0.4, 1), colors: [Color(0xFF3F3F46), Color(0xFF09090B)]);
      case 'violet':
      default:
        return const LinearGradient(begin: Alignment(-0.4, -1), end: Alignment(0.4, 1), colors: [Color(0xFF6D28D9), Color(0xFF2563EB)]);
    }
  }

  static ThemeData theme({bool reduceMotion = false}) {
    final dark = _p.isDark;
    final base = ThemeData(brightness: _p.brightness, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: text, displayColor: text);
    final scheme = dark
        ? ColorScheme.dark(
            primary: purple500,
            onPrimary: Colors.white,
            secondary: blue,
            onSecondary: Colors.white,
            surface: surface2,
            onSurface: text,
            error: danger,
            onError: Colors.white,
          )
        : ColorScheme.light(
            primary: purple,
            onPrimary: Colors.white,
            secondary: blue,
            onSecondary: Colors.white,
            surface: surface2,
            onSurface: text,
            error: danger,
            onError: Colors.white,
          );
    const transitions = PageTransitionsTheme(builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
    });
    const still = PageTransitionsTheme(builders: {
      TargetPlatform.iOS: _NoTransitionsBuilder(),
      TargetPlatform.android: _NoTransitionsBuilder(),
    });
    return base.copyWith(
      // Mismo comportamiento en Android que en iPhone: rebote al desplazar, volver deslizando desde el borde,
      // selección de texto y controles con el estilo de iOS.
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: scheme,
      textTheme: textTheme,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      cupertinoOverrideTheme: CupertinoThemeData(brightness: _p.brightness, primaryColor: dark ? purple400 : purple),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: dark ? purple400 : purple,
        selectionColor: const Color(0x668B5CF6),
        selectionHandleColor: dark ? purple400 : purple,
      ),
      pageTransitionsTheme: reduceMotion ? still : transitions,
    );
  }
}

/// Paleta oscura fija para las pantallas que siempre van sobre negro (historias, visores, bienvenida, Reels).
class TxDark {
  TxDark._();

  static const bg = Color(0xFF09090B);
  static const surface1 = Color(0xFF0F0F12);
  static const surface2 = Color(0xFF18181B);
  static const surface3 = Color(0xFF202024);
  static const surface4 = Color(0xFF27272A);
  static const border = Color(0x12FFFFFF);
  static const borderStrong = Color(0x1FFFFFFF);
  static const text = Color(0xFFFAFAFA);
  static const muted = Color(0xFFA1A1AA);
  static const subtle = Color(0xFF71717A);

  static TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color color = text, double? height}) =>
      Tx.display(size, weight: weight, color: color, height: height);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color color = text, double? height}) =>
      Tx.body(size, weight: weight, color: color, height: height);

  /// Tema oscuro para una pantalla que va sobre negro aunque la app esté en modo claro (campos, chips, deslizadores).
  static Widget scope(BuildContext context, Widget child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(brightness: Brightness.dark, surface: surface2, onSurface: text),
        scaffoldBackgroundColor: Colors.black,
        canvasColor: surface2,
        textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
        cupertinoOverrideTheme: const CupertinoThemeData(brightness: Brightness.dark),
      ),
      child: CupertinoTheme(data: const CupertinoThemeData(brightness: Brightness.dark), child: child),
    );
  }
}

/// «Reducir movimiento»: como en iOS, las pantallas aparecen con un fundido en vez de deslizarse.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      FadeTransition(opacity: animation, child: child);
}
