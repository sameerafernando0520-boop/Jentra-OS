import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_controller.dart';
import 'package:jentra_desktop/src/features/inventory_transfer/inventory_transfer_screen.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';

import 'inventory_transfer_workspace_test.dart' show Transfers;
import 'support/procurement_fakes.dart' show Keys;

Map<String, Object?> transit() => {
  'id': 'existing',
  'version': 7,
  'status': 'in_transit',
  'reference': 'TR-7',
  'document_date': '2026-09-30',
  'source_warehouse_name': 'Source warehouse',
  'destination_warehouse_name': 'Destination warehouse',
  'lines': [
    {
      'product_name': 'Paper lot',
      'base_quantity': '0.000003',
      'quantity': '0.000002',
      'carrying_value': '9007199254.740993',
    },
  ],
  'events': [
    {
      'operation': 'dispatch',
      'posting_date': '2026-09-30',
      'reason': 'Source dispatch',
      'request_id': 'original-request',
    },
  ],
};

class InteractiveTransfers extends Transfers {
  String tracking = 'lot';
  final optionsCalls = <(String, String?, String?)>[];
  final holdingsCalls = <(String, String?)>[];
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async => {
    'items': after == null ? [transit()] : [],
    'next_cursor': after == null ? 'transfer-cursor' : null,
  };
  @override
  Future<Map<String, Object?>> holdings(
    TenantContext scope,
    String asOf, {
    String? after,
  }) async {
    holdingsCalls.add((asOf, after));
    return {
      'as_of': asOf,
      'items': after == null
          ? [
              {...transit(), 'currency_code': 'LKR'},
            ]
          : [],
      'next_cursor': after == null ? 'holding-cursor' : null,
    };
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
    String search = '',
  }) async {
    optionsCalls.add((resource, warehouse, product));
    return {
      'items': resource == 'warehouses'
          ? [
              {'id': 'source', 'name': 'Source warehouse', 'branch_id': 'b'},
              {
                'id': 'destination',
                'name': 'Destination warehouse',
                'branch_id': 'other',
              },
            ]
          : resource == 'products'
          ? [
              {
                'id': 'paper',
                'name': 'Paper lot',
                'base_unit_id': 'each',
                'tracking_mode': tracking,
                'units': [
                  {
                    'id': 'each',
                    'name': 'Each',
                    'numerator': '1',
                    'denominator': '1',
                  },
                  {
                    'id': 'pack',
                    'name': 'Pack',
                    'numerator': '3',
                    'denominator': '2',
                  },
                ],
              },
            ]
          : resource == 'lots'
          ? [
              {'id': 'lot', 'code': 'LOT-42', 'available_quantity': '3'},
            ]
          : [
              {'id': 'serial', 'code': 'SERIAL-42', 'available_quantity': '1'},
            ],
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
  late QuotationDraftStore store;
  late InteractiveTransfers gateway;
  late InventoryTransferController c;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = InteractiveTransfers()..uncertain = false;
    c = InventoryTransferController(
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
        home: Scaffold(body: InventoryTransferWorkspace(controller: c)),
      ),
    );
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

  Future<void> tap(WidgetTester tester, String text) async {
    final f = find.text(text).last;
    await tester.scrollUntilVisible(
      f,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> input(WidgetTester tester, String label, String value) async {
    final f = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(f);
    await tester.enterText(f, value);
    await tester.pump();
  }

  testWidgets(
    'immediate lot transfer chooses scoped warehouses and exact rational conversion with no copied money',
    (tester) async {
      await mount(tester);
      await tap(tester, 'New transfer');
      await settle(tester);
      await tap(tester, 'From: Select warehouse');
      expect(find.text('Destination warehouse'), findsNothing);
      await tap(tester, 'Source warehouse');
      await tap(tester, 'To: Select warehouse');
      await tap(tester, 'Destination warehouse');
      await input(tester, 'Transfer reference', 'TR-EXACT');
      await input(tester, 'Posting date (YYYY-MM-DD)', '2026-09-30');
      await input(tester, 'Reason', 'Exact stock replenishment');
      final method = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Transfer method',
      );
      await tester.ensureVisible(method);
      await tester.tap(method);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Immediate warehouse transfer').last);
      await tester.pumpAndSettle();
      await tap(tester, 'Add product');
      await tap(tester, 'Paper lot');
      await input(tester, 'Quantity', '0.000002');
      final unit = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Transaction unit',
      );
      await tester.ensureVisible(unit);
      await tester.tap(unit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pack (3/2)').last);
      await tester.pumpAndSettle();
      await tap(tester, 'Lot: Select lot');
      await tap(tester, 'LOT-42');
      expect((c.form!['lines'] as List).single['conversion_numerator'], '3');
      expect(gateway.optionsCalls.last, ('lots', 'source', 'paper'));
      await tap(tester, 'Save local draft');
      await settle(tester);
      final saved = await tester.runAsync(
        () => store.load(scope, InventoryTransferController.slot),
      );
      expect((saved!.form['lines'] as List).single['quantity'], '0.000002');
      await tap(tester, 'Post immediate transfer');
      await settle(tester);
      final command = gateway.commands.single;
      expect(command.context, scope);
      expect(command.payload['operation'], 'immediate');
      expect(command.payload['source_warehouse_id'], 'source');
      expect(command.payload['destination_warehouse_id'], 'destination');
      final line = (command.payload['lines'] as List).single as Map;
      expect(line['quantity'], '0.000002');
      expect(line['conversion_numerator'], '3');
      expect(line['conversion_denominator'], '2');
      expect(line['lot_id'], 'lot');
      expect(line.containsKey('product_name'), false);
      expect(line.containsKey('carrying_value'), false);
      expect(c.form, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'serial selection deduplicates removes and reselects before exact serial-count dispatch',
    (tester) async {
      gateway.tracking = 'serial';
      await mount(tester);
      await tap(tester, 'New transfer');
      await settle(tester);
      await tap(tester, 'From: Select warehouse');
      await tap(tester, 'Source warehouse');
      await tap(tester, 'To: Select warehouse');
      await tap(tester, 'Destination warehouse');
      await input(tester, 'Transfer reference', 'TR-SERIAL');
      await input(tester, 'Posting date (YYYY-MM-DD)', '2026-09-30');
      await input(tester, 'Reason', 'One traced serial');
      await tap(tester, 'Add product');
      await tap(tester, 'Paper lot');
      await tap(tester, 'Select serial');
      await tap(tester, 'SERIAL-42');
      await tap(tester, 'Select serial');
      await tap(tester, 'SERIAL-42');
      expect((c.form!['lines'] as List).single['serial_ids'], ['serial']);
      final remove = find
          .descendant(
            of: find.widgetWithText(InputChip, 'SERIAL-42'),
            matching: find.byType(Icon),
          )
          .last;
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect((c.form!['lines'] as List).single['serial_ids'], isEmpty);
      await tap(tester, 'Select serial');
      await tap(tester, 'SERIAL-42');
      await tap(tester, 'Dispatch shipment');
      await settle(tester);
      expect(
        (gateway.commands.single.payload['lines'] as List).single['serial_ids'],
        ['serial'],
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final operation in ['receive', 'reverse']) {
    testWidgets(
      '$operation uses original transfer version without historical output in recovered form',
      (tester) async {
        await mount(tester);
        await tap(tester, 'Movement history');
        expect(find.text('dispatch · 2026-09-30'), findsOneWidget);
        await tap(
          tester,
          operation == 'receive' ? 'Receive shipment' : 'Prepare reversal',
        );
        await settle(tester);
        expect(c.form!['version'], 7);
        expect(c.form!.containsKey('events'), false);
        expect(
          (c.form!['lines'] as List).single.containsKey('carrying_value'),
          false,
        );
        await input(tester, 'Reason', 'Verified warehouse correction');
        await tap(
          tester,
          operation == 'receive' ? 'Confirm receipt' : 'Post reasoned reversal',
        );
        await settle(tester);
        expect(gateway.commands.single.expectedEntityVersion, 7);
        expect(gateway.commands.single.payload['id'], 'existing');
        expect(gateway.commands.single.payload['operation'], operation);
        expect(gateway.commands.single.payload.containsKey('lines'), false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'dated transit report keeps original cutoff across paging and clears on disconnect',
    (tester) async {
      await mount(tester);
      await tap(tester, 'Dated stock in transit');
      await input(tester, 'As of posting date (YYYY-MM-DD)', '2026-09-30');
      await tap(tester, 'View holdings');
      await settle(tester);
      expect(find.textContaining('9007199254.740993'), findsOneWidget);
      await input(tester, 'As of posting date (YYYY-MM-DD)', '2026-10-01');
      await tap(tester, 'Load more holdings');
      await settle(tester);
      expect(gateway.holdingsCalls, [
        ('2026-09-30', null),
        ('2026-09-30', 'holding-cursor'),
      ]);
      await tap(tester, 'Load more transfers');
      await settle(tester);
      expect(c.cursor, isNull);
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('9007199254.740993'), findsNothing);
      expect(c.holdings, isEmpty);
      expect(c.loadedHoldingsDate, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'removing transfer line and discarding local form sends no command',
    (tester) async {
      await mount(tester);
      await tester.runAsync(c.create);
      c.addProduct({
        'id': 'paper',
        'name': 'Paper',
        'tracking_mode': 'none',
        'base_unit_id': 'each',
        'units': [
          {'id': 'each', 'name': 'Each', 'numerator': '1', 'denominator': '1'},
        ],
      });
      await tester.pumpAndSettle();
      await tap(tester, 'Remove line');
      expect(c.form!['lines'], isEmpty);
      await tap(tester, 'Discard draft');
      await settle(tester);
      expect(c.form, isNull);
      expect(gateway.commands, isEmpty);
    },
  );
}
