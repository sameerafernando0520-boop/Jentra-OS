import 'dart:async';

import 'package:flutter/material.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';
import 'package:jentra_sales/src/ui/components.dart';

import 'support/field_sales_fixture.dart';

void main() {
  testWidgets('delayed catalogue restores every protected draft quantity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeFieldSalesGateway();
    final c = FieldSalesController(gateway: gateway, store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.open();
    await c.selectCustomer('customer');
    final products = <FieldSalesJson>[
      ...c.products,
      {
        ...c.products.first,
        'policy_id': 'second-policy',
        'name': 'Second Product',
      },
    ];
    expect(
      await c.saveDraft({
        ...fieldInput,
        'notes': 'Preserved delivery note',
        'lines': [
          ...fieldInput['lines'] as List,
          {
            'policy_id': 'second-policy',
            'policy_version': '1',
            'quantity': '2.5',
          },
        ],
      }),
      isTrue,
    );
    // Reopen as a genuine restored workspace: select through the rendered UI.
    await c.selectScope(fieldScope);
    gateway.catalogueWait = Completer<List<FieldSalesJson>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: salesTheme(Brightness.light),
        home: FieldSalesWorkspace(c, onLeave: () async {}),
      ),
    );
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assigned customer with no transactions'));
    await tester.pump();
    expect(c.busy, isTrue);
    gateway.catalogueWait!.complete(products);
    await tester.pumpAndSettle();
    for (final (label, expected) in [
      ('Quantity · Governed Product', '1.125'),
      ('Quantity · Second Product', '2.5'),
      ('Order notes', 'Preserved delivery note'),
    ]) {
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label,
      );
      expect(field, findsOneWidget, reason: label);
      await tester.ensureVisible(field);
      expect(tester.widget<TextField>(field).controller!.text, expected);
    }
    expect(gateway.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    c.clear();
  });

  testWidgets(
    'dirty navigation preserves edits and saved drafts never auto-submit',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeFieldSalesGateway();
      final store = MemorySalesStore();
      final c = FieldSalesController(gateway: gateway, store: store);
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
      final notes = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Order notes',
      );
      await tester.ensureVisible(notes);
      await tester.enterText(notes, 'Unsaved customer note');
      await tester.pump();
      await c.preview(fieldInput);
      await tester.pump();
      expect(c.review, isNotNull);
      await tester.tap(find.text('Orders').last);
      await tester.pumpAndSettle();
      expect(find.text('Keep your order changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved customer note'), findsOneWidget);
      await tester.tap(find.text('Orders').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save local draft'));
      await tester.pumpAndSettle();
      expect(c.savedDraft!['notes'], 'Unsaved customer note');
      expect(c.review, isNull);
      expect(gateway.commands, isEmpty);
      expect(find.text('No submitted requests'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.clear();
    },
  );
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets(
      'governed portfolio and composer adapt at $width with 200% text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = FieldSalesController(
          gateway: FakeFieldSalesGateway(),
          store: MemorySalesStore(),
        );
        addTearDown(c.dispose);
        await c.open();
        await c.selectCustomer('customer');
        await tester.pumpWidget(
          MaterialApp(
            theme: salesTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: FieldSalesWorkspace(c, onLeave: () async {}),
          ),
        );
        await tester.tap(find.text('Customers').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Assigned customer with no transactions'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(
          find.text('Prepare a governed order'),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Review current company terms'),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        c.clear();
      },
    );
  }
}
