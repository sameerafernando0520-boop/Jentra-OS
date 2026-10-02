import 'dart:async';

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
import 'support/procurement_fakes.dart' show Keys, Gateway;

class ReadState {
  Completer<CursorPage<Map<String, Object?>>>? reply;
  bool denied = false, called = false;
  Future<CursorPage<Map<String, Object?>>> read() async {
    called = true;
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Access removed.',
      );
    }
    return reply?.future ?? Future.value(CursorPage(items: [], limit: 50));
  }
}

class Bills extends BillGateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> bills(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Payments extends PaymentGateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> proposals(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Receipts extends ReceiptGateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> receipts(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Returns extends ReturnGateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> returns(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Requisitions extends Gateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Sourcing extends Gateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Orders extends OrderGateway {
  final state = ReadState();
  @override
  Future<CursorPage<Map<String, Object?>>> orders(
    TenantContext scope, {
    String? after,
  }) => state.read();
}

class Units extends UnitGateway {
  final state = ReadState();
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async {
    final page = await state.read();
    return {
      'items': [
        for (final item in page.items) {'detail': item},
      ],
      'base_currency': 'LKR',
      'next_cursor': page.nextCursor,
    };
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    legalEntityId: 'e',
    branchId: 'b',
    actorId: 'a',
  );
  for (final module in [
    'bills',
    'payments',
    'receipts',
    'returns',
    'requisitions',
    'sourcing',
    'orders',
    'units',
  ]) {
    test(
      '$module ignores an old connection and retains encrypted inputs on access loss',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        final drafts = QuotationDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
        );
        late dynamic c;
        late ReadState state;
        late String slot;
        switch (module) {
          case 'bills':
            final gateway = Bills();
            state = gateway.state;
            slot = SupplierBillController.slot;
            c = SupplierBillController(
              scope: scope,
              gateway: gateway,
              references: Gateway(),
              drafts: drafts,
              online: true,
            );
          case 'payments':
            final gateway = Payments();
            state = gateway.state;
            slot = SupplierPaymentController.slot;
            c = SupplierPaymentController(
              scope: scope,
              gateway: gateway,
              references: Gateway(),
              drafts: drafts,
              online: true,
            );
          case 'receipts':
            final gateway = Receipts();
            state = gateway.state;
            slot = GoodsReceiptController.slot;
            c = GoodsReceiptController(
              scope: scope,
              gateway: gateway,
              references: Gateway(),
              drafts: drafts,
              online: true,
              canPost: true,
            );
          case 'requisitions':
            final gateway = Requisitions();
            state = gateway.state;
            slot = ProcurementController.slot;
            c = ProcurementController(
              scope: scope,
              gateway: gateway,
              store: drafts,
              online: true,
            );
          case 'sourcing':
            final gateway = Sourcing();
            state = gateway.state;
            slot = SourcingController.slot;
            c = SourcingController(
              scope: scope,
              gateway: gateway,
              drafts: drafts,
              online: true,
            );
          case 'orders':
            final gateway = Orders();
            state = gateway.state;
            slot = PurchaseOrderController.slot;
            c = PurchaseOrderController(
              scope: scope,
              gateway: gateway,
              references: Gateway(),
              drafts: drafts,
              online: true,
            );
          case 'units':
            final gateway = Units();
            state = gateway.state;
            slot = ProductUnitController.slot;
            c = ProductUnitController(
              scope: scope,
              gateway: gateway,
              references: gateway,
              drafts: drafts,
              online: true,
            );
          default:
            final gateway = Returns();
            state = gateway.state;
            slot = PurchaseReturnController.slot;
            c = PurchaseReturnController(
              scope: scope,
              gateway: gateway,
              drafts: drafts,
              online: true,
            );
        }
        addTearDown(() async {
          c.dispose();
          await db.close();
        });
        await drafts.save(scope, slot, {
          'id': 'saved',
          'reason': 'Protected local inputs',
        });
        state.reply = Completer();
        final loading = c.initialize() as Future<void>;
        for (var i = 0; i < 1000 && !state.called; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(state.called, isTrue);
        c.setOnline(false);
        c.setOnline(true);
        state.reply!.complete(
          CursorPage(
            items: [
              {'id': 'stale', 'grand_total': '90071992547409.123456'},
            ],
            limit: 50,
          ),
        );
        await loading;
        expect(c.page.items, isEmpty);
        if (module != 'units') expect(c.selected, isNull);
        state.reply = null;
        state.denied = true;
        await c.initialize();
        expect(c.accessDenied, isTrue);
        expect(c.locked, isTrue);
        expect(c.page.items, isEmpty);
        expect(
          (await drafts.load(scope, slot))!.form['reason'],
          'Protected local inputs',
        );
        state.denied = false;
        await c.initialize();
        expect(c.accessDenied, isFalse);
      },
    );
  }
}
