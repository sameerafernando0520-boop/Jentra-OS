import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_employee/src/data/employee_gateway.dart';
import 'package:jentra_employee/src/data/employee_storage.dart';
import 'package:jentra_employee/src/employee_controller.dart';

import 'support/employee_fixture.dart';

class DelayedWorkspaceAuthGateway extends FixtureGateway {
  final workspaceGate = Completer<List<EmployeeWorkspace>>();
  int workspaceReads = 0;

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() {
    workspaceReads++;
    return workspaceGate.future;
  }
}

class DelayedAuthCompletionGateway extends FixtureGateway {
  DelayedAuthCompletionGateway({this.failWorkspace = false});
  final bool failWorkspace;
  final signInGate = Completer<void>();
  int workspaceReads = 0;

  @override
  Future<void> signIn(String email, String password) async {
    await super.signIn(email, password);
    await signInGate.future;
  }

  @override
  Future<List<EmployeeWorkspace>> listWorkspaces() async {
    workspaceReads++;
    if (failWorkspace) {
      throw const EmployeeFailure('SERVICE_UNAVAILABLE', 'Synthetic outage.');
    }
    return [fixtureWorkspace];
  }
}

class SilentAuthGateway extends FixtureGateway {
  @override
  Stream<String?> get actorChanges => const Stream.empty();
}

void main() {
  test('successful sign-in keeps its actor-triggered workspace load busy without duplicating it', () async {
    final gateway = DelayedWorkspaceAuthGateway();
    await gateway.signOut();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(FixtureStore()),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);

    final signingIn = controller.signIn('employee@example.test', 'synthetic');
    await Future<void>.delayed(Duration.zero);
    final readsWhileLoading = gateway.workspaceReads;
    final busyWhileLoading = controller.busy;
    gateway.workspaceGate.complete([fixtureWorkspace]);
    await signingIn;
    await Future<void>.delayed(Duration.zero);

    expect(readsWhileLoading, 1);
    expect(busyWhileLoading, isTrue);
    expect(controller.phase, EmployeePhase.ready);
    expect(controller.identity?.employeeId, fixtureEmployee);
  });

  for (final failWorkspace in [false, true]) {
    test(
      'sign-in completion does not repeat a ${failWorkspace ? 'failed' : 'ready'} workspace load',
      () async {
        final gateway = DelayedAuthCompletionGateway(
          failWorkspace: failWorkspace,
        );
        await gateway.signOut();
        final controller = EmployeeController(
          gateway: gateway,
          draftStore: EmployeeDraftStore(FixtureStore()),
        );
        addTearDown(controller.dispose);
        addTearDown(gateway.close);

        final signingIn = controller.signIn(
          'employee@example.test',
          'synthetic',
        );
        await Future<void>.delayed(Duration.zero);
        final expectedPhase = failWorkspace
            ? EmployeePhase.chooseWorkspace
            : EmployeePhase.ready;
        expect(controller.phase, expectedPhase);
        expect(
          controller.error?.code,
          failWorkspace ? 'SERVICE_UNAVAILABLE' : null,
        );
        gateway.signInGate.complete();
        await signingIn;

        expect(gateway.workspaceReads, 1);
        expect(controller.phase, expectedPhase);
        expect(
          controller.error?.code,
          failWorkspace ? 'SERVICE_UNAVAILABLE' : null,
        );
        expect(controller.busy, isFalse);
      },
    );
  }

  test('a gateway without an actor event still starts after sign-in', () async {
    final gateway = SilentAuthGateway();
    await gateway.signOut();
    final controller = EmployeeController(
      gateway: gateway,
      draftStore: EmployeeDraftStore(FixtureStore()),
    );
    addTearDown(controller.dispose);
    addTearDown(gateway.close);

    await controller.signIn('employee@example.test', 'synthetic');

    expect(controller.phase, EmployeePhase.ready);
    expect(controller.identity?.employeeId, fixtureEmployee);
    expect(controller.busy, isFalse);
  });
}
