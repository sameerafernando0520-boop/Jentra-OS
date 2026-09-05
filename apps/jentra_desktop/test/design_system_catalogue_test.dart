import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/catalogue/component_catalogue_screen.dart';

void main() {
  setUpAll(() async {
    const root = 'packages/jentra_design_system/assets/fonts';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('$root/Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('$root/Manrope-Medium.ttf'))
          ..addFont(rootBundle.load('$root/Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('$root/IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final scenario in [
    (
      name: '1024_light_compact',
      size: const Size(1024, 720),
      dark: false,
      density: JentraDensity.compact,
    ),
    (
      name: '1440_light_comfortable',
      size: const Size(1440, 900),
      dark: false,
      density: JentraDensity.comfortable,
    ),
    (
      name: '1440_dark_compact',
      size: const Size(1440, 900),
      dark: true,
      density: JentraDensity.compact,
    ),
    (
      name: '1920_dark_comfortable',
      size: const Size(1920, 1080),
      dark: true,
      density: JentraDensity.comfortable,
    ),
  ]) {
    testWidgets('logo-led catalogue ${scenario.name}', (tester) async {
      await _pump(
        tester,
        scenario.size,
        dark: scenario.dark,
        density: scenario.density,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/catalogue_${scenario.name}.png'),
      );
      for (var i = 1; i < 3; i++) {
        await tester.tap(find.byKey(Key('catalogue-tab-$i')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('catalogue forms and sample actions give real feedback', (
    tester,
  ) async {
    await _pump(tester, const Size(1440, 1100));
    await tester.tap(find.byKey(const Key('catalogue-tab-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve preview'));
    await tester.pumpAndSettle();
    expect(find.text('Preview approved'), findsOneWidget);
    expect(
      find.text('Preview approved. No business record was changed.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Validate preview'));
    await tester.tap(find.text('Validate preview'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a customer name.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('specimen-customer')),
      'Ceylon Trading',
    );
    await tester.ensureVisible(find.text('Validate preview'));
    await tester.tap(find.text('Validate preview'));
    await tester.pumpAndSettle();
    expect(
      find.text('Preview is valid. No document was submitted.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalogue reflows all sections at 200 percent text', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await _pump(tester, const Size(1024, 720), dark: dark, scale: 2);
      for (var i = 0; i < 3; i++) {
        await tester.ensureVisible(find.byKey(Key('catalogue-tab-$i')));
        await tester.tap(find.byKey(Key('catalogue-tab-$i')));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Section $i in ${dark ? 'dark' : 'light'}',
        );
        await tester.drag(
          find.byKey(const Key('catalogue-scroll')),
          const Offset(0, -650),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  bool dark = false,
  JentraDensity density = JentraDensity.comfortable,
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: dark
          ? JentraTheme.dark(density: density)
          : JentraTheme.light(density: density),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: ComponentCatalogueScreen()),
    ),
  );
  await tester.pumpAndSettle();
}
