import 'package:flutter/material.dart';

abstract final class JentraColors {
  static const navy950 = Color(0xFF041321);
  static const navy900 = Color(0xFF061B31);
  static const navy800 = Color(0xFF102F4C);
  static const navy700 = Color(0xFF214C70);
  static const brandNavy = navy900;
  static const blue700 = Color(0xFF0051B0);
  static const blue600 = Color(0xFF0064D9);
  static const blue400 = Color(0xFF68B7FF);
  static const actionBlue = blue600;
  static const cyan500 = Color(0xFF00B8D9);
  static const teal600 = Color(0xFF008C82);
  static const lime400 = Color(0xFF77E52D);

  // Retained for source compatibility. Product actions use actionBlue;
  // status components use the foreground/surface pairs in semantic colors.

  static const green700 = Color(0xFF08663F);
  static const green600 = Color(0xFF0B7A4B);
  static const green500 = Color(0xFF12965B);
  static const green400 = Color(0xFF22B573);

  static const appBackground = Color(0xFFF4F7FA);
  static const panel = Color(0xFFFFFFFF);
  static const border = Color(0xFFDCE5ED);
  static const borderStrong = Color(0xFF7C8D9E);
  static const textPrimary = Color(0xFF10283F);
  static const textSecondary = Color(0xFF5B6D7E);
  static const neutralSurface = Color(0xFFEEF2F6);

  static const info = Color(0xFF0757B2);
  static const infoSurface = Color(0xFFECF4FF);
  static const warning = Color(0xFF8A4A00);
  static const warningSurface = Color(0xFFFFF4DE);
  static const danger = Color(0xFFB42318);
  static const dangerSurface = Color(0xFFFFF1F0);
  static const success = Color(0xFF00695C);
  static const successSurface = Color(0xFFE7F6F0);

  static const darkPanel = Color(0xFF0B2238);
  static const darkPanelElevated = Color(0xFF122D45);
  static const darkBorder = Color(0xFF294158);
  static const darkBorderStrong = Color(0xFF71889D);
  static const darkTextPrimary = Color(0xFFF4F7FA);
  static const darkTextSecondary = Color(0xFFACBECE);

  /// Brand expression only: do not use this gradient behind operational text.
  static const brandGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [blue600, cyan500, teal600, lime400],
    stops: [0, 0.44, 0.72, 1],
  );
}

abstract final class JentraSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
  static const x10 = 40.0;
  static const x12 = 48.0;
}

abstract final class JentraRadii {
  static const control = 8.0;
  static const card = 14.0;
  static const dialog = 20.0;
}

abstract final class JentraMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const deliberate = Duration(milliseconds: 240);
}

abstract final class JentraTypography {
  static const sansFamily = 'packages/jentra_design_system/Manrope';
  static const monoFamily = 'packages/jentra_design_system/IBM Plex Mono';
  static const fallbackFamilies = <String>[
    'packages/jentra_design_system/Noto Sans Sinhala',
    'packages/jentra_design_system/Noto Sans Tamil',
  ];
}

enum JentraDensity {
  compact(rowHeight: 32, controlHeight: 36),
  comfortable(rowHeight: 40, controlHeight: 44);

  const JentraDensity({required this.rowHeight, required this.controlHeight});

  final double rowHeight;
  final double controlHeight;
}

@immutable
final class JentraSemanticColors extends ThemeExtension<JentraSemanticColors> {
  const JentraSemanticColors({
    required this.panel,
    required this.panelElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.navigation,
    required this.navigationActive,
    required this.successSurface,
    required this.warningSurface,
    required this.dangerSurface,
    required this.infoSurface,
    this.borderStrong = JentraColors.borderStrong,
    this.action = JentraColors.actionBlue,
    this.actionHover = JentraColors.blue700,
    this.focusRing = JentraColors.actionBlue,
    this.success = JentraColors.success,
    this.warning = JentraColors.warning,
    this.danger = JentraColors.danger,
    this.info = JentraColors.info,
    this.neutralSurface = JentraColors.neutralSurface,
  });

  final Color panel;
  final Color panelElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color navigation;
  final Color navigationActive;
  final Color successSurface;
  final Color warningSurface;
  final Color dangerSurface;
  final Color infoSurface;
  final Color borderStrong;
  final Color action;
  final Color actionHover;
  final Color focusRing;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutralSurface;

  @override
  JentraSemanticColors copyWith({
    Color? panel,
    Color? panelElevated,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? navigation,
    Color? navigationActive,
    Color? successSurface,
    Color? warningSurface,
    Color? dangerSurface,
    Color? infoSurface,
    Color? borderStrong,
    Color? action,
    Color? actionHover,
    Color? focusRing,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? neutralSurface,
  }) => JentraSemanticColors(
    panel: panel ?? this.panel,
    panelElevated: panelElevated ?? this.panelElevated,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    navigation: navigation ?? this.navigation,
    navigationActive: navigationActive ?? this.navigationActive,
    successSurface: successSurface ?? this.successSurface,
    warningSurface: warningSurface ?? this.warningSurface,
    dangerSurface: dangerSurface ?? this.dangerSurface,
    infoSurface: infoSurface ?? this.infoSurface,
    borderStrong: borderStrong ?? this.borderStrong,
    action: action ?? this.action,
    actionHover: actionHover ?? this.actionHover,
    focusRing: focusRing ?? this.focusRing,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
    neutralSurface: neutralSurface ?? this.neutralSurface,
  );

  @override
  JentraSemanticColors lerp(covariant JentraSemanticColors? other, double t) {
    if (other == null) return this;
    return JentraSemanticColors(
      panel: Color.lerp(panel, other.panel, t)!,
      panelElevated: Color.lerp(panelElevated, other.panelElevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      navigation: Color.lerp(navigation, other.navigation, t)!,
      navigationActive: Color.lerp(
        navigationActive,
        other.navigationActive,
        t,
      )!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      action: Color.lerp(action, other.action, t)!,
      actionHover: Color.lerp(actionHover, other.actionHover, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      neutralSurface: Color.lerp(neutralSurface, other.neutralSurface, t)!,
    );
  }
}

extension JentraThemeContext on BuildContext {
  JentraSemanticColors get jentraColors =>
      Theme.of(this).extension<JentraSemanticColors>()!;
}
