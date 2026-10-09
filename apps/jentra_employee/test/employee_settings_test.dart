import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/employee_app.dart';

import 'support/employee_fixture.dart';

void main() {
  for (final initialTheme in [ThemeMode.light, ThemeMode.system]) {
    testWidgets(
      'theme and language changes stay selected from ${initialTheme.name}',
      (tester) async {
        final gateway = FixtureGateway();
        final controller = await fixtureController(gateway: gateway);
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        await tester.pumpWidget(
          EmployeeApp(
            controller: controller,
            observeLifecycle: false,
            initialThemeMode: initialTheme,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('employee-nav-more')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('employee-settings')),
          250,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byKey(const Key('employee-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('employee-appearance')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dark').last);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byKey(const Key('employee-language'))))
              .brightness,
          Brightness.dark,
        );
        expect(
          tester
              .widget<DropdownButton<ThemeMode>>(
                find.byKey(const Key('employee-appearance')),
              )
              .value,
          ThemeMode.dark,
        );
        await tester.tap(find.byKey(const Key('employee-language')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('தமிழ்').last);
        await tester.pumpAndSettle();
        expect(find.text('அமைப்புகள்'), findsOneWidget);
        expect(
          Theme.of(tester.element(find.byKey(const Key('employee-language'))))
              .brightness,
          Brightness.dark,
        );
        // Flutter's pageBack helper searches the English tooltip. Tap the real
        // Material button so this also exercises a localized settings route.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('employee-nav-work')), findsNothing);
        expect(find.byKey(const Key('employee-nav-more')), findsOneWidget);
        expect(tester.takeException(), isNull);
        controller.lock();
      },
    );
  }
}
