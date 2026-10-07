import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_milestones.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_milestones_platform.dart';
import 'package:jentra_desktop/src/features/projects/milestones_controller.dart';
import 'package:jentra_desktop/src/features/projects/milestones_screen.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

import 'support/service_paused_keys.dart';

String uid(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final scope = TenantContext(
  tenantId: uid(1),
  actorId: uid(2),
  legalEntityId: uid(3),
  branchId: uid(4),
);
final projectId = uid(5),
    id = uid(6),
    plan = uid(7),
    taskId = uid(8),
    employee = uid(9);
Map<String, Object?> input() => {
  'action': 'create',
  'id': id,
  'project_id': projectId,
  'plan_id': plan,
  'task_id': taskId,
  'owner_id': employee,
  'name': 'Customer acceptance',
  'due_date': '2026-10-05',
  'amount': '125.25',
  'commercial_terms': 'Whole accepted deliverable',
  'payment_terms': 'Payment within 30 days from invoice date',
  'payment_due_days': 30,
  'evidence_reference': 'ACCEPTANCE-01',
  'reason': 'Original commercial terms',
};
MilestoneRecord record() => MilestoneRecord.fromJson(
  {
    'id': id,
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': scope.branchId,
    'project_id': projectId,
    'version': 1,
    'status': 'draft',
    'revision_id': uid(10),
    'plan_id': plan,
    'task_id': taskId,
    'task_name': 'Accepted deliverable',
    'owner_id': employee,
    'owner_name': 'Engineer One',
    'customer_id': uid(11),
    'customer_name': 'Customer One',
    'currency_code': 'LKR',
    'precision': 2,
    'name': 'Customer acceptance',
    'due_date': '2026-10-05',
    'amount': '125.250000',
    'commercial_terms': 'Whole accepted deliverable',
    'payment_terms': 'Payment within 30 days from invoice date',
    'payment_due_days': 30,
    'evidence_reference': 'ACCEPTANCE-01',
    'digest': 'a' * 64,
    'recorded_by': scope.actorId,
    'reason': 'Original terms',
    'unit_status': null,
  },
  scope,
  projectId,
);

class ProjectFake extends Fake implements ProjectRepository {
  Completer<void>? taskGate;
  ProjectRecord get project => ProjectRecord.fromJson({
    'id': projectId,
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': scope.branchId,
    'code': 'DELIVERY',
    'name': 'Customer installation',
    'customer_id': uid(11),
    'customer_name': 'Customer One',
    'manager_id': employee,
    'manager_name': 'Engineer One',
    'currency_code': 'LKR',
    'precision': 2,
    'start_date': '2026-10-05',
    'end_date_exclusive': '2026-10-07',
    'version': 4,
    'status': 'open',
    'current_plan_id': plan,
  });
  ProjectTask get task => ProjectTask.fromJson({
    'id': taskId,
    'project_id': projectId,
    'plan_id': plan,
    'name': 'Accepted deliverable',
    'owner_id': employee,
    'owner_name': 'Engineer One',
    'start_date': '2026-10-05',
    'end_date_exclusive': '2026-10-07',
    'planned_seconds': 0,
    'progress': 10000,
    'dependencies': [],
  }, projectId);
  @override
  Future<ProjectDetail> detail(
    TenantContext s,
    String p,
    ProjectSection section, {
    String? parentId,
    String? after,
  }) async {
    await taskGate?.future;
    return ProjectDetail(project, section, [task], null);
  }

  @override
  Future<ProjectPage<ProjectChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
  }) async => ProjectPage([
    ProjectChoice.fromJson({
      'id': employee,
      'name': 'Engineer One',
      'code': 'ENGINEER',
      'version': 1,
    }, 'employees'),
  ], null);
}

class MilestoneFake implements MilestoneRepository {
  @override
  final ProjectFake projects = ProjectFake();
  Completer<void>? commandGate, authorizationGate;
  DomainError? failure, authFailure;
  bool failRead = false;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  Map<String, Object?>? receipt;
  @override
  Future<void> authorize(TenantContext s, String cap) async {
    await authorizationGate?.future;
    if (authFailure != null) throw authFailure!;
  }

  @override
  Future<ProjectPage<MilestoneRecord>> list(
    TenantContext s,
    String p, {
    String? after,
  }) async {
    if (failRead) {
      throw const DomainError(
        code: 'SERVICE_UNAVAILABLE',
        message: 'Optional read failed.',
      );
    }
    return ProjectPage([record()], null);
  }

  @override
  Future<MilestoneDetail> detail(
    TenantContext s,
    String p,
    String id, {
    String kind = 'events',
    String? after,
  }) async => MilestoneDetail(record(), kind, [], null);
  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    await commandGate?.future;
    if (failure != null) throw failure!;
    return receipt = {
      'request_id': c.commandId,
      'command_id': c.commandId,
      'correlation_id': c.commandId,
      'warnings': [],
      'entity': {
        'id': c.payload['id'],
        'tenant_id': sTenant(c),
        'legal_entity_id': c.context.legalEntityId,
        'branch_id': c.context.branchId,
        'project_id': c.payload['project_id'],
        'version': c.expectedEntityVersion! + 1,
        'status': 'draft',
        'revision_id': uid(10),
      },
    };
  }

  String sTenant(CommandEnvelope<Map<String, Object?>> c) => c.context.tenantId;
  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext s,
    String p,
    String a,
    String key,
  ) async => receipt;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late JentraLocalDatabase db;
  late EncryptedDraftRepository encrypted;
  late PausedKeys keys;
  late MilestoneFake repo;
  MilestonesController create() => MilestonesController(
    scope: scope,
    projectId: projectId,
    repository: repo,
    drafts: {
      for (final a in milestoneActions) a: milestoneDraftStore(encrypted, a),
    },
    permissions: {'projects.view', 'projects.manage', 'projects.approve'},
    online: true,
    monitor: false,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = PausedKeys();
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
    repo = MilestoneFake();
  });
  tearDown(() async => db.close());
  Future<void> ready(MilestonesController c) async {
    await c.initialize();
    c.form = input();
    c.expectedVersion = 0;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 1000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(done(), isTrue);
  }

  test(
    'disconnect during sealing freezes original envelope without dispatch',
    () async {
      final c = create();
      await ready(c);
      keys.armed = true;
      final work = c.send();
      await keys.entered.future;
      c.setOnline(false);
      keys.release.complete();
      await work;
      expect(repo.commands, isEmpty);
      final saved = await c.drafts['create']!.load(scope, id);
      expect(saved!.pending, isNotNull);
      final original = saved.pending!.envelope.toJson((p) => p),
          fresh = create();
      await fresh.initialize();
      await fresh.resume(fresh.recovery.single);
      await fresh.retryOriginal();
      expect(repo.commands.single.toJson((p) => p), original);
      expect(await fresh.drafts['create']!.load(scope, id), isNull);
      c.dispose();
      fresh.dispose();
    },
  );
  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'dispose' : 'disconnect'} after dispatch durably acknowledges original scoped receipt',
      () async {
        final c = create();
        await ready(c);
        repo.commandGate = Completer<void>();
        final work = c.send();
        await until(() => repo.commands.isNotEmpty);
        final request = c.pending!;
        if (dispose) {
          c.dispose();
        } else {
          c.setOnline(false);
        }
        repo.commandGate!.complete();
        await work;
        expect(
          await MilestoneCommandAcknowledgements(c.drafts['create']!)
              .contains(request),
          isTrue,
        );
        expect(await c.drafts['create']!.load(scope, id), isNull);
        expect(c.confirmed, false);
        expect(c.records, isEmpty);
        if (!dispose) c.dispose();
      },
    );
  }
  test('MFA revocation clears plaintext draft and scoped records', () async {
    final c = create();
    await ready(c);
    repo.authFailure = const DomainError(
      code: 'MFA_REQUIRED',
      message: 'Fresh MFA required.',
    );
    await c.checkAccess();
    expect(c.denied, true);
    expect(c.form, isNull);
    expect(c.project, isNull);
    expect(c.records, isEmpty);
    c.dispose();
  });
  test(
    'fresh save revocation clears plaintext before surfacing storage failure',
    () async {
      final c = create();
      await ready(c);
      repo.authFailure = const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'No current action authority.',
      );
      await expectLater(c.save(), throwsA(isA<DomainError>()));
      expect(c.denied, true);
      expect(c.form, isNull);
      c.dispose();
    },
  );
  test('uncertain result retains exact sealed request and actor-owned reconciliation', () async {
    final c = create();
    await ready(c);
    repo.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'No reply.',
      retryable: true,
    );
    await c.send();
    final request = c.pending!;
    repo.failure = null;
    await c.retryOriginal();
    expect(repo.commands.length, 2);
    expect(
      repo.commands[0].toJson((p) => p),
      repo.commands[1].toJson((p) => p),
    );
    expect(
      await MilestoneCommandAcknowledgements(c.drafts['create']!)
          .contains(request),
      true,
    );
    c.dispose();
  });
  test('conflict requires explicit current revision binding', () async {
    final c = create();
    await ready(c);
    repo.failure = const DomainError(
      code: 'VERSION_CONFLICT',
      message: 'Changed.',
    );
    await c.send();
    expect(c.conflicted, true);
    expect(c.pending, isNull);
    await c.compare();
    await c.adoptComparison();
    expect(c.expectedVersion, 1);
    expect(c.conflicted, false);
    repo.failure = null;
    await c.send();
    expect(repo.commands.last.expectedEntityVersion, 1);
    c.dispose();
  });
  test('known acknowledgement survives optional read failure', () async {
    final c = create();
    await ready(c);
    repo.failRead = true;
    await c.send();
    expect(c.confirmed, true);
    expect(await c.drafts['create']!.load(scope, id), isNull);
    c.dispose();
  });
  test(
    'known milestone confirmation survives encrypted acknowledgement failure',
    () async {
      final c = create();
      await ready(c);
      await db.customStatement(
        "CREATE TEMP TRIGGER milestone_ack_insert_failure BEFORE INSERT ON encrypted_drafts WHEN NEW.entity_type='projects.milestone.acknowledgement' BEGIN SELECT RAISE(ABORT,'Synthetic acknowledgement failure'); END",
      );
      await c.send();
      expect(c.confirmed, true);
      expect(c.pending, isNotNull);
      expect(c.message, contains('Saving the encrypted confirmation failed'));
      await c.send();
      expect(repo.commands, hasLength(1));
      await db.customStatement('DROP TRIGGER milestone_ack_insert_failure');
      await c.reconcile();
      expect(await c.drafts['create']!.load(scope, id), isNull);
      c.dispose();
    },
  );
  for (final altered in ['body', 'timestamp']) {
    test(
      'milestone acknowledgement rejects altered $altered with reused identities',
      () async {
        final c = create();
        await ready(c);
        repo.commandGate = Completer<void>();
        final work = c.send();
        await until(() => repo.commands.isNotEmpty);
        final original = c.pending!;
        repo.commandGate!.complete();
        await work;
        final e = original.envelope,
            changed = ScopedPendingCommand(
              original.action,
              CommandEnvelope<Map<String, Object?>>(
                commandId: e.commandId,
                idempotencyKey: e.idempotencyKey,
                context: e.context,
                expectedEntityVersion: e.expectedEntityVersion,
                clientTimestamp: altered == 'timestamp'
                    ? e.clientTimestamp.add(const Duration(seconds: 1))
                    : e.clientTimestamp,
                payload: altered == 'body'
                    ? {...e.payload, 'amount': '126.25'}
                    : e.payload,
              ),
            );
        await expectLater(
          MilestoneCommandAcknowledgements(c.drafts['create']!)
              .contains(changed),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'DRAFT_SCOPE_MISMATCH',
            ),
          ),
        );
        c.dispose();
      },
    );
  }
  testWidgets(
    'named task picker cannot repopulate or select after disconnect',
    (tester) async {
      final c = create();
      await c.initialize();
      await c.begin('create');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MilestonesWorkspace(projectId: projectId, controller: c),
          ),
        ),
      );
      repo.projects.taskGate = Completer<void>();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Task: Choose approved task'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task: Choose approved task'));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      c.setOnline(false);
      repo.projects.taskGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Accepted deliverable'), findsNothing);
      expect(c.form, isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  for (final dark in [false, true]) {
    for (final compact in [false, true]) {
      for (final editor in [false, true]) {
        testWidgets(
          '${editor ? 'form' : 'register'} ${dark ? 'dark' : 'light'} ${compact ? 'compact' : 'comfortable'}200 percent',
          (tester) async {
            tester.view.physicalSize = const Size(1024, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final manrope = FontLoader(JentraTypography.sansFamily)
              ..addFont(
                rootBundle.load(
                  'packages/jentra_design_system/assets/fonts/Manrope-Regular.ttf',
                ),
              )
              ..addFont(
                rootBundle.load(
                  'packages/jentra_design_system/assets/fonts/Manrope-SemiBold.ttf',
                ),
              );
            await manrope.load();
            final icons = FontLoader('MaterialIcons')
              ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
            await icons.load();
            final c = create();
            await c.initialize();
            if (editor) {
              await c.begin('create');
              c.form = input();
              c.labels['task_id'] = 'Accepted deliverable';
              c.labels['owner_id'] = 'Engineer One';
            }
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: JentraTheme.light(
                    density: compact
                        ? JentraDensity.compact
                        : JentraDensity.comfortable,
                  ),
                  darkTheme: JentraTheme.dark(
                    density: compact
                        ? JentraDensity.compact
                        : JentraDensity.comfortable,
                  ),
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(2)),
                    child: child!,
                  ),
                  home: RepaintBoundary(
                    key: const ValueKey('milestones'),
                    child: MilestonesWorkspace(
                      projectId: projectId,
                      controller: c,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            if (editor) {
              await tester.scrollUntilVisible(
                find.text('Create milestone'),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
            }
            await expectLater(
              find.byKey(const ValueKey('milestones')),
              matchesGoldenFile(
                'goldens/milestones-${editor ? 'form' : 'register'}-${dark ? 'dark' : 'light'}-${compact ? 'compact' : 'comfortable'}-200.png',
              ),
            );
            await tester.pumpWidget(const SizedBox());
            c.dispose();
          },
        );
      }
    }
  }
}
