import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_screen.dart';
import 'support/procurement_fakes.dart';

class PaymentGateway extends Gateway implements SupplierPaymentGateway {
  @override
  Future<Map<String, Object?>> allocationRates(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> itemDetail(
    TenantContext scope,
    String itemId, {
    String? after,
  }) async => {
    'item': {'id': itemId, 'amount': '-100', 'currency_code': 'LKR'},
    'allocations': [],
  };
  @override
  Future<Map<String, Object?>> allocationTargets(
    TenantContext scope,
    String sourceId, {
    String? after,
  }) async => {'items': []};
  @override
  Future<Map<String, Object?>> correctAllocation(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) => send(action, command);
  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope, {
    required String supplierId,
    required String currency,
    required String asOf,
    required List<int> buckets,
  }) async => {
    'supplier_id': supplierId,
    'currency_code': currency,
    'as_of': asOf,
    'open_amount': '295.300000',
    'open_base_amount': '295.300000',
    'rows': [],
    'aging': [],
    'bucket_days': buckets,
  };
  final operations = <String>[];
  @override
  Future<CursorPage<Map<String, Object?>>> proposals(
    TenantContext scope, {
    String? after,
  }) => rfqs(scope, after: after);
  @override
  Future<CursorPage<Map<String, Object?>>> payments(
    TenantContext scope, {
    String? after,
  }) => rfqs(scope, after: after);
  @override
  Future<Map<String, Object?>> payableItems(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) async => {'items': []};
  Future<Map<String, Object?>> send(
    String operation,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    operations.add(operation);
    await source(command);
    return {
      ...command.payload,
      'id': command.payload['id'] ?? command.payload['document_id'],
      'status': operation == 'post' ? 'posted' : 'draft',
      'version': 2,
    };
  }

  @override
  Future<Map<String, Object?>> saveProposal(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('save', command);
  @override
  Future<Map<String, Object?>> transitionProposal(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('transition', command);
  @override
  Future<Map<String, Object?>> postPayment(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('post', command);
}

void main() {
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
  late PaymentGateway gateway;
  late SupplierPaymentController c;
  SupplierPaymentController controller({TenantContext context = scope}) =>
      SupplierPaymentController(
        scope: context,
        gateway: gateway,
        references: gateway,
        drafts: drafts,
        online: true,
        canPost: true,
        canApprove: true,
        canAllocate: true,
        canReverse: true,
      );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = PaymentGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.create();
    c.chooseSupplier({'id': 'supplier', 'name': 'Office Supplies Lanka'});
    c.chooseBank({
      'id': 'bank',
      'name': 'Operating bank · LKR',
      'currency_code': 'LKR',
    });
    c.update('document_date', '2026-09-30');
    c.addItem({
      'id': 'bill',
      'document_number': 'SB-0042',
      'kind': 'bill',
      'due_date': '2026-09-30',
      'currency_code': 'LKR',
      'residual': {'amount': '295.300000'},
    });
    c.amount('bill', '100.00');
  }

  test(
    'exact partial allocation survives uncertain restart with same command',
    () async {
      await draft();
      await c.saveServer();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      c.amount('bill', '2');
      expect((c.form!['lines'] as List).single['amount'], '100.00');
      gateway.uncertain = false;
      await c.saveServer();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
    },
  );
  test(
    'recording retries the payment RPC and immutable reference after restart',
    () async {
      await c.initialize();
      c.select({
        'id': 'payment',
        'status': 'approved',
        'version': 3,
        'total': '100.00',
      });
      await c.action('post', reference: 'BANK-0042');
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      gateway.uncertain = false;
      await c.saveServer();
      expect(gateway.operations, ['post', 'post']);
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.showingPayments, isTrue);
    },
  );
  test('editor cannot approve their own payment proposal', () async {
    await c.initialize();
    c.select({
      'id': 'payment',
      'status': 'pending_approval',
      'version': 2,
      'created_by': 'other',
      'prepared_by': 'a',
    });
    await c.action('approve');
    expect(gateway.commands, isEmpty);
  });
  test(
    'invalid precision and zero net payment never enter transport',
    () async {
      await draft();
      c.amount('bill', '0.0000001');
      await c.saveServer();
      expect(gateway.commands, isEmpty);
      c.amount('bill', '100');
      c.addItem({
        'id': 'credit',
        'document_number': 'DN-1',
        'kind': 'credit',
        'due_date': '2026-09-30',
        'currency_code': 'LKR',
        'residual': {'amount': '-100'},
      });
      expect(c.proposedTotal, '0.000000');
      await c.saveServer();
      expect(gateway.commands, isEmpty);
    },
  );
  test('exact totals above binary integer precision retain cents', () async {
    await draft();
    c.amount('bill', '90071992547409.91');
    c.addItem({
      'id': 'credit',
      'document_number': 'DN-1',
      'kind': 'credit',
      'due_date': '2026-09-30',
      'currency_code': 'LKR',
      'residual': {'amount': '-0.01'},
    });
    expect(c.proposedTotal, '90071992547409.900000');
  });
  test('another branch cannot recover pending payment command', () async {
    await draft();
    await c.saveServer();
    c.dispose();
    c = controller(
      context: const TenantContext(
        tenantId: 't',
        actorId: 'a',
        legalEntityId: 'e',
        branchId: 'other',
      ),
    );
    await c.initialize();
    expect(c.form, isNull);
    expect(c.local, isNull);
  });
  test('post success remains distinct from register refresh failure', () async {
    await draft();
    gateway.uncertain = false;
    gateway.failRefresh = true;
    await c.saveServer();
    expect(c.form, isNull);
    expect(c.error, contains('Saved successfully'));
  });
  test('allocation retry preserves exact reopened-credit command', () async {
    await c.initialize();
    await c.inspectItem('payment-item');
    await c.beginAllocation();
    c.update('posting_date', '2026-09-14');
    c.update('reason', 'Correct allocation');
    c.update('target_open_item_id', 'bill');
    c.update('transaction_amount', '100');
    await c.saveServer();
    final original = jsonEncode(gateway.commands.single.toJson((p) => p));
    c.dispose();
    c = controller();
    await c.initialize();
    gateway.uncertain = false;
    await c.saveServer();
    expect(gateway.operations, ['allocate', 'allocate']);
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
  });
  test('reversal retry retains linked allocation and reason', () async {
    await c.initialize();
    await c.reverseAllocation(
      {'id': 'allocation'},
      date: '2026-09-14',
      reason: 'Correct supplier bill',
    );
    await c.saveServer();
    final original = jsonEncode(gateway.commands.single.toJson((p) => p));
    c.dispose();
    c = controller();
    await c.initialize();
    gateway.uncertain = false;
    await c.saveServer();
    expect(gateway.operations, ['reverse', 'reverse']);
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'allocation correction ${dark ? 'dark' : 'light'} remains usable at 200 percent',
      (tester) async {
        await tester.runAsync(() async {
          await c.initialize();
          await c.inspectItem('payment-item');
          await c.beginAllocation();
        });
        c.update('_source_number', 'PAY-0042');
        c.update('posting_date', '2026-09-14');
        c.update('reason', 'Apply remaining supplier credit');
        c.update('target_open_item_id', 'bill');
        c.update('_target_number', 'SB-0042');
        c.update('_target_currency', 'LKR');
        c.update('transaction_amount', '100');
        tester.view.physicalSize = const Size(1024, 1300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: SupplierPaymentWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/supplier_allocation_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(find.text('Record allocation correction'));
        await tester.pumpAndSettle();
        expect(
          find.text('Record allocation correction').hitTestable(),
          findsOneWidget,
        );
      },
    );
    testWidgets(
      'dated AP statement ${dark ? 'dark' : 'light'} retains exact aging',
      (tester) async {
        await tester.runAsync(() async {
          await c.initialize();
          await c.loadStatement(
            supplierId: 'supplier',
            supplierName: 'Office Supplies Lanka',
            currency: 'LKR',
            asOf: '2026-09-14',
            buckets: [7, 14, 30],
          );
        });
        c.statementReport = {
          ...c.statementReport!,
          'open_amount': '20.000000',
          'open_base_amount': '20.000000',
          'aging': [
            {'bucket': 2, 'amount': '20.000000', 'base_amount': '20.000000'},
          ],
          'rows': [
            {
              'document_number': 'SB-0042',
              'source_type': 'supplier_bill',
              'posting_date': '2026-09-01',
              'due_date': '2026-09-01',
              'open_amount': '20.000000',
              'open_base_amount': '20.000000',
            },
          ],
        };
        tester.view.physicalSize = const Size(1024, 1300);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? JentraTheme.dark() : JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(body: SupplierPaymentWorkspace(controller: c)),
            ),
          ),
        );
        await tester.tap(find.text('Supplier statement and AP aging'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('8–14 days'), findsOneWidget);
        await tester.ensureVisible(
          find.text('Open 20.000000 · Base 20.000000'),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/supplier_statement_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
    testWidgets('payment proposal ${dark ? 'dark' : 'light'} at 200 percent', (
      tester,
    ) async {
      await tester.runAsync(draft);
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
            child: Scaffold(body: SupplierPaymentWorkspace(controller: c)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/supplier_payment_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
      await tester.ensureVisible(find.text('Save proposal'));
      await tester.pumpAndSettle();
      expect(find.text('Save proposal').hitTestable(), findsOneWidget);
    });
  }
}
