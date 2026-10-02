import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/operations/operational_read_access.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_controller.dart';
import 'package:jentra_desktop/src/features/procurement/procurement_picker.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/purchase_order_controller.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/product_unit_controller.dart';

import 'support/procurement_fakes.dart';

class References extends Gateway
    implements
        PurchaseOrderGateway,
        GoodsReceiptGateway,
        SupplierBillGateway,
        SupplierPaymentGateway,
        ProductUnitGateway {
  Completer<void>? hold;
  final entered = Completer<void>();
  Object? failure;
  final reads = <(String?, String)>[];
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async {
    reads.add((after, search));
    if (!entered.isCompleted) entered.complete();
    if (hold != null) await hold!.future;
    if (failure != null) throw failure!;
    return {
      'items': [
        {
          'id': after == null ? 'one' : 'two',
          'code': 'PRIVATE',
          'name': after == null ? 'Supplier One' : 'Supplier Two',
        },
      ],
      'next_cursor': after == null ? 'after-one' : null,
    };
  }

  // Every unexpected command fails; this fixture must only issue bounded reads.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef Access = ({
  OperationalReadAccess access,
  void Function(bool) online,
  VoidCallback dispose,
  bool Function() denied,
});

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  late References gateway;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = References();
  });
  tearDown(() => db.close());
  final factories = <String, Access Function()>{
    'requisition': () {
      final c = ProcurementController(
        scope: scope,
        gateway: gateway,
        store: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'sourcing': () {
      final c = SourcingController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'order': () {
      final c = PurchaseOrderController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'receipt': () {
      final c = GoodsReceiptController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'bill': () {
      final c = SupplierBillController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'payment': () {
      final c = SupplierPaymentController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
    'product unit': () {
      final c = ProductUnitController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
      );
      return (
        access: c,
        online: c.setOnline,
        dispose: c.dispose,
        denied: () => c.accessDenied,
      );
    },
  };
  Future<void> open(WidgetTester tester, Access c) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pickSourcingReference(
                context,
                gateway,
                scope,
                'suppliers',
                access: c.access,
              ),
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open selector'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final factory in factories.entries) {
    testWidgets('${factory.key} root choices clear offline and cannot revive', (
      tester,
    ) async {
      final c = factory.value();
      addTearDown(c.dispose);
      await open(tester, c);
      expect(find.text('PRIVATE · Supplier One'), findsOneWidget);
      c.online(false);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE · Supplier One'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      c.online(true);
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE · Supplier One'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open selector'));
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE · Supplier One'), findsOneWidget);
      expect(gateway.reads, hasLength(2));
      expect(gateway.commands, isEmpty);
    });
    testWidgets('${factory.key} disposed workspace rejects a late root read', (
      tester,
    ) async {
      final c = factory.value();
      gateway.hold = Completer<void>();
      await open(tester, c);
      c.dispose();
      await tester.pump();
      gateway.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE · Supplier One'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('${factory.key} typed denial invalidates controller access', (
      tester,
    ) async {
      final c = factory.value();
      addTearDown(c.dispose);
      gateway.failure = const DomainError(
        code: 'MFA_REQUIRED',
        message: 'SECRET private claims',
      );
      await open(tester, c);
      await tester.pumpAndSettle();
      expect(c.denied(), isTrue);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
    });
  }
  testWidgets('reference paging and explicit search preserve bounded queries', (
    tester,
  ) async {
    final c = factories['bill']!();
    addTearDown(c.dispose);
    await open(tester, c);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE · Supplier Two'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Code 100%');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(gateway.reads, [(null, ''), ('after-one', ''), (null, 'Code 100%')]);
    expect(find.text('PRIVATE · Supplier Two'), findsNothing);
  });
}
