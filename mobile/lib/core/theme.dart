import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema visual de TREVIX (mismos tokens que la web: assets/css/tokens.css).
class Tx {
  Tx._();

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

  static const purple = Color(0xFF7C3AED);
  static const purple300 = Color(0xFFC4B5FD);
  static const purple400 = Color(0xFFA78BFA);
  static const purple500 = Color(0xFF8B5CF6);
  static const purple700 = Color(0xFF6D28D9);
  static const blue = Color(0xFF2563EB);
  static const blue400 = Color(0xFF60A5FA);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFDB2777);

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

  static const brandText = LinearGradient(colors: [purple300, purple400, blue400]);

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

  static TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color color = text, double? height}) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color, letterSpacing: -0.4, height: height);

  static TextStyle body(double size, {FontWeight weight = FontWeight.w400, Color color = text, double? height}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

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

  static ThemeData theme() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: text, displayColor: text);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: purple500,
        onPrimary: Colors.white,
        secondary: blue,
        onSecondary: Colors.white,
        surface: surface2,
        onSurface: text,
        error: danger,
        onError: Colors.white,
      ),
      textTheme: textTheme,
      dividerColor: border,
      splashFactory: InkSparkle.splashFactory,
      highlightColor: Colors.transparent,
      textSelectionTheme: const TextSelectionThemeData(cursorColor: purple400, selectionColor: Color(0x668B5CF6), selectionHandleColor: purple400),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
