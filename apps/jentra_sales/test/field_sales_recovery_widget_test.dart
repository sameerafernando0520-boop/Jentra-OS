import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/ui/components.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';

import 'support/field_sales_fixture.dart';

Future<void> _pump(WidgetTester tester, FieldSalesController c) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: salesTheme(Brightness.light),
      home: FieldSalesWorkspace(c, onLeave: () async {}),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an expired submission can be cleared from the workspace', (
    tester,
  ) async {
    final gateway = FakeFieldSalesGateway();
    final store = MemorySalesStore();
    final old = FieldSalesCommand(
      actorId: 'rep',
      scope: fieldScope,
      commandId: 'command',
      key: 'key',
      at: DateTime.now()
          .subtract(const Duration(days: 2))
          .toUtc()
          .toIso8601String(),
      payload: {
        'id': 'request',
        'input': fieldInput,
        'source_digest': 'a' * 64,
      },
    );
    await store.write(
      'jentra.sales.command.v1.rep.${fieldScope.key}',
      jsonEncode(old.toJson()),
    );
    final c = FieldSalesController(gateway: gateway, store: store);
    addTearDown(c.dispose);
    await c.open();
    await _pump(tester, c);

    expect(find.text('Check your original submission'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear if not received'));
    await tester.tap(find.text('Clear if not received'));
    await tester.pumpAndSettle();

    expect(find.text('Check your original submission'), findsNothing);
    expect(find.textContaining('Nothing was ordered'), findsOneWidget);
    expect(c.pending, isNull);
    expect(gateway.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    c.clear();
  });

  testWidgets('a submission that can still be retried has no clear action', (
    tester,
  ) async {
    final gateway = FakeFieldSalesGateway();
    final c = FieldSalesController(gateway: gateway, store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.open();
    await c.selectCustomer('customer');
    await c.preview(fieldInput);
    gateway.submitFailure = const FieldSalesFailure(
      'OUTCOME_UNKNOWN',
      'No reply',
    );
    await c.submit();
    await _pump(tester, c);

    expect(find.text('Check your original submission'), findsOneWidget);
    expect(find.text('Clear if not received'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.clear();
  });

  testWidgets('the open order form offers its typed content for safekeeping', (
    tester,
  ) async {
    final gateway = FakeFieldSalesGateway();
    final c = FieldSalesController(gateway: gateway, store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.open();
    await c.selectCustomer('customer');
    await _pump(tester, c);
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();

    expect(c.unsavedOrder, isNotNull);
    expect(c.unsavedOrder!(), isNull, reason: 'nothing typed yet');
    final notes = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == 'Order notes',
    );
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Typed before expiry');
    await tester.pump();
    expect(c.unsavedOrder!()!['notes'], 'Typed before expiry');
    expect(c.unsavedOrder!()!['customer_id'], 'customer');

    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.unsavedOrder, isNull, reason: 'a closed form offers nothing');
    c.clear();
  });
}
