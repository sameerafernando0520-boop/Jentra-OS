import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_controller.dart';
import 'package:jentra_desktop/src/features/procurement/sourcing_screen.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

import 'support/procurement_fakes.dart';

Map<String, Object?> approvedRequirement() => {
  'id': 'req',
  'version': 7,
  'document_number': 'REQ-7',
  'justification': 'Exact paper sourcing',
  'lines': [
    {'line_id': 'line', 'description': 'Paper pack', 'quantity': '3'},
    {'line_id': 'excluded', 'description': 'Not required', 'quantity': '1'},
  ],
};
Map<String, Object?> issuedRfq() => {
  'id': 'rfq',
  'version': 4,
  'status': 'issued',
  'document_number': 'RFQ-4',
  'title': 'Exact paper sourcing',
  'close_date': '2026-10-01',
  'invited_suppliers': [
    {'id': 'supplier', 'name': 'Supplier One'},
  ],
  'lines': [
    {'source_line_id': 'line', 'description': 'Paper pack', 'quantity': '3'},
  ],
  'quotes': [
    {
      'id': 'quote',
      'supplier_id': 'supplier',
      'supplier_name': 'Supplier One',
      'complete': true,
      'quote_date': '2026-09-30',
      'valid_until': '2026-10-01',
      'currency_code': 'USD',
      'exchange_rate': '1.000001',
      'exchange_rate_id': 'rate',
      'rate_date': '2026-09-30',
      'payment_terms': '30 days',
      'delivery_terms': 'Warehouse',
      'total': '9007199254.740993',
      'base_total': '9007208261.940248',
      'lines': [
        {
          'source_line_id': 'line',
          'description': 'Paper pack',
          'quantity': '3',
          'unit_price': '9007199254.740993',
          'discount_percent': '0.000001',
          'tax_definition_id': null,
          'line_total': '9007199254.740993',
        },
      ],
    },
  ],
};

class SourcingReferences extends Gateway {
  final reads = <(String, String?, String)>[];
  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async {
    reads.add((resource, after, search));
    return {
      'base_currency': 'LKR',
      'items': [
        {
          'id': resource == 'suppliers'
              ? 'supplier'
              : resource == 'rates'
              ? 'rate'
              : 'tax',
          'code': 'REF',
          'name': resource == 'suppliers'
              ? 'Supplier One'
              : resource == 'rates'
              ? 'Governed FX'
              : 'Input tax',
          'currency_code': 'USD',
          'exchange_rate': '1.000001',
          'rate_date': '2026-09-30',
          'detail': approvedRequirement(),
        },
      ],
    };
  }

  @override
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  }) async => CursorPage(
    items: [issuedRfq()],
    limit: 50,
    nextCursor: after == null ? 'rfq-cursor' : null,
  );
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
  late QuotationDraftStore store;
  late SourcingReferences gateway;
  late SourcingController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = SourcingReferences()..uncertain = false;
    c = SourcingController(
      scope: scope,
      gateway: gateway,
      drafts: store,
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.runAsync(c.initialize);
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SourcingWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      while (c.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> input(WidgetTester tester, String label, String value) async {
    final f = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(f);
    await tester.enterText(f, value);
    await tester.pump();
  }

  testWidgets(
    'issue RFQ selects approved source lines and invited supplier with scoped immutable version',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Issue RFQ from requisition');
      await tap(tester, 'REF · Input tax');
      await settle(tester);
      expect(c.form!['requisition_version'], 7);
      await input(tester, 'Sourcing title', 'Reviewed exact source');
      await input(tester, 'RFQ date', '2026-09-30');
      await input(tester, 'Close date', '2026-10-01');
      await tap(tester, 'Not required · 1');
      expect(c.form!['source_line_ids'], ['line']);
      await tap(tester, 'Add invited supplier');
      await tap(tester, 'REF · Supplier One');
      await settle(tester);
      expect(c.form!['invited_supplier_ids'], ['supplier']);
      await tap(tester, 'Add invited supplier');
      await tap(tester, 'REF · Supplier One');
      await settle(tester);
      expect(c.form!['invited_supplier_ids'], ['supplier']);
      final remove = find
          .descendant(
            of: find.widgetWithText(InputChip, 'Supplier One'),
            matching: find.byType(Icon),
          )
          .last;
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(c.form!['invited_supplier_ids'], isEmpty);
      await tap(tester, 'Add invited supplier');
      await tap(tester, 'REF · Supplier One');
      await settle(tester);
      await tap(tester, 'Save on this device');
      await settle(tester);
      expect(
        (await tester.runAsync(
          () => store.load(scope, SourcingController.slot),
        ))!.form['title'],
        'Reviewed exact source',
      );
      await tap(tester, 'Issue RFQ');
      await settle(tester);
      final command = gateway.commands.single;
      expect(command.context, scope);
      expect(command.expectedEntityVersion, isNull);
      expect(command.payload['operation'], 'issue');
      expect(command.payload['requisition_id'], 'req');
      expect(command.payload['requisition_version'], 7);
      expect(command.payload['source_line_ids'], ['line']);
      expect(command.payload['invited_supplier_ids'], ['supplier']);
      expect(command.payload.keys.any((k) => k.startsWith('_')), false);
      expect(c.form, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'supplier response preserves exact fields governed FX and tax choices then sealed server save',
    (tester) async {
      await mount(tester);
      await tap(tester, 'RFQ-4 · Exact paper sourcing');
      await tap(tester, 'Record response · Supplier One');
      await settle(tester);
      expect(c.form!['quote_id'], 'quote');
      await input(tester, 'Quotation date', '2026-09-30');
      await input(tester, 'Valid until', '2026-10-01');
      await input(tester, 'Payment terms', '60 days');
      await input(tester, 'Delivery terms', 'Split delivery');
      await tap(tester, 'Use base currency');
      expect(c.form!['currency_code'], 'LKR');
      expect(c.form!['exchange_rate_id'], isNull);
      await tap(tester, 'Choose governed FX rate');
      await tap(tester, 'REF · Governed FX');
      await settle(tester);
      expect(c.form!['exchange_rate_id'], 'rate');
      expect(c.form!['exchange_rate'], '1.000001');
      await input(tester, 'Quantity', '0.000001');
      await input(tester, 'Unit price', '9007199254.740993');
      await input(tester, 'Discount %', '0.000001');
      await tap(tester, 'Choose input tax');
      await tap(tester, 'REF · Input tax');
      await settle(tester);
      expect((c.form!['lines'] as List).single['tax_definition_id'], 'tax');
      await tap(tester, 'No tax');
      expect((c.form!['lines'] as List).single['tax_definition_id'], isNull);
      await tap(tester, 'Save to server');
      await settle(tester);
      final command = gateway.commands.single;
      expect(command.expectedEntityVersion, 4);
      expect(command.payload['exchange_rate_id'], 'rate');
      expect(command.payload['payment_terms'], '60 days');
      expect(command.payload['lines'], [
        {
          'source_line_id': 'line',
          'quantity': '0.000001',
          'unit_price': '9007199254.740993',
          'discount_percent': '0.000001',
          'tax_definition_id': null,
        },
      ]);
      expect(c.form, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'supplier selection rationale cancels empty choice and confirms original quote/version only',
    (tester) async {
      await mount(tester);
      await tap(tester, 'RFQ-4 · Exact paper sourcing');
      await tap(tester, 'Load more');
      expect(c.page.items.length, 2);
      // Select one current item explicitly after paging before opening its rationale.
      c.select(issuedRfq());
      await tester.pumpAndSettle();
      await tap(tester, 'Select supplier with reason');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      await tap(tester, 'Select supplier with reason');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      await tap(tester, 'Select supplier with reason');
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        '  Reliable split delivery  ',
      );
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      final command = gateway.commands.single;
      expect(command.context, scope);
      expect(command.expectedEntityVersion, 4);
      expect(command.payload, {
        'id': 'rfq',
        'operation': 'select',
        'quote_id': 'quote',
        'selection_reason': 'Reliable split delivery',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'discard confirmation retains local notes when cancelled and removes only current scoped draft',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() => c.issue(approvedRequirement()));
      await tester.pumpAndSettle();
      await input(tester, 'Sourcing title', 'Keep these notes');
      await tap(tester, 'Discard local draft');
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(c.form!['title'], 'Keep these notes');
      await tap(tester, 'Discard local draft');
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(c.form, isNull);
      expect(
        await tester.runAsync(() => store.load(scope, SourcingController.slot)),
        isNull,
      );
      expect(gateway.commands, isEmpty);
    },
  );
  for (final key in ['quantity', 'unit_price', 'discount_percent']) {
    for (final invalid in ['1e3', '0.0000001', '-0.000001']) {
      test('$key rejects $invalid before sealing supplier response', () async {
        await c.initialize();
        c.select(issuedRfq());
        await c.quote({'id': 'supplier', 'name': 'Supplier One'});
        c.update('lines', [
          {...(c.form!['lines'] as List).single as Map, key: invalid},
        ]);
        await c.saveServer();
        expect(gateway.commands, isEmpty);
        expect(c.local?.pending, isNull);
        expect(c.error, contains('exact $key'));
      });
    }
  }
}
