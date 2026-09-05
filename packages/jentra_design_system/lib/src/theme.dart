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
    final action = isDark ? JentraColors.blue400 : JentraColors.actionBlue;
    final actionHover = isDark ? const Color(0xFF91CAFF) : JentraColors.blue700;
    final onAction = isDark ? JentraColors.navy950 : Colors.white;
    final strongBorder = isDark
        ? JentraColors.darkBorderStrong
        : JentraColors.borderStrong;
    final semantic = JentraSemanticColors(
      panel: panel,
      panelElevated: isDark
          ? JentraColors.darkPanelElevated
          : JentraColors.panel,
      border: border,
      borderStrong: strongBorder,
      textPrimary: foreground,
      textSecondary: secondary,
      navigation: JentraColors.navy900,
      navigationActive: JentraColors.navy800,
      action: action,
      actionHover: actionHover,
      focusRing: action,
      success: isDark ? const Color(0xFF95E4C4) : JentraColors.success,
      successSurface: isDark
          ? const Color(0xFF12392F)
          : JentraColors.successSurface,
      warning: isDark ? const Color(0xFFFFD58A) : JentraColors.warning,
      warningSurface: isDark
          ? const Color(0xFF3C2D15)
          : JentraColors.warningSurface,
      danger: isDark ? const Color(0xFFFFB4AE) : JentraColors.danger,
      dangerSurface: isDark
          ? const Color(0xFF41282D)
          : JentraColors.dangerSurface,
      info: isDark ? const Color(0xFFA4D1FF) : JentraColors.info,
      infoSurface: isDark ? const Color(0xFF173650) : JentraColors.infoSurface,
      neutralSurface: isDark
          ? JentraColors.darkPanelElevated
          : JentraColors.neutralSurface,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: JentraColors.actionBlue,
      brightness: brightness,
      primary: action,
      onPrimary: onAction,
      primaryContainer: semantic.infoSurface,
      onPrimaryContainer: semantic.info,
      secondary: semantic.success,
      onSecondary: isDark ? JentraColors.navy950 : Colors.white,
      secondaryContainer: semantic.successSurface,
      onSecondaryContainer: semantic.success,
      tertiary: semantic.warning,
      onTertiary: isDark ? JentraColors.navy950 : Colors.white,
      surface: panel,
      onSurface: foreground,
      onSurfaceVariant: secondary,
      surfaceContainerLowest: background,
      surfaceContainerLow: panel,
      surfaceContainer: semantic.neutralSurface,
      surfaceContainerHigh: semantic.panelElevated,
      surfaceContainerHighest: semantic.panelElevated,
      surfaceTint: Colors.transparent,
      outline: strongBorder,
      outlineVariant: border,
      error: semantic.danger,
      onError: isDark ? JentraColors.navy950 : Colors.white,
      errorContainer: semantic.dangerSurface,
      onErrorContainer: semantic.danger,
    );

    final typography = Typography.material2021().black.apply(
      fontFamily: JentraTypography.sansFamily,
      fontFamilyFallback: JentraTypography.fallbackFamilies,
      bodyColor: foreground,
      displayColor: foreground,
    );
    final textTheme = typography.copyWith(
      headlineLarge: typography.headlineLarge?.copyWith(
        fontSize: 32,
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
      bodySmall: typography.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.45,
        color: secondary,
      ),
      labelLarge: typography.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: typography.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelSmall: typography.labelSmall?.copyWith(
        fontSize: 11,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
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
      focusColor: action.withValues(alpha: 0.18),
      hoverColor: action.withValues(alpha: 0.06),
      splashFactory: NoSplash.splashFactory,
      visualDensity: density == JentraDensity.compact
          ? const VisualDensity(horizontal: -1, vertical: -2)
          : VisualDensity.standard,
      extensions: <ThemeExtension<dynamic>>[semantic],
      iconTheme: IconThemeData(color: secondary, size: 20),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JentraRadii.card),
          side: BorderSide(color: border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        elevation: 18,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JentraRadii.dialog),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: panel,
        isDense: true,
        hintStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        labelStyle: textTheme.bodyMedium?.copyWith(color: secondary),
        floatingLabelStyle: TextStyle(color: action),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JentraSpacing.x3,
          vertical: JentraSpacing.x3,
        ),
        border: _inputBorder(strongBorder),
        enabledBorder: _inputBorder(strongBorder),
        disabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(action, width: 2),
        errorBorder: _inputBorder(semantic.danger),
        focusedErrorBorder: _inputBorder(semantic.danger, width: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style:
            FilledButton.styleFrom(
              minimumSize: Size(0, density.controlHeight),
              backgroundColor: action,
              foregroundColor: onAction,
              disabledBackgroundColor: border,
              disabledForegroundColor: secondary,
              padding: const EdgeInsets.symmetric(horizontal: JentraSpacing.x4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JentraRadii.control),
              ),
              textStyle: textTheme.labelLarge,
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) return border;
                if (states.contains(WidgetState.hovered)) return actionHover;
                return action;
              }),
              side: WidgetStateProperty.resolveWith((states) {
                return states.contains(WidgetState.focused)
                    ? BorderSide(color: onAction, width: 2)
                    : BorderSide.none;
              }),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              minimumSize: Size(0, density.controlHeight),
              foregroundColor: foreground,
              side: BorderSide(color: strongBorder),
              textStyle: textTheme.labelLarge,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JentraRadii.control),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return BorderSide(color: border);
                }
                return BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? action
                      : strongBorder,
                  width: states.contains(WidgetState.focused) ? 2 : 1,
                );
              }),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: action,
          minimumSize: Size(0, density.controlHeight),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JentraRadii.control),
          ),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(semantic.neutralSurface),
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: secondary,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
        dataRowMinHeight: density.rowHeight,
        dataRowMaxHeight: density.rowHeight,
        headingRowHeight: 40,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: action),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      popupMenuTheme: PopupMenuThemeData(
        color: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(JentraRadii.card),
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
