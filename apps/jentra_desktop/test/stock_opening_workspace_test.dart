import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';
import 'package:jentra_desktop/src/features/stock_opening/stock_opening_controller.dart';
import 'package:jentra_desktop/src/features/stock_opening/stock_opening_screen.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_stock_opening_platform.dart';
import 'stock_opening_fixtures.dart';

Future<StockOpeningController> pumpOpening(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  Size size = const Size(1440, 1100),
  bool edit = false,
  bool register = false,
  bool offline = false,
  String status = 'draft',
  bool selfApproval = false,
  bool pending = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  late JentraLocalDatabase db;
  late StockOpeningController c;
  await tester.runAsync(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    final repo = FakeStockOpeningRepository()
      ..doc = StockOpeningDocument({
        ...openingSnapshot(status: status),
        if (selfApproval) 'prepared_by': 'actor',
      });
    c = StockOpeningController(
      scope: openingScope,
      capabilities: openingPermissions,
      repository: repo,
      drafts: StockOpeningDraftStore(
        EncryptedDraftRepository(
          db,
          DraftCipher(keyStore: OpeningMemoryKeys()),
        ),
      ),
      online: !offline,
    );
    if (register) {
      await c.refresh();
    } else {
      await c.open(repo.doc);
      if (edit) await c.edit();
    }
    if (pending) {
      repo.failure = TimeoutException('lost response');
      await c.action('post');
    }
  });
  addTearDown(() async {
    if (c.active) c.dispose();
    await db.close();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('opening-golden'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: Scaffold(body: StockOpeningWorkspace(controller: c)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-Medium.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${base}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('opening register shows exact value and status', (tester) async {
    await pumpOpening(tester, register: true);
    expect(find.text('OPEN-00001'), findsOneWidget);
    expect(find.text('LKR 248500.000000'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('opening-golden')),
      matchesGoldenFile('goldens/stock_opening_register_light.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('opening editor renders count lot details and exact preview', (
    tester,
  ) async {
    await pumpOpening(tester, edit: true);
    expect(find.text('Count details'), findsOneWidget);
    expect(find.text('LOT-2026-09'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('opening-golden')),
      matchesGoldenFile('goldens/stock_opening_editor_light.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('opening editor supports dark theme', (tester) async {
    await pumpOpening(tester, edit: true, dark: true);
    await expectLater(
      find.byKey(const Key('opening-golden')),
      matchesGoldenFile('goldens/stock_opening_editor_dark.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('200 percent text remains scrollable without overflow', (
    tester,
  ) async {
    await pumpOpening(
      tester,
      edit: true,
      scale: 2,
      size: const Size(1024, 1000),
    );
    await expectLater(
      find.byKey(const Key('opening-golden')),
      matchesGoldenFile('goldens/stock_opening_editor_text200.png'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -2800),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'posted opening presents immutable stock and journal references',
    (tester) async {
      await pumpOpening(tester, status: 'posted');
      expect(find.text('Edit count'), findsNothing);
      expect(find.text('Post opening'), findsNothing);
      expect(find.text('Journal reference · journal-001'), findsOneWidget);
      await expectLater(
        find.byKey(const Key('opening-golden')),
        matchesGoldenFile('goldens/stock_opening_posted.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('self approval and offline posting are unavailable', (
    tester,
  ) async {
    await pumpOpening(
      tester,
      status: 'pending_approval',
      selfApproval: true,
      offline: true,
    );
    expect(find.text('Approve'), findsNothing);
    expect(find.textContaining('A separate approver'), findsOneWidget);
    expect(find.text('Working offline'), findsOneWidget);
  });
  testWidgets('uncertain post shows durable retry and blocks replacement', (
    tester,
  ) async {
    final c = await pumpOpening(tester, status: 'approved', pending: true);
    expect(c.pending, true);
    expect(find.text('Retry saved command'), findsOneWidget);
    expect(find.text('New opening'), findsNothing);
    await expectLater(
      find.byKey(const Key('opening-golden')),
      matchesGoldenFile('goldens/stock_opening_recovery.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'product picker creates serial fields and removes cached data on scope change',
    (tester) async {
      final c = await pumpOpening(tester, edit: true);
      await tester.ensureVisible(find.text('Add product'));
      await tester.tap(find.text('Add product'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Laser printer'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.textContaining('Laser printer'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -1700),
      );
      await tester.pumpAndSettle();
      expect(find.text('Serial codes · one per line'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Add product'));
      await tester.tap(find.text('Add product'));
      await tester.pumpAndSettle();
      c.dispose();
      await tester.pumpAndSettle();
      expect(find.text('Business scope changed'), findsOneWidget);
      expect(find.textContaining('Laser printer'), findsNothing);
    },
  );
  testWidgets(
    'navigation and direct route fail closed without cost visibility',
    (tester) async {
      expect(
        visibleJentraDestinations({
          'inventory.adjustments.post',
        }).any((d) => d.path == '/inventory'),
        false,
      );
      expect(
        visibleJentraDestinations(
          openingPermissions,
        ).any((d) => d.path == '/inventory'),
        true,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeTenantContextProvider.overrideWithValue(openingScope),
            businessCapabilitiesProvider.overrideWith(
              (ref) async => {'inventory.adjustments.post'},
            ),
          ],
          child: MaterialApp(home: const Scaffold(body: StockOpeningScreen())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('require cost visibility'), findsOneWidget);
    },
  );
}
