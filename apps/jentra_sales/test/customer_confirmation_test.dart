import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_sales/src/confirmation_controller.dart';
import 'package:jentra_sales/src/ui/customer_confirmation.dart';
import 'package:jentra_sales/src/ui/components.dart';

import 'confirmation_controller_test.dart'
    show FakeConfirmationGateway, confirmationOffer;

Future<void> openReview(
  WidgetTester tester,
  ConfirmationController c, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: salesTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: CustomerConfirmationPage(c),
    ),
  );
  await tester.scrollUntilVisible(
    find.text('Send email code'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send email code'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byType(TextField),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '482619');
  await tester.scrollUntilVisible(
    find.text('Verify email code'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Verify email code'));
  await tester.pumpAndSettle();
  expect(c.stage, ConfirmationStage.review);
  await tester.scrollUntilVisible(
    find.textContaining('postcode: 12345'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(
    find.textContaining('address · line1: Customer address'),
    findsOneWidget,
  );
}

void main() {
  testWidgets('already recorded is neutral and exposes no response action', (
    tester,
  ) async {
    final gateway = FakeConfirmationGateway()..verification = Completer();
    final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
    addTearDown(c.dispose);
    await c.requestCode();
    gateway.verification!.complete({'state': 'already_recorded'});
    await c.verify('482619');
    await tester.pumpWidget(CustomerConfirmationApp(c));
    expect(find.text('Response already recorded'), findsOneWidget);
    expect(find.text('You rejected the reviewed terms.'), findsNothing);
    expect(find.text('You accepted the reviewed terms.'), findsNothing);
    expect(find.text('Accept these terms'), findsNothing);
    expect(find.text('Reject these terms'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'backgrounding an in-flight verification discards its late terms',
    (tester) async {
      final gateway = FakeConfirmationGateway()..verification = Completer();
      final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
      addTearDown(c.dispose);
      await tester.pumpWidget(CustomerConfirmationApp(c));
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '482619');
      await tester.tap(find.text('Verify email code'));
      await tester.pump();
      expect(c.busy, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      gateway.verification!.complete({
        'state': 'review',
        'proof': 'ab' * 32,
        'offer': confirmationOffer,
      });
      await tester.pumpAndSettle();
      expect(c.offer, isNull);
      expect(find.text('Response unavailable'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [360.0, 768.0, 1280.0]) {
    testWidgets(
      'recipient explicitly reviews and accepts at $width with 200% text',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FakeConfirmationGateway();
        final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
        addTearDown(c.dispose);
        await openReview(tester, c, scale: 2);
        expect(gateway.responses, isEmpty);
        await tester.scrollUntilVisible(
          find.text('Total: LKR 1.270000'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Total: LKR 1.270000'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byType(Checkbox),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Accept these terms'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Accept these terms'));
        await tester.pumpAndSettle();
        expect(find.text('Response recorded'), findsOneWidget);
        expect(gateway.responses, [('accept', '', true)]);
        expect(c.offer, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('disabled provider shows unavailable without a customer action', (
    tester,
  ) async {
    final c = ConfirmationController(token: 'ab' * 32, gateway: null);
    addTearDown(c.dispose);
    await tester.pumpWidget(CustomerConfirmationApp(c));
    expect(find.text('Response unavailable'), findsOneWidget);
    expect(find.text('Send email code'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'recipient may read email before review but backgrounding verified terms locks them',
    (tester) async {
      final c = ConfirmationController(
        token: 'ab' * 32,
        gateway: FakeConfirmationGateway(),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(CustomerConfirmationApp(c));
      await tester.tap(find.text('Send email code'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(c.stage, ConfirmationStage.code);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.enterText(find.byType(TextField), '482619');
      await tester.tap(find.text('Verify email code'));
      await tester.pumpAndSettle();
      expect(find.text('Jentra Company · Authorized customer'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(c.offer, isNull);
      expect(find.text('Response unavailable'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('uncertain response offers only an explicit original retry', (
    tester,
  ) async {
    final gateway = FakeConfirmationGateway()..failResponse = true;
    final c = ConfirmationController(token: 'ab' * 32, gateway: gateway);
    addTearDown(c.dispose);
    await openReview(tester, c);
    await tester.scrollUntilVisible(
      find.byType(Checkbox),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Reject these terms'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Reject these terms'));
    await tester.pumpAndSettle();
    expect(find.text('Retry original response'), findsOneWidget);
    expect(find.text('Accept these terms'), findsNothing);
    expect(gateway.responses.length, 1);
    gateway.failResponse = false;
    await tester.ensureVisible(find.text('Retry original response'));
    await tester.tap(find.text('Retry original response'));
    await tester.pumpAndSettle();
    expect(gateway.responses, [('reject', '', true), ('reject', '', true)]);
    expect(find.text('Response recorded'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
