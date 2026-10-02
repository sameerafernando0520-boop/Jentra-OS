import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_screen.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_screen.dart';

import 'goods_receipt_workspace_test.dart' show ReceiptGateway;
import 'purchase_order_workspace_test.dart' show OrderGateway;
import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> sourceOrder({String tracking = 'lot'}) => {
  'id': 'order',
  'status': 'approved',
  'version': 4,
  'document_number': 'PO-42',
  'warehouse_id': 'warehouse',
  'created_by': 'other',
  'lines': [
    {
      'line_id': 'source-line',
      'description': 'Paper pack',
      'quantity': '3',
      'remaining_quantity': '3',
      'received_quantity': '0',
      'conversion_numerator': '2',
      'conversion_denominator': '1',
      '_tracking_mode': tracking,
    },
  ],
};

class ReceiptReferences extends ReceiptGateway {
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'items': resource == 'receipt_controls'
        ? []
        : [
            {
              'id': resource,
              'code': '5200',
              'name': resource == 'receipt_orders'
                  ? 'PO-42'
                  : 'Receipt account',
              'detail': sourceOrder(),
            },
          ],
    'base_currency': 'LKR',
  };
}

class OrderReferences extends OrderGateway {
  @override
  Future<Map<String, Object?>> saveOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) async => {'lines': <Object?>[], ...await super.saveOrder(command)};
  @override
  Future<Map<String, Object?>> transitionOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) async => {'lines': <Object?>[], ...await super.transitionOrder(command)};
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'items': [
      {
        'id': resource,
        'code': 'REF',
        'name': 'Reference $resource',
        'currency_code': 'USD',
        'exchange_rate': '1.000001',
        'rate_date': '2026-09-30',
        'detail': {
          'id': 'req',
          'version': 3,
          'status': 'approved',
          'document_number': 'PR-42',
          'need_by': '2026-10-02',
          'currency_code': 'LKR',
          'lines': [
            {
              'line_id': 'req-line',
              'product_id': 'product',
              'unit_id': 'unit',
              'description': 'Paper pack',
              'quantity': '0.000001',
              'estimated_unit_price': '9007199254.740993',
            },
          ],
        },
      },
    ],
    'base_currency': 'LKR',
  };
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late ReceiptReferences receipts;
  late OrderReferences orders;
  late GoodsReceiptController receipt;
  late PurchaseOrderController order;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    receipts = ReceiptReferences()..uncertain = false;
    orders = OrderReferences()..uncertain = false;
    receipt = GoodsReceiptController(
      scope: scope,
      gateway: receipts,
      references: receipts,
      drafts: drafts,
      online: true,
      canSetup: true,
      canApprove: true,
    );
    order = PurchaseOrderController(
      scope: scope,
      gateway: orders,
      references: orders,
      drafts: drafts,
      online: true,
      canApprove: true,
    );
  });
  tearDown(() async {
    receipt.dispose();
    order.dispose();
    await db.close();
  });
  Future<void> render(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 2500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> enter(WidgetTester t, String label, String value) async {
    await t.ensureVisible(field(label));
    await t.enterText(field(label), value);
    await t.pump();
  }

  Future<void> tap(WidgetTester t, String label) async {
    final f = find.text(label);
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> pick(WidgetTester t, String label) async {
    await tap(t, label);
    await t.tap(find.byType(ListTile).last);
    await t.pumpAndSettle();
  }

  for (final tracking in ['lot', 'serial']) {
    testWidgets(
      'receipt $tracking inputs preserve exact quantities and tracking in the atomic wire command',
      (t) async {
        await receipt.initialize();
        await receipt.create(sourceOrder(tracking: tracking));
        await render(t, GoodsReceiptWorkspace(controller: receipt));
        await enter(t, 'Posting date (YYYY-MM-DD)', '2026-09-30');
        await enter(t, 'Supplier delivery reference', 'DEL-42');
        await enter(
          t,
          'Accepted quantity',
          tracking == 'lot' ? '0.000001' : '1',
        );
        await enter(t, 'Rejected quantity', '0.000001');
        await enter(t, 'Rejection reason', 'Damaged carton');
        if (tracking == 'lot') {
          await enter(t, 'Lot code', 'LOT-42');
          await enter(t, 'Manufacture date (optional)', '2026-09-01');
          await enter(t, 'Expiry date (optional)', '2026-12-01');
        } else {
          await enter(t, 'Serial numbers (one per line)', 'SN-1, SN-2');
        }
        await tap(t, 'Save on this device');
        expect(
          (await drafts.load(
            scope,
            GoodsReceiptController.slot,
          ))!.expectedVersion,
          4,
        );
        await tap(t, 'Post goods receipt');
        expect(receipt.error, isNull);
        final command = receipts.commands.single;
        expect(command.expectedEntityVersion, 4);
        final line = (command.payload['lines'] as List).single as Map;
        expect(line['accepted_quantity'], tracking == 'lot' ? '0.000001' : '1');
        expect(line['order_line_id'], 'source-line');
        expect(line.keys.where((k) => '$k'.startsWith('_')), isEmpty);
        if (tracking == 'serial') {
          expect(line['serial_codes'], ['SN-1', 'SN-2']);
        }
        expect(receipt.form, isNull);
      },
    );
  }
  testWidgets(
    'receipt configured accounts and maximum allowance remain scoped exact inputs',
    (t) async {
      await receipt.initialize();
      await render(t, GoodsReceiptWorkspace(controller: receipt));
      await tap(t, 'Receipt posting accounts');
      await pick(t, 'GRNI liability account: Choose account');
      await pick(t, 'Default expense account: Choose account');
      await enter(t, 'Maximum over-receipt percentage', '0.000001');
      await tap(t, 'Save posting accounts');
      expect(receipts.operations, ['controls']);
      expect(receipts.commands.single.context, scope);
      expect(
        receipts.commands.single.payload['maximum_over_receipt_percent'],
        '0.000001',
      );
      expect(
        receipts.commands.single.payload['grni_account_id'],
        'receipt_accounts',
      );
    },
  );
  testWidgets(
    'independent extra quantity approval uses selected source version and reason',
    (t) async {
      await receipt.createAllowance(sourceOrder());
      await render(t, GoodsReceiptWorkspace(controller: receipt));
      await t.tap(find.text('Paper pack'));
      await t.pumpAndSettle();
      await enter(t, 'Extra quantity above the order', '0.000001');
      await enter(t, 'Approval reason', 'Pack rounding exception');
      await tap(t, 'Approve allowance');
      expect(receipts.operations, ['allowance']);
      expect(receipts.commands.single.expectedEntityVersion, 4);
      expect(receipts.commands.single.payload['order_line_id'], 'source-line');
      expect(receipts.commands.single.payload['extra_quantity'], '0.000001');
    },
  );
  testWidgets(
    'receipt reversal asks for a reason and leaves original document linked',
    (t) async {
      await receipt.initialize();
      receipt.select({
        'id': 'original',
        'version': 7,
        'status': 'posted',
        'document_number': 'GR-42',
        'lines': [],
      });
      await render(t, GoodsReceiptWorkspace(controller: receipt));
      await tap(t, 'Reverse receipt');
      await enter(t, 'Posting date (YYYY-MM-DD)', '2026-09-30');
      await enter(t, 'Reason', 'Wrong warehouse');
      await t.tap(find.widgetWithText(FilledButton, 'Reverse receipt'));
      await t.pumpAndSettle();
      expect(receipts.operations, ['reverse']);
      expect(receipts.commands.single.payload['document_id'], 'original');
      expect(receipts.commands.single.expectedEntityVersion, 7);
    },
  );
  testWidgets(
    'receipt discard preserves unsent work until the user chooses discard',
    (t) async {
      await receipt.create(sourceOrder());
      await render(t, GoodsReceiptWorkspace(controller: receipt));
      await tap(t, 'Discard draft');
      await tap(t, 'Keep draft');
      expect(receipt.form, isNotNull);
      await tap(t, 'Discard draft');
      await tap(t, 'Discard');
      expect(receipt.form, isNull);
      expect(await drafts.load(scope, GoodsReceiptController.slot), isNull);
    },
  );
  testWidgets(
    'direct purchase order source and governed rates retain exact line values',
    (t) async {
      await order.initialize();
      await render(t, PurchaseOrderWorkspace(controller: order));
      await pick(t, 'Create from approved requisition');
      await enter(t, 'Order date', '2026-09-30');
      await enter(t, 'Promised date', '2026-10-02');
      await pick(t, 'Choose receiving warehouse');
      await pick(t, 'Change supplier');
      await pick(t, 'Choose governed FX rate');
      await enter(t, 'Payment terms', '30 days');
      await enter(t, 'Delivery terms', 'Delivered');
      await enter(t, 'Quantity', '0.000002');
      await enter(t, 'Unit price', '9007199254.740993');
      await enter(t, 'Discount %', '0.000001');
      await pick(t, 'Choose input tax');
      await tap(t, 'No tax');
      await tap(t, 'Save on this device');
      final saved = (await drafts.load(
        scope,
        PurchaseOrderController.slot,
      ))!.form;
      expect(
        (saved['lines'] as List).single['unit_price'],
        '9007199254.740993',
      );
      await tap(t, 'Save to server');
      expect(order.error, isNull);
      final payload = orders.commands.single.payload;
      expect(payload['source_requisition_version'], 3);
      expect(payload['exchange_rate_id'], 'rates');
      expect(payload['exchange_rate'], '1.000001');
      expect((payload['lines'] as List).single['quantity'], '0.000002');
      expect((payload['lines'] as List).single['source_line_id'], 'req-line');
      expect((payload['lines'] as List).single['tax_definition_id'], isNull);
    },
  );
  for (final (status, label, action, needsReason) in [
    ('draft', 'Submit for approval', 'submit', false),
    ('pending_approval', 'Approve', 'approved', false),
    ('pending_approval', 'Reject with reason', 'rejected', true),
    ('rejected', 'Recall to draft', 'recall', true),
    ('approved', 'Create revision', 'revise', true),
    ('approved', 'Cancel remaining order', 'cancel', true),
  ]) {
    testWidgets(
      'purchase order $action is governed by original source version',
      (t) async {
        await order.initialize();
        order.select({
          'id': 'order',
          'version': 8,
          'status': status,
          'revision': 2,
          'document_number': 'PO-42',
          'created_by': 'other',
          'source_snapshot': {'document_number': 'PR-42'},
          'payment_terms': '30 days',
          'delivery_terms': 'Delivered',
          'currency_code': 'LKR',
          'exchange_rate': '1',
          'base_total': '9007199254.740993',
          'lines': [],
        });
        await render(t, PurchaseOrderWorkspace(controller: order));
        await tap(t, label);
        if (needsReason) {
          await enter(t, 'Reason', 'Supplier agreed amendment');
          await tap(t, 'Confirm');
        }
        expect(order.error, isNull);
        expect(orders.commands, hasLength(1));
        expect(orders.commands.single.payload['document_id'], 'order');
        expect(orders.commands.single.expectedEntityVersion, 8);
        expect(
          orders.commands.single.payload['action'] ??
              orders.commands.single.payload['decision'],
          action,
        );
        expect(
          jsonEncode(orders.commands.single.toJson((v) => v)),
          contains('"actor_id":"a"'),
        );
      },
    );
  }
}
