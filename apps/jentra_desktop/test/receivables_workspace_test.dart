import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_screen.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'receivables_controller_test.dart' as f;

Future<ReceivablesController> pump(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1,
  Size size = const Size(1440, 1000),
  bool edit = false,
  bool offline = false,
  Set<String>? caps,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  late JentraLocalDatabase db;
  late ReceivablesController c;
  await tester.runAsync(() async {
    db = JentraLocalDatabase(NativeDatabase.memory());
    c = ReceivablesController(
      scope: f.scope,
      capabilities: caps ?? f.permissions,
      repository: f.FakeReceivables(),
      drafts: ReceivableDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: f.MemoryKeys())),
        newId: () => '00000000-0000-4000-8000-000000000099',
      ),
      online: !offline,
    );
    await c.open(ReceivableDocument(f.snapshot()));
    if (edit) await c.edit();
  });
  addTearDown(db.close);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('receivables-golden'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: Scaffold(body: ReceivablesWorkspace(controller: c)),
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
  testWidgets(
    'invoice source detail renders exact totals and guarded actions',
    (tester) async {
      await pump(tester);
      expect(find.text('INV-0001'), findsOneWidget);
      expect(find.text('LKR 118000.000000'), findsOneWidget);
      expect(find.text('Submit'), findsOneWidget);
      expect(find.text('Post document'), findsNothing);
      await expectLater(
        find.byKey(const Key('receivables-golden')),
        matchesGoldenFile('goldens/receivables_invoice_1440_light.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('invoice editor dark theme', (tester) async {
    await pump(tester, dark: true, edit: true);
    expect(find.text('From delivery'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('receivables-golden')),
      matchesGoldenFile('goldens/receivables_editor_1440_dark.png'),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow editor at 200 percent text remains scrollable', (
    tester,
  ) async {
    await pump(tester, edit: true, scale: 2, size: const Size(1024, 1000));
    await expectLater(
      find.byKey(const Key('receivables-golden')),
      matchesGoldenFile('goldens/receivables_editor_1024_text200.png'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -1800),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('offline and view-only users cannot dispatch mutations', (
    tester,
  ) async {
    await pump(tester, offline: true, caps: {'sales.invoices.view'});
    expect(find.text('Submit'), findsNothing);
    expect(find.text('Edit draft'), findsNothing);
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('uncertain result displays saved-command retry', (tester) async {
    final c = await pump(tester);
    final repo = c.repository as f.FakeReceivables;
    repo.doc = ReceivableDocument(f.snapshot(status: 'approved'));
    await tester.runAsync(() async {
      await c.open(repo.doc);
      repo.failure = Exception('network');
      await c.action('post');
    });
    await tester.pumpAndSettle();
    expect(find.text('Retry saved command'), findsOneWidget);
    await expectLater(
      find.byKey(const Key('receivables-golden')),
      matchesGoldenFile('goldens/receivables_recovery_1440_light.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
