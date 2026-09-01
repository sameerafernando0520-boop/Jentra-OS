import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class JentraTheme {
  static ThemeData light({JentraDensity density = JentraDensity.comfortable}) =>
      _create(Brightness.light, density);

  static ThemeData dark({JentraDensity density = JentraDensity.comfortable}) =>
      _create(Brightness.dark, density);

  static ThemeData _create(Brightness brightness, JentraDensity density) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? JentraColors.navy950
        : JentraColors.appBackground;
    final panel = isDark ? JentraColors.darkPanel : JentraColors.panel;
    final border = isDark ? JentraColors.darkBorder : JentraColors.border;
    final foreground = isDark
        ? JentraColors.darkTextPrimary
        : JentraColors.textPrimary;
    final secondary = isDark
        ? JentraColors.darkTextSecondary
        : JentraColors.textSecondary;
    final scheme = ColorScheme.fromSeed(
      seedColor: JentraColors.green600,
      brightness: brightness,
      primary: isDark ? JentraColors.green400 : JentraColors.green700,
      surface: panel,
      error: JentraColors.danger,
    );

    final typography = Typography.material2021().black.apply(
      fontFamily: 'IBM Plex Sans',
      package: 'jentra_design_system',
      fontFamilyFallback: JentraTypography.fallbackFamilies,
      bodyColor: foreground,
      displayColor: foreground,
    );
    final textTheme = typography.copyWith(
      headlineLarge: typography.headlineLarge?.copyWith(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineMedium: typography.headlineMedium?.copyWith(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: typography.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: typography.titleMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: typography.bodyLarge?.copyWith(fontSize: 14, height: 1.45),
      bodyMedium: typography.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
      labelLarge: typography.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: typography.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: JentraTypography.sansFamily,
      textTheme: textTheme,
      dividerColor: border,
      focusColor: JentraColors.green400.withValues(alpha: 0.28),
      splashFactory: NoSplash.splashFactory,
      visualDensity: density == JentraDensity.compact
          ? const VisualDensity(horizontal: -1, vertical: -2)
          : VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[
        JentraSemanticColors(
          panel: panel,
          panelElevated: isDark
              ? JentraColors.darkPanelElevated
              : JentraColors.panel,
          border: border,
          textPrimary: foreground,
          textSecondary: secondary,
          navigation: JentraColors.navy900,
          navigationActive: JentraColors.navy800,
          successSurface: isDark
              ? JentraColors.green700.withValues(alpha: 0.25)
              : JentraColors.successSurface,
          warningSurface: isDark
              ? JentraColors.warning.withValues(alpha: 0.22)
              : JentraColors.warningSurface,
          dangerSurface: isDark
              ? JentraColors.danger.withValues(alpha: 0.22)
              : JentraColors.dangerSurface,
          infoSurface: isDark
              ? JentraColors.info.withValues(alpha: 0.20)
              : JentraColors.infoSurface,
        ),
      ],
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JentraRadii.card),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JentraRadii.dialog),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JentraSpacing.x3,
          vertical: JentraSpacing.x3,
        ),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(JentraColors.green500, width: 2),
        errorBorder: _inputBorder(JentraColors.danger),
        focusedErrorBorder: _inputBorder(JentraColors.danger, width: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(0, density.controlHeight),
          backgroundColor: JentraColors.green700,
          foregroundColor: Colors.white,
          disabledBackgroundColor: border,
          disabledForegroundColor: secondary,
          padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(0, density.controlHeight),
          foregroundColor: foreground,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: JentraColors.navy900,
          borderRadius: BorderRadius.circular(JentraRadii.control),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(JentraRadii.control),
        borderSide: BorderSide(color: color, width: width),
      );
}
