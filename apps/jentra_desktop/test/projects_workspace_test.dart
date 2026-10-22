import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/projects/projects_controller.dart';
import 'package:jentra_desktop/src/features/projects/projects_screen.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

final samples = projectMap(
  jsonDecode(
    File(
      '../../packages/jentra_platform/test/fixtures/projects_rollback_projections.json',
    ).readAsStringSync(),
  ),
);
final record = projectMap(projectMap(samples['plans'])['project']);
final samplePlan = projectMap(
  (projectMap(samples['plans'])['rows'] as List).first,
);
final scope = TenantContext(
  tenantId: record['tenant_id'] as String,
  legalEntityId: record['legal_entity_id'] as String,
  branchId: record['branch_id'] as String,
  actorId: samplePlan['prepared_by'] as String,
);
const secondChoice = 'ffffffff-ffff-4fff-afff-ffffffffffff';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  bool armed = false;
  final readStarted = Completer<void>();
  final readGate = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (armed) {
      armed = false;
      readStarted.complete();
      await readGate.future;
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class Repository implements ProjectRepository {
  int version = 3;
  int? planVersion;
  bool deny = false,
      failRefresh = false,
      pendingPlan = false,
      changeReview = false;
  DomainError? failure;
  DomainError? authorityFailure;
  String? deniedCapability;
  Completer<void>? directoryGate, choiceGate, commandGate, receiptGate;
  Completer<void>? commandStarted, receiptStarted;
  Completer<void>? authorityStarted, authorityGate;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final reads = <(ProjectSection, String?)>[];
  Map<String, Object?>? receipt;
  Map<String, Object?> wire() => {...record, 'version': version};
  @override
  Future<ProjectProviderState> authorize(
    TenantContext s,
    String capability,
  ) async {
    final denied = deny || capability == deniedCapability;
    final authorityError = authorityFailure;
    authorityStarted?.complete();
    await authorityGate?.future;
    if (authorityError != null) throw authorityError;
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Synthetic access revoked.',
      );
    }
    return const ProjectProviderState(
      'LKR',
      2,
      expenseEvidence: false,
      supplierBill: false,
    );
  }

  @override
  Future<ProjectPage<ProjectRecord>> directory(
    TenantContext s, {
    String? after,
  }) async {
    await directoryGate?.future;
    if (failRefresh) {
      throw const DomainError(
        code: 'SERVICE_UNAVAILABLE',
        message: 'Synthetic optional read failure.',
      );
    }
    return ProjectPage([ProjectRecord.fromJson(wire())], null);
  }

  @override
  Future<ProjectDetail> detail(
    TenantContext s,
    String id,
    ProjectSection section, {
    String? parentId,
    String? after,
  }) async {
    reads.add((section, parentId));
    if (section == ProjectSection.timeEvents) {
      return ProjectDetail(ProjectRecord.fromJson(wire()), section, [], null);
    }
    final original = projectMap(samples[section.wire]);
    final values = (original['rows'] as List)
        .map(projectMap)
        .map<ProjectRow>(
          (r) => switch (section) {
            ProjectSection.plans => ProjectPlan.fromJson(
              pendingPlan
                  ? {
                      ...r,
                      'status': 'pending',
                      'version': planVersion ?? version,
                      'decision': null,
                    }
                  : r,
              id,
            ),
            ProjectSection.tasks => ProjectTask.fromJson(r, id),
            ProjectSection.resources => ProjectResource.fromJson(r, id, 'LKR'),
            ProjectSection.time => ProjectTime.fromJson(r, id, 'LKR', 2),
            ProjectSection.cost => ProjectBudget.fromJson(r, id, 'LKR', 2),
            ProjectSection.resourceCost => ProjectResourceCost.fromJson(
              r,
              id,
              'LKR',
            ),
            ProjectSection.timeCost => ProjectTimeCost.fromJson(
              r,
              id,
              'LKR',
              2,
            ),
            ProjectSection.units => ProjectUnit.fromJson(r, id, 'LKR', 2),
            ProjectSection.timeEvents => throw StateError('Handled separately'),
          },
        )
        .where(
          (r) =>
              parentId == null ||
              !{ProjectSection.time, ProjectSection.plans}.contains(section) ||
              r.id == parentId,
        )
        .toList();
    if (changeReview && section == ProjectSection.resources) {
      version++;
    }
    return ProjectDetail(ProjectRecord.fromJson(wire()), section, values, null);
  }

  @override
  Future<ProjectPage<ProjectChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
  }) async {
    await choiceGate?.future;
    final id = after == null ? record['manager_id'] as String : secondChoice;
    return ProjectPage([
      ProjectChoice.fromJson({
        'id': id,
        'name': after == null ? 'Synthetic manager' : 'Second named employee',
        'code': after == null ? 'MANAGER' : 'SECOND',
        'version': 1,
      }, kind),
    ], after == null ? id : null);
  }

  @override
  Future<ProjectPage<ProjectAttendanceClaim>> attendanceClaims(
    TenantContext s,
    String employeeId, {
    String? after,
  }) async => ProjectPage([], null);
  @override
  Future<ProjectLocalResolution> localCandidates(
    TenantContext s,
    CalendarCoverage c,
    CivilDate d,
    int minute, {
    int second = 0,
  }) async => throw const DomainError(
    code: 'SERVICE_UNAVAILABLE',
    message: 'Resolver fixture is unavailable.',
  );
  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> c,
    String currency,
    int precision,
  ) async {
    commands.add(c);
    commandStarted?.complete();
    await commandGate?.future;
    if (failure != null) {
      throw failure!;
    }
    final p = c.payload, a = p['action'] as String;
    final entity = <String, Object?>{
      'id': p['id'],
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'version': c.expectedEntityVersion! + 1,
      if (a.startsWith('time_')) ...{
        'project_id': p['project_id'],
        'employee_id': p['employee_id'],
        'revision_id': samplePlan['id'],
        'status': switch (a) {
          'time_create' || 'time_correct' => 'draft',
          'time_submit' => 'submitted',
          'time_approve' => 'approved',
          'time_reject' => 'rejected',
          _ => 'cancelled',
        },
      } else ...{
        'status': a == 'close' ? 'closed' : 'open',
        'current_plan_id': a == 'create'
            ? null
            : a == 'approve_plan'
            ? p['plan_id']
            : record['current_plan_id'],
      },
    };
    final response = <String, Object?>{
      'request_id': c.commandId,
      'command_id': c.commandId,
      'correlation_id': c.commandId,
      'entity': entity,
      'warnings': <Object?>[],
    };
    receipt = {
      'command_id': c.commandId,
      'idempotency_key': c.idempotencyKey,
      'request_hash': List.filled(64, 'a').join(),
      'response': response,
    };
    return response;
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext s,
    String key,
    String action,
  ) async {
    receiptStarted?.complete();
    await receiptGate?.future;
    return receipt;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late JentraLocalDatabase db;
  late EncryptedDraftRepository encrypted;
  late Keys keys;
  late Repository repository;
  ProjectsController create({Set<String>? permissions}) => ProjectsController(
    scope: scope,
    repository: repository,
    drafts: {for (final a in projectActions) a: projectDrafts(encrypted, a)},
    permissions: permissions ?? projectCapabilities,
    online: true,
    monitor: false,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
    repository = Repository();
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> creation(ProjectsController c) async {
    await c.initialize();
    await c.begin('create');
    c.edit('code', 'SYN');
    c.edit('name', 'Synthetic new project');
    c.choose(
      'manager_id',
      ProjectChoice.fromJson({
        'id': record['manager_id'],
        'name': 'Synthetic manager',
        'code': 'MANAGER',
        'version': 1,
      }, 'employees'),
    );
    c.edit('reason', 'Synthetic governed creation');
  }

  testWidgets('unavailable projects explains module availability', (
    tester,
  ) async {
    repository.authorityFailure = const DomainError(
      code: 'FEATURE_NOT_ENTITLED',
      message: 'Untrusted server details',
    );
    final c = create();
    await c.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProjectsWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Projects is not enabled for this business. Ask your administrator to review module availability.',
      ),
      findsOneWidget,
    );
    expect(find.text('Untrusted server details'), findsNothing);
    expect(c.denied, isTrue);
    expect(repository.commands, isEmpty);
    expect(tester.takeException(), isNull);
    c.dispose();
  });

  test(
    'project entitlement loss clears plaintext and retains the sealed request',
    () async {
      final c = create();
      await creation(c);
      repository.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic timeout',
        retryable: true,
      );
      await c.send();
      final draftId = c.form!['id'] as String;
      final original = c.pending!.toJson();
      repository.authorityFailure = const DomainError(
        code: 'FEATURE_NOT_ENTITLED',
        message: 'Untrusted server details',
      );
      await c.checkAccess();
      expect(c.error, startsWith('Projects is not enabled for this business.'));
      expect(c.current, isFalse);
      expect(c.records, isEmpty);
      expect(c.rows, isEmpty);
      expect(c.form, isNull);
      expect(c.local, isNull);
      expect(c.recovery, isEmpty);
      expect(
        (await c.drafts['create']!.load(scope, draftId))!.pending!.toJson(),
        original,
      );
      expect(repository.commands, hasLength(1));
      c.dispose();
    },
  );

  test('project navigation requires current project view authority', () {
    final without = visibleJentraDestinations({});
    final withView = visibleJentraDestinations({'projects.view'});
    expect(without.any((n) => n.path == '/projects'), isFalse);
    expect(withView.any((n) => n.path == '/projects'), isTrue);
  });
  test(
    'read-only project permission cannot decrypt write drafts or create forms',
    () async {
      final c = create(permissions: {'projects.view'});
      await c.initialize();
      await c.begin('create');
      expect(c.form, isNull);
      expect(c.recovery, isEmpty);
      expect(repository.commands, isEmpty);
      c.dispose();
    },
  );
  test(
    'encrypted form saves incomplete named fields without issuing a command',
    () async {
      final c = create();
      await c.initialize();
      await c.begin('create');
      c.edit('name', 'Incomplete synthetic project');
      await c.save();
      expect(c.local!.form['name'], 'Incomplete synthetic project');
      expect(repository.commands, isEmpty);
      expect(await c.canLeave(), isTrue);
      c.dispose();
    },
  );
  test('unknown result survives restart and exact body, timestamp and identity are retried', () async {
    final c = create();
    await creation(c);
    repository.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic lost response',
      retryable: true,
    );
    await c.send();
    final original = c.pending!.envelope;
    c.edit('name', 'Changed');
    expect(c.form!['name'], 'Synthetic new project');
    await c.begin('create');
    expect(c.pending!.envelope.commandId, original.commandId);
    c.dispose();
    final resumed = create();
    await resumed.initialize();
    await resumed.resume(resumed.recovery.single);
    repository.failure = null;
    await resumed.send();
    final retry = repository.commands.last;
    expect(retry.commandId, original.commandId);
    expect(retry.idempotencyKey, original.idempotencyKey);
    expect(retry.clientTimestamp, original.clientTimestamp);
    expect(retry.payload, original.payload);
    expect(resumed.confirmed, isNotNull);
    expect(resumed.pending, isNull);
    resumed.dispose();
  });
  test(
    'current confirmation remains known when optional directory refresh fails',
    () async {
      final c = create();
      await creation(c);
      repository.failRefresh = true;
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNull);
      expect(c.message, contains('Confirmed'));
      expect(
        await c.drafts['create']!.load(scope, c.form!['id'] as String),
        isNull,
      );
      c.dispose();
    },
  );
  test('confirmed cleanup failure blocks new commands and can be retried independently', () async {
    final c = create();
    await creation(c);
    await db.customStatement(
      "CREATE TEMP TRIGGER project_cleanup_failure BEFORE DELETE ON encrypted_drafts BEGIN SELECT RAISE(ABORT,'Synthetic cleanup failure'); END",
    );
    await c.send();
    expect(c.confirmed, isNotNull);
    expect(c.pending, isNotNull);
    await c.begin('create');
    expect(repository.commands.length, 1);
    await db.customStatement('DROP TRIGGER project_cleanup_failure');
    await c.retryConfirmedCleanup();
    expect(c.pending, isNull);
    expect(c.confirmed, isNotNull);
    expect(repository.commands.length, 1);
    c.dispose();
  });
  test(
    'own receipt reconciliation confirms the exact original command',
    () async {
      final c = create();
      await creation(c);
      repository.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic lost response',
        retryable: true,
      );
      await c.send();
      final sealed = c.pending!.envelope;
      repository.failure = null;
      final response = await repository.command(sealed, 'LKR', 2);
      expect(response['command_id'], sealed.commandId);
      await c.reconcile();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNull);
      c.dispose();
    },
  );
  test('another request receipt cannot clear the pending original', () async {
    final c = create();
    await creation(c);
    repository.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic lost response',
      retryable: true,
    );
    await c.send();
    final original = c.pending!.envelope;
    repository.receipt = {
      'command_id': secondChoice,
      'idempotency_key': original.idempotencyKey,
      'response': {},
    };
    await c.reconcile();
    expect(c.pending!.envelope.commandId, original.commandId);
    expect(c.confirmed, isNull);
    c.dispose();
  });
  test(
    'revocation clears every operational, cost and recovery projection',
    () async {
      final c = create();
      await creation(c);
      await c.select(c.records.single.id);
      await c.show(ProjectSection.cost);
      expect(c.rows, isNotEmpty);
      repository.deny = true;
      await c.checkAccess();
      expect(c.error, 'Project access changed. Select an authorized scope.');
      expect(c.current, isFalse);
      expect(c.records, isEmpty);
      expect(c.rows, isEmpty);
      expect(c.form, isNull);
      expect(c.recovery, isEmpty);
      expect(c.planReview, isNull);
      expect(c.comparison, isNull);
      c.dispose();
    },
  );
  test(
    'revoking private plan authority clears resident decrypted recovery',
    () async {
      final original = create();
      await original.initialize();
      await original.select(original.records.single.id);
      await original.begin('plan');
      original.edit('budget', '1234.56');
      await original.save();
      expect(original.local!.form['budget'], '1234.56');
      original.dispose();
      final resumed = create();
      await resumed.initialize();
      expect(resumed.form, isNull);
      expect(resumed.recovery.single.draft.form['budget'], '1234.56');
      repository.deniedCapability = 'projects.cost.manage';
      await resumed.checkAccess();
      expect(resumed.current, isFalse);
      expect(resumed.recovery, isEmpty);
      expect(resumed.form, isNull);
      expect(resumed.rows, isEmpty);
      resumed.dispose();
      // Revocation clears plaintext; it does not erase the scoped encrypted record.
      repository.deniedCapability = null;
      final restored = create();
      await restored.initialize();
      expect(restored.recovery.single.draft.form['budget'], '1234.56');
      restored.dispose();
    },
  );
  test('validated late command confirmation persists after disposal', () async {
    final c = create();
    await creation(c);
    repository.commandStarted = Completer<void>();
    repository.commandGate = Completer<void>();
    final work = c.send();
    await repository.commandStarted!.future;
    c.dispose();
    repository.commandGate!.complete();
    await work;
    expect(c.confirmed, isNull);
    final restored = create();
    await restored.initialize();
    expect(restored.recovery, isEmpty);
    expect(repository.commands, hasLength(1));
    restored.dispose();
  });
  test('old authority denial cannot revoke a reconnected epoch', () async {
    final c = create();
    await c.initialize();
    repository.deny = true;
    repository.authorityStarted = Completer<void>();
    repository.authorityGate = Completer<void>();
    final work = c.refresh();
    await repository.authorityStarted!.future;
    c.setOnline(false);
    c.setOnline(true);
    repository.deny = false;
    repository.authorityGate!.complete();
    await work;
    expect(c.current, isTrue);
    repository.authorityStarted = null;
    repository.authorityGate = null;
    await c.refresh();
    expect(c.records, isNotEmpty);
    c.dispose();
  });
  test('old directory response cannot populate a reconnected epoch', () async {
    final c = create();
    repository.directoryGate = Completer<void>();
    final work = c.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    c.setOnline(false);
    c.setOnline(true);
    repository.directoryGate!.complete();
    await work;
    expect(c.records, isEmpty);
    repository.directoryGate = null;
    await c.refresh();
    expect(c.records, isNotEmpty);
    c.dispose();
  });
  test(
    'task draft retains an explicit named owner through encrypted restart',
    () async {
      final c = create();
      await c.initialize();
      await c.select(c.records.single.id);
      await c.begin('plan');
      final owner = (await c.choices('employees')).rows.first;
      c.addTask(
        'Owned synthetic task',
        c.selected!.start.value,
        c.selected!.end.value,
        owner: owner,
      );
      expect(
        projectMap((c.form!['tasks'] as List).single)['owner_id'],
        owner.id,
      );
      expect(c.labels[owner.id], owner.name);
      await c.save();
      c.dispose();
      final restored = create();
      await restored.initialize();
      expect(
        projectMap(
          (restored.recovery.single.draft.form['tasks'] as List).single,
        )['owner_id'],
        owner.id,
      );
      restored.dispose();
    },
  );
  test('current MFA denial clears project plaintext and recovery', () async {
    final c = create();
    await creation(c);
    await c.save();
    repository.authorityFailure = const DomainError(
      code: 'MFA_REQUIRED',
      message: 'Synthetic MFA expired',
    );
    await c.checkAccess();
    expect(c.current, isFalse);
    expect(c.form, isNull);
    expect(c.records, isEmpty);
    expect(c.recovery, isEmpty);
    c.dispose();
  });
  test(
    'validated late own receipt persists after disposal without retry',
    () async {
      final c = create();
      await creation(c);
      repository.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic unknown original result',
        retryable: true,
      );
      await c.send();
      final original = c.pending!.envelope;
      repository.receipt = {
        'command_id': original.commandId,
        'idempotency_key': original.idempotencyKey,
        'response': {
          'request_id': original.commandId,
          'command_id': original.commandId,
          'correlation_id': original.commandId,
          'entity': {
            'id': original.payload['id'],
            'tenant_id': scope.tenantId,
            'legal_entity_id': scope.legalEntityId,
            'branch_id': scope.branchId,
            'version': original.expectedEntityVersion! + 1,
            'status': 'open',
            'current_plan_id': null,
          },
          'warnings': <Object?>[],
        },
      };
      repository.receiptStarted = Completer<void>();
      repository.receiptGate = Completer<void>();
      final work = c.reconcile();
      await repository.receiptStarted!.future;
      c.dispose();
      repository.receiptGate!.complete();
      await work;
      final restored = create();
      await restored.initialize();
      expect(restored.recovery, isEmpty);
      expect(repository.commands, hasLength(1));
      restored.dispose();
    },
  );
  test(
    'confirmed cleanup survives restart without dispatching the request again',
    () async {
      final c = create();
      await creation(c);
      await db.customStatement(
        "CREATE TEMP TRIGGER project_ack_cleanup_failure BEFORE DELETE ON encrypted_drafts BEGIN SELECT RAISE(ABORT,'Synthetic cleanup failure'); END",
      );
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNotNull);
      c.dispose();
      await db.customStatement('DROP TRIGGER project_ack_cleanup_failure');
      final restored = create();
      await restored.initialize();
      expect(restored.recovery, isEmpty);
      expect(repository.commands, hasLength(1));
      restored.dispose();
    },
  );
  test(
    'confirmation remains known when encrypted acknowledgement insert fails',
    () async {
      final c = create();
      await creation(c);
      await db.customStatement(
        "CREATE TEMP TRIGGER project_ack_insert_failure BEFORE INSERT ON encrypted_drafts WHEN NEW.entity_type='projects.command.acknowledgement' BEGIN SELECT RAISE(ABORT,'Synthetic acknowledgement failure'); END",
      );
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNotNull);
      expect(c.message, contains('Saving the encrypted confirmation failed'));
      final original = c.pending!.envelope;
      await c.send();
      expect(repository.commands, hasLength(1));
      c.dispose();
      await db.customStatement('DROP TRIGGER project_ack_insert_failure');
      final restored = create();
      await restored.initialize();
      expect(
        restored.recovery.single.draft.pending!.envelope.commandId,
        original.commandId,
      );
      restored.dispose();
    },
  );
  test(
    'connection changes during sealing preserve original without dispatch',
    () async {
      final c = create();
      await creation(c);
      keys.armed = true;
      final work = c.send();
      await keys.readStarted.future;
      c.setOnline(false);
      c.setOnline(true);
      keys.readGate.complete();
      await work;
      expect(repository.commands, isEmpty);
      c.dispose();
      final restored = create();
      await restored.initialize();
      expect(restored.recovery.single.draft.pending, isNotNull);
      final original = restored.recovery.single.draft.pending!.envelope;
      await restored.resume(restored.recovery.single);
      await restored.send();
      expect(repository.commands.single.commandId, original.commandId);
      expect(repository.commands.single.payload, original.payload);
      restored.dispose();
    },
  );
  test('late directory data cannot restore disposed scope', () async {
    final c = create();
    repository.directoryGate = Completer<void>();
    final work = c.initialize();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    repository.directoryGate!.complete();
    await work;
    expect(c.records, isEmpty);
  });
  test(
    'version conflict requires comparison before a new expected version',
    () async {
      final c = create();
      await c.initialize();
      await c.select(c.records.single.id);
      await c.begin('close');
      c.edit('reason', 'Synthetic closure');
      repository.failure = const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Synthetic stale project',
      );
      await c.send();
      expect(c.conflict, isTrue);
      expect(c.pending, isNull);
      c.edit('reason', 'Changed');
      expect(c.form!['reason'], 'Synthetic closure');
      repository.version = 7;
      await c.compare();
      expect(c.comparison!.project.version, 7);
      await c.adoptComparison();
      expect(c.expectedVersion, 7);
      expect(c.conflict, isFalse);
      c.dispose();
    },
  );
  test(
    'time conflict reads its exact target rather than only the first page',
    () async {
      final c = create();
      await c.initialize();
      await c.select(c.records.single.id);
      final time =
          (await repository.detail(
                scope,
                c.selected!.id,
                ProjectSection.time,
              )).rows.single
              as ProjectTime;
      await c.begin('time_cancel', time: time);
      c.edit('reason', 'Synthetic cancellation');
      repository.failure = const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Synthetic stale time',
      );
      await c.send();
      await c.compare();
      expect(repository.reads.last, (ProjectSection.time, time.id));
      c.dispose();
    },
  );
  test('stale rejection reviews the exact original plan at the new project version', () async {
    repository.pendingPlan = true;
    repository.planVersion = 3;
    final c = create();
    await c.initialize();
    await c.select(c.records.single.id);
    final plan = c.rows.single as ProjectPlan;
    await c.begin('reject_plan', plan: plan);
    c.edit('reason', 'Synthetic original basis rejection');
    repository.failure = const DomainError(
      code: 'VERSION_CONFLICT',
      message: 'Concurrent project progress',
    );
    await c.send();
    repository.version = 7;
    await c.compare();
    expect(repository.reads.last, (ProjectSection.plans, plan.id));
    await c.adoptComparison();
    expect(c.conflict, isFalse);
    expect(c.expectedVersion, 7);
    expect(c.planReview!.projectVersion, 7);
    expect(c.planReview!.plan.version, 3);
    expect(c.form!['digest'], plan.digest);
    expect(c.planReview!.tasks.length, 2);
    c.dispose();
  });
  test('approval loads the complete immutable tasks, capacity, private rates and budget', () async {
    repository.pendingPlan = true;
    final c = create();
    await c.initialize();
    await c.select(c.records.single.id);
    final plan = c.rows.single as ProjectPlan;
    await c.begin('approve_plan', plan: plan);
    expect(c.planReview!.tasks.length, 2);
    expect(c.planReview!.resources.single.plannedSeconds, 7200);
    expect(
      c.planReview!.rates.single.hourlyRate.toDecimalString(),
      '18.000000',
    );
    expect(c.planReview!.budget.budget.toDecimalString(), '1000.000000');
    c.dispose();
  });
  test('changing project during full review leaves no approval form or partial private basis', () async {
    repository.pendingPlan = true;
    final c = create();
    await c.initialize();
    await c.select(c.records.single.id);
    final plan = c.rows.single as ProjectPlan;
    repository.changeReview = true;
    await c.begin('approve_plan', plan: plan);
    expect(c.form, isNull);
    expect(c.planReview, isNull);
    expect(repository.commands, isEmpty);
    c.dispose();
  });
  test(
    'cost capability is required before loading or recovering plan approval',
    () async {
      repository.pendingPlan = true;
      final c = create(permissions: {'projects.view', 'projects.approve'});
      await c.initialize();
      await c.select(c.records.single.id);
      await c.begin('approve_plan', plan: c.rows.single as ProjectPlan);
      expect(c.form, isNull);
      expect(repository.reads.where((r) => r.$1.privateCost), isEmpty);
      c.dispose();
    },
  );
  testWidgets(
    'project creation chooses named employee and loads another page',
    (tester) async {
      final c = create();
      await creation(c);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(body: ProjectsWorkspace(controller: c)),
        ),
      );
      await tester.ensureVisible(find.text('Manager: Synthetic manager'));
      await tester.tap(find.text('Manager: Synthetic manager'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic manager'), findsOneWidget);
      await tester.tap(find.text('Load next named page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second named employee'));
      await tester.pumpAndSettle();
      expect(c.form!['manager_id'], secondChoice);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'plan review shows the full frozen commercial and private basis',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      repository.pendingPlan = true;
      final c = create();
      await c.initialize();
      await c.select(c.records.single.id);
      await c.begin('approve_plan', plan: c.rows.single as ProjectPlan);
      await tester.pumpWidget(
        MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(body: ProjectsWorkspace(controller: c)),
        ),
      );
      await tester.ensureVisible(find.textContaining('Internal cost budget:'));
      expect(
        find.textContaining('Internal cost budget: 1000.000000 LKR'),
        findsOneWidget,
      );
      expect(find.textContaining('cost 18.000000'), findsOneWidget);
      expect(find.textContaining('Exact approval digest:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  for (final dark in [false, true]) {
    for (final density in [JentraDensity.comfortable, JentraDensity.compact]) {
      for (final editor in [false, true]) {
        testWidgets(
          'project ${editor ? 'approval' : 'register'} ${dark ? 'dark' : 'light'} ${density.name} 200 percent preview',
          (tester) async {
            tester.view.physicalSize = const Size(1440, 2000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            repository.pendingPlan = editor;
            final c = create();
            await c.initialize();
            if (editor) {
              await c.select(c.records.single.id);
              await c.begin('approve_plan', plan: c.rows.single as ProjectPlan);
            }
            final theme = dark
                ? JentraTheme.dark(density: density)
                : JentraTheme.light(density: density);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(1440, 2000),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('project-preview'),
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: ProjectsWorkspace(controller: c),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('project-preview')),
              matchesGoldenFile(
                'goldens/projects-${editor ? 'approval' : 'register'}-${dark ? 'dark' : 'light'}-${density.name}-200.png',
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
          },
        );
      }
    }
  }
}
