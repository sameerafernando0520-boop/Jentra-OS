import 'package:flutter/material.dart';

abstract final class JentraColors {
  static const navy950 = Color(0xFF071426);
  static const navy900 = Color(0xFF0B1F3A);
  static const navy800 = Color(0xFF12345B);
  static const navy700 = Color(0xFF1B4B7A);

  static const green700 = Color(0xFF08663F);
  static const green600 = Color(0xFF0B7A4B);
  static const green500 = Color(0xFF12965B);
  static const green400 = Color(0xFF22B573);

  static const appBackground = Color(0xFFF5F7FA);
  static const panel = Color(0xFFFFFFFF);
  static const border = Color(0xFFD7E0E8);
  static const textPrimary = Color(0xFF15202B);
  static const textSecondary = Color(0xFF5B6978);

  static const info = Color(0xFF2563EB);
  static const infoSurface = Color(0xFFEFF6FF);
  static const warning = Color(0xFFB45309);
  static const warningSurface = Color(0xFFFFF7ED);
  static const danger = Color(0xFFB42318);
  static const dangerSurface = Color(0xFFFFF1F0);
  static const success = green700;
  static const successSurface = Color(0xFFECFDF3);

  static const darkPanel = Color(0xFF0E253F);
  static const darkPanelElevated = Color(0xFF14304F);
  static const darkBorder = Color(0xFF294663);
  static const darkTextPrimary = Color(0xFFF4F7FA);
  static const darkTextSecondary = Color(0xFFB8C7D6);
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
  static const control = 6.0;
  static const card = 10.0;
  static const dialog = 14.0;
}

abstract final class JentraMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const deliberate = Duration(milliseconds: 240);
}

abstract final class JentraTypography {
  static const sansFamily = 'packages/jentra_design_system/IBM Plex Sans';
  static const monoFamily = 'packages/jentra_design_system/IBM Plex Mono';
  static const fallbackFamilies = <String>[
    'packages/jentra_design_system/Noto Sans Sinhala',
    'packages/jentra_design_system/Noto Sans Tamil',
  ];
}

enum JentraDensity {
  compact(rowHeight: 32, controlHeight: 34),
  comfortable(rowHeight: 40, controlHeight: 40);

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
    );
  }
}

extension JentraThemeContext on BuildContext {
  JentraSemanticColors get jentraColors =>
      Theme.of(this).extension<JentraSemanticColors>()!;
}
