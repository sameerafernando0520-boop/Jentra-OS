import 'dart:async';

import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

// Representative development-only fixture; never included by a production entrypoint.
const fixtureWorkspace = EmployeeWorkspace(
  tenantId: '10000000-0000-4000-8000-000000000001',
  legalEntityId: '10000000-0000-4000-8000-000000000002',
  branchId: '10000000-0000-4000-8000-000000000003',
  tenantName: 'Jentra development',
  entityName: 'Development employer',
  branchName: 'Colombo',
  timeZone: 'Asia/Colombo',
);
const fixtureActor = '10000000-0000-4000-8000-000000000004';
const fixtureEmployee = '10000000-0000-4000-8000-000000000005';

EmployeeReview fixtureReview({String status = 'reviewed', int version = 3}) =>
    EmployeeReview(
      id: '10000000-0000-4000-8000-000000000006',
      version: version,
      status: status,
      startDate: DateTime(2026, 7, 1),
      endDateExclusive: DateTime(2026, 10, 1),
      objectives: const [
        'Keep handover notes clear and up to date.',
        'Review upcoming work with the team each week.',
      ],
      comments: 'Development preview of an employee-visible review.',
    );

class FixtureStore implements EmployeeKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FixtureGateway implements EmployeeGateway {
  FixtureGateway({this.linked = true, this.withReview = true});
  bool linked, withReview;
  String? _actor = fixtureActor;
  final _changes = StreamController<String?>.broadcast(sync: true);
  final receipts = <String>{};
  EmployeeReview review = fixtureReview();
  @override
  String? get actorId => _actor;
  @override
  Stream<String?> get actorChanges => _changes.stream;
  @override
  Future<void> signIn(String email, String password) async {
    _actor = fixtureActor;
    _changes.add(_actor);
  }

  @override
  Future<void> signOut() async {
    _actor = null;
    _changes.add(null);
  }

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() async => const [
    fixtureWorkspace,
  ];
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) async {
    if (!linked) {
      throw const EmployeeFailure('SELF_LINK_REQUIRED', 'A link is required.');
    }
    return EmployeeIdentity(
      workspace: workspace,
      actorId: _actor!,
      employeeId: fixtureEmployee,
      displayName: 'Preview employee',
    );
  }

  @override
  Future<List<EmployeeLink>> listLinks(EmployeeWorkspace workspace) async => [
    EmployeeLink(
      id: '10000000-0000-4000-8000-000000000007',
      employeeId: fixtureEmployee,
      displayName: 'Preview employee',
      version: 1,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  ];
  @override
  Future<EmployeeReviewPage> listReviews(
    EmployeeIdentity identity, {
    String? after,
  }) async => EmployeeReviewPage(withReview ? [review] : [], null);
  @override
  Future<void> execute(EmployeePendingCommand command) async {
    receipts.add(command.envelope.commandId);
    switch (command.envelope.payload['action']) {
      case 'link_accept':
        linked = true;
      case 'link_reject':
        linked = false;
      case 'review_acknowledge':
        review = fixtureReview(
          status: 'acknowledged',
          version: review.version + 1,
        );
    }
  }

  @override
  Future<bool> hasReceipt(EmployeePendingCommand command) async =>
      receipts.contains(command.envelope.commandId);
  Future<void> close() => _changes.close();
}

Future<EmployeeController> fixtureController({
  FixtureGateway? gateway,
  FixtureStore? store,
}) async {
  final controller = EmployeeController(
    gateway: gateway ?? FixtureGateway(),
    draftStore: EmployeeDraftStore(store ?? FixtureStore()),
  );
  await controller.start();
  return controller;
}
