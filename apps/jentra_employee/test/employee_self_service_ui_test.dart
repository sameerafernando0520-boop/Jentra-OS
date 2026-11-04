import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_self_service.dart';
import 'package:jentra_employee/src/employee_self_service_controller.dart';
import 'package:jentra_employee/src/l10n/employee_strings.dart';
import 'package:jentra_employee/src/ui/employee_attendance.dart';
import 'package:jentra_employee/src/ui/employee_leave.dart';
import 'package:jentra_employee/src/ui/employee_private_services.dart';
import 'package:jentra_employee/src/ui/employee_theme.dart';

import 'support/employee_fixture.dart';
import 'support/employee_self_fixture.dart';

void main() {
  for (final language in ['en', 'si', 'ta']) {
    testWidgets('HR services and forms render at 200 percent in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = SelfGateway();
      final c = EmployeeSelfServiceController(
        gateway: gateway,
        store: FixtureStore(),
        currentIdentity: () => selfIdentity,
      );
      addTearDown(c.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await c.load(EmployeeService.leavePolicies);
        final screens = <Widget Function()>[
          () => Scaffold(body: EmployeeAttendanceBody(controller: c)),
          () => EmployeeAttendanceRequestScreen(controller: c),
          () => EmployeeLeaveRequestScreen(controller: c),
          () => EmployeePrivateServiceScreen(
            controller: c,
            service: EmployeeService.payslips,
          ),
          () => EmployeePrivateDetailScreen(
            controller: c,
            service: EmployeeService.payslips,
            id: selfRecordId,
          ),
          () => EmployeePrivateServiceScreen(
            controller: c,
            service: EmployeeService.documents,
          ),
          () => EmployeePrivateServiceScreen(
            controller: c,
            service: EmployeeService.cases,
          ),
          () => EmployeeCaseComposeScreen(controller: c),
          () => EmployeePrivateDetailScreen(
            controller: c,
            service: EmployeeService.cases,
            id: selfRecordId,
          ),
          () => EmployeeInboxScreen(controller: c, onOpenDestination: (_) {}),
        ];
        for (var i = 0; i < screens.length; i++) {
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('$language-$i'),
              theme: employeeTheme(Brightness.light),
              locale: Locale(language),
              supportedLocales: const [
                Locale('en'),
                Locale('si'),
                Locale('ta'),
              ],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: screens[i](),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'screen $i in $language',
          );
          expect(find.byType(Scrollable), findsWidgets);
          if (i == 7) {
            expect(
              tester
                  .getSemantics(find.byKey(const Key('employee-case-subject')))
                  .label,
              contains(EmployeeStrings(language)('caseSubject')),
            );
          }
        }
        expect(c.errors[EmployeeService.inbox], isNull);
        expect(c.pages[EmployeeService.inbox]?.items.length, 1);
        await tester.scrollUntilVisible(
          find.text(EmployeeStrings(language)('inboxGenericTitle')),
          180,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.text(EmployeeStrings(language)('inboxGenericTitle')),
          findsOneWidget,
        );
        expect(find.text('PRIVATE_CASE_BODY'), findsNothing);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets(
    'case form sends real employee command and preserves exact payslip revision',
    (tester) async {
      final gateway = SelfGateway();
      final store = FixtureStore();
      final c = EmployeeSelfServiceController(
        gateway: gateway,
        store: store,
        currentIdentity: () => selfIdentity,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: employeeTheme(Brightness.light),
          home: EmployeeCaseComposeScreen(
            controller: c,
            payslip: EmployeeServiceRecord(
              serviceRow(EmployeeService.payslips),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('employee-case-subject')),
        'Payslip question',
      );
      await tester.enterText(
        find.byKey(const Key('employee-case-body')),
        'Please check this calculation.',
      );
      final button = find.text(const EmployeeStrings('en')('requestSend'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(gateway.sends, 1);
      expect(gateway.sentRpc, 'employee_case_command');
      final payload = selfMap(gateway.sent!['p_payload']);
      expect(payload['payslip_id'], selfRecordId);
      expect(payload['payslip_revision_id'], selfSecondId);
      expect(payload.containsKey('employee_id'), isFalse);
      expect(payload['category'], 'payroll');
      expect(c.confirmed, isTrue);
      expect(c.pending, isNull);
    },
  );
}
