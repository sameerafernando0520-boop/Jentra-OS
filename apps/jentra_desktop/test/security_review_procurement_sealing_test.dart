import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_return_controller.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_controller.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_controller.dart';
import 'package:jentra_desktop/src/features/procurement/product_unit_controller.dart';

import 'supplier_bill_workspace_test.dart' show BillGateway;
import 'supplier_payment_workspace_test.dart' show PaymentGateway;
import 'goods_receipt_workspace_test.dart' show ReceiptGateway;
import 'purchase_return_workspace_test.dart' show ReturnGateway;
import 'purchase_order_workspace_test.dart' show OrderGateway;
import 'product_unit_workspace_test.dart' show UnitGateway;
import 'support/procurement_fakes.dart' show Gateway;
import 'security_review_sealing_test.dart' show PausedKeys;

const scope = TenantContext(
  tenantId: 't',
  actorId: 'a',
  legalEntityId: 'e',
  branchId: 'b',
);
dynamic controller(String name, dynamic gateway, QuotationDraftStore store) =>
    switch (name) {
      'requisition' => ProcurementController(
        scope: scope,
        gateway: gateway,
        store: store,
        online: true,
      ),
      'order' => PurchaseOrderController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
      ),
      'receipt' => GoodsReceiptController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
      ),
      'bill' => SupplierBillController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
        canPost: true,
      ),
      'payment' => SupplierPaymentController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
        canPost: true,
      ),
      'unit' => ProductUnitController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: store,
        online: true,
      ),
      'sourcing' => SourcingController(
        scope: scope,
        gateway: gateway,
        drafts: store,
        online: true,
      ),
      _ => PurchaseReturnController(
        scope: scope,
        gateway: gateway,
        drafts: store,
        online: true,
      ),
    };
String slot(String name) => switch (name) {
  'requisition' => ProcurementController.slot,
  'order' => PurchaseOrderController.slot,
  'receipt' => GoodsReceiptController.slot,
  'bill' => SupplierBillController.slot,
  'payment' => SupplierPaymentController.slot,
  'unit' => ProductUnitController.slot,
  'sourcing' => SourcingController.slot,
  _ => PurchaseReturnController.slot,
};

Future<void> seed(String name, dynamic c) async {
  if (name == 'return') {
    // Start with the source-derived editor inputs without warming the cipher.
    // create() itself autosaves; a key-store pause after it would never fire.
    final source = await c.gateway.returnSource(scope, 'bill', 'source-bill');
    c.form = {
      'id': 'original-return',
      'source_kind': 'bill',
      'source_id': 'source-bill',
      'currency_code': source['currency_code'],
      '_rounding_scale': source['rounding_scale'],
      'document_date': '2026-09-15',
      'reason': 'Original exact return',
      'reference': 'SUP-42',
      'lines': [
        for (final raw in source['lines'] as List)
          {
            ...(raw as Map).cast<String, Object?>(),
            'line_id': 'original-return-line',
            '_original_quantity': raw['quantity'] ?? raw['accepted_quantity'],
            'quantity': '0.15',
            'serial_ids': <String>[],
          },
      ],
    };
  } else if (name == 'unit') {
    c.form = {
      'id': 'unit-conversion',
      'product_id': 'product',
      'unit_id': 'unit',
      'numerator': '3',
      'denominator': '2',
      'status': 'active',
    };
  } else if (name == 'sourcing') {
    c.form = {
      'id': 'original-rfq',
      'operation': 'issue_rfq',
      'reason': 'Original supplier invitation',
      'lines': <Map<String, Object?>>[],
    };
  } else {
    c.selected = {
      'id': 'original-document',
      'version': 7,
      'status': name == 'receipt'
          ? 'posted'
          : name == 'payment'
          ? 'approved'
          : 'draft',
    };
  }
}

Future<void> send(String name, dynamic c, {bool retry = false}) async {
  if (retry) {
    if (name == 'sourcing') {
      await c.send();
    } else if (name == 'return') {
      await c.post();
    } else {
      await c.saveServer();
    }
    return;
  }
  switch (name) {
    case 'requisition' || 'order':
      await c.transition('submit');
    case 'receipt':
      await c.reverse('2026-09-21', 'Original receipt reversal');
    case 'bill':
      await c.action('post');
    case 'payment':
      await c.action('post', reference: 'Original bank payment');
    case 'unit':
      await c.saveServer();
    case 'sourcing':
      await c.send();
    default:
      await c.post();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final name in [
    'requisition',
    'order',
    'receipt',
    'bill',
    'payment',
    'unit',
    'sourcing',
    'return',
  ]) {
    for (final change in ['disconnect', 'reconnect', 'dispose']) {
      test(
        '$name retains exact sealed command across $change before dispatch',
        () async {
          final db = JentraLocalDatabase(NativeDatabase.memory()),
              keys = PausedKeys();
          final store = QuotationDraftStore.procurement(
            EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          );
          final dynamic gateway = switch (name) {
            'order' => OrderGateway(),
            'receipt' => ReceiptGateway(),
            'bill' => BillGateway(),
            'payment' => PaymentGateway(),
            'unit' => UnitGateway(),
            'return' => ReturnGateway(),
            _ => Gateway(),
          };
          gateway.uncertain = false;
          final c = controller(name, gateway, store);
          var disposed = false;
          try {
            await c.initialize();
            await seed(name, c);
            keys.armed = true;
            final sending = send(name, c);
            await keys.entered.future.timeout(const Duration(seconds: 5));
            if (change == 'dispose') {
              c.dispose();
              disposed = true;
            } else {
              c.setOnline(false);
              if (change == 'reconnect') c.setOnline(true);
            }
            keys.release.complete();
            await sending;
            expect(gateway.commands, isEmpty);
            final recovery = await store.load(scope, slot(name));
            expect(
              recovery?.pending,
              isNotNull,
              reason: 'Keep the original identity after sealing.',
            );
            final original = recovery!.pending!.envelope.toJson((x) => x);
            if (!disposed) {
              c.dispose();
              disposed = true;
            }
            final fresh = controller(name, gateway, store);
            try {
              await fresh.initialize();
              await send(name, fresh, retry: true);
              expect(gateway.commands, hasLength(1));
              expect(gateway.commands.single.toJson((x) => x), original);
              expect((await store.load(scope, slot(name)))?.pending, isNull);
            } finally {
              fresh.dispose();
            }
          } finally {
            if (!keys.release.isCompleted) keys.release.complete();
            if (!disposed) c.dispose();
            await db.close();
          }
        },
      );
    }
  }
}
