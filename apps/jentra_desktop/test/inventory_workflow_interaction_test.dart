import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_controller.dart';
import 'package:jentra_desktop/src/features/stock_count/stock_count_screen.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_controller.dart';
import 'package:jentra_desktop/src/features/disposition/disposition_screen.dart';

import 'stock_count_workspace_test.dart' show Counts;
import 'disposition_workspace_test.dart' show Dispositions;
import 'report_workflow_interaction_test.dart' show finish, press, field;
import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> fixtureOptions(String resource, {String mode = 'none'}) =>
    {
      'items': [
        switch (resource) {
          'warehouses' => {'id': 'w', 'name': 'Synthetic warehouse'},
          'accounts' => {
            'id': 'expense',
            'name': 'Synthetic variance',
            'code': '5900',
          },
          'lots' => {'id': 'lot', 'name': 'Held lot', 'code': 'LOT-1'},
          _ => {
            'id': 'p',
            'name': 'Synthetic paper',
            'sku': 'P-1',
            'base_unit_id': 'unit',
            'tracking_mode': mode,
            'on_hand_quantity': '10.000000',
          },
        },
        if (resource == 'serials') ...[
          for (final code in ['SER-1', 'SER-2'])
            {'id': code, 'code': code, 'status': 'held', 'lot_id': 'lot'},
        ],
      ],
    };

class CountWorkflow extends Counts {
  @override
  Future<Map<String, Object?>> options(
    TenantContext s,
    String r, {
    String? warehouse,
    String? after,
    String search = '',
  }) async => optionsPage(r);
  Map<String, Object?> optionsPage(String r) => fixtureOptions(r);
  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await super.execute(verb, command);
    return detailResult = {
      ...result,
      'status': verb == 'cancel' ? 'cancelled' : result['status'],
    };
  }
}

class DispositionWorkflow extends Dispositions {
  DispositionWorkflow(this.mode);
  final String mode;
  final verbs = <String>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext s,
    String r, {
    String? warehouse,
    String? product,
    String? after,
  }) async => optionsPage(r);
  Map<String, Object?> optionsPage(String r) => fixtureOptions(r, mode: mode);
  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    verbs.add(verb);
    final result = await super.execute(verb, command);
    return {
      ...result,
      'status': switch (verb) {
        'submit' => 'pending_approval',
        'cancel' => 'cancelled',
        _ => 'draft',
      },
    };
  }
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
  late QuotationDraftStore drafts;
  final controllers = <ChangeNotifier>[];
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await db.close();
  });
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1600, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> pick(
    WidgetTester tester,
    String button,
    String choice,
    bool Function() busy,
  ) async {
    await press(tester, find.widgetWithText(OutlinedButton, button), busy);
    await press(tester, find.widgetWithText(ListTile, choice), busy);
  }

  testWidgets(
    'count captures cutoff before micro-unit editing and retains uncertain original save',
    (tester) async {
      final gateway = CountWorkflow();
      final c = StockCountController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
        permissions: {'inventory.adjustments.post', 'inventory.cost.view'},
      );
      controllers.add(c);
      await tester.runAsync(c.initialize);
      await mount(tester, StockCountWorkspace(controller: c));
      await press(
        tester,
        find.widgetWithText(FilledButton, 'New count'),
        () => c.busy,
      );
      await tester.enterText(field('Posting date (YYYY-MM-DD)'), '2026-09-30');
      await tester.enterText(field('Count reason'), ' Verify cutoff units ');
      await pick(
        tester,
        'Warehouse: Select',
        'Synthetic warehouse',
        () => c.busy,
      );
      await pick(
        tester,
        'Variance account: Select',
        'Synthetic variance',
        () => c.busy,
      );
      await pick(tester, 'Add product', 'Synthetic paper', () => c.busy);
      expect(
        tester
            .widget<TextFormField>(field('Counted quantity in base units'))
            .enabled,
        false,
      );
      await press(
        tester,
        find.widgetWithText(TextButton, 'Remove product'),
        () => c.busy,
      );
      expect(c.form!['lines'], isEmpty);
      await pick(tester, 'Add product', 'Synthetic paper', () => c.busy);
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Capture cutoff'),
        () => c.busy,
      );
      expect(gateway.commands.single.payload['capture_only'], true);
      expect(c.form!['cutoff_at'], '2026-09-15T20:00:00Z');
      expect(c.form!['version'], 1);
      await tester.enterText(
        field('Counted quantity in base units'),
        '9.999999',
      );
      await tester.enterText(
        field('Unit cost for a positive adjustment into empty stock'),
        '0.000001',
      );
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'Save locally'),
        () => c.busy,
      );
      expect(gateway.commands, hasLength(1));
      gateway.uncertain = true;
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Save count'),
        () => c.busy,
      );
      final original = gateway.commands.last.toJson((v) => v);
      expect(gateway.commands.last.expectedEntityVersion, 1);
      expect(
        (gateway.commands.last.payload['lines'] as List)
            .single['counted_quantity'],
        '9.999999',
      );
      expect(
        (gateway.commands.last.payload['lines'] as List)
            .single['empty_unit_cost'],
        '0.000001',
      );
      expect(c.local!.pending, isNotNull);
      gateway.uncertain = false;
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Retry saved action'),
        () => c.busy,
      );
      expect(gateway.commands.last.toJson((v) => v), original);
      expect(c.local!.pending, isNull);
      expect(c.form!['version'], 2);
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'Cancel count'),
        () => c.busy,
      );
      await press(
        tester,
        find.widgetWithText(TextButton, 'Back'),
        () => c.busy,
      );
      expect(gateway.verbs.last, 'save');
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'Cancel count'),
        () => c.busy,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason'),
        'Count duplicated',
      );
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Confirm'),
        () => c.busy,
      );
      expect(gateway.verbs.last, 'cancel');
      expect(gateway.commands.last.payload['note'], 'Count duplicated');
      await press(
        tester,
        find.widgetWithText(TextButton, 'Discard local copy / close'),
        () => c.busy,
      );
      expect(c.form, isNull);
    },
  );

  for (final mode in ['none', 'lot', 'serial']) {
    testWidgets(
      '$mode disposition selects held identity and retries exact governed preview',
      (tester) async {
        final gateway = DispositionWorkflow(mode);
        final c = DispositionController(
          scope: scope,
          gateway: gateway,
          drafts: drafts,
          online: true,
          permissions: {'inventory.dispositions.post', 'inventory.cost.view'},
        );
        controllers.add(c);
        await tester.runAsync(c.initialize);
        await mount(tester, DispositionWorkspace(controller: c));
        await press(
          tester,
          find.widgetWithText(FilledButton, 'New disposition'),
          () => c.busy,
        );
        await tester.enterText(
          field('Posting date (YYYY-MM-DD)'),
          '2026-09-30',
        );
        await tester.enterText(
          field('Disposition reason'),
          'Dispose quarantined paper',
        );
        await pick(
          tester,
          'Warehouse: Select',
          'Synthetic warehouse',
          () => c.busy,
        );
        await pick(
          tester,
          'Variance account: Select',
          'Synthetic variance',
          () => c.busy,
        );
        await pick(tester, 'Add held product', 'Synthetic paper', () => c.busy);
        await press(
          tester,
          find.widgetWithText(TextButton, 'Remove line'),
          () => c.busy,
        );
        expect(c.form!['lines'], isEmpty);
        await pick(tester, 'Add held product', 'Synthetic paper', () => c.busy);
        if (mode != 'serial') {
          await tester.enterText(field('Quantity in base units'), '0.000001');
        } else {
          expect(
            tester
                .widget<TextFormField>(field('Quantity in base units'))
                .enabled,
            false,
          );
          await press(
            tester,
            find.widgetWithText(OutlinedButton, 'Select held serials'),
            () => c.busy,
          );
          for (final code in ['SER-1', 'SER-2', 'SER-1', 'SER-1']) {
            await tester.tap(
              find.widgetWithText(CheckboxListTile, '$code · held'),
            );
            await tester.pumpAndSettle();
          }
          await press(
            tester,
            find.widgetWithText(FilledButton, 'Use 2 serials'),
            () => c.busy,
          );
          expect((c.form!['lines'] as List).single['serial_ids'], [
            'SER-2',
            'SER-1',
          ]);
        }
        if (mode == 'lot') {
          await pick(tester, 'Held lot: Select', 'Held lot', () => c.busy);
        }
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'Save locally'),
          () => c.busy,
        );
        expect(gateway.commands, isEmpty);
        gateway.uncertain = true;
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Save exact preview'),
          () => c.busy,
        );
        final original = gateway.commands.single.toJson((v) => v);
        final line =
            (gateway.commands.single.payload['lines'] as List).single as Map;
        expect(line['quantity'], mode == 'serial' ? '2' : '0.000001');
        expect(line['product_id'], 'p');
        expect(line['lot_id'], mode == 'none' ? null : 'lot');
        expect(line.containsKey('carrying_value'), false);
        gateway.uncertain = false;
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Retry saved action'),
          () => c.busy,
        );
        expect(gateway.commands.last.toJson((v) => v), original);
        expect(c.form!['grand_total'], '30.037037');
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'Submit for approval'),
          () => c.busy,
        );
        expect(gateway.verbs.last, 'submit');
        expect(gateway.commands.last.expectedEntityVersion, 1);
        expect(c.form!['status'], 'pending_approval');
        expect(
          find.widgetWithText(FilledButton, 'Approve disposition'),
          findsNothing,
        );
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'Recall for revision'),
          () => c.busy,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Reason'),
          'Correct held quantity',
        );
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Confirm'),
          () => c.busy,
        );
        expect(gateway.verbs.last, 'recall');
        expect(gateway.commands.last.payload['note'], 'Correct held quantity');
        await press(
          tester,
          find.widgetWithText(TextButton, 'Discard local copy / close'),
          () => c.busy,
        );
        expect(c.form, isNull);
        await finish(tester, () => c.busy);
      },
    );
  }
}
