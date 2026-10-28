import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_push.dart';
import 'package:jentra_employee/src/ui/employee_push_settings.dart';
import 'package:jentra_employee/src/ui/employee_theme.dart';

import 'employee_gateway_test.dart' show person;
import 'employee_push_test.dart' show Transport, Repository;
import 'secure_storage_test.dart' show MemoryStore;

void main() {
  for (final language in ['en', 'si', 'ta']) {
    testWidgets(
      'notification controls fit phone width at 200 percent in $language',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = Transport();
        final repository = Repository();
        final push = EmployeePushCoordinator(
          transport: transport,
          repository: repository,
          store: MemoryStore(),
          currentIdentity: () => person,
        );
        addTearDown(() async {
          push.dispose();
          await transport.close();
        });
        var authorized = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: employeeTheme(Brightness.light),
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('si'), Locale('ta')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EmployeePushSettings(
                    coordinator: push,
                    authorized: () => authorized,
                    onRefresh: () async {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final enable = find.byKey(const Key('employee-push-enable'));
        expect(tester.widget<FilledButton>(enable).onPressed, isNull);
        expect(transport.permissions, 0);
        authorized = true;
        await push.enable();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('employee-push-disable')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await push.disconnect();
        await tester.pumpAndSettle();
        expect(push.enabled, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
