import 'package:flutter/material.dart';

import 'i18n.dart';

/// Temas de color de marca (Ajustes › Apariencia). El predeterminado es TREVIX.
enum BrandTheme {
  trevix,
  ocean,
  sunset,
  forest,
  ember;

  String get label => switch (this) {
        BrandTheme.trevix => 'TREVIX',
        BrandTheme.ocean => tr('Océano'),
        BrandTheme.sunset => tr('Atardecer'),
        BrandTheme.forest => tr('Bosque'),
        BrandTheme.ember => tr('Ember'),
      };

  BrandColors get colors => switch (this) {
        BrandTheme.trevix => BrandColors.trevix,
        BrandTheme.ocean => BrandColors.ocean,
        BrandTheme.sunset => BrandColors.sunset,
        BrandTheme.forest => BrandColors.forest,
        BrandTheme.ember => BrandColors.ember,
      };
}

/// Tokens de marca que cambian con el tema elegido (claro/oscuro aparte).
class BrandColors {
  const BrandColors({
    required this.core,
    required this.soft,
    required this.strong,
    required this.mid,
    required this.secondary,
    required this.secondarySoft,
    required this.tertiary,
  });

  final Color core;
  final Color soft;
  final Color strong;
  final Color mid;
  final Color secondary;
  final Color secondarySoft;
  final Color tertiary;

  static const trevix = BrandColors(
    core: Color(0xFF7C3AED),
    soft: Color(0xFFC4B5FD),
    strong: Color(0xFF6D28D9),
    mid: Color(0xFF8B5CF6),
    secondary: Color(0xFF2563EB),
    secondarySoft: Color(0xFF60A5FA),
    tertiary: Color(0xFF22D3EE),
  );

  static const ocean = BrandColors(
    core: Color(0xFF0284C7),
    soft: Color(0xFF7DD3FC),
    strong: Color(0xFF0369A1),
    mid: Color(0xFF0EA5E9),
    secondary: Color(0xFF0D9488),
    secondarySoft: Color(0xFF2DD4BF),
    tertiary: Color(0xFF67E8F9),
  );

  static const sunset = BrandColors(
    core: Color(0xFFDB2777),
    soft: Color(0xFFF9A8D4),
    strong: Color(0xFFBE185D),
    mid: Color(0xFFEC4899),
    secondary: Color(0xFFEA580C),
    secondarySoft: Color(0xFFFB923C),
    tertiary: Color(0xFFFBBF24),
  );

  static const forest = BrandColors(
    core: Color(0xFF059669),
    soft: Color(0xFF6EE7B7),
    strong: Color(0xFF047857),
    mid: Color(0xFF10B981),
    secondary: Color(0xFF0F766E),
    secondarySoft: Color(0xFF2DD4BF),
    tertiary: Color(0xFF84CC16),
  );

  static const ember = BrandColors(
    core: Color(0xFFDC2626),
    soft: Color(0xFFFCA5A5),
    strong: Color(0xFFB91C1C),
    mid: Color(0xFFEF4444),
    secondary: Color(0xFFEA580C),
    secondarySoft: Color(0xFFFB923C),
    tertiary: Color(0xFFF59E0B),
  );
}
