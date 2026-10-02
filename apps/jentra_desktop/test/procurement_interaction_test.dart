import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_screen.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_screen.dart';

import 'supplier_bill_workspace_test.dart' show BillGateway;
import 'support/procurement_fakes.dart';

class BillReferences extends BillGateway {
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async => {
    'base_currency': 'LKR',
    'items': resource == 'bill_controls'
        ? []
        : [
            {
              'id': resource,
              'code': 'REF',
              'name': resource,
              'currency_code': 'USD',
              'description': 'Matched paper',
              'receipt_line_id': 'receipt-line',
              'supplier_id': 'bill_suppliers',
              'available_quantity': '0.000001',
              'source_snapshot': {
                'unit_price': '9.123456',
                'discount_percent': '0',
                'tax_definition_id': null,
              },
              'detail': {
                'receipt_line_id': 'receipt-line',
                'supplier_id': 'bill_suppliers',
                'description': 'Matched paper',
                'available_quantity': '0.000001',
                'source_snapshot': {
                  'unit_price': '9.123456',
                  'discount_percent': '0',
                  'tax_definition_id': null,
                },
              },
            },
          ],
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
  late BillReferences gateway;
  late SupplierBillController bill;
  late SourcingController sourcing;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = BillReferences()..uncertain = false;
    bill = SupplierBillController(
      scope: scope,
      gateway: gateway,
      references: gateway,
      drafts: drafts,
      online: true,
      canPost: true,
      canSetup: true,
      canApprove: true,
    );
    sourcing = SourcingController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
  });
  tearDown(() async {
    bill.dispose();
    sourcing.dispose();
    await db.close();
  });
  Future<void> pump(WidgetTester tester, Widget workspace) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: workspace)));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  Future<void> choose(
    WidgetTester tester,
    String button,
    String resource,
  ) async {
    await tester.ensureVisible(find.text(button));
    await tester.tap(find.text(button));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REF · $resource'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'bill controls select scoped accounts and save exact tolerance strings',
    (tester) async {
      await tester.runAsync(bill.configure);
      await pump(tester, SupplierBillWorkspace(controller: bill));
      await choose(
        tester,
        'AP control liability: Choose account',
        'bill_accounts',
      );
      await choose(tester, 'Input tax asset: Choose account', 'bill_accounts');
      await choose(
        tester,
        'Purchase variance expense: Choose account',
        'bill_accounts',
      );
      await tester.enterText(
        field('Net amount tolerance in bill currency'),
        '0.000001',
      );
      await tester.enterText(
        field('Unit price tolerance percentage'),
        '2.123456',
      );
      await tester.runAsync(bill.saveServer);
      final payload = gateway.commands.single.payload;
      expect(payload['amount_tolerance'], '0.000001');
      expect(payload['price_percent_tolerance'], '2.123456');
      expect(payload['payable_account_id'], 'bill_accounts');
      expect(payload.keys.any((k) => k.startsWith('_')), isFalse);
      expect(bill.form, isNull);
    },
  );
  testWidgets(
    'direct expense editor selects supplier FX expense and tax without decimal coercion',
    (tester) async {
      await tester.runAsync(() async {
        await bill.create();
        bill.addDirect();
      });
      await pump(tester, SupplierBillWorkspace(controller: bill));
      await choose(tester, 'Choose supplier', 'bill_suppliers');
      await choose(tester, 'Choose governed FX rate', 'bill_rates');
      await choose(tester, 'Choose expense account', 'bill_expenses');
      await choose(tester, 'Choose input tax', 'bill_taxes');
      for (final entry in {
        'Supplier invoice reference': 'INV-EXACT',
        'Posting date (YYYY-MM-DD)': '2026-09-30',
        'Due date (YYYY-MM-DD)': '2026-10-30',
        'Description': 'Exact direct expense',
        'Quantity': '0.000001',
        'Unit price': '90071992547409.123456',
        'Discount percentage': '0.000001',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.enterText(field(entry.key), entry.value);
      }
      await tester.runAsync(bill.saveServer);
      final payload = gateway.commands.single.payload;
      final line = (payload['lines'] as List).single as Map;
      expect(line['unit_price'], '90071992547409.123456');
      expect(line['quantity'], '0.000001');
      expect(line['expense_account_id'], 'bill_expenses');
      expect(line['tax_definition_id'], 'bill_taxes');
      expect(payload['currency_code'], 'USD');
      expect(payload['exchange_rate_id'], 'bill_rates');
      expect(line.keys.any((k) => '$k'.startsWith('_')), isFalse);
    },
  );
  testWidgets(
    'bill match exceptions remain exact and own-edit approval stays disabled',
    (tester) async {
      final row = <String, Object?>{
        'id': 'bill',
        'document_number': 'BILL-1',
        'supplier_reference': 'INV-1',
        'document_date': '2026-09-30',
        'due_date': '2026-10-30',
        'currency_code': 'USD',
        'status': 'draft',
        'version': 1,
        'created_by': 'other',
        'updated_by': 'a',
        'subtotal': '90071992547409.123456',
        'tax_total': '0.000001',
        'total': '90071992547409.123457',
        'match_result': {
          'exceptions': [
            {
              'exceptions': [
                {
                  'code': 'PRICE_VARIANCE',
                  'expected': '9.123456',
                  'actual': '9.123457',
                },
              ],
            },
          ],
        },
        'match_approvals': [
          {'reason': 'Independent review retained'},
        ],
        'lines': [
          {
            'description': 'Exact receipt line',
            'quantity': '0.000001',
            'unit_price': '9.123457',
            'discount_percent': '0',
            'net_amount': '0.000001',
            'tax_amount': '0.000001',
          },
        ],
      };
      bill.page = CursorPage(items: [row], limit: 50, nextCursor: 'next');
      bill.select(row);
      await pump(tester, SupplierBillWorkspace(controller: bill));
      expect(find.text('Match exceptions require review'), findsOneWidget);
      expect(
        find.textContaining('Expected 9.123456 · Actual 9.123457'),
        findsOneWidget,
      );
      expect(
        find.text('Approval recorded · Independent review retained'),
        findsOneWidget,
      );
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Approve match exceptions'),
      );
      expect(button.onPressed, isNull);
      bill.selected = {
        ...row,
        'match_result': {'blocked': true},
      };
      bill.emit();
      await tester.pumpAndSettle();
      expect(find.text('Receipt quantity unavailable'), findsOneWidget);
      bill.denyReadAccess();
      await tester.pumpAndSettle();
      expect(find.textContaining('90071992547409'), findsNothing);
      expect(find.text('Recheck access'), findsOneWidget);
    },
  );
  testWidgets(
    'sourcing comparison preserves exact totals and blocks incomplete choices',
    (tester) async {
      final quote = {
        'id': 'quote',
        'supplier_name': 'Supplier Exact',
        'complete': true,
        'currency_code': 'USD',
        'total': '90071992547409.123456',
        'base_total': '90071992547409.123456',
        'valid_until': '2026-10-30',
        'exchange_rate': '1.0000000001',
        'payment_terms': '30 days',
        'delivery_terms': 'Recorded',
        'lines': [
          {
            'description': 'Paper',
            'quantity': '0.000001',
            'unit_price': '9.123456',
            'line_total': '0.000001',
          },
        ],
      };
      sourcing.baseCurrency = 'LKR';
      sourcing.select({
        'id': 'rfq',
        'document_number': 'RFQ-1',
        'status': 'issued',
        'version': 1,
        'title': 'Recorded sourcing',
        'close_date': '2026-10-30',
        'selection_reason': 'Historical independent decision',
        'invited_suppliers': [
          {'id': 'supplier', 'name': 'Supplier Exact'},
        ],
        'quotes': [
          quote,
          {
            ...quote,
            'id': 'incomplete',
            'supplier_name': 'Incomplete Supplier',
            'complete': false,
          },
        ],
        'lines': [],
      });
      await pump(
        tester,
        SourcingWorkspace(controller: sourcing, canOrder: true),
      );
      expect(find.textContaining('90071992547409.123456'), findsNWidgets(2));
      expect(
        find.text('Selection rationale: Historical independent decision'),
        findsOneWidget,
      );
      final choices = tester
          .widgetList<TextButton>(
            find.widgetWithText(TextButton, 'Select supplier with reason'),
          )
          .toList();
      expect(choices[0].onPressed, isNotNull);
      expect(choices[1].onPressed, isNull);
      sourcing.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('90071992547409.123456'), findsNothing);
    },
  );
}
