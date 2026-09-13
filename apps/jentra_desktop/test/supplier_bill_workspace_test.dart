import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_bill_screen.dart';
import 'support/procurement_fakes.dart';

class BillGateway extends Gateway implements SupplierBillGateway {
  final operations = <String>[];
  @override
  Future<CursorPage<Map<String, Object?>>> bills(
    TenantContext scope, {
    String? after,
  }) => rfqs(scope, after: after);
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
  Future<Map<String, Object?>> saveBill(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('save', command);
  @override
  Future<Map<String, Object?>> saveBillControls(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('controls', command);
  @override
  Future<Map<String, Object?>> billAction(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) => send(action, command);
}

void main() {
  setUpAll(() async {
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
  late BillGateway gateway;
  late SupplierBillController c;
  SupplierBillController controller() => SupplierBillController(
    scope: scope,
    gateway: gateway,
    references: gateway,
    drafts: drafts,
    online: true,
    canPost: true,
    canApprove: true,
    canSetup: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = BillGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.create(
      receipt: {
        'receipt_line_id': 'receipt-line',
        'supplier_id': 'supplier',
        'description': 'Office paper · carton',
        'currency_code': 'LKR',
        'available_quantity': '0.45',
        'source_snapshot': {
          'unit_price': '123.456789',
          'discount_percent': '10',
          'tax_definition_id': null,
        },
      },
    );
    c.update('document_date', '2026-09-14');
    c.update('due_date', '2026-10-14');
    c.update('supplier_reference', 'INV-0042');
    c.update('_supplier_name', 'Office Supplies Lanka');
  }

  test('exact bill draft and source survive uncertain restart', () async {
    await draft();
    await c.saveServer();
    final original = jsonEncode(gateway.commands.single.toJson((p) => p));
    c.dispose();
    c = controller();
    await c.initialize();
    c.update('supplier_reference', 'changed');
    expect(c.form!['supplier_reference'], 'INV-0042');
    gateway.uncertain = false;
    await c.saveServer();
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
    expect(
      (gateway.commands.last.payload['lines'] as List).single,
      isNot(contains('_supplier_name')),
    );
    expect(c.form, isNull);
  });
  test(
    'posting recovery retries the post RPC instead of saving a new draft',
    () async {
      await c.initialize();
      c.select({
        'id': 'bill',
        'status': 'draft',
        'version': 1,
        'supplier_reference': 'INV-0042',
        'created_by': 'a',
      });
      await c.action('post');
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      gateway.uncertain = false;
      await c.saveServer();
      expect(gateway.operations, ['post', 'post']);
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
    },
  );
  test('bill editor cannot approve their own matching exception', () async {
    await c.initialize();
    c.select({
      'id': 'bill',
      'status': 'draft',
      'version': 1,
      'created_by': 'other',
      'updated_by': 'a',
    });
    await c.action('approve', reason: 'Approve own edit');
    expect(gateway.commands, isEmpty);
  });
  test('malformed financial inputs never enter transport', () async {
    await draft();
    final id = ((c.form!['lines'] as List).single as Map)['line_id'] as String;
    c.updateLine(id, 'unit_price', 0.1);
    await c.saveServer();
    expect(gateway.commands, isEmpty);
    expect(c.error, contains('exact'));
  });
  for (final dark in [false, true]) {
    testWidgets(
      'supplier bill ${dark ? 'dark' : 'light'} at 200% retains match controls',
      (tester) async {
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
              child: Scaffold(body: SupplierBillWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/supplier_bill_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(find.text('Save and match bill'));
        await tester.pumpAndSettle();
        expect(find.text('Save and match bill').hitTestable(), findsOneWidget);
      },
    );
  }
}
