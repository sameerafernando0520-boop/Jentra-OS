import 'package:flutter/material.dart';

abstract final class AppTheme {
  // Brand Colors
  static const primaryNavy = Color(0xFF081A4B);
  static const secondaryNavy = Color(0xFF113A8F);
  static const accentBlue = Color(0xFF2F6DFF);
  static const gradientStart = Color(0xFF14C6C7);
  static const gradientEnd = Color(0xFF33E1B3);

  // Semantic Colors
  static const success = Color(0xFF00C48C);
  static const warning = Color(0xFFF6A609);
  static const danger = Color(0xFFE5484D);

  // Light Palette
  static const backgroundLight = Color(0xFFF8FAFC);
  static const cardLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE2E8F0);
  static const textPrimaryLight = Color(0xFF081A4B);
  static const textSecondaryLight = Color(0xFF64748B);

  // Dark Palette
  static const backgroundDark = Color(0xFF0B0F19);
  static const cardDark = Color(0xFF111827);
  static const borderDark = Color(0xFF1F2937);
  static const textPrimaryDark = Color(0xFFF8FAFC);
  static const textSecondaryDark = Color(0xFF94A3B8);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? backgroundDark : backgroundLight;
    final cardBg = isDark ? cardDark : cardLight;
    final border = isDark ? borderDark : borderLight;
    final textPrimary = isDark ? textPrimaryDark : textPrimaryLight;
    final textSecondary = isDark ? textSecondaryDark : textSecondaryLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: isDark ? accentBlue : primaryNavy,
      onPrimary: Colors.white,
      secondary: secondaryNavy,
      onSecondary: Colors.white,
      tertiary: gradientStart,
      onTertiary: primaryNavy,
      error: danger,
      onError: Colors.white,
      surface: cardBg,
      onSurface: textPrimary,
      surfaceContainerLow: isDark ? const Color(0xFF161E2E) : cardLight,
      surfaceContainerLowest: isDark ? const Color(0xFF0F172A) : Colors.white,
      outline: border,
      outlineVariant: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Manrope',
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: bg,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardBg,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: textSecondary, fontSize: 14),
        labelStyle: TextStyle(color: textSecondary, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: accentBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          backgroundColor: isDark ? accentBlue : primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          foregroundColor: textPrimary,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          textStyle: const TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        elevation: 0,
        indicatorColor: isDark
            ? accentBlue.withValues(alpha: 0.2)
            : secondaryNavy.withValues(alpha: 0.1),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: isDark ? gradientStart : secondaryNavy);
          }
          return IconThemeData(color: textSecondary);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isDark ? Colors.white : primaryNavy,
            );
          }
          return TextStyle(
            fontFamily: 'Manrope',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: textSecondary,
          );
        }),
      ),
    );
  }
}
