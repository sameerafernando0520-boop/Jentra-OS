import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';
import 'support/procurement_fakes.dart' show Keys;

class Counts implements StockCountGateway {
  bool uncertain = false;
  Map<String, Object?>? detailResult;
  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async =>
      detailResult!;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final verbs = <String>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? after,
    String search = '',
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    verbs.add(verb);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry saved command.',
      );
    }
    return {
      ...command.payload,
      'id': command.payload['id'] ?? command.payload['document_id'],
      'version': (command.expectedEntityVersion ?? 0) + 1,
      'status': verb == 'save'
          ? 'draft'
          : verb == 'post'
          ? 'posted'
          : 'pending_approval',
      'cutoff_at': '2026-09-15T20:00:00Z',
      'currency_code': 'LKR',
      'grand_total': command.payload['capture_only'] == true
          ? '0.000000'
          : '20.024691',
      'warehouse_name': 'Colombo warehouse',
      'offset_account_name': 'Inventory variance',
      'lines': [
        for (final l in command.payload['lines'] as List? ?? [])
          {
            ...l as Map,
            if (command.payload['capture_only'] == true)
              'counted_quantity': '10.000000',
            'product_name': 'Recycled office paper',
            'baseline_quantity': '10.000000',
            'variance_quantity': command.payload['capture_only'] == true
                ? '0.000000'
                : '-2.000000',
            'variance_value': command.payload['capture_only'] == true
                ? '0.000000'
                : '-20.024691',
          },
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late Counts gateway;
  late StockCountController c;
  StockCountController make({TenantContext context = scope}) =>
      StockCountController(
        scope: context,
        gateway: gateway,
        drafts: drafts,
        online: true,
        permissions: {
          'inventory.adjustments.post',
          'inventory.cost.view',
          'workflow.approvals.decide',
        },
      );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = Counts();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> capture() async {
    await c.initialize();
    await c.create();
    c.update('warehouse_id', 'warehouse');
    c.update('offset_account_id', 'expense');
    c.update('reason', 'Physical cycle count');
    c.update('document_date', '2026-09-15');
    c.addProduct({
      'id': 'paper',
      'name': 'Recycled office paper',
      'on_hand_quantity': '10.000000',
    });
    await c.act('save');
  }

  test('count capture seals an explicit snapshot request', () async {
    await capture();
    expect(gateway.commands.single.payload['capture_only'], true);
    expect(c.form!['version'], 1);
    c.addProduct({'id': 'other', 'name': 'Other', 'on_hand_quantity': '1'});
    expect((c.form!['lines'] as List).length, 1);
  });
  test(
    'unsaved count edits cannot submit a different server document',
    () async {
      await capture();
      c.updateLine(0, 'counted_quantity', '8');
      await c.act('submit');
      expect(c.error, contains('Save the count changes'));
      expect(gateway.commands.length, 1);
    },
  );
  test(
    'uncertain count save retains exact quantity and version on restart',
    () async {
      await capture();
      c.updateLine(0, 'counted_quantity', '9007199254.740993');
      gateway.uncertain = true;
      await c.act('save');
      final original = jsonEncode(gateway.commands.last.toJson((p) => p));
      expect(c.local?.pending, isNotNull);
      c.dispose();
      c = make();
      await c.initialize();
      c.updateLine(0, 'counted_quantity', '1');
      gateway.uncertain = false;
      await c.act('retry');
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(gateway.commands.last.expectedEntityVersion, 1);
    },
  );
  test(
    'uncertain approved post retains posting operation on restart',
    () async {
      await c.initialize();
      await c.open({
        'id': 'approved',
        'version': 4,
        'status': 'approved',
        'reason': 'Approved variance',
        'lines': [],
      });
      gateway.uncertain = true;
      await c.act('post');
      final original = jsonEncode(gateway.commands.last.toJson((p) => p));
      c.dispose();
      c = make();
      await c.initialize();
      gateway.uncertain = false;
      await c.act('retry');
      expect(gateway.verbs.last, 'post');
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form!['status'], 'posted');
    },
  );
  test('offline navigation preserves unsubmitted counted quantities', () async {
    await capture();
    c.updateLine(0, 'counted_quantity', '8.125');
    c.setOnline(false);
    await c.act('save');
    expect(gateway.commands.length, 1);
    expect(await c.canLeave(), true);
    c.dispose();
    c = make();
    await c.initialize();
    expect((c.form!['lines'] as List).single['counted_quantity'], '8.125');
    expect(c.form!['_dirty'], true);
  });
  test('another branch cannot recover a count draft', () async {
    await capture();
    c.dispose();
    c = make(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await c.initialize();
    expect(c.form, isNull);
  });
  Future<void> tracked({bool serial = false}) async {
    await capture();
    final source = {...c.form!};
    await c.close();
    await c.open({
      ...source,
      'lines': [
        {
          ...(source['lines'] as List).single as Map,
          'tracking_mode': serial ? 'serial' : 'lot',
          'product_name': serial ? 'Barcode scanners' : 'Recycled office paper',
          'baseline_quantity': serial ? '2.000000' : '10.000000',
          'counted_quantity': serial ? '2.000000' : '10.000000',
          'identities': [
            {
              'id': 'one',
              'code': serial ? 'SER-001' : 'LOT-A',
              'baseline_quantity': serial ? '1' : '5',
              'counted_quantity': serial ? '1' : '5',
              'disposition': serial ? 'quarantine' : 'saleable',
              'baseline_version': 2,
            },
            {
              'id': 'two',
              'code': serial ? 'SER-002' : 'LOT-B',
              'baseline_quantity': serial ? '1' : '5',
              'counted_quantity': serial ? '1' : '5',
              'disposition': 'available',
              'baseline_version': 3,
            },
          ],
        },
      ],
    });
  }

  test('tracked save sanitizes identities and retains exact total', () async {
    await tracked();
    c.updateIdentity(0, 0, '9007199254.740993');
    expect(
      (c.form!['lines'] as List).single['counted_quantity'],
      '9007199259.740993',
    );
    await c.act('save');
    final ids =
        (gateway.commands.last.payload['lines'] as List).single['identities']
            as List;
    expect(ids.first, {'id': 'one', 'counted_quantity': '9007199254.740993'});
  });
  test(
    'register summary loads detail before opening and persists it',
    () async {
      await capture();
      gateway.detailResult = {...c.form!};
      final id = c.form!['id'];
      await c.close();
      await c.open({'id': id});
      expect(c.form!['lines'], isNotEmpty);
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.form!['lines'], isNotEmpty);
    },
  );
  test(
    'invalid tracked quantity is retained locally but cannot be sent',
    () async {
      await tracked(serial: true);
      c.updateIdentity(0, 0, '0.5');
      final before = gateway.commands.length;
      await c.act('save');
      expect(gateway.commands.length, before);
      expect(c.error, contains('present or absent'));
    },
  );
  test('uncertain identity counts remain immutable through restart', () async {
    await tracked(serial: true);
    c.updateIdentity(0, 0, '0');
    gateway.uncertain = true;
    await c.act('save');
    final before = jsonEncode(gateway.commands.last.toJson((p) => p));
    c.dispose();
    c = make();
    await c.initialize();
    c.updateIdentity(0, 0, '1');
    gateway.uncertain = false;
    await c.act('retry');
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), before);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'serial identity count ${dark ? 'dark' : 'light'} at 200 percent',
      (tester) async {
        await tracked(serial: true);
        c.updateIdentity(0, 0, '0');
        tester.view.physicalSize = const Size(1024, 1700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: StockCountWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile(
            'goldens/stock_count_serial_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
  test(
    'linked correction captures a new baseline and new line identities',
    () async {
      await capture();
      final original = {...c.form!, 'status': 'posted'};
      await c.close();
      await c.open(original);
      await c.correct();
      expect(c.form!['corrects_count_id'], original['id']);
      expect(c.form!['id'], isNot(original['id']));
      expect(c.form!['version'], isNull);
      expect(
        (c.form!['lines'] as List).single['line_id'],
        isNot((original['lines'] as List).single['line_id']),
      );
      c.update('reason', 'Correct the prior physical count');
      await c.act('save');
      expect(gateway.commands.last.payload['capture_only'], true);
      expect(
        gateway.commands.last.payload['corrects_count_id'],
        original['id'],
      );
    },
  );
  testWidgets('count controls remain reachable at minimum desktop height', (
    tester,
  ) async {
    await capture();
    tester.view.physicalSize = const Size(1024, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: StockCountWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save count'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  for (final dark in [false, true]) {
    testWidgets('count editor ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await capture();
      c.updateLine(0, 'counted_quantity', '8');
      tester.view.physicalSize = const Size(1024, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: StockCountWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/stock_count_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Save count'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
