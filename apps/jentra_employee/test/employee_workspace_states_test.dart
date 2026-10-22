import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_app.dart';
import 'package:jentra_employee/src/employee_controller.dart';
import 'package:jentra_employee/src/l10n/employee_strings.dart';

import 'support/employee_fixture.dart';

class EmptyWorkspaceGateway extends FixtureGateway {
  EmptyWorkspaceGateway({required this.failRead});
  final bool failRead;

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() async {
    if (failRead) {
      throw const EmployeeFailure('SERVICE_UNAVAILABLE', 'Synthetic outage.');
    }
    return [];
  }
}

void main() {
  for (final failRead in [false, true]) {
    testWidgets(
      '${failRead ? 'failed' : 'successful empty'} workspace read gives the correct next step',
      (tester) async {
        final gateway = EmptyWorkspaceGateway(failRead: failRead);
        final controller = EmployeeController(
          gateway: gateway,
          draftStore: EmployeeDraftStore(FixtureStore()),
        );
        addTearDown(controller.dispose);
        addTearDown(gateway.close);
        await controller.start();
        await tester.pumpWidget(
          EmployeeApp(controller: controller, observeLifecycle: false),
        );
        await tester.pumpAndSettle();

        const strings = EmployeeStrings('en');
        expect(
          find.text(strings('noWorkspaces')),
          failRead ? findsNothing : findsOneWidget,
        );
        expect(
          find.text(strings('failureService')),
          failRead ? findsOneWidget : findsNothing,
        );
        if (failRead) expect(find.text(strings('retry')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
