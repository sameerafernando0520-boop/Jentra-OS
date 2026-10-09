import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/ui/leave_draft_screen.dart';

import 'employee_sign_in_test.dart' show host;

void main() {
  testWidgets(
    'leave draft validates fields and saves only the chosen local content',
    (tester) async {
      EmployeeLeaveDraft? saved;
      await tester.pumpWidget(
        host(
          EmployeeLeaveDraftScreen(
            initialDate: DateTime(2026, 10, 9),
            onSave: (draft) async {
              saved = draft;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('employee-save-draft')));
      await tester.pump();
      expect(saved, isNull);
      expect(
        find.text('Enter a leave type of up to 80 characters.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('employee-leave-type')),
        'Annual leave',
      );
      await tester.enterText(
        find.byKey(const Key('employee-leave-reason')),
        'Family appointment',
      );
      await tester.tap(find.byKey(const Key('employee-save-draft')));
      await tester.pumpAndSettle();
      expect(saved?.leaveType, 'Annual leave');
      expect(saved?.reason, 'Family appointment');
      expect(saved?.startDate, DateTime(2026, 10, 9));
      expect(saved?.endDate, DateTime(2026, 10, 9));
    },
  );

  testWidgets('reversed leave dates never reach local storage', (tester) async {
    var saved = false;
    await tester.pumpWidget(
      host(
        EmployeeLeaveDraftScreen(
          initialDraft: EmployeeLeaveDraft(
            leaveType: 'Annual leave',
            reason: 'Family appointment',
            startDate: DateTime(2026, 10, 12),
            endDate: DateTime(2026, 10, 9),
          ),
          onSave: (draft) async {
            saved = true;
            return true;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('employee-save-draft')));
    await tester.pump();
    expect(saved, isFalse);
    expect(
      find.text('The last day must be on or after the first day.'),
      findsOneWidget,
    );
    expect(find.text('Not submitted to HR'), findsOneWidget);
  });
}
