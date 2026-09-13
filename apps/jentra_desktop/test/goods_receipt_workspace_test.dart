import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_controller.dart';
import 'package:jentra_desktop/src/features/procurement/goods_receipt_screen.dart';
import 'support/procurement_fakes.dart';

class ReceiptGateway extends Gateway
    implements GoodsReceiptGateway, ReceiptAllowanceGateway {
  final operations = <String>[];
  @override
  Future<Map<String, Object?>> approveReceiptAllowance(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('allowance', command);
  @override
  Future<CursorPage<Map<String, Object?>>> receipts(
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
      'id': command.payload['id'] ?? command.payload['document_id'],
      'status': operation == 'reverse' ? 'reversed' : 'posted',
      'version': 1,
    };
  }

  @override
  Future<Map<String, Object?>> postReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('post', command);
  @override
  Future<Map<String, Object?>> reverseReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('reverse', command);
  @override
  Future<Map<String, Object?>> saveReceiptControls(
    CommandEnvelope<Map<String, Object?>> command,
  ) => send('controls', command);
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
  late ReceiptGateway gateway;
  late GoodsReceiptController c;
  GoodsReceiptController controller() => GoodsReceiptController(
    scope: scope,
    gateway: gateway,
    references: gateway,
    drafts: drafts,
    online: true,
    canSetup: true,
    canApprove: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = ReceiptGateway();
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> draft() async {
    await c.initialize();
    await c.create({
      'id': 'order',
      'status': 'approved',
      'version': 3,
      'document_number': 'PO-0007',
      'warehouse_id': 'warehouse',
      'lines': [
        {
          'line_id': 'order-line',
          'description': 'Office paper · carton',
          'remaining_quantity': '0.5',
          'conversion_numerator': '12',
          'conversion_denominator': '1',
          '_tracking_mode': 'lot',
        },
      ],
    });
    c.update('document_date', '2026-09-13');
    c.update('reference', 'Delivery note 0042');
    final id = ((c.form!['lines'] as List).single as Map)['line_id'] as String;
    c.updateLine(id, 'accepted_quantity', '0.25');
    c.updateLine(id, 'rejected_quantity', '0.1');
    c.updateLine(id, 'rejection_reason', 'Damaged packaging');
    c.updateLine(id, 'lot_code', 'PAPER-2026-09');
  }

  test(
    'uncertain posting survives restart with exact quantities and the same source version',
    () async {
      await draft();
      await c.saveServer();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      expect(gateway.commands.single.expectedEntityVersion, 3);
      expect(
        (gateway.commands.single.payload['lines'] as List).single,
        isNot(contains('_tracking_mode')),
      );
      c.dispose();
      c = controller();
      await c.initialize();
      c.update('reference', 'changed');
      expect(c.form!['reference'], 'Delivery note 0042');
      gateway.uncertain = false;
      await c.saveServer();
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(gateway.operations, ['post', 'post']);
      expect(c.form, isNull);
    },
  );
  test(
    'over receipt and unexplained rejection fail before sealing a command',
    () async {
      await draft();
      final id =
          ((c.form!['lines'] as List).single as Map)['line_id'] as String;
      c.updateLine(id, 'accepted_quantity', '0.6');
      await c.saveServer();
      expect(gateway.commands, isEmpty);
      expect(c.error, contains('remaining'));
      c.updateLine(id, 'accepted_quantity', '0.25');
      c.updateLine(id, 'rejection_reason', '');
      await c.saveServer();
      expect(gateway.commands, isEmpty);
      expect(c.error, contains('rejected'));
    },
  );
  test(
    'reversal retry retains lifecycle operation after controller restart',
    () async {
      await c.initialize();
      c.select({
        'id': 'receipt',
        'version': 1,
        'status': 'posted',
        'lines': [],
      });
      await c.reverse('2026-09-14', 'Wrong delivery');
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      gateway.uncertain = false;
      await c.saveServer();
      expect(gateway.operations, ['reverse', 'reverse']);
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.selected!['status'], 'reversed');
    },
  );
  test('offline exit saves draft without a server write', () async {
    await draft();
    c.setOnline(false);
    expect(await c.canLeave(), isTrue);
    expect(gateway.commands, isEmpty);
    c.dispose();
    c = controller();
    await c.initialize();
    expect(c.form!['reference'], 'Delivery note 0042');
  });
  test(
    'allowance approval retains its exact operation after uncertain restart',
    () async {
      await c.initialize();
      await c.createAllowance({
        'id': 'order',
        'version': 3,
        'status': 'approved',
        'document_number': 'PO-0007',
        'created_by': 'other',
        'lines': [],
      });
      c.update('order_line_id', 'line');
      c.update('extra_quantity', '0.000001');
      c.update('reason', 'Pack-size variance');
      await c.saveServer();
      final original = jsonEncode(gateway.commands.single.toJson((p) => p));
      c.dispose();
      c = controller();
      await c.initialize();
      gateway.uncertain = false;
      await c.saveServer();
      expect(gateway.operations, ['allowance', 'allowance']);
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), original);
      expect(c.form, isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'goods receipt ${dark ? 'dark' : 'light'} at 200% preserves posting controls',
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
              child: Scaffold(body: GoodsReceiptWorkspace(controller: c)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/goods_receipt_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
        await tester.ensureVisible(find.text('Post goods receipt'));
        await tester.pumpAndSettle();
        expect(find.text('Post goods receipt').hitTestable(), findsOneWidget);
      },
    );
  }
}
