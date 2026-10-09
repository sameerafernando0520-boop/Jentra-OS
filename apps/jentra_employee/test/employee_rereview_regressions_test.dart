import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/employee_app.dart';

import 'employee_review_fixes_test.dart' show DelayedAuthGateway;
import 'support/employee_fixture.dart';

class LogoutRetryGateway extends FixtureGateway {
  int attempts = 0;
  @override
  Future<void> signOut() async {
    await super.signOut();
    if (++attempts == 1) {
      throw const EmployeeFailure(
        'DURABLE_LOGOUT_INCOMPLETE',
        'Synthetic protected session removal failure.',
      );
    }
    // The employee gateway reports remote failure only after local removal.
    throw const EmployeeFailure(
      'UNCERTAIN_RESULT',
      'Remote revocation failed.',
    );
  }
}

Future<void> signInThroughForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('employee-email')),
    'employee@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('employee-password')),
    'synthetic',
  );
  await tester.ensureVisible(find.byKey(const Key('employee-sign-in')));
  await tester.tap(find.byKey(const Key('employee-sign-in')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('foreground Lock app sign-out sign-in works without OS resume', (
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
    await tester.tap(find.byKey(const Key('employee-nav-more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Lock app'), 350);
    await tester.tap(find.text('Lock app'));
    await tester.pumpAndSettle();
    expect(find.text('Preview employee'), findsNothing);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await signInThroughForm(tester);
    expect(find.text('Preview employee'), findsOneWidget);
    expect(controller.identity?.employeeId, fixtureEmployee);
    controller.lock();
  });

  testWidgets(
    'verified local logout recovery permits login after remote failure',
    (tester) async {
      final gateway = LogoutRetryGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      await controller.signOut();
      await tester.pumpAndSettle();
      expect(controller.error?.code, 'DURABLE_LOGOUT_INCOMPLETE');
      expect(find.text('Preview employee'), findsNothing);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Signed out on this device. Server session revocation could not be confirmed.',
        ),
        findsOneWidget,
      );
      await signInThroughForm(tester);
      expect(find.text('Preview employee'), findsOneWidget);
      expect(controller.identity?.employeeId, fixtureEmployee);
      controller.lock();
    },
  );

  testWidgets(
    'manual lock stays private when delayed authentication completes',
    (tester) async {
      final gateway = DelayedAuthGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      final signingIn = controller.signIn('employee@example.test', 'synthetic');
      controller.lock();
      gateway.signInGate.complete();
      await signingIn;
      await tester.pumpAndSettle();
      expect(gateway.selfReads, 0);
      expect(find.text('Preview employee'), findsNothing);
      await tester.tap(find.text('Continue securely'));
      await tester.pumpAndSettle();
      expect(gateway.selfReads, 1);
      expect(find.text('Preview employee'), findsOneWidget);
      controller.lock();
    },
  );
}
