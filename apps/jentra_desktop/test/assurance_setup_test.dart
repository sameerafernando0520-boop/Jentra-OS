import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_screen.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'assurance_workspace_test.dart' as fixtures;
import 'support/procurement_fakes.dart' show Keys;

final _auditor = fixtures.uid(70), _external = fixtures.uid(71);

class _People implements AssurancePeopleGateway {
  bool fail = false;
  @override
  Future<AssurancePeople> people(TenantContext scope) async {
    if (fail) throw StateError('unavailable');
    return AssurancePeople.fromJson({
      'members': [
        {'user_id': fixtures.lead, 'label': 'Lead auditor'},
        {'user_id': fixtures.actor, 'label': 'Nadeesha Perera'},
        {'user_id': _auditor, 'label': 'Kasun Silva'},
        {'user_id': _external, 'label': 'External reviewer'},
      ],
      'truncated': false,
    });
  }
}

class _SetupGateway extends fixtures.FakeAssuranceGateway {
  int version = 1;
  final controls = <Map<String, Object?>>[];
  final membership = <Map<String, Object?>>[];

  _SetupGateway() {
    status = 'planning';
  }

  @override
  Future<Map<String, Object?>> engagement(
    TenantContext scope,
    String id,
  ) async {
    final result = await super.engagement(scope, id);
    return {
      ...result,
      'engagement': {...result['engagement'] as Map, 'version': version},
      'controls': controls,
      'events': [...result['events'] as List, ...membership],
    };
  }

  @override
  Future<Map<String, Object?>> auditorCommand(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final receipt = await super.auditorCommand(command);
    version++;
    final payload = command.payload;
    if (payload['action'] == 'map_control') {
      controls.add({
        'id': payload['control_id'],
        'control_code': payload['control_code'],
        'title': payload['title'],
        'owner_id': payload['owner_id'],
        'risk': payload['risk'],
      });
    } else {
      membership.add({
        'version': version,
        'action': payload['action'],
        'aggregate_type': 'team_member',
        'aggregate_id': payload['user_id'],
        'from_status': null,
        'to_status': null,
        'actor_id': fixtures.actor,
        'occurred_at': '2026-10-18T09:00:00Z',
      });
    }
    return receipt;
  }
}

void main() {
  late JentraLocalDatabase database;
  late _SetupGateway gateway;
  late _People people;
  late AssuranceWorkspaceController controller;
  final scope = TenantContext(
    tenantId: fixtures.uid(20),
    actorId: fixtures.actor,
    legalEntityId: fixtures.uid(21),
    branchId: fixtures.uid(22),
  );

  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    gateway = _SetupGateway();
    people = _People();
    controller = AssuranceWorkspaceController(
      scope: scope,
      gateway: gateway,
      drafts: QuotationDraftStore(
        EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
      ),
      online: true,
      capabilities: const {
        'assurance.engagement.manage',
        'assurance.evidence.view',
      },
      people: people,
      clock: () => DateTime.utc(2026, 10, 18, 12),
    );
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> open() async {
    await controller.initialize();
    await controller.open(fixtures.eng);
  }

  test('an empty planned engagement gains an independent control', () async {
    await open();
    expect(
      controller.view!.transitionTargets(controller.capabilities),
      isEmpty,
    );
    await controller.startCommand('map_control', {
      'control_code': 'TRS-SIGN',
      'title': 'Dual signatories',
      'owner_id': fixtures.actor,
      'risk': 'high',
    });
    await controller.submitCommand();
    expect(controller.error, isNull);
    final command = gateway.auditorCommands.single;
    expect(command.expectedEntityVersion, 1);
    expect(command.payload['control_id'], isNotEmpty);
    expect(controller.view!.controls.single.ownerId, fixtures.actor);
    expect(controller.view!.transitionTargets(controller.capabilities), [
      EngagementStatus.fieldwork,
    ]);
    expect(
      controller.setupChoices('add_team_member').map((p) => p.userId),
      isNot(contains(fixtures.actor)),
    );
  });

  test(
    'external grant is bounded and uncertain retries preserve the envelope',
    () async {
      await open();
      await controller.startCommand('add_team_member', {
        'user_id': _external,
        'role': 'auditor',
      });
      controller.commandField('role', 'external');
      controller.commandField('expires_at', '2027-02-01');
      await controller.submitCommand();
      expect(gateway.auditorCommands, isEmpty);
      expect(controller.error, contains('90 days'));
      controller.commandField('expires_at', '2026-11-01');
      gateway.auditorFailure = 'UNCERTAIN_RESULT';
      await controller.submitCommand();
      expect(controller.commandPending, isTrue);
      final saved = gateway.auditorCommands.single;
      expect(saved.payload['expires_at'], '2026-11-01T00:00:00Z');
      gateway.auditorFailure = null;
      await controller.submitCommand();
      expect(gateway.auditorCommands.last.commandId, saved.commandId);
      expect(gateway.auditorCommands.last.idempotencyKey, saved.idempotencyKey);
      expect(gateway.auditorCommands.last.payload, saved.payload);
      expect(controller.commandPending, isFalse);
      expect(controller.error, isNull);
    },
  );

  test('internal roles omit expiry and the lead cannot be removed', () async {
    await open();
    await controller.startCommand('add_team_member', {
      'user_id': _auditor,
      'role': 'auditor',
    });
    controller.commandField('role', 'external');
    expect(controller.commandForm['expires_at'], isNotNull);
    controller.commandField('role', 'reviewer');
    expect(controller.commandForm.containsKey('expires_at'), isFalse);
    await controller.submitCommand();
    expect(
      gateway.auditorCommands.single.payload.containsKey('expires_at'),
      isFalse,
    );
    expect(controller.setupChoices('revoke_team_member').map((p) => p.userId), [
      _auditor,
    ]);
    await controller.startCommand('revoke_team_member', {
      'user_id': fixtures.lead,
      'reason': 'Rotating the review team',
    });
    await controller.submitCommand();
    expect(gateway.auditorCommands.length, 1);
    controller.commandField('user_id', _auditor);
    await controller.submitCommand();
    expect(
      gateway.auditorCommands.last.payload['action'],
      'revoke_team_member',
    );
    expect(controller.setupChoices('revoke_team_member'), isEmpty);
    expect(
      controller.setupChoices('add_team_member').map((p) => p.userId),
      isNot(contains(_auditor)),
    );
  });

  test(
    'directory failure keeps existing reads and blocks unidentified setup',
    () async {
      people.fail = true;
      await open();
      expect(controller.verified, isTrue);
      expect(controller.peopleError, isNotNull);
      await controller.startCommand('map_control', {
        'control_code': 'TRS-SIGN',
        'title': 'Dual signatories',
        'owner_id': fixtures.actor,
        'risk': 'high',
      });
      await controller.submitCommand();
      expect(gateway.auditorCommands, isEmpty);
      expect(controller.error, contains('eligible person'));
    },
  );

  test('closed stages never start team changes or new controls', () async {
    gateway.status = 'cancelled';
    await open();
    for (final action in [
      'map_control',
      'add_team_member',
      'revoke_team_member',
    ]) {
      await controller.startCommand(action, {});
      expect(controller.commanding, isFalse);
    }
  });

  testWidgets('setup chooses a named owner and exposes the control workflow', (
    tester,
  ) async {
    await tester.runAsync(open);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: Scaffold(body: AssuranceWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add control').hitTestable());
    await tester.runAsync(() async {
      if (!controller.busy) return;
      final idle = Completer<void>();
      void changed() {
        if (!controller.busy && !idle.isCompleted) idle.complete();
      }

      controller.addListener(changed);
      try {
        await idle.future.timeout(const Duration(seconds: 10));
      } finally {
        controller.removeListener(changed);
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('user ID'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('setup-person-owner_id')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('setup-person-owner_id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nadeesha Perera').last);
    await tester.pumpAndSettle();
    expect(controller.commandForm['owner_id'], fixtures.actor);
  });
}
