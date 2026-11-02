import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/sales_app.dart';
import 'package:jentra_sales/src/sales_controller.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/ui/order_editor.dart';

void main() {
  for (final width in [320.0, 360.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('preview pages reflow at $width pixels', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = SalesController(store: MemorySalesStore());
      addTearDown(c.dispose);
      await c.enterPreview();
      await tester.pumpWidget(SalesApp(controller: c));
      await tester.pumpAndSettle();
      for (final page in SalesPage.values) {
        c.go(page);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$page at $width');
      }
    });
  }
  testWidgets('phone pages and login support 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final c = SalesController(store: MemorySalesStore());
    addTearDown(c.dispose);
    await tester.pumpWidget(SalesApp(controller: c));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await c.enterPreview();
    await tester.pumpAndSettle();
    for (final page in SalesPage.values) {
      c.go(page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$page at 200 percent');
    }
  });
  testWidgets('preview is explicit and logout removes sample data', (
    tester,
  ) async {
    final c = SalesController(store: MemorySalesStore());
    addTearDown(c.dispose);
    await tester.pumpWidget(SalesApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Ceylon Home & Living'), findsNothing);
    await tester.ensureVisible(find.text('Explore the preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore the preview').hitTestable());
    await tester.pumpAndSettle();
    expect(c.preview, isTrue);
    expect(find.text('A good day to connect.'), findsOneWidget);
    await c.leave();
    await tester.pumpAndSettle();
    expect(c.customers, isEmpty);
    expect(find.text('Explore the preview'), findsOneWidget);
  });
  for (final width in [360.0, 1024.0]) {
    testWidgets('review and save an exact fractional order at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = SalesController(store: MemorySalesStore());
      addTearDown(c.dispose);
      await c.enterPreview();
      await tester.pumpWidget(SalesApp(controller: c));
      await tester.pumpAndSettle();
      openOrderEditor(
        tester.element(find.text('New order').first),
        c,
        customer: c.customers.first,
        product: c.products.first,
      );
      await tester.pumpAndSettle();
      final quantity = find.widgetWithText(TextFormField, 'Quantity · piece');
      await tester.ensureVisible(quantity);
      await tester.enterText(quantity, '1.125');
      await tester.ensureVisible(find.text('Review order'));
      await tester.tap(find.text('Review order').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Subtotal  LKR 1,406.25'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save local draft'));
      await tester.pumpAndSettle();
      expect(
        c.orders.where((o) => o.local).single.subtotal.toDecimalString(),
        '1406.25',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('dark tablet workspace has no layout exceptions', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = SalesController(store: MemorySalesStore());
    addTearDown(c.dispose);
    c.toggleTheme();
    await c.enterPreview();
    await tester.pumpWidget(SalesApp(controller: c));
    await tester.pumpAndSettle();
    for (final page in SalesPage.values) {
      c.go(page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Dark $page');
    }
  });
  testWidgets('dirty order cannot be closed without a discard choice', (
    tester,
  ) async {
    final c = SalesController(store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.enterPreview();
    await tester.pumpWidget(SalesApp(controller: c));
    await tester.pumpAndSettle();
    openOrderEditor(
      tester.element(find.text('New order').first),
      c,
      customer: c.customers.first,
      product: c.products.first,
    );
    await tester.pumpAndSettle();
    final quantity = find.widgetWithText(TextFormField, 'Quantity · piece');
    await tester.ensureVisible(quantity);
    await tester.enterText(quantity, '12');
    await tester.tap(find.byTooltip('Close order editor'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderEditor), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.byTooltip('Close order editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderEditor), findsNothing);
    expect(c.orders.where((o) => o.local), isEmpty);
  });
  testWidgets('tablet customer detail stays within filtered customers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = SalesController(store: MemorySalesStore());
    addTearDown(c.dispose);
    await c.enterPreview();
    c.go(SalesPage.customers);
    await tester.pumpWidget(SalesApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanka Retail Collective').first);
    await tester.pumpAndSettle();
    expect(find.text('Dinesh Silva'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Search customers'),
      'Metro Essentials',
    );
    await tester.pumpAndSettle();
    expect(find.text('Lanka Retail Collective'), findsNothing);
    expect(find.text('Dinesh Silva'), findsNothing);
    expect(find.text('Kasun Wijesinghe'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
