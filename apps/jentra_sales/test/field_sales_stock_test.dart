import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/field_sales_stock.dart';
import 'package:jentra_sales/src/ui/components.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';

import 'support/field_sales_fixture.dart';

FieldSalesJson product(
  String state, [
  Map<String, String> warehouses = const {},
  Object? asOf = '2026-11-17T08:05:00+00:00',
]) => {
  'policy_id': 'policy',
  'stock_state': state,
  'stock_by_warehouse': [
    for (final w in warehouses.entries)
      {'warehouse_id': w.key, 'state': w.value},
  ],
  'stock_as_of': asOf,
};

void main() {
  test('the selected warehouse decides the state', () {
    final p = product('in_stock', {'a': 'in_stock', 'b': 'out_of_stock'});
    expect(fieldStockState(p, 'a'), FieldStockState.inStock);
    expect(fieldStockState(p, 'b'), FieldStockState.outOfStock);
    // No warehouse chosen yet: in stock somewhere in the branch.
    expect(fieldStockState(p, null), FieldStockState.inStock);
  });

  test('untracked products stay untracked for every warehouse', () {
    final p = product('not_tracked');
    expect(fieldStockState(p, null), FieldStockState.notTracked);
    expect(fieldStockState(p, 'a'), FieldStockState.notTracked);
  });

  test('anything the app does not recognise is unknown, never in stock', () {
    expect(
      fieldStockState(product('unavailable'), null),
      FieldStockState.unknown,
    );
    expect(fieldStockState(product('plenty'), 'a'), FieldStockState.unknown);
    expect(fieldStockState({'policy_id': 'p'}, 'a'), FieldStockState.unknown);
    expect(
      fieldStockState(product('in_stock', {'a': 'in_stock'}), 'missing'),
      FieldStockState.unknown,
    );
    expect(
      fieldStockState({
        'stock_state': 'in_stock',
        'stock_by_warehouse': 'broken',
      }, 'a'),
      FieldStockState.unknown,
    );
  });

  test('every state has plain words', () {
    expect(fieldStockLabel(FieldStockState.inStock), 'In stock');
    expect(fieldStockLabel(FieldStockState.outOfStock), 'Out of stock');
    expect(fieldStockLabel(FieldStockState.notTracked), 'Stock not tracked');
    expect(fieldStockLabel(FieldStockState.unknown), 'Stock not known');
  });

  test('the note gives the time read and says nothing is reserved', () {
    final local = DateTime.parse('2026-11-17T08:05:00+00:00').toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    expect(
      fieldStockNote([product('in_stock')]),
      'Stock checked at $time. It is a guide only: nothing is reserved.',
    );
  });

  test('without a usable time the note says stock is not known', () {
    for (final products in [
      <FieldSalesJson>[],
      [product('unavailable')],
      [product('in_stock', const {}, null)],
      [product('in_stock', const {}, 'not a time')],
    ]) {
      expect(
        fieldStockNote(products),
        'Stock availability is not known right now.',
      );
    }
  });

  testWidgets('the order form shows availability for the chosen warehouse', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeFieldSalesGateway()
      ..stock = {
        'stock_state': 'in_stock',
        'stock_by_warehouse': [
          {'warehouse_id': 'warehouse', 'state': 'out_of_stock'},
          {'warehouse_id': 'elsewhere', 'state': 'in_stock'},
        ],
        'stock_as_of': '2026-11-17T08:05:00+00:00',
      };
    final c = FieldSalesController(gateway: gateway, store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.open();
    await c.selectCustomer('customer');
    await tester.pumpWidget(
      MaterialApp(
        theme: salesTheme(Brightness.light),
        home: FieldSalesWorkspace(c, onLeave: () async {}),
      ),
    );
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Stock checked at'), findsOneWidget);
    expect(find.textContaining('currently unavailable'), findsNothing);
    expect(find.text('In stock'), findsOneWidget);
    await tester.tap(find.text('Fulfilment warehouse'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approved Warehouse').last);
    await tester.pumpAndSettle();
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('In stock'), findsNothing);
    expect(find.textContaining('may not be able to supply'), findsNothing);
    await tester.ensureVisible(find.text('Add product'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Out of stock in this warehouse. Your company may not be able to supply this line on time.',
      ),
      findsOneWidget,
    );
    expect(gateway.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    c.clear();
  });
}
