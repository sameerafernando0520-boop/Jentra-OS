import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

const _secondWorkspace = EmployeeWorkspace(
  tenantId: '10000000-0000-4000-8000-000000000001',
  legalEntityId: '10000000-0000-4000-8000-000000000002',
  branchId: '10000000-0000-4000-8000-000000000009',
  tenantName: 'Synthetic company',
  entityName: 'Synthetic employer',
  branchName: 'Second branch',
  timeZone: 'Asia/Colombo',
);

class _Gateway extends FixtureGateway {
  int signOutCalls = 0, identityReads = 0;
  bool multiple = false;
  @override
  Future<void> signOut() async {
    signOutCalls++;
    await super.signOut();
  }

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() async => [
    fixtureWorkspace,
    if (multiple) _secondWorkspace,
  ];
  @override
  Future<EmployeeIdentity> resolveIdentity(EmployeeWorkspace workspace) async {
    identityReads++;
    return super.resolveIdentity(workspace);
  }
}

void main() {
  test(
    'identity disconnect hook completes before the sign-out RPC starts',
    () async {
      final gateway = _Gateway(), hook = Completer<void>();
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(FixtureStore()),
        beforeIdentityChange: () => hook.future,
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await controller.start();
      final request = controller.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(controller.phase, EmployeePhase.locked);
      expect(controller.identity, isNull);
      expect(gateway.signOutCalls, 0);
      expect(gateway.actorId, fixtureActor);
      hook.complete();
      await request;
      expect(gateway.signOutCalls, 1);
      expect(gateway.actorId, isNull);
      expect(controller.phase, EmployeePhase.signedOut);
    },
  );

  test(
    'failed identity disconnect hook blocks resolving a different workspace',
    () async {
      final gateway = _Gateway()..multiple = true;
      var rejectHook = false;
      final controller = EmployeeController(
        gateway: gateway,
        draftStore: EmployeeDraftStore(FixtureStore()),
        beforeIdentityChange: () async {
          if (rejectHook)
            throw const EmployeeFailure(
              'PUSH_DISCONNECT_INCOMPLETE',
              'Synthetic disconnect failure',
            );
        },
      );
      addTearDown(controller.dispose);
      addTearDown(gateway.close);
      await controller.start();
      await controller.selectWorkspace(fixtureWorkspace);
      expect(controller.identity?.workspace.key, fixtureWorkspace.key);
      final previousReads = gateway.identityReads;
      rejectHook = true;
      await controller.selectWorkspace(_secondWorkspace);
      expect(gateway.identityReads, previousReads);
      expect(controller.identity, isNull);
      expect(controller.phase, EmployeePhase.chooseWorkspace);
      expect(controller.error?.code, 'PUSH_DISCONNECT_INCOMPLETE');
      expect(gateway.actorId, fixtureActor);
    },
  );
}
