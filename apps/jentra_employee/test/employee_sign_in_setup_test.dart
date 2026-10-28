import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/ui/employee_theme.dart';
import 'package:jentra_employee/src/ui/sign_in_screen.dart';

void main() {
  testWidgets(
    'storage failure gives its recovery action without blaming company setup',
    (tester) async {
      const failure =
          'Jentra Employee is already open in another tab. Close that tab, then reload this one.';
      var signIns = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: employeeTheme(Brightness.light),
          home: EmployeeSignInScreen(
            connected: false,
            busy: false,
            error: failure,
            onSignIn: (_, _) async {
              signIns++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(failure), findsOneWidget);
      expect(
        find.textContaining('Your company connection is not ready'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('employee-email')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('employee-password')))
            .enabled,
        isFalse,
      );
      expect(signIns, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing connection still explains company setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: employeeTheme(Brightness.light),
        home: EmployeeSignInScreen(
          connected: false,
          busy: false,
          onSignIn: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your company connection is not ready'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
