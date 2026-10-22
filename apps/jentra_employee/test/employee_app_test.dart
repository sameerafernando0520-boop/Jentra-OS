import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/employee_app.dart';

import 'support/employee_fixture.dart';

void main() {
  testWidgets('employee navigation reaches honest work leave and pay states', (
    tester,
  ) async {
    final gateway = FixtureGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Preview employee'), findsOneWidget);
    await tester.tap(find.byKey(const Key('employee-nav-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('employee-more-work')),
      180,
    );
    await tester.tap(find.byKey(const Key('employee-more-work')));
    await tester.pumpAndSettle();
    expect(
      find.text('Work records are not available here yet'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('employee-nav-leave')));
    await tester.pumpAndSettle();
    expect(find.text('Leave balances are not available yet'), findsOneWidget);
    expect(find.text('Prepare a leave draft'), findsOneWidget);
    await tester.tap(find.byKey(const Key('employee-nav-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('employee-more-pay')),
      180,
    );
    await tester.tap(find.byKey(const Key('employee-more-pay')));
    await tester.pumpAndSettle();
    expect(
      find.text('Your payslips are not available here yet'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Payslips are not connected in this app version. Contact your payroll team for a payslip or pay question.',
      ),
      findsOneWidget,
    );
    expect(find.text('0.00'), findsNothing);
    controller.lock();
  });

  testWidgets('review acknowledgement requires explicit receipt selection', (
    tester,
  ) async {
    final gateway = FixtureGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('employee-open-reviews')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const Key('employee-review-10000000-0000-4000-8000-000000000006'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('employee-acknowledge')),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('employee-acknowledge')))
          .onPressed,
      isNull,
    );
    expect(gateway.review.status, 'reviewed');
    await tester.tap(find.byKey(const Key('employee-receipt-check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('employee-acknowledge')));
    await tester.pumpAndSettle();
    expect(controller.reviews.single.status, 'acknowledged');
    controller.lock();
  });

  testWidgets('account linking requires reviewing the employee and workplace', (
    tester,
  ) async {
    final gateway = FixtureGateway(linked: false);
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('employee-accept-link')));
    await tester.pumpAndSettle();
    expect(find.text('Link this employee profile?'), findsOneWidget);
    expect(gateway.linked, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.linked, isFalse);
    await tester.tap(find.byKey(const Key('employee-accept-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('employee-confirm-link')));
    await tester.pumpAndSettle();
    expect(controller.identity?.employeeId, fixtureEmployee);
    controller.lock();
  });

  testWidgets(
    'backgrounding removes private routes and requires revalidation',
    (tester) async {
      final gateway = FixtureGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await tester.pumpWidget(EmployeeApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-open-reviews')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const Key('employee-review-10000000-0000-4000-8000-000000000006'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Keep handover notes clear and up to date.'),
        findsOneWidget,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        find.text('Keep handover notes clear and up to date.'),
        findsNothing,
      );
      expect(find.text('Your employee app is locked'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        find.text('Keep handover notes clear and up to date.'),
        findsNothing,
      );
      expect(find.text('Preview employee'), findsOneWidget);
      controller.lock();
    },
  );

  testWidgets(
    'large text keeps secondary destinations accessible through More',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FixtureGateway(withReview: false);
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      await tester.pumpAndSettle();
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(Scaffold)))
            .scale(16),
        32,
      );
      expect(find.byKey(const Key('employee-nav-work')), findsNothing);
      await tester.tap(find.byKey(const Key('employee-nav-more')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('employee-more-pay')).hitTestable(),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('employee-more-pay')));
      await tester.pumpAndSettle();
      expect(
        find.text('Your payslips are not available here yet'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      controller.lock();
    },
  );
}
