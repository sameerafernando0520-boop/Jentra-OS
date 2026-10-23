import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_mfa.dart';
import 'package:jentra_employee/src/ui/employee_mfa_panel.dart';

class _Gateway implements EmployeeMfaGateway {
  final changes = StreamController<String?>.broadcast(sync: true);
  List<EmployeeMfaFactor> available = [];
  int enrollments = 0;
  @override
  String? get actorId => 'original';
  @override
  Stream<String?> get actorChanges => changes.stream;
  @override
  bool isVerifiedSession = false;
  @override
  Future<List<EmployeeMfaFactor>> factors() async => available;
  @override
  Future<EmployeeMfaEnrollment> enroll() async {
    enrollments++;
    available = [
      const EmployeeMfaFactor(
        'setup',
        'Setup',
        verified: false,
        recoverable: true,
      ),
    ];
    return const EmployeeMfaEnrollment('setup', 'SYNTHETICSETUPKEY');
  }

  @override
  Future<void> cancelEnrollment(String factorId) async {
    available = [];
  }

  @override
  Future<void> verify(String factorId, String code) async {
    isVerifiedSession = true;
  }
}

Widget _host(
  _Gateway gateway, {
  String language = 'en',
  double scale = 1,
  Future<void> Function()? onVerified,
}) => MaterialApp(
  locale: Locale(language),
  supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: SingleChildScrollView(
        child: EmployeeMfaPanel(
          gateway: gateway,
          observeLifecycle: false,
          onVerified: onVerified ?? () async {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'a disposed enrollment can be explicitly finished without re-exposing its setup key',
    (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.changes.close);
      var completed = 0;
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-mfa-enroll')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-mfa-setup-key')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _host(
          gateway,
          onVerified: () async {
            completed++;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-mfa-setup-key')), findsNothing);
      expect(find.byKey(const Key('employee-mfa-code')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('employee-mfa-restore-setup')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('employee-mfa-setup-key')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('employee-mfa-code')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('employee-mfa-verify')));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(gateway.enrollments, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changing authenticators clears a code entered for the old factor',
    (tester) async {
      final gateway = _Gateway()
        ..available = [
          const EmployeeMfaFactor('first', 'First'),
          const EmployeeMfaFactor('second', 'Second'),
        ];
      addTearDown(gateway.changes.close);
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('employee-mfa-code')),
        '123456',
      );
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .onChanged!('second');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('employee-mfa-code')))
            .controller
            ?.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'expired setup clears entered code before explicit setup recovery',
    (tester) async {
      final gateway = _Gateway();
      addTearDown(gateway.changes.close);
      await tester.pumpWidget(_host(gateway));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-mfa-enroll')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('employee-mfa-code')),
        '123456',
      );
      await tester.pump(const Duration(minutes: 5));
      expect(find.byKey(const Key('employee-mfa-code')), findsNothing);
      await tester.tap(find.text('Check authenticators again'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('employee-mfa-restore-setup')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('employee-mfa-code')))
            .controller
            ?.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final language in ['si', 'ta']) {
    testWidgets('verification remains reachable at200percent in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway()
        ..available = [const EmployeeMfaFactor('verified', 'Authenticator')];
      addTearDown(gateway.changes.close);
      var completed = 0;
      await tester.pumpWidget(
        _host(
          gateway,
          language: language,
          scale: 2,
          onVerified: () async {
            completed++;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('employee-mfa-code')));
      await tester.enterText(
        find.byKey(const Key('employee-mfa-code')),
        '123456',
      );
      await tester.ensureVisible(find.byKey(const Key('employee-mfa-verify')));
      await tester.tap(find.byKey(const Key('employee-mfa-verify')));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
