import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

void main() {
  testWidgets('status communicates meaning with icon and semantics — NFR-7', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: const Scaffold(
            body: JentraStatusBadge(
              label: 'Approved',
              tone: JentraStatusTone.success,
            ),
          ),
        ),
      );

      expect(find.text('Approved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.bySemanticsLabel('Status: Approved'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  test('density tokens match approved row heights — FR-7', () {
    expect(JentraDensity.compact.rowHeight, 32);
    expect(JentraDensity.comfortable.rowHeight, 40);
  });

  test('qualified font families are never package-prefixed twice', () {
    final body = JentraTheme.light().textTheme.bodyMedium!;
    expect(body.fontFamily, JentraTypography.sansFamily);
    expect(
      body.copyWith(fontFamily: JentraTypography.monoFamily).fontFamily,
      JentraTypography.monoFamily,
    );
    expect(body.fontFamilyFallback, JentraTypography.fallbackFamilies);
  });

  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light
        ? JentraTheme.light()
        : JentraTheme.dark();
    final colors = theme.extension<JentraSemanticColors>()!;

    test('$brightness text and status pairs meet WCAG AA contrast', () {
      for (final surface in [
        theme.scaffoldBackgroundColor,
        colors.panel,
        colors.panelElevated,
      ]) {
        expect(
          _contrast(colors.textPrimary, surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(colors.textSecondary, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      for (final pair in [
        (colors.success, colors.successSurface),
        (colors.warning, colors.warningSurface),
        (colors.danger, colors.dangerSurface),
        (colors.info, colors.infoSurface),
        (colors.textSecondary, colors.neutralSurface),
      ]) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });

    test('$brightness action labels and control boundaries are distinct', () {
      final button = theme.filledButtonTheme.style!;
      for (final states in [
        <WidgetState>{},
        {WidgetState.hovered},
        {WidgetState.focused},
      ]) {
        final background = button.backgroundColor!.resolve(states)!;
        final foreground = button.foregroundColor!.resolve(states)!;
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
      for (final background in [colors.panel, theme.scaffoldBackgroundColor]) {
        expect(
          _contrast(colors.borderStrong, background),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(colors.focusRing, background),
          greaterThanOrEqualTo(3),
        );
      }
    });
  }

  testWidgets('loading action announces progress and prevents duplicate work', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(
            body: JentraPrimaryButton(
              label: 'Create quotation',
              loading: true,
              onPressed: () => calls++,
            ),
          ),
        ),
      );
      await tester.tap(find.byType(FilledButton));
      expect(calls, 0);
      expect(find.text('Create quotation'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Create quotation, in progress'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('supplied logo loads and fits a narrow scaled sidebar', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.dark(),
          home: const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 160,
                  height: 88,
                  child: JentraBrandLockup(
                    size: 40,
                    inverse: true,
                    showTagline: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Jentra OS. Operate. Connect. Grow.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.byType(JentraBrandWordmark), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('panels provide a Material surface for interactive rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: Scaffold(
          body: JentraPanel(
            child: SwitchListTile(
              title: const Text('Compact density'),
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}
