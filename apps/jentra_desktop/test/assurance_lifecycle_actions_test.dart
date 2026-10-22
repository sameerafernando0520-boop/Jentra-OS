import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_controller.dart';
import 'package:jentra_desktop/src/features/assurance/assurance_workspace_screen.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'assurance_workspace_test.dart' as fixtures;
import 'support/procurement_fakes.dart' show Keys;

class _LifecycleGateway extends fixtures.FakeAssuranceGateway {
  final history = <Map<String, Object?>>[];
  final source = fixtures.uid(90);
  Completer<void>? sourcePause;
  Completer<void>? sourceEntered;
  String sourceStatus = 'issued';
  @override
  Future<Map<String, Object?>> engagement(
    TenantContext scope,
    String id,
  ) async {
    if (id == source && sourcePause != null) {
      if (!(sourceEntered?.isCompleted ?? true)) {
        sourceEntered!.complete();
      }
      await sourcePause!.future;
    }
    final value = await super.engagement(scope, id);
    return {
      ...value,
      if (id == source)
        'engagement': {...value['engagement'] as Map, 'status': sourceStatus},
      'events': [...value['events'] as List, ...history],
    };
  }
}

void main() {
  late JentraLocalDatabase database;
  late _LifecycleGateway gateway;
  late AssuranceWorkspaceController controller;
  late QuotationDraftStore drafts;
  final scope = TenantContext(
    tenantId: fixtures.uid(20),
    actorId: fixtures.actor,
    legalEntityId: fixtures.uid(21),
    branchId: fixtures.uid(22),
  );
  final requestId = fixtures.uid(40),
      evidenceId = fixtures.uid(41),
      holdId = fixtures.uid(42);

  AssuranceWorkspaceController makeController({bool online = true}) =>
      AssuranceWorkspaceController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        evidenceFiles: fixtures.FakeEvidenceFiles(),
        online: online,
        capabilities: const {
          'assurance.evidence.view',
          'assurance.evidence.request',
          'assurance.remediation.manage',
          'assurance.retention.manage',
          'assurance.finding.issue',
          'assurance.test.perform',
        },
        clock: () => DateTime.utc(2026, 10, 22),
      );

  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    gateway = _LifecycleGateway();
    gateway.requests = [
      {
        'id': requestId,
        'control_id': fixtures.uid(30),
        'owner_id': fixtures.actor,
        'status': 'open',
        'due_date': '2026-10-30',
      },
    ];
    gateway.findings = [
      {
        'id': fixtures.finding,
        'title': 'Dual payment authorisation',
        'severity': 'high',
        'status': 'remediating',
        'owner_id': fixtures.actor,
      },
    ];
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    controller = makeController();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  Future<void> open() async {
    await controller.initialize();
    await controller.open(fixtures.eng);
  }

  Future<void> startCarryForward() async {
    await open();
    controller.engagements.add(
      AssuranceEngagementSummary.fromJson({
        'id': gateway.source,
        'name': 'Prior Treasury audit',
        'status': 'issued',
        'version': 9,
        'period_start': '2025-04-01',
        'period_end': '2026-03-31',
        'lead_auditor_id': fixtures.lead,
        'evidence_frozen': true,
        'open_requests': 0,
        'overdue_requests': 0,
        'open_findings': 1,
        'overdue_findings': 1,
        'candidate_exceptions': 0,
      }),
    );
    await controller.startCommand('carry_forward', {
      'source_finding_id': '',
      'control_id': fixtures.uid(30),
    });
    await controller.loadCarrySource(gateway.source);
    controller.commandField('source_finding_id', fixtures.finding);
    await controller.saveCommand();
    expect(controller.error, isNull);
  }

  Future<void> render(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: JentraTheme.light(),
        home: Scaffold(body: AssuranceWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object?> event(String action, String actor) => {
    'version': 2,
    'action': action,
    'aggregate_type': 'retention_hold',
    'aggregate_id': holdId,
    'from_status': null,
    'to_status': null,
    'actor_id': actor,
    'occurred_at': '2026-10-20T09:00:00Z',
  };

  test('open evidence cancellation seals a reason and retries the exact uncertain request', () async {
    await open();
    await controller.startCommand('cancel_request', {
      'request_id': requestId,
      'reason': 'Duplicate request superseded by a signed mandate.',
    });
    gateway.auditorFailure = 'UNCERTAIN_RESULT';
    await controller.submitCommand();
    expect(controller.commandPending, isTrue);
    final original = gateway.auditorCommands.single;
    controller.commandField('reason', 'Changed after sending');
    gateway.auditorFailure = null;
    await controller.submitCommand();
    expect(
      gateway.auditorCommands.last.idempotencyKey,
      original.idempotencyKey,
    );
    expect(gateway.auditorCommands.last.payload, original.payload);
    expect(controller.error, isNull);
  });

  test('frozen evidence cannot start cancellation', () async {
    gateway.frozen = true;
    await open();
    await controller.startCommand('cancel_request', {
      'request_id': requestId,
      'reason': 'No longer required',
    });
    expect(controller.commanding, isFalse);
    expect(gateway.auditorCommands, isEmpty);
  });

  test(
    'finding owner submits a real selected file digest for independent retest',
    () async {
      await open();
      await controller.startCommand('submit_remediation', {
        'finding_id': fixtures.finding,
        'evidence_sha256': '',
        'note': 'Updated mandate retained with the remediation record.',
      });
      await controller.chooseCommandWorkpaper('evidence_sha256');
      final digest = controller.commandForm['evidence_sha256'];
      expect(digest, matches(RegExp(r'^[a-f0-9]{64}$')));
      await controller.submitCommand();
      expect(controller.error, isNull);
      expect(gateway.auditorCommands.single.payload['evidence_sha256'], digest);
      expect(
        gateway.auditorCommands.single.payload.containsKey(
          'evidence_sha256_file_name',
        ),
        isFalse,
      );
    },
  );

  test('another finding owner cannot submit this remediation', () async {
    gateway.findings.single['owner_id'] = fixtures.lead;
    await open();
    await controller.startCommand('submit_remediation', {
      'finding_id': fixtures.finding,
      'evidence_sha256': 'a' * 64,
      'note': 'A separately owned remediation',
    });
    expect(controller.commanding, isFalse);
    expect(gateway.auditorCommands, isEmpty);
  });

  test('retention hold gets its own persistent identifier', () async {
    await open();
    await controller.startCommand('place_hold', {
      'reason': 'Preserve evidence for an active investigation.',
    });
    final id = controller.commandForm['hold_id'];
    expect(id, isNotEmpty);
    await controller.submitCommand();
    expect(controller.error, isNull);
    expect(gateway.auditorCommands.single.payload['hold_id'], id);
  });

  test('hold release requires a different actor and retains the exact hold identifier', () async {
    gateway.history.add(event('place_hold', fixtures.actor));
    await open();
    await controller.startCommand('release_hold', {
      'hold_id': holdId,
      'reason': 'Investigation completed.',
    });
    expect(controller.commanding, isFalse);
    gateway.history[0] = event('place_hold', fixtures.lead);
    await controller.open(fixtures.eng);
    await controller.startCommand('release_hold', {
      'hold_id': holdId,
      'reason': 'Investigation completed after independent review.',
    });
    await controller.submitCommand();
    expect(controller.error, isNull);
    expect(gateway.auditorCommands.single.payload['hold_id'], holdId);
    expect(AuditorAction.of('release_hold').requiresRecentMfa, isTrue);
  });

  test('monitoring runs only against a supported immutable snapshot', () async {
    gateway.requests.single.addAll({
      'status': 'submitted',
      'evidence': {
        'id': evidenceId,
        'sha256': 'a' * 64,
        'collected_by': fixtures.lead,
        'collection_method': 'system',
        'query_version':
            assuranceSourceKinds['it_control.access_review']!.queryVersion,
      },
    });
    await open();
    await controller.startCommand('run_monitoring', {
      'evidence_id': evidenceId,
      'control_id': fixtures.uid(30),
    });
    await controller.submitCommand();
    expect(controller.error, isNull);
    expect(gateway.auditorCommands.single.payload['evidence_id'], evidenceId);
    expect(AuditorAction.of('run_monitoring').rpc, AssuranceRpc.evidence);
  });

  testWidgets(
    'a chosen workpaper updates the visible digest without resetting manual edits',
    (tester) async {
      await tester.runAsync(() async {
        await open();
        await controller.startCommand('submit_remediation', {
          'finding_id': fixtures.finding,
          'evidence_sha256': '',
          'note': 'Signed remediation record',
        });
      });
      await render(tester);
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Remediation evidence SHA-256',
      );
      EditableText editor() => tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editor().controller.text, isEmpty);
      await tester.runAsync(
        () => controller.chooseCommandWorkpaper('evidence_sha256'),
      );
      await tester.pumpAndSettle();
      expect(
        editor().controller.text,
        controller.commandForm['evidence_sha256'],
      );
      expect(editor().controller.text, matches(RegExp(r'^[a-f0-9]{64}$')));
      final retainedEditor = editor().controller;
      await tester.enterText(field, 'a' * 64);
      await tester.pumpAndSettle();
      expect(editor().controller, same(retainedEditor));
      expect(controller.commandForm['evidence_sha256'], 'a' * 64);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved carry-forward reloads its context beyond the first register page',
    (tester) async {
      await tester.runAsync(startCarryForward);
      final savedForm = Map<String, Object?>.of(controller.commandForm);
      controller.dispose();
      controller = makeController();
      await tester.runAsync(controller.initialize);
      expect(controller.error, isNull);
      expect(controller.view?.id, fixtures.eng);
      expect(controller.carrySources, isEmpty);
      expect(controller.carrySource?.id, gateway.source);
      expect(controller.commandForm, savedForm);
      await render(tester);
      expect(find.text('Dual payment authorisation'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(controller.submitCommand);
      expect(controller.error, isNull);
      expect(
        gateway.auditorCommands.single.payload['source_finding_id'],
        fixtures.finding,
      );
      expect(
        gateway.auditorCommands.single.payload.containsKey(
          'source_engagement_id',
        ),
        isFalse,
      );
      expect(
        gateway.auditorCommands.single.payload['finding_id'],
        savedForm['finding_id'],
      );
    },
  );

  test(
    'restoring an uncertain carry-forward preserves the sealed exact retry',
    () async {
      await startCarryForward();
      gateway.auditorFailure = 'UNCERTAIN_RESULT';
      await controller.submitCommand();
      final sealed = gateway.auditorCommands.single;
      controller.dispose();
      controller = makeController();
      await controller.initialize();
      expect(controller.commandPending, isTrue);
      expect(controller.command!.pending!.envelope.payload, sealed.payload);
      gateway.auditorFailure = null;
      await controller.submitCommand();
      expect(controller.error, isNull);
      expect(
        gateway.auditorCommands.last.idempotencyKey,
        sealed.idempotencyKey,
      );
      expect(gateway.auditorCommands.last.payload, sealed.payload);
    },
  );

  testWidgets(
    'an offline saved carry-forward renders without an unverified engagement',
    (tester) async {
      await tester.runAsync(startCarryForward);
      controller.dispose();
      controller = makeController(online: false);
      await tester.runAsync(controller.initialize);
      expect(controller.view, isNull);
      await render(tester);
      expect(
        find.text(
          'Refresh to load the saved engagement before editing this draft.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(gateway.auditorCommands, isEmpty);
    },
  );

  test('losing verified connectivity while restoring never publishes a late source', () async {
    await startCarryForward();
    controller.dispose();
    controller = makeController();
    gateway.sourcePause = Completer<void>();
    gateway.sourceEntered = Completer<void>();
    final restoring = controller.initialize();
    await gateway.sourceEntered!.future;
    expect(controller.view?.id, fixtures.eng);
    controller.setOnline(false);
    gateway.sourcePause!.complete();
    await restoring;
    expect(controller.view, isNull);
    expect(controller.carrySource, isNull);
    expect(controller.verified, isFalse);
  });
}
