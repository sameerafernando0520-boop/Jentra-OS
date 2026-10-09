import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

class DelayedAuthGateway extends FixtureGateway {
  DelayedAuthGateway() {
    super.signOut();
  }
  final signInGate = Completer<void>();
  int selfReads = 0;
  bool revoked = false;
  @override
  Future<void> signIn(String email, String password) async {
    await signInGate.future;
    await super.signIn(email, password);
  }

  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) async {
    selfReads++;
    if (revoked) throw const EmployeeFailure('PERMISSION_DENIED', 'Revoked');
    return super.resolveIdentity(workspace);
  }
}

class UncertainGateway extends FixtureGateway {
  @override
  Future<void> execute(EmployeePendingCommand command) async {
    throw const EmployeeFailure('UNCERTAIN_RESULT', 'Unknown');
  }
}

class LogoutGateway extends FixtureGateway {
  @override
  Future<void> signOut() async {
    await super.signOut();
    throw const EmployeeFailure(
      'UNCERTAIN_RESULT',
      'Remote logout unavailable.',
    );
  }
}

void main() {
  testWidgets(
    'delayed auth cannot reopen background data and resume checks revoked access',
    (tester) async {
      final gateway = DelayedAuthGateway();
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(FixtureStore()),
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await tester.pumpWidget(EmployeeApp(controller: controller));
      final signingIn = controller.signIn('employee@example.test', 'synthetic');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      gateway.signInGate.complete();
      await signingIn;
      await tester.pumpAndSettle();
      expect(controller.phase, EmployeePhase.locked);
      expect(gateway.selfReads, 0);
      expect(find.text('Preview employee'), findsNothing);
      gateway.revoked = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.selfReads, 1);
      expect(controller.identity, isNull);
      expect(find.text('Preview employee'), findsNothing);
      controller.lock();
    },
  );

  testWidgets('aged draft expiry removes and disposes open editor body', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 9);
    final store = EmployeeDraftStore(FixtureStore(), now: () => now);
    const identity = EmployeeIdentity(
      workspace: fixtureWorkspace,
      actorId: fixtureActor,
      employeeId: fixtureEmployee,
      displayName: 'Preview employee',
    );
    await store.saveDraft(
      identity,
      EmployeeLeaveDraft(
        leaveType: 'Annual',
        reason: 'Private old draft reason',
        startDate: DateTime(2026, 10, 12),
        endDate: DateTime(2026, 10, 13),
      ),
    );
    now = now.add(const Duration(hours: 23));
    final gateway = FixtureGateway();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: store,
      now: () => now,
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.start();
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('employee-nav-leave')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Edit draft')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit draft'));
    await tester.pumpAndSettle();
    final editor = tester
        .widget<TextFormField>(find.byKey(const Key('employee-leave-reason')))
        .controller!;
    expect(editor.text, 'Private old draft reason');
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('employee-leave-reason')), findsNothing);
    expect(find.text('Private old draft reason'), findsNothing);
    expect(controller.leaveDraft, isNull);
    expect(() => editor.addListener(() {}), throwsFlutterError);
    expect(find.byKey(const Key('employee-save-draft')), findsNothing);
    controller.lock();
  });

  testWidgets('not-found receipt outcome is visible and announced', (
    tester,
  ) async {
    final gateway = UncertainGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.acknowledgeReview(controller.reviews.single);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    await controller.reconcileCommand();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No receipt exists yet. You can explicitly retry the exact saved request.',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsWidgets,
    );
    controller.lock();
  });

  testWidgets('remote revocation warning is visible after local logout', (
    tester,
  ) async {
    final gateway = LogoutGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    await controller.signOut();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Signed out on this device. Server session revocation could not be confirmed.',
      ),
      findsOneWidget,
    );
    controller.lock();
  });

  testWidgets('confirmed action outcome survives fresh identity refresh', (
    tester,
  ) async {
    final gateway = FixtureGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    await controller.acknowledgeReview(controller.reviews.single);
    await tester.pumpWidget(
      EmployeeApp(controller: controller, observeLifecycle: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('The server confirmed your request.'), findsOneWidget);
    controller.lock();
  });
  for (final language in ['si', 'ta']) {
    testWidgets(
      'stable access failure renders localized interface copy in $language',
      (tester) async {
        final gateway = FixtureGateway();
        final controller = await fixtureController(gateway: gateway);
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        controller.lock();
        controller.error = const EmployeeFailure(
          'PERMISSION_DENIED',
          'English safe provider text',
        );
        await tester.pumpWidget(
          EmployeeApp(
            controller: controller,
            initialLocale: Locale(language),
            observeLifecycle: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('English safe provider text'), findsNothing);
        expect(
          find.text(
            language == 'si'
                ? 'HR ප්‍රවේශය වෙනස් වී ඇත. ඔබගේ ගිණුම් අවසර පරීක්ෂා කිරීමට HR අමතන්න.'
                : 'HR அணுகல் மாறியுள்ளது. உங்கள் கணக்கு அனுமதிகளைச் சரிபார்க்க HR ஐத் தொடர்புகொள்ளவும்.',
          ),
          findsOneWidget,
        );
        controller.lock();
      },
    );
  }
}
