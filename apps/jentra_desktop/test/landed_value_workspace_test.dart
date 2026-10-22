import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_controller.dart';
import 'package:jentra_desktop/src/features/landed_value/landed_value_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

const allocation = <String, Object?>{
  'receipt_line_id': 'receipt',
  'receipt_number': 'GR-0042',
  'product_name': 'Office paper',
  'basis_hash': 'basis',
  'amount': '10.000001',
  'inventory_amount': '6.666667',
  'variance_amount': '3.333334',
  'received_quantity': '3.000000',
  'held_quantity': '2.000000',
  'consumed_quantity': '1.000000',
  'currency_code': 'LKR',
  'legs': [
    {
      'warehouse_id': 'wh',
      'warehouse_name': 'Colombo warehouse',
      'value': '6.666667',
    },
  ],
};

class LandedGateway implements LandedValueGateway {
  String? failure;
  bool readFailure = false;
  bool readDenied = false;
  Completer<Map<String, Object?>>? pendingPosted;
  List<Map<String, Object?>> posted = [];
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (readDenied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access changed',
      );
    }
    if (readFailure) throw StateError('offline');
    if (resource == 'posted' && pendingPosted != null) {
      return pendingPosted!.future;
    }
    return {
      'items': switch (resource) {
        'receipts' => [
          {
            'id': 'receipt',
            'document_number': 'GR-0042',
            'product_name': 'Office paper',
          },
        ],
        'accounts' => [
          {'id': 'expense', 'code': '5300', 'name': 'Freight expense'},
        ],
        'posted' => posted,
        _ => [],
      },
    };
  }

  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) async => allocation;
  @override
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return {
      ...allocation,
      ...command.payload,
      'status': 'posted',
      'version': 1,
      'journal_ids': ['journal'],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late LandedGateway gateway;
  late LandedValueController c;
  LandedValueController make({TenantContext context = scope}) =>
      LandedValueController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = LandedGateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    await c.create();
    for (final entry in {
      'receipt_line_id': 'receipt',
      'offset_account_id': 'expense',
      'variance_account_id': 'expense',
      'amount': '10.000001',
      'document_date': '2026-09-19',
      'reference': 'FREIGHT-42',
      'reason': 'Reclassify recorded freight expense',
    }.entries) {
      c.update(entry.key, entry.value);
    }
    await c.calculate();
    expect(c.error, isNull);
  }

  test('posting seals server preview and expected creation version', () async {
    await ready();
    await c.post();
    expect(c.error, isNull);
    expect(gateway.commands.single.payload['basis_hash'], 'basis');
    expect(gateway.commands.single.expectedEntityVersion, 0);
    expect(c.form!['status'], 'posted');
  });
  test(
    'uncertain restart preserves byte-identical posting and blocks edits',
    () async {
      await ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.post();
      expect(c.local?.pending, isNotNull);
      final encoded = jsonEncode(gateway.commands.single.toJson((x) => x));
      await c.close();
      expect(c.form, isNotNull);
      c.dispose();
      c = make();
      await c.initialize();
      c.update('amount', '20');
      gateway.failure = null;
      await c.post();
      expect(jsonEncode(gateway.commands.last.toJson((x) => x)), encoded);
    },
  );
  test('conflict survives restart and requires fresh server preview', () async {
    await ready();
    gateway.failure = 'VERSION_CONFLICT';
    await c.post();
    expect(c.local?.pending, isNull);
    expect(c.preview, isNull);
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.preview, isNull);
    gateway.failure = null;
    await c.post();
    expect(gateway.commands.length, 1);
    await c.calculate();
    await c.post();
    expect(c.error, isNull);
    expect(gateway.commands.length, 2);
  });
  test('editing invalidates a prior preview', () async {
    await ready();
    c.update('amount', '20');
    await c.post();
    expect(gateway.commands, isEmpty);
  });
  test('linked reversal keeps original ID with expected version one', () async {
    await ready();
    await c.post();
    final original = c.form!['id'];
    await c.reverse();
    c.update('reason', 'Wrong receipt allocation');
    await c.post();
    expect(gateway.commands.last.payload['reverse_of'], original);
    expect(gateway.commands.last.expectedEntityVersion, 1);
  });
  test(
    'confirmed posting remains confirmed after register refresh failure',
    () async {
      await ready();
      gateway.readFailure = true;
      await c.post();
      expect(c.form!['status'], 'posted');
      expect(c.message, contains('confirmed'));
      expect(c.local?.pending, isNull);
    },
  );
  test('offline editor persists without sending and isolates branch', () async {
    await ready();
    c.setOnline(false);
    expect(await c.canLeave(), true);
    await c.post();
    expect(gateway.commands, isEmpty);
    final other = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await other.initialize();
    expect(other.form, isNull);
    other.dispose();
  });
  Future<void> render(
    WidgetTester tester, {
    bool dark = false,
    double height = 1800,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(1024, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? JentraTheme.dark() : JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: LandedValueWorkspace(controller: c)),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('unloaded posted register explains how to load its records', (
    tester,
  ) async {
    await render(tester);
    expect(find.text('Posted adjustments not loaded'), findsOneWidget);
    expect(find.text('No posted landed adjustments'), findsNothing);
    await tester.tap(find.text('Refresh posted'));
    await tester.pumpAndSettle();
    expect(find.text('Posted adjustments not loaded'), findsNothing);
    expect(find.text('No posted landed adjustments'), findsOneWidget);
    expect(gateway.commands, isEmpty);
  });

  testWidgets('empty posted register explains how to start an adjustment', (
    tester,
  ) async {
    await c.initialize();
    await render(tester);
    expect(find.text('No posted landed adjustments'), findsOneWidget);
    expect(
      find.textContaining('recording the receipt and freight expense'),
      findsOneWidget,
    );
    await tester.tap(find.text('New landed adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('No posted landed adjustments'), findsNothing);
    expect(find.text('Local adjustment'), findsOneWidget);
    expect(gateway.commands, isEmpty);
  });

  testWidgets('loading and offline reads never claim the register is empty', (
    tester,
  ) async {
    await c.initialize();
    gateway.pendingPosted = Completer<Map<String, Object?>>();
    final refresh = c.refresh('posted');
    await render(tester, settle: false);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No posted landed adjustments'), findsNothing);
    gateway.pendingPosted!.complete({'items': []});
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('No posted landed adjustments'), findsOneWidget);
    c.setOnline(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.text('No posted landed adjustments'), findsNothing);
    expect(find.text('Posted adjustments not loaded'), findsNothing);
  });

  testWidgets('read failure and existing postings replace the empty state', (
    tester,
  ) async {
    gateway.readFailure = true;
    await c.initialize();
    await render(tester);
    expect(
      find.textContaining('Unable to complete this action'),
      findsOneWidget,
    );
    expect(find.text('No posted landed adjustments'), findsNothing);
    gateway.readFailure = false;
    gateway.posted = [
      {
        'reference': 'FREIGHT-42',
        'receipt_number': 'GR-0042',
        'document_date': '2026-10-22',
        'currency_code': 'LKR',
        'amount': '10.000001',
      },
    ];
    await c.refresh('posted');
    await tester.pumpAndSettle();
    expect(find.text('FREIGHT-42 · GR-0042'), findsOneWidget);
    expect(find.text('No posted landed adjustments'), findsNothing);
    expect(gateway.commands, isEmpty);
  });

  testWidgets(
    'revoked cross-branch access hides costs and retains encrypted work',
    (tester) async {
      await ready();
      gateway.readDenied = true;
      await c.refresh('posted');
      expect(c.preview, isNull);
      expect(c.options, isEmpty);
      expect(await drafts.load(scope, LandedValueController.slot), isNotNull);
      await render(tester);
      expect(find.text('Recheck access'), findsOneWidget);
      expect(find.textContaining('6.666667'), findsNothing);
      await c.post();
      expect(gateway.commands, isEmpty);
      gateway.readDenied = false;
      await c.initialize();
      expect(c.accessDenied, isFalse);
      expect(c.preview, isNull);
      await c.calculate();
      expect(c.preview, isNotNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('landed preview ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await ready();
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/landed_value_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets('posting is reachable at minimum desktop height', (tester) async {
    await ready();
    await render(tester, height: 720);
    await tester.scrollUntilVisible(
      find.text('Post adjustment'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Post adjustment'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm posting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
