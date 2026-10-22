import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/l10n/employee_strings.dart';

import 'support/employee_fixture.dart';

void main() {
  for (final language in ['en', 'si', 'ta']) {
    testWidgets(
      'saved draft notice leaves navigation usable in landscape at 200 percent in $language',
      (tester) async {
        tester.view.physicalSize = const Size(640, 360);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final gateway = FixtureGateway();
        final controller = await fixtureController(gateway: gateway);
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        controller.notice = 'Draft saved on this device for up to 24 hours. It has not been submitted.';
        try {
          await tester.pumpWidget(
            EmployeeApp(
              controller: controller,
              observeLifecycle: false,
              initialLocale: Locale(language),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('employee-nav-more')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const Key('employee-nav-more')));
          await tester.pumpAndSettle();
          expect(
            find.text(EmployeeStrings(language)('more')),
            findsNWidgets(2),
          );
          expect(tester.takeException(), isNull);
        } finally {
          controller.lock();
        }
      },
    );
  }
}
