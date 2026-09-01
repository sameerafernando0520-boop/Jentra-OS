import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadTestFonts);

  testWidgets('bundled typefaces render in the test engine', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: Key('typeface-probe'),
              child: SizedBox(
                width: 520,
                height: 132,
                child: ColoredBox(
                  color: Colors.white,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IBM Plex Sans · Jentra operating system',
                          style: TextStyle(
                            fontFamily: JentraTypography.sansFamily,
                          ),
                        ),
                        Text(
                          'IBM Plex Mono 500 · INV-2026-01084',
                          style: TextStyle(
                            fontFamily: JentraTypography.monoFamily,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'LKR 12.84M · 123,456.789000',
                          style: TextStyle(
                            fontFamily: JentraTypography.monoFamily,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          'ව්‍යාපාර පාලනය · வணிக மேலாண்மை',
                          style: TextStyle(
                            fontFamily: JentraTypography.sansFamily,
                            fontFamilyFallback:
                                JentraTypography.fallbackFamilies,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byKey(const Key('typeface-probe')),
      matchesGoldenFile('goldens/typeface_probe.png'),
    );
  });

  testWidgets('foundation shell exposes routes and command palette — AC-6', (
    tester,
  ) async {
    await _pumpJentra(
      tester,
      size: const Size(1440, 900),
      preferences: const AppPreferences(
        themeMode: ThemeMode.light,
        density: JentraDensity.comfortable,
      ),
    );

    expect(find.text('Good morning, Shehan'), findsOneWidget);
    expect(find.text('Command centre'), findsWidgets);
    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Preview metrics'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Search modules, records, or commands…'), findsOneWidget);
    expect(find.text('Permission-aware'), findsOneWidget);
  });

  for (final scenario
      in <({String name, Size size, ThemeMode theme, JentraDensity density})>[
        (
          name: '1024_light_compact',
          size: const Size(1024, 720),
          theme: ThemeMode.light,
          density: JentraDensity.compact,
        ),
        (
          name: '1024_dark_comfortable',
          size: const Size(1024, 720),
          theme: ThemeMode.dark,
          density: JentraDensity.comfortable,
        ),
        (
          name: '1440_light_comfortable',
          size: const Size(1440, 900),
          theme: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
        (
          name: '1440_dark_compact',
          size: const Size(1440, 900),
          theme: ThemeMode.dark,
          density: JentraDensity.compact,
        ),
        (
          name: '1920_light_comfortable',
          size: const Size(1920, 1080),
          theme: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
        (
          name: '1920_dark_comfortable',
          size: const Size(1920, 1080),
          theme: ThemeMode.dark,
          density: JentraDensity.comfortable,
        ),
      ]) {
    testWidgets('dashboard golden ${scenario.name} — AC-1 / AC-7', (
      tester,
    ) async {
      await _pumpJentra(
        tester,
        size: scenario.size,
        preferences: AppPreferences(
          themeMode: scenario.theme,
          density: scenario.density,
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JentraApp)),
      );
      expect(
        container.read(appPreferencesProvider).requireValue.themeMode,
        scenario.theme,
      );
      final renderedTheme = Theme.of(
        tester.element(find.byType(Scaffold).first),
      );
      expect(
        renderedTheme.brightness,
        scenario.theme == ThemeMode.dark ? Brightness.dark : Brightness.light,
      );

      await expectLater(
        find.byType(JentraApp),
        matchesGoldenFile('goldens/dashboard_${scenario.name}.png'),
      );
    });
  }
}

Future<void> _loadTestFonts() async {
  const fontRoot = 'packages/jentra_design_system/assets/fonts';
  final sans = FontLoader(JentraTypography.sansFamily)
    ..addFont(rootBundle.load('$fontRoot/IBMPlexSans-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/IBMPlexSans-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/IBMPlexSans-SemiBold.ttf'));
  final mono = FontLoader(JentraTypography.monoFamily)
    ..addFont(rootBundle.load('$fontRoot/IBMPlexMono-Regular.ttf'));
  final sinhala = FontLoader(JentraTypography.fallbackFamilies.first)
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansSinhala-SemiBold.ttf'));
  final tamil = FontLoader(JentraTypography.fallbackFamilies.last)
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-Regular.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-Medium.ttf'))
    ..addFont(rootBundle.load('$fontRoot/NotoSansTamil-SemiBold.ttf'));
  final materialIcons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await sans.load();
  await mono.load();
  await sinhala.load();
  await tamil.load();
  await materialIcons.load();
}

Future<void> _pumpJentra(
  WidgetTester tester, {
  required Size size,
  required AppPreferences preferences,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          const RuntimeConfig(
            environment: 'development',
            supabaseUrl: '',
            supabasePublishableKey: '',
          ),
        ),
        foundationGatewayProvider.overrideWithValue(null),
        appPreferencesProvider.overrideWithBuild(
          (ref, notifier) async => preferences,
        ),
        tenantListProvider.overrideWithBuild(
          (ref, notifier) async => const [
            TenantSummary(
              id: 'preview-tenant',
              name: 'Jentra Holdings',
              slug: 'jentra-holdings',
              status: 'active',
              membershipStatus: 'active',
            ),
          ],
        ),
      ],
      child: const JentraApp(),
    ),
  );
  await tester.pumpAndSettle();
}
