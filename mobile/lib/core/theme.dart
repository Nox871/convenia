import 'package:flutter/material.dart';

/// Design tokens de Convenia. Fuente de verdad: especificación visual del
/// producto. No introducir colores/tamaños fuera de esta paleta.
class AppColors {
  AppColors._();

  static const brandDark = Color(0xFF0F172A);
  static const slate800 = Color(0xFF1E293B);
  static const slate600 = Color(0xFF475569);
  static const slate400 = Color(0xFF94A3B8);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate50 = Color(0xFFF8FAFC);
  static const white = Color(0xFFFFFFFF);

  static const bestPriceGreen = Color(0xFF059669);
  static const bestPriceDark = Color(0xFF047857);
  static const bestPriceSurface = Color(0xFFECFDF5);
  static const bestPriceBorder = Color(0xFFA7F3D0);

  static const d1 = Color(0xFFDC2626);
  static const exito = Color(0xFFFBBF24);

  static const error = Color(0xFFF43F5E);
  static const errorSurface = Color(0xFFFFF1F2);

  /// Color de marca por código de supermercado (para badges/acentos).
  static Color forSupermarket(String code) {
    switch (code.toUpperCase()) {
      case 'D1':
        return d1;
      case 'EXITO':
        return exito;
      default:
        return slate600;
    }
  }
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

class AppText {
  AppText._();

  static const _fontFamily = 'Roboto';

  static const hero = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.brandDark,
    height: 1.25,
  );

  static const screenTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.brandDark,
  );

  static const sectionTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.brandDark,
  );

  static const productName = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.brandDark,
  );

  static const priceMain = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    color: AppColors.brandDark,
  );

  static const priceCard = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.brandDark,
  );

  static const body = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.slate600,
  );

  static const caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.slate400,
  );
}

ThemeData buildConveniaTheme() {
  final base = ThemeData(useMaterial3: true, fontFamily: 'Roboto');
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.slate50,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.brandDark,
      secondary: AppColors.bestPriceGreen,
      error: AppColors.error,
      surface: AppColors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.white,
      foregroundColor: AppColors.brandDark,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandDark,
        foregroundColor: AppColors.white,
        minimumSize: const Size.fromHeight(AppSpacing.buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.slate100),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.slate100),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        borderSide: const BorderSide(color: AppColors.brandDark, width: 1.5),
      ),
    ),
  );
}
