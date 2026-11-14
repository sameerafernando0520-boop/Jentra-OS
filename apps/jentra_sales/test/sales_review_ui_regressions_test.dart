import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/sales_app.dart';
import 'package:jentra_sales/src/sales_controller.dart';
import 'package:jentra_sales/src/ui/components.dart';
import 'package:jentra_sales/src/ui/field_sales_workspace.dart';

import 'support/field_sales_fixture.dart';

void main() {
  testWidgets('impossible delivery dates do not request company review', (
    tester,
  ) async {
    _setView(tester, const Size(430, 1000));
    final gateway = _PreviewRecordingGateway();
    final controller = FieldSalesController(
      gateway: gateway,
      store: MemorySalesStore(),
    );
    addTearDown(controller.dispose);
    await controller.open();
    await controller.selectCustomer('customer');
    expect(await controller.saveDraft(fieldInput), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: salesTheme(Brightness.light),
        home: FieldSalesWorkspace(controller, onLeave: () async {}),
      ),
    );
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    final date = _textField('Requested delivery date');
    await tester.ensureVisible(date);
    await tester.enterText(date, '2099-02-31');
    final review = find.text('Review current company terms');
    await tester.ensureVisible(review);
    await tester.tap(review.hitTestable());
    await tester.pumpAndSettle();

    final dateFormField = find.ancestor(
      of: date,
      matching: find.byType(TextFormField),
    );
    expect(
      tester.state<FormFieldState<String>>(dateFormField).hasError,
      isTrue,
    );
    expect(gateway.previewInputs, isEmpty);
    expect(controller.review, isNull);
    expect(gateway.fixture.commands, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.clear();
  });

  testWidgets('Android system Back preserves a dirty governed order', (
    tester,
  ) async {
    _setView(tester, const Size(430, 1000));
    final store = MemorySalesStore();
    final gateway = FakeFieldSalesGateway();
    final field = FieldSalesController(gateway: gateway, store: store);
    final controller = SalesController(store: store, field: field);
    addTearDown(field.dispose);
    addTearDown(controller.dispose);
    await field.open();
    await field.selectCustomer('customer');
    await tester.pumpWidget(SalesApp(controller: controller));
    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
    final notes = _textField('Order notes');
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Keep this unsaved customer order');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Keep your order changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this unsaved customer order'), findsOneWidget);
    expect(field.savedDraft, isNull);
    expect(gateway.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    field.clear();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
    'preview navigation and exit remain usable in a short wide window',
    (tester) async {
      _setView(tester, const Size(1440, 320));
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = SalesController(store: MemorySalesStore());
      addTearDown(controller.dispose);
      await controller.enterPreview();
      await tester.pumpWidget(SalesApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final (label, page) in [
        ('Customers', SalesPage.customers),
        ('Orders', SalesPage.orders),
        ('More', SalesPage.more),
        ('Today', SalesPage.today),
      ]) {
        final rail = find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(rail).position.jumpTo(0);
        await tester.pumpAndSettle();
        final destination = find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.text(label),
        );
        await tester.scrollUntilVisible(destination, 100, scrollable: rail);
        await tester.pumpAndSettle();
        expect(destination.hitTestable(), findsOneWidget);
        await tester.tap(destination.hitTestable());
        await tester.pumpAndSettle();
        expect(controller.page, page);
        expect(tester.takeException(), isNull, reason: label);
      }
      final exit = find.text('Exit preview');
      await tester.scrollUntilVisible(
        exit,
        100,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(exit.hitTestable(), findsOneWidget);
      await tester.tap(exit.hitTestable());
      await tester.pumpAndSettle();
      expect(controller.preview, isFalse);
      expect(controller.customers, isEmpty);
      expect(find.text('Explore the preview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _textField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

final class _PreviewRecordingGateway implements FieldSalesGateway {
  final fixture = FakeFieldSalesGateway();
  final previewInputs = <FieldSalesJson>[];

  @override
  String? get actorId => fixture.actorId;
  @override
  Future<FieldSalesJson> workspace() => fixture.workspace();
  @override
  Future<List<FieldSalesJson>> customers(FieldSalesScope scope) =>
      fixture.customers(scope);
  @override
  Future<List<FieldSalesJson>> catalogue(
    FieldSalesScope scope,
    String customer,
  ) => fixture.catalogue(scope, customer);
  @override
  Future<List<FieldSalesJson>> subjects(FieldSalesScope scope) =>
      fixture.subjects(scope);
  @override
  Future<FieldSalesJson> preview(FieldSalesScope scope, FieldSalesJson input) {
    previewInputs.add(input);
    return fixture.preview(scope, input);
  }

  @override
  Future<FieldSalesJson> submit(FieldSalesCommand command) =>
      fixture.submit(command);
  @override
  Future<FieldSalesJson> receipt(FieldSalesScope scope, String key) =>
      fixture.receipt(scope, key);
}
