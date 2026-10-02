import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_screen.dart';

import 'supplier_payment_workspace_test.dart' show PaymentGateway;
import 'support/procurement_fakes.dart' show Keys;

class PaymentEvidence extends PaymentGateway {
  final statementRequests = <Map<String, Object?>>[];
  final targetCursors = <String?>[],
      rateCursors = <String?>[],
      itemCursors = <String?>[];
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'items': [
      {'id': resource, 'code': 'REF', 'name': resource, 'currency_code': 'USD'},
    ],
  };
  @override
  Future<Map<String, Object?>> payableItems(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) async {
    itemCursors.add(after);
    return {
      'items': [
        {
          'id': after == null ? 'bill' : 'credit',
          'document_number': after == null ? 'SB-EXACT' : 'CR-EXACT',
            'kind': after == null ? 'bill' : 'credit',
          'due_date': '2026-09-30',
          'currency_code': 'USD',
          'residual': {
            'amount': after == null ? '9007199254.740993' : '-0.000001',
          },
          'claimed': false,
        },
        if (after == null)
          {
            'id': 'claimed',
            'document_number': 'CLAIMED',
            'kind': 'bill',
            'due_date': '2026-09-30',
            'currency_code': 'USD',
            'residual': {'amount': '5.000001'},
            'claimed': true,
          },
      ],
      'next_cursor': after == null ? 'next-payable' : null,
    };
  }

  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope, {
    required String supplierId,
    required String currency,
    required String asOf,
    required List<int> buckets,
  }) async {
    statementRequests.add({
      'supplier': supplierId,
      'currency': currency,
      'date': asOf,
      'buckets': buckets,
    });
    return {
      'supplier_id': supplierId,
      'supplier_name': 'Historical Supplier',
      'currency_code': currency,
      'as_of': asOf,
      'bucket_days': buckets,
      'open_amount': '9007199254.740993',
      'open_base_amount': '99999999999.999999',
      'aging': [
        for (final index in [-1, 0, 1, 2, 4])
          {'bucket': index, 'amount': '0.000001', 'base_amount': '9.999999'},
      ],
      'rows': [
        for (final kind in [
          'supplier_bill',
          'supplier_payment',
          'purchase_return',
          'other',
        ])
          {
            'id': 'credit',
            'source_type': kind,
            'document_number': kind,
            'posting_date': '2026-09-28',
            'due_date': '2026-09-30',
            'open_amount': '9007199254.740993',
            'open_base_amount': '99999999999.999999',
          },
      ],
    };
  }

  @override
  Future<Map<String, Object?>> itemDetail(
    TenantContext scope,
    String itemId, {
    String? after,
  }) async => {
    'item': {
      'id': itemId,
      'document_number': 'UNAPPLIED',
      'amount': '-9007199254.740993',
      'base_amount': '-99999999999.999999',
      'currency_code': 'USD',
    },
    'allocations': [
      {
        'id': after == null ? 'allocation' : 'old-allocation',
        'source_document_number': 'PAY-01',
        'target_document_number': 'BILL-01',
        'source_amount': '0.000001',
        'transaction_amount': '0.000002',
        'exchange_difference': '0.000001',
        'posting_date': '2026-09-28',
        if (after != null)
          'reversal': {
            'posting_date': '2026-09-29',
            'reason': 'Linked correction',
          },
      },
    ],
    'next_cursor': after == null ? 'allocation-next' : null,
  };
  @override
  Future<Map<String, Object?>> allocationTargets(
    TenantContext scope,
    String sourceId, {
    String? after,
  }) async {
    targetCursors.add(after);
    return {
      'items': [
        {
          'id': after == null ? 'target' : 'target2',
          'document_number': after == null ? 'TARGET' : 'TARGET2',
          'currency_code': after == null ? 'LKR' : 'USD',
          'amount': '99999999999.999999',
        },
      ],
      'next_cursor': after == null ? 'target-next' : null,
    };
  }

  @override
  Future<Map<String, Object?>> allocationRates(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) async {
    rateCursors.add(after);
    return {
      'items': [
        {
          'id': after == null ? 'rate' : 'rate2',
          'rate': '2.0000000000',
          'date': '2026-09-28',
        },
      ],
      'next_cursor': after == null ? 'rate-next' : null,
    };
  }
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
  late PaymentEvidence gateway;
  late SupplierPaymentController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = PaymentEvidence()..uncertain = false;
    c = SupplierPaymentController(
      scope: scope,
      gateway: gateway,
      references: gateway,
      drafts: drafts,
      online: true,
      canPost: true,
      canApprove: true,
      canAllocate: true,
      canReverse: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierPaymentWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> choose(
    WidgetTester tester,
    String label,
    String resource,
  ) async {
    await tap(tester, label);
    await tap(tester, 'REF · $resource');
  }

  testWidgets(
    'proposal selects scoped references and exact due amounts with claimed items blocked',
    (tester) async {
      await tester.runAsync(c.create);
      await pump(tester);
      await choose(tester, 'Choose supplier', 'payment_suppliers');
      await choose(tester, 'Choose payment bank', 'payment_banks');
      await choose(tester, 'Choose FX rate if required', 'payment_rates');
      await tester.enterText(field('Payment date'), '2026-09-30');
      await tap(tester, 'Find due bills and credits');
      await tap(tester, 'CLAIMED · bill');
      expect(c.form!['lines'], isEmpty);
      await tap(tester, 'SB-EXACT · bill');
      await tap(tester, 'More open items');
      await tap(tester, 'CR-EXACT · credit');
      final amounts = find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.labelText == 'Amount to allocate',
      );
      expect(amounts, findsNWidgets(2));
      await tester.enterText(amounts.first, '9007199254.740993');
      expect(c.proposedTotal, '9007199254.740992');
      await tap(tester, 'Save on this device');
      final local = await drafts.load(scope, SupplierPaymentController.slot);
      expect(
        (local!.form['lines'] as List).first['amount'],
        '9007199254.740993',
      );
      await tap(tester, 'Save proposal');
      final p = gateway.commands.single.payload;
      expect(p['supplier_id'], 'payment_suppliers');
      expect(p['cash_bank_account_id'], 'payment_banks');
      expect(p['exchange_rate_id'], 'payment_rates');
      expect((p['lines'] as List).first['amount'], '9007199254.740993');
      expect(gateway.itemCursors, [null, 'next-payable']);
      expect(c.local, isNull);
      final raw = await db.select(db.encryptedDrafts).get();
      expect(
        raw.every(
          (r) =>
              !latin1.decode(r.encryptedPayload).contains('9007199254.740993'),
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dated AP statement validates boundaries and exposes historical document and allocation pages',
    (tester) async {
      await pump(tester);
      await tap(tester, 'Supplier statement and AP aging');
      await tap(tester, 'Load dated statement');
      expect(gateway.statementRequests, isEmpty);
      await choose(tester, 'Choose statement supplier', 'payment_suppliers');
      await tester.enterText(field('Statement as of'), '2026-09-30');
      await tester.enterText(field('Currency code'), 'USD');
      await tester.enterText(field('Aging boundaries in days'), '30,30,90');
      await tap(tester, 'Load dated statement');
      expect(gateway.statementRequests, isEmpty);
      await tester.enterText(field('Aging boundaries in days'), '30,60,90');
      await tap(tester, 'Load dated statement');
      expect(gateway.statementRequests.single['buckets'], [30, 60, 90]);
      for (final label in [
        'Unapplied credits',
        'Not overdue',
        '1–30 days',
        '31–60 days',
        'Over 90 days',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.text('Open 9007199254.740993 · Base 99999999999.999999'),
        findsOneWidget,
      );
      await tap(tester, 'supplier_bill · Supplier bill');
      expect(find.text('Open-item history · UNAPPLIED'), findsOneWidget);
      await tap(tester, 'More allocation history');
      expect(
        find.text('Reversed 2026-09-29 · Linked correction'),
        findsOneWidget,
      );
      c.setOnline(false);
      await tester.pump();
      expect(find.textContaining('9007199254'), findsNothing);
      expect(c.itemDetail, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'allocation correction selects cross-currency targets and rates then seals exact strings',
    (tester) async {
      await c.inspectItem('credit');
      await pump(tester);
      await tap(tester, 'Allocate unapplied credit');
      await tester.enterText(
        field('Correction posting date (YYYY-MM-DD)'),
        '2026-09-30',
      );
      await tester.enterText(
        field('Reason'),
        'Apply unmatched recorded payment',
      );
      await tester.enterText(field('Credit amount (USD)'), '0.000001');
      await tap(tester, 'Find eligible bills');
      await tap(tester, 'More eligible bills');
      await tap(tester, 'TARGET · LKR 99999999999.999999');
      await tester.enterText(field('Bill amount (LKR)'), '0.000002');
      await tap(tester, 'Find conversion rates');
      await tap(tester, 'More conversion rates');
      await tester.ensureVisible(find.text('USD → LKR · 2.0000000000').first);
      await tester.tap(find.text('USD → LKR · 2.0000000000').first);
      await tester.pump();
      await tap(tester, 'Record allocation correction');
      expect(gateway.operations.single, 'allocate');
      final allocation =
          (gateway.commands.single.payload['allocations'] as List).single
              as Map;
      expect(allocation['source_amount'], '0.000001');
      expect(allocation['transaction_amount'], '0.000002');
      expect(allocation['exchange_rate_id'], 'rate');
      expect(allocation['target_open_item_id'], 'target');
      expect(gateway.targetCursors, [null, 'target-next']);
      expect(gateway.rateCursors, [null, 'rate-next']);
      expect(c.itemDetail, isNull);
      expect(c.statementReport, isNull);
      expect(c.local, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'allocation reversal retains the immutable identity and requires a reason',
    (tester) async {
      await c.inspectItem('credit');
      await pump(tester);
      await tap(tester, 'Reverse allocation');
      await tester.enterText(field('Reason'), 'Wrong bill allocation');
      await tap(tester, 'Confirm');
      expect(find.text('Reverse the selected allocation'), findsOneWidget);
      await tester.enterText(field('Reason'), '');
      await tap(tester, 'Record allocation correction');
      expect(gateway.commands, isEmpty);
      expect(c.error, contains('reason'));
      await tester.enterText(field('Reason'), 'Wrong bill allocation');
      await tap(tester, 'Record allocation correction');
      expect(gateway.operations.single, 'reverse');
      expect(gateway.commands.single.payload['allocation_id'], 'allocation');
      expect(
        gateway.commands.single.payload.containsKey('allocations'),
        isFalse,
      );
      expect(c.local, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
