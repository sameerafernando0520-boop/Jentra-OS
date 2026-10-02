import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/landed_extension.dart';
import 'package:jentra_platform/landed_extension_platform.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_controller.dart';
import 'package:jentra_desktop/src/features/landed_extension/landed_extension_screen.dart';

import '../../../packages/jentra_domain/test/support/landed_extension_fixture.dart';
import 'landed_extension_workspace_test.dart' show Landed;
import 'support/procurement_fakes.dart' show Keys;

class LandedChoices extends Landed {
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async => {
    'items': switch (resource) {
      'accounts' => [
        {'id': landedAccount, 'code': 'FREIGHT', 'name': 'Recorded freight'},
      ],
      'receipts' => [
        {
          'id': landedReceipt,
          'document_number': 'GR-EXACT',
          'product_name': 'Recorded paper',
          'received_quantity': '3.000000',
          'warehouse_name': 'Main warehouse',
        },
      ],
      _ => <Map<String, Object?>>[],
    },
  };
}

void main() {
  const scope = TenantContext(
    tenantId: '10000000-0000-0000-0000-000000000001',
    legalEntityId: '10000000-0000-0000-0000-000000000002',
    branchId: '10000000-0000-0000-0000-000000000003',
    actorId: '10000000-0000-0000-0000-000000000004',
  );
  late JentraLocalDatabase db;
  late LandedChoices gateway;
  late LandedExtensionController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    gateway = LandedChoices()..uncertain = false;
    c = LandedExtensionController(
      scope: scope,
      gateway: gateway,
      drafts: LandedExtensionDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      ),
      online: true,
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LandedExtensionWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  testWidgets(
    'manual landed inputs preserve chosen receipts exact weights and charge through encrypted save',
    (tester) async {
      await tester.runAsync(() async {
        await c.initialize();
        await c.create();
      });
      await pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manual exact positive weights').last);
      await tester.pumpAndSettle();
      for (var i = 1; i <= 2; i++) {
        final account = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(account);
        await tester.tap(account);
        await tester.pumpAndSettle();
        await tester.tap(find.text('FREIGHT Recorded freight').last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      for (final entry in {
        'Reference': 'FREIGHT-EXACT',
        'Reason': 'Recorded charge',
        'Posting date (YYYY-MM-DD)': '2026-09-29',
        'Total landed charge': '9007199254740.123456',
        'Exact positive weight': '1.000001',
      }.entries) {
        await tester.ensureVisible(field(entry.key));
        await tester.enterText(field(entry.key), entry.value);
      }
      await tester.runAsync(c.save);
      expect(c.error, isNull);
      final local = await tester.runAsync(
        () => c.drafts.store.load(scope, c.id),
      );
      expect(local!.form['total_amount'], '9007199254740.123456');
      expect((local.form['receipts'] as List).single, {
        'receipt_line_id': landedReceipt,
        'weight': '1.000001',
      });
      expect(local.form['offset_account_id'], landedAccount);
      expect(gateway.commands, isEmpty);
      await tester.runAsync(c.calculate);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Held inventory 6004799503160.082304'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Consumed variance 3002399751580.041152'),
        findsOneWidget,
      );
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('6004799503160.082304'), findsNothing);
      expect(c.form!['total_amount'], '9007199254740.123456');
    },
  );
  testWidgets(
    'linked correction freezes receipt basis and accounts while keeping exact corrected charge editable',
    (tester) async {
      c.posted = {
        ...landedEvidence(),
        'id': landedId,
        'status': 'posted',
        'version': 1,
        'reference': 'FREIGHT-ORIGINAL',
        'reason': 'Original recorded charge',
      };
      await tester.runAsync(c.correction);
      await pump(tester);
      expect(
        find.textContaining(
          'Receipt identities, accounts and allocation weights remain frozen',
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.enterText(
        field('Corrected total amount'),
        '9007199254740.123455',
      );
      c.weight(landedReceipt, '999');
      c.update('offset_account_id', 'foreign');
      c.update('basis_mode', 'quantity');
      expect(c.form!['receipts'], isNull);
      expect(c.form!['offset_account_id'], isNull);
      expect(c.form!['basis_mode'], isNull);
      expect(c.form!['correction_of'], landedId);
      expect(c.form!['total_amount'], '9007199254740.123455');
      await tester.runAsync(c.save);
      expect(c.error, isNull);
      expect(gateway.commands, isEmpty);
    },
  );
}
