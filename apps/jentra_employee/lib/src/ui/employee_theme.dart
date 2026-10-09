import 'package:flutter/material.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

ThemeData employeeTheme(Brightness brightness) {
  final base = brightness == Brightness.dark
      ? JentraTheme.dark()
      : JentraTheme.light();
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontSize: 30,
      height: 1.2,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontSize: 26,
      height: 1.25,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, height: 1.35),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontSize: 17,
      height: 1.4,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
    bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 13, height: 1.45),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 16, height: 1.35),
    labelMedium: base.textTheme.labelMedium?.copyWith(
      fontSize: 14,
      height: 1.4,
    ),
  );
  return base.copyWith(
    textTheme: text,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    chipTheme: base.chipTheme.copyWith(
      showCheckmark: false,
      selectedColor: base.colorScheme.primary.withValues(alpha: .12),
      backgroundColor: base.colorScheme.surface,
      labelStyle: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(color: base.colorScheme.outline.withValues(alpha: .6)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: base.scaffoldBackgroundColor,
      foregroundColor: base.colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleTextStyle: text.titleMedium,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: base.colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: base.colorScheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: text.labelLarge,
      ),
    ),
  );
}
