import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/l10n/employee_strings.dart';
import 'package:jentra_employee/src/ui/employee_reviews.dart';
import 'package:jentra_employee/src/ui/leave_draft_screen.dart';
import 'package:jentra_employee/src/ui/sign_in_screen.dart';

import 'employee_sign_in_test.dart' show host;
import 'support/employee_fixture.dart';

class ReviewSearchGateway extends FixtureGateway {
  @override
  Future<EmployeeReviewPage> listReviews(
    EmployeeIdentity identity, {
    String? after,
  }) async => EmployeeReviewPage([
    fixtureReview(),
    EmployeeReview(
      id: '10000000-0000-4000-8000-000000000009',
      version: 4,
      status: 'acknowledged',
      startDate: DateTime(2026, 4, 1),
      endDateExclusive: DateTime(2026, 7, 1),
      objectives: const ['Team planning'],
      comments: 'Planning objectives received.',
    ),
  ], null);
}

void main() {
  for (final language in ['si', 'ta']) {
    testWidgets(
      'new employee flows remain usable at 200 percent in $language',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final gateway = ReviewSearchGateway();
        final controller = await fixtureController(gateway: gateway);
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        final s = EmployeeStrings(language);
        final verticalScroll = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        );
        try {
          await tester.pumpWidget(
            EmployeeApp(
              controller: controller,
              observeLifecycle: false,
              initialLocale: Locale(language),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('employee-nav-activity')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text(s('viewAll')).hitTestable(),
            200,
            scrollable: verticalScroll.first,
          );
          await tester.tap(find.text(s('viewAll')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('employee-review-search')),
            'planning',
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              const Key('employee-review-10000000-0000-4000-8000-000000000006'),
            ),
            findsNothing,
          );
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('employee-nav-more')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text(s('hrHelp')).hitTestable(),
            220,
            scrollable: verticalScroll.first,
          );
          await tester.tap(find.text(s('hrHelp')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('employee-help-leave')).hitTestable(),
            180,
            scrollable: verticalScroll.first,
          );
          await tester.tap(find.byKey(const Key('employee-help-leave')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text(s('createDraft')).hitTestable(),
            220,
            scrollable: verticalScroll.first,
          );
          await tester.tap(find.text(s('createDraft')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('employee-leave-range')).hitTestable(),
            220,
            scrollable: verticalScroll.first,
          );
          expect(tester.takeException(), isNull);
          expect(gateway.receipts, isEmpty);
        } finally {
          controller.lock();
        }
      },
    );
  }

  test(
    'calendar summary uses date parts across leap days and time offsets',
    () {
      expect(
        employeeCalendarDays(DateTime(2024, 2, 28, 23), DateTime(2024, 3, 1)),
        3,
      );
      expect(
        employeeCalendarDays(
          DateTime.utc(2026, 3, 8, 23),
          DateTime(2026, 3, 9, 1),
        ),
        2,
      );
      expect(
        employeeCalendarDays(DateTime(2026, 10, 12), DateTime(2026, 10, 11)),
        0,
      );
    },
  );

  testWidgets('range picker changes the summary without submitting a draft', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      host(
        EmployeeLeaveDraftScreen(
          initialDraft: EmployeeLeaveDraft(
            leaveType: 'Annual',
            reason: 'Appointment',
            startDate: DateTime(2026, 10, 12),
            endDate: DateTime(2026, 10, 14),
          ),
          onSave: (_) async {
            saved = true;
            return true;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('employee-leave-range')));
    await tester.tap(find.byKey(const Key('employee-leave-range')));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.text('19').first);
    await tester.tap(find.text('23').first);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('5 calendar days'), findsOneWidget);
    expect(saved, isFalse);
  });

  testWidgets(
    'activity and review search are cleared when the app backgrounds',
    (tester) async {
      final gateway = ReviewSearchGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      try {
        await tester.pumpWidget(EmployeeApp(controller: controller));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('employee-nav-activity')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('View all'), 180);
        await tester.tap(find.text('View all'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('employee-review-search')),
          'planning',
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('employee-review-search')), findsNothing);
        expect(find.text('Team planning'), findsNothing);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('employee-open-reviews')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const Key('employee-review-search')),
              )
              .controller!
              .text,
          isEmpty,
        );
      } finally {
        controller.lock();
      }
    },
  );

  testWidgets('activity keeps local drafts distinct from review receipts', (
    tester,
  ) async {
    final gateway = ReviewSearchGateway();
    final controller = await fixtureController(gateway: gateway);
    addTearDown(controller.dispose);
    addTearDown(gateway.close);
    try {
      await controller.saveLeaveDraft(
        EmployeeLeaveDraft(
          leaveType: 'Annual',
          reason: 'Family appointment',
          startDate: DateTime(2026, 10, 12),
          endDate: DateTime(2026, 10, 13),
        ),
      );
      await tester.pumpWidget(
        EmployeeApp(controller: controller, observeLifecycle: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('employee-nav-activity')));
      await tester.pumpAndSettle();
      expect(find.text('Not submitted to HR'), findsOneWidget);
      expect(find.text('Annual'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(
          const Key(
            'employee-activity-review-10000000-0000-4000-8000-000000000009',
          ),
        ),
        220,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('employee-page-activity')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Receipt acknowledged'), findsOneWidget);
      expect(gateway.receipts, isEmpty);
    } finally {
      controller.lock();
    }
  });

  testWidgets(
    'review search matches own published content and can be cleared',
    (tester) async {
      final gateway = ReviewSearchGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      try {
        await tester.pumpWidget(
          host(EmployeeReviewsScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('employee-review-search')),
          'planning',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const Key('employee-review-10000000-0000-4000-8000-000000000006'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const Key('employee-review-10000000-0000-4000-8000-000000000009'),
          ),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('employee-review-search')),
          'unmatched',
        );
        await tester.pumpAndSettle();
        expect(find.text('No matching reviews'), findsOneWidget);
        await tester.tap(find.byKey(const Key('employee-review-search-clear')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const Key('employee-review-10000000-0000-4000-8000-000000000006'),
          ),
          findsOneWidget,
        );
      } finally {
        controller.lock();
      }
    },
  );

  testWidgets(
    'receipt filter does not include reviews awaiting acknowledgement',
    (tester) async {
      final gateway = ReviewSearchGateway();
      final controller = await fixtureController(gateway: gateway);
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      try {
        await tester.pumpWidget(
          host(EmployeeReviewsScreen(controller: controller)),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('employee-review-filter-acknowledged')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(
            const Key('employee-review-10000000-0000-4000-8000-000000000006'),
          ),
          findsNothing,
        );
        expect(
          find.byKey(
            const Key('employee-review-10000000-0000-4000-8000-000000000009'),
          ),
          findsOneWidget,
        );
        expect(gateway.receipts, isEmpty);
      } finally {
        controller.lock();
      }
    },
  );

  testWidgets(
    'leave summary counts inclusive calendar days without submitting',
    (tester) async {
      var saved = false;
      await tester.pumpWidget(
        host(
          EmployeeLeaveDraftScreen(
            initialDraft: EmployeeLeaveDraft(
              leaveType: 'Annual',
              reason: 'Appointment',
              startDate: DateTime(2026, 10, 12),
              endDate: DateTime(2026, 10, 14),
            ),
            onSave: (_) async {
              saved = true;
              return true;
            },
          ),
        ),
      );
      expect(find.text('3 calendar days'), findsOneWidget);
      expect(find.byKey(const Key('employee-leave-range')), findsOneWidget);
      expect(saved, isFalse);
    },
  );

  testWidgets('account access help stays available before company connection', (
    tester,
  ) async {
    var signedIn = false;
    await tester.pumpWidget(
      host(
        EmployeeSignInScreen(
          connected: false,
          busy: false,
          onSignIn: (_, _) async {
            signedIn = true;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('employee-account-help')));
    await tester.tap(find.byKey(const Key('employee-account-help')));
    await tester.pumpAndSettle();
    expect(find.text('Account access'), findsWidgets);
    expect(
      find.text(
        'Ask HR to confirm your company account and active workplace membership.',
      ),
      findsOneWidget,
    );
    expect(signedIn, isFalse);
  });
}
