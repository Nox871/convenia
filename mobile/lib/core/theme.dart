import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens de Convenia. Fuente de verdad: identidad visual de marca.
/// No introducir colores fuera de esta paleta -- en particular, nunca un
/// color propio por supermercado: la marca de cada tienda se comunica con su
/// NOMBRE (ver `widgets/supermarket_badge.dart`), nunca con un color
/// distintivo, para que los 5 (o N) supermercados se sientan igual de
/// neutrales entre sí.
///
/// Todos los tokens son `const Color` (literales, no `.withValues()` en
/// runtime) para poder usarse en constructores `const` en toda la app.
class AppColors {
  AppColors._();

  static const brandIndigo = Color(0xFF5B4FE9);
  static const ink = Color(0xFF17171C);
  static const softIvory = Color(0xFFF7F5EF);
  static const white = Color(0xFFFFFFFF);
  static const lavenderMist = Color(0xFFECEAFF);

  static const success = Color(0xFF16805C);
  static const warning = Color(0xFFB7791F);
  static const error = Color(0xFFC94A4A);

  // Jerarquía de texto/bordes derivada de Ink (no son colores de marca
  // nuevos, sólo la misma tinta a distinta intensidad, precalculada como
  // constante para poder usarse en widgets `const`).
  static const inkMuted = Color(0xFF5B5B63);
  static const inkFaint = Color(0xFF9A9AA2);
  static const mist = Color(0xFFF1F0F5); // superficie/borde neutro claro

  // Superficies semánticas (ahorro/advertencia/error) -- regla 80/15/5:
  // softIvory/white dominan fondos, brandIndigo es la acción principal,
  // success/warning/error son sólo estado, nunca decoración.
  static const successSurface = Color(0xFFE3F3EC);
  static const successBorder = Color(0xFFB9E0CD);
  static const warningSurface = Color(0xFFFBF0DD);
  static const errorSurface = Color(0xFFF7E7E7);
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  static const horizontalPage = 16.0;
  static const cardRadius = 16.0;
  static const buttonRadius = 12.0;
  static const chipRadius = 9999.0;
  static const searchBarHeight = 56.0;
  static const buttonHeight = 48.0;
}

/// Manrope para títulos/precios/elementos de marca; Inter para cuerpo,
/// datos y metadatos -- nunca al revés.
class AppText {
  AppText._();

  static final hero = GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.25,
  );

  static final screenTitle = GoogleFonts.manrope(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static final sectionTitle = GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static final productName = GoogleFonts.manrope(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
  );

  static final priceMain = GoogleFonts.manrope(
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
  );

  static final priceCard = GoogleFonts.manrope(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );

  static final body = GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.inkMuted,
  );

  static final caption = GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.inkFaint,
  );
}

ThemeData buildConveniaTheme() {
  final base = ThemeData(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.softIvory,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.brandIndigo,
      secondary: AppColors.brandIndigo,
      error: AppColors.error,
      surface: AppColors.white,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.softIvory,
      foregroundColor: AppColors.ink,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppText.screenTitle,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandIndigo,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.lavenderMist,
      labelTextStyle: WidgetStateProperty.all(
        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.ink),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.mist),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.mist),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
      ),
    ),
  );
}
