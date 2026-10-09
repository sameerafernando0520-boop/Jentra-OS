import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_employee/src/ui/sign_in_screen.dart';

Widget host(
  Widget child, {
  double scale = 1,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: JentraTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

void main() {
  testWidgets('invalid credentials never reach sign-in', (tester) async {
    var sent = false;
    await tester.pumpWidget(
      host(
        EmployeeSignInScreen(
          connected: true,
          busy: false,
          onSignIn: (email, password) async {
            sent = true;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('employee-sign-in')));
    await tester.pump();
    expect(sent, isFalse);
    expect(find.text('Enter your work email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('valid credentials are sent without modifying the password', (
    tester,
  ) async {
    String? sentEmail;
    String? sentPassword;
    await tester.pumpWidget(
      host(
        EmployeeSignInScreen(
          connected: true,
          busy: false,
          onSignIn: (email, password) async {
            sentEmail = email;
            sentPassword = password;
          },
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('employee-email')),
      ' staff@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('employee-password')),
      ' Keep spaces ',
    );
    await tester.tap(find.byKey(const Key('employee-sign-in')));
    await tester.pump();
    expect(sentEmail, 'staff@example.com');
    expect(sentPassword, ' Keep spaces ');
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('employee-password')),
              matching: find.byType(TextField),
            ),
          )
          .obscureText,
      isTrue,
    );
  });

  testWidgets('unconfigured app cannot accept credentials', (tester) async {
    var sent = false;
    await tester.pumpWidget(
      host(
        EmployeeSignInScreen(
          connected: false,
          busy: false,
          onSignIn: (email, password) async {
            sent = true;
          },
        ),
      ),
    );
    expect(
      find.text('Your company connection is not ready yet.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('employee-sign-in')),
    );
    expect(button.onPressed, isNull);
    expect(sent, isFalse);
  });

  testWidgets(
    'sign-in stays reachable on a narrow phone with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          EmployeeSignInScreen(
            connected: true,
            busy: false,
            onSignIn: (email, password) async {},
          ),
          scale: 2,
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('employee-password')));
      await tester.tap(find.byKey(const Key('employee-password')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('employee-sign-in')));
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('employee-sign-in'))).height,
        greaterThanOrEqualTo(48),
      );
    },
  );
}
