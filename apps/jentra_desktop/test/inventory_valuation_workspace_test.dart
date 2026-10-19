import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/inventory_valuation/inventory_valuation_controller.dart';
import 'package:jentra_desktop/src/features/inventory_valuation/inventory_valuation_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> report(String id) => {
  'id': id,
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': 'b',
  'entity_name': 'Jentra Trading',
  'as_of': '2026-09-20',
  'generated_at': '2026-09-21 05:30 UTC',
  'currency_code': 'LKR',
  'status': 'generated',
  'version': 1,
  'warehouse_value': '100.000001',
  'transit_value': '20.000000',
  'inventory_value': '120.000001',
  'gl_value': '120.000000',
  'difference': '0.000001',
  'difference_count': 1,
  'stock_count': 1,
  'accounts': [
    {'id': 'account', 'code': '1100', 'name': 'Inventory control'},
  ],
};

class ValuationGateway implements InventoryValuationGateway {
  String? failure, readFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final reads = <Map<String, Object?>>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access/read failed');
    }
    return {
      'items': resource == 'accounts'
          ? [
              {
                'id': 'account',
                'code': '1100',
                'name': 'Inventory control',
                'status': 'active',
              },
            ]
          : <Object?>[],
    };
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return report(command.payload['id'] as String);
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? evidenceKey,
  }) async {
    reads.add({
      'id': id,
      'section': section,
      'after': after,
      'key': evidenceKey,
    });
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: 'Access/read failed');
    }
    return {
      'summary': report(id),
      'section': section,
      'evidence_key': evidenceKey,
      'next_cursor': after == null ? '50' : null,
      'items': [
        if (section == 'stock')
          {
            'id': 'warehouse:product',
            'warehouse_name': 'Colombo warehouse',
            'product_name': 'Office paper',
            'quantity': '3.000000',
            'value': '100.000001',
            'average_cost': '33.333333666667',
          },
        if (section == 'differences')
          {
            'id': 'command:source',
            'inventory_value': '100.000001',
            'gl_value': '100.000000',
            'difference': '0.000001',
          },
      ],
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
  late ValuationGateway gateway;
  late InventoryValuationController c;
  InventoryValuationController make({TenantContext context = scope}) =>
      InventoryValuationController(
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
    gateway = ValuationGateway();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    c.form = {...c.form, 'id': 'valuation-report-0042'};
    c.date('2026-09-20');
    c.account('account', true);
  }

  test(
    'generation saves exact account basis and expected creation version',
    () async {
      await ready();
      await c.generate();
      expect(c.error, isNull);
      expect(gateway.commands.single.expectedEntityVersion, 0);
      expect(gateway.commands.single.payload['account_ids'], ['account']);
      expect(c.summary['difference'], '0.000001');
    },
  );
  test(
    'uncertain generation survives restart with identical sealed command',
    () async {
      await ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await c.generate();
      final sealed = jsonEncode(gateway.commands.single.toJson((x) => x));
      await c.newReport();
      expect(c.local?.pending, isNotNull);
      c.dispose();
      c = make();
      await c.initialize();
      c.date('2026-09-19');
      gateway.failure = null;
      await c.generate();
      expect(jsonEncode(gateway.commands.last.toJson((x) => x)), sealed);
    },
  );
  test(
    'confirmed generation remains confirmed if evidence read fails',
    () async {
      await ready();
      gateway.readFailure = 'READ_FAILED';
      await c.generate();
      expect(c.form['status'], 'generated');
      expect(c.local?.pending, isNull);
      expect(c.message, contains('Report saved'));
    },
  );
  test('saved report can reopen after controller restart', () async {
    await ready();
    await c.generate();
    final id = c.summary['id'];
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.summary['id'], id);
    expect(c.rows, isNotEmpty);
  });
  test('source filters and page cursors remain tied to same report', () async {
    await ready();
    await c.generate();
    await c.sources('command:source');
    await c.selectSection('journals');
    await c.refreshPage(more: true);
    expect(gateway.reads.last['key'], 'command:source');
    expect(gateway.reads.last['after'], '50');
    await c.selectSection('stock');
    expect(gateway.reads.last['key'], isNull);
    expect(gateway.reads.last['after'], isNull);
  });
  test('reviewing another saved report preserves unsubmitted inputs', () async {
    await ready();
    final id = c.form['id'];
    await c.open(report('older-report'));
    expect(c.form['id'], id);
    expect(c.selectedAccounts, ['account']);
  });
  test(
    'offline generation does not send and drafts stay branch isolated',
    () async {
      await ready();
      c.setOnline(false);
      await c.save();
      await c.generate();
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
      expect(other.selectedAccounts, isEmpty);
      other.dispose();
    },
  );
  Future<void> render(
    WidgetTester tester, {
    bool dark = false,
    double height = 1500,
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
          child: Scaffold(body: InventoryValuationWorkspace(controller: c)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permission rejection clears costs while retaining encrypted request',
    (tester) async {
      await ready();
      await c.generate();
      gateway.readFailure = 'PERMISSION_DENIED';
      await c.refreshPage();
      await render(tester);
      expect(c.summary, isEmpty);
      expect(find.text('Recheck access'), findsOneWidget);
      expect(find.textContaining('120.000001'), findsNothing);
      expect(
        await drafts.load(scope, InventoryValuationController.slot),
        isNotNull,
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets('valuation ${dark ? 'dark' : 'light'} 200 percent', (
      tester,
    ) async {
      await ready();
      await c.generate();
      await render(tester, dark: dark);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          'goldens/inventory_valuation_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
  testWidgets('source differences and paging reachable at minimum desktop', (
    tester,
  ) async {
    await ready();
    await c.generate();
    await c.selectSection('differences');
    await render(tester, height: 720);
    await tester.scrollUntilVisible(
      find.text('View source lines').hitTestable(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('View source lines'));
    await tester.pumpAndSettle();
    expect(c.evidenceKey, 'command:source');
    expect(tester.takeException(), isNull);
  });
}
