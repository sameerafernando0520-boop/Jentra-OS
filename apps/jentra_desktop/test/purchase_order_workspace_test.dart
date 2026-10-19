import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_screen.dart';

import 'support/procurement_fakes.dart';

class OrderGateway extends Gateway implements PurchaseOrderGateway {
  String? failure;
  final verbs = <String>[];
  @override
  Future<CursorPage<Map<String, Object?>>> orders(
    TenantContext s, {
    String? after,
  }) => rfqs(s, after: after);
  @override
  Future<Map<String, Object?>> saveOrder(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    verbs.add('save');
    return _result(c);
  }

  @override
  Future<Map<String, Object?>> transitionOrder(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    verbs.add('transition');
    return _result(c);
  }

  Future<Map<String, Object?>> _result(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Retry original command.',
      );
    }
    if (failure != null) {
      throw DomainError(code: failure!, message: 'Order changed.');
    }
    return {
      'id': c.payload['id'] ?? c.payload['document_id'],
      'status': 'draft',
      'version': 2,
      'revision': 2,
    };
  }
}

void main() {
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late OrderGateway gateway;
  late PurchaseOrderController c;
  PurchaseOrderController controller() => PurchaseOrderController(
    scope: scope,
    gateway: gateway,
    references: gateway,
    drafts: drafts,
    online: true,
    canApprove: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = OrderGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Map<String, Object?> order({String status = 'draft'}) => {
    'id': 'order',
    'status': status,
    'version': 1,
    'revision': 1,
    'document_number': 'PO-0001',
    'document_date': '2026-09-13',
    'promised_date': '2026-09-30',
    'warehouse_id': 'warehouse',
    '_warehouse_name': 'Main warehouse',
    'supplier_id': 'supplier',
    '_supplier_name': 'Supplier One',
    'source_rfq_id': 'rfq',
    'source_quote_id': 'quote',
    'source_snapshot': {'document_number': 'RFQ-0001'},
    'currency_code': 'LKR',
    'exchange_rate': '1',
    'rate_date': '2026-09-13',
    'payment_terms': '30 days',
    'delivery_terms': 'Delivered to warehouse',
    'total': '333.330000',
    'base_total': '333.330000',
    'created_by': 'a',
    'commercial_editor_id': 'a',
    'submitted_by': 'a',
    'lines': [
      {
        'line_id': 'line',
        'source_line_id': 'source',
        'description': 'Paper',
        'unit_id': 'unit',
        'quantity': '3',
        'unit_price': '123.456789',
        'discount_percent': '10',
        'tax_definition_id': null,
        'received_quantity': '0.000000',
        'billed_quantity': '0.000000',
        'cancelled_quantity': '0.000000',
        'remaining_quantity': '3.000000',
        'line_total': '333.330000',
      },
    ],
  };
  test('uncertain revision survives restart and retries lifecycle RPC, never draft save', () async {
    await c.initialize();
    c.select(order(status: 'approved'));
    await c.transition('revise', reason: 'Supplier price amendment');
    final original = jsonEncode(gateway.commands.single.toJson((p) => p));
    c.dispose();
    c = controller();
    await c.initialize();
    c.update('payment_terms', 'changed');
    expect(c.form!['payment_terms'], '30 days');
    gateway.uncertain = false;
    await c.saveServer();
    expect(gateway.verbs, ['transition', 'transition']);
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
    expect(c.form, isNull);
    expect(await drafts.load(scope, PurchaseOrderController.slot), isNull);
  });
  test('conflict retains raw edit and prevents replacing command', () async {
    await c.initialize();
    await c.edit(order());
    gateway.uncertain = false;
    gateway.failure = 'VERSION_CONFLICT';
    await c.saveServer();
    expect(c.local!.errorCode, 'VERSION_CONFLICT');
    c.update('payment_terms', 'changed');
    expect(c.form!['payment_terms'], '30 days');
    await c.saveServer();
    expect(gateway.commands.length, 1);
  });
  test('order creator cannot approve in controller', () async {
    await c.initialize();
    c.select(order(status: 'pending_approval'));
    await c.transition('approve');
    expect(gateway.commands, isEmpty);
  });
  test(
    'offline order edits persist for same scope and never issue command',
    () async {
      await c.initialize();
      await c.edit(order());
      c.setOnline(false);
      c.update('payment_terms', '45 days');
      await c.saveServer();
      expect(gateway.commands, isEmpty);
      expect(await c.canLeave(), isTrue);
      expect(
        (await drafts.load(
          scope,
          PurchaseOrderController.slot,
        ))!.form['payment_terms'],
        '45 days',
      );
    },
  );
  test(
    'direct requisition order seals supplier terms and original source line',
    () async {
      await c.initialize();
      await c.createFromRequisition({
        'id': 'req',
        'version': 3,
        'status': 'approved',
        'document_number': 'PR-0001',
        'need_by': '2026-09-30',
        'currency_code': 'LKR',
        'lines': [
          {
            'line_id': 'source',
            'unit_id': 'unit',
            'description': 'Paper',
            'quantity': '3',
            'estimated_unit_price': '100.123456',
          },
        ],
      });
      c.update('document_date', '2026-09-13');
      c.update('warehouse_id', 'warehouse');
      c.update('supplier_id', 'supplier');
      c.update('payment_terms', '14 days');
      c.update('delivery_terms', 'Delivered');
      await c.saveServer();
      final first = gateway.commands.single;
      expect(first.payload['source_requisition_id'], 'req');
      expect(first.payload['source_requisition_version'], 3);
      expect(
        (first.payload['lines'] as List).single['source_line_id'],
        'source',
      );
      expect(
        (first.payload['lines'] as List).single['unit_price'],
        '100.123456',
      );
      expect(first.payload.containsKey('_source_number'), isFalse);
      gateway.uncertain = false;
      await c.saveServer();
      expect(gateway.commands.last.toJson((p) => p), first.toJson((p) => p));
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'purchase order ${dark ? 'dark' : 'light'} at 200% retains actions',
      (tester) async {
        await tester.runAsync(() async {
          await c.initialize();
          await c.edit(order());
        });
        tester.view.physicalSize = const Size(1024, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: PurchaseOrderWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/purchase_order_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(find.text('Save on this device'));
        await tester.pumpAndSettle();
        expect(find.text('Save on this device').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
