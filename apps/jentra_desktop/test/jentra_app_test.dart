import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'package:jentra_desktop/src/app.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/setup/business_setup_controller.dart';
import 'package:jentra_desktop/src/router.dart';

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

  testWidgets(
    'Wave 2 Business Setup Centre is routed and actionable — AC-216',
    (tester) async {
      await _pumpJentra(
        tester,
        size: const Size(1440, 900),
        preferences: const AppPreferences(
          themeMode: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JentraApp)),
      );
      container.read(routerProvider).go('/setup');
      await tester.pumpAndSettle();

      expect(find.text('Business setup'), findsWidgets);
      expect(find.text('Finance'), findsWidgets);
      expect(find.text('Parties'), findsWidgets);
      expect(find.text('Catalogue'), findsWidgets);
      expect(find.text('Governance'), findsWidgets);
      expect(find.text('Files & data'), findsWidgets);
      expect(find.text('Reports'), findsWidgets);
      expect(find.text('Chart of accounts'), findsWidgets);
      expect(find.text('Create account'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('setup-search')), 'Cash');
      await tester.pumpAndSettle();
      expect(find.text('1000'), findsOneWidget);

      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('New account'), findsOneWidget);
      expect(find.byKey(const Key('setup-code-field')), findsOneWidget);
      expect(find.byKey(const Key('setup-name-field')), findsOneWidget);
      expect(find.text('Save draft'), findsOneWidget);
      expect(find.text('Save to server'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
    },
  );

  testWidgets(
    'Wave 2 renders every resource and configurable form — FR-201 through FR-240',
    (tester) async {
      await _pumpJentra(
        tester,
        size: const Size(1440, 900),
        preferences: const AppPreferences(
          themeMode: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JentraApp)),
      );
      container.read(routerProvider).go('/setup');
      await tester.pumpAndSettle();
      final controller = container.read(
        businessSetupControllerProvider.notifier,
      );

      for (final resource in BusinessSetupResource.values) {
        await controller.selectResource(resource);
        await tester.pumpAndSettle();
        expect(
          find.text(resource.label),
          findsWidgets,
          reason: '${resource.name} must render its setup workspace',
        );
        expect(tester.takeException(), isNull);
      }

      final formResources = BusinessSetupResource.values.where(
        (resource) =>
            !resource.isReadOnly &&
            resource != BusinessSetupResource.attachments,
      );
      for (final resource in formResources) {
        await controller.selectResource(resource);
        await tester.pumpAndSettle();
        final createLabel = 'Create ${resource.singularLabel}';
        expect(
          find.text(createLabel),
          findsOneWidget,
          reason: '${resource.name} must expose its permitted create command',
        );
        await tester.tap(find.text(createLabel));
        await tester.pumpAndSettle();
        expect(
          find.text('New ${resource.singularLabel}'),
          findsOneWidget,
          reason: '${resource.name} must render its complete form definition',
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('Wave 2 offline commands are guarded — AC-217', (tester) async {
    await _pumpJentra(
      tester,
      size: const Size(1440, 900),
      preferences: const AppPreferences(
        themeMode: ThemeMode.light,
        density: JentraDensity.comfortable,
      ),
      connectivity: ConnectivityState.offline,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    container.read(routerProvider).go('/setup');
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.textContaining('Imports and server commands are paused'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Import'))
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(
      find.text('Offline: only an encrypted local draft can be saved.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<JentraPrimaryButton>(
            find.widgetWithText(JentraPrimaryButton, 'Save to server'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Save draft'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Wave 2 view-only capability hides mutations — AC-218', (
    tester,
  ) async {
    await _pumpJentra(
      tester,
      size: const Size(1440, 900),
      preferences: const AppPreferences(
        themeMode: ThemeMode.light,
        density: JentraDensity.comfortable,
      ),
      capabilities: const {'finance.setup.view'},
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    container.read(routerProvider).go('/setup');
    await tester.pumpAndSettle();

    expect(find.text('Chart of accounts'), findsWidgets);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Import'))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Wave 2 setup opens the first permitted resource when finance is hidden — AC-218',
    (tester) async {
      await _pumpJentra(
        tester,
        size: const Size(1440, 900),
        preferences: const AppPreferences(
          themeMode: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
        capabilities: const {'crm.parties.view'},
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JentraApp)),
      );
      container.read(routerProvider).go('/setup');
      await tester.pumpAndSettle();

      expect(find.text('Parties'), findsWidgets);
      expect(find.text('CUS-001'), findsOneWidget);
      expect(find.text('Access is restricted'), findsNothing);
      expect(find.text('Create party'), findsNothing);
    },
  );

  testWidgets(
    'Wave 2 unauthorized capability hides and denies setup — AC-218',
    (tester) async {
      await _pumpJentra(
        tester,
        size: const Size(1440, 900),
        preferences: const AppPreferences(
          themeMode: ThemeMode.light,
          density: JentraDensity.comfortable,
        ),
        capabilities: const {},
      );

      expect(find.text('Business setup'), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Business setup');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Business setup'), findsNothing);
      expect(find.text('No commands match your search.'), findsOneWidget);
      await tester.tap(find.text('No commands match your search.'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(JentraApp)),
      );
      container.read(routerProvider).go('/setup');
      await tester.pumpAndSettle();
      expect(find.text('Access is restricted'), findsOneWidget);
      expect(find.text('1000'), findsNothing);
    },
  );

  testWidgets('Wave 2 setup forms surface field validation — AC-216', (
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    container.read(routerProvider).go('/setup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to server'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required.'), findsNWidgets(2));
    expect(find.text('New account'), findsOneWidget);
  });

  testWidgets('Wave 2 setup confirms discarding dirty forms — FR-241', (
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

    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    container.read(routerProvider).go('/setup');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('setup-code-field')), '1010');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('New account'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('New account'), findsNothing);
  });

  testWidgets('Wave 2 setup remains reachable at 200% text scale — EC-224', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpJentra(
      tester,
      size: const Size(1024, 720),
      preferences: const AppPreferences(
        themeMode: ThemeMode.light,
        density: JentraDensity.compact,
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(JentraApp)),
    );
    container.read(routerProvider).go('/setup');
    await tester.pumpAndSettle();

    expect(find.text('Business setup'), findsWidgets);
    await expectLater(
      find.byType(JentraApp),
      matchesGoldenFile('goldens/setup_1024_light_compact_text_200.png'),
    );
    final layoutException = tester.takeException();
    expect(
      layoutException,
      isNull,
      reason: layoutException is FlutterError
          ? layoutException.toStringDeep()
          : layoutException?.toString(),
    );
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
    testWidgets('setup golden ${scenario.name} — AC-216', (tester) async {
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
      container.read(routerProvider).go('/setup');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(JentraApp),
        matchesGoldenFile('goldens/setup_${scenario.name}.png'),
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
  ConnectivityState connectivity = ConnectivityState.online,
  Set<String>? capabilities,
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
        connectivityStateProvider.overrideWith(
          (ref) => Stream.value(connectivity),
        ),
        if (capabilities != null)
          businessCapabilitiesProvider.overrideWith(
            (ref) async => capabilities,
          ),
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
