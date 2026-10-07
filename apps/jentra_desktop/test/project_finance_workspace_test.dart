import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_project_finance_platform.dart';
import 'package:jentra_desktop/src/features/projects/project_finance_controller.dart';
import 'package:jentra_desktop/src/features/projects/project_finance_screen.dart';
import 'package:jentra_desktop/src/features/projects/expense_evidence_screen.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_design_system/jentra_design_system.dart';

final samples = projectMap(
  jsonDecode(
    File(
      '../../packages/jentra_platform/test/fixtures/project_finance_rollback_projections.json',
    ).readAsStringSync(),
  ),
);
final source = projectMap(samples['expenses']);
final project = source['project_id'] as String;
final scope = TenantContext(
  tenantId: source['tenant_id'] as String,
  legalEntityId: source['legal_entity_id'] as String,
  branchId: source['branch_id'] as String,
  actorId: '10000000-0000-0000-0000-000000000004',
);
final allCaps = {
  expenseEvidenceView,
  'projects.cost.view',
  'projects.margin.view',
  'projects.billing.manage',
  ...projectFinanceActions.map(projectFinanceCapability),
};

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class Repository implements ProjectFinanceRepository {
  String? denyCapability, expenseStatus;
  bool deny = false, failRead = false;
  DomainError? failure;
  Completer<void>? readGate;
  Completer<void>? commandGate, receiptGate, authorizeGate;
  Completer<void>? evidenceGate;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  Map<String, Object?>? confirmation;
  int currentVersion = 3;
  @override
  Future<void> authorizeEvidence(
    TenantContext s,
    String projectId,
    String expenseId,
  ) async {
    await evidenceGate?.future;
    await authorize(s, 'projects.expenses.evidence.view');
  }

  @override
  Future<void> authorize(TenantContext s, String cap) async {
    await authorizeGate?.future;
    if (deny || denyCapability == cap) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Synthetic access revoked.',
      );
    }
  }

  @override
  Future<ProjectFinancePage<ProjectFinanceRow>> detail(
    TenantContext s,
    String id,
    String currency,
    ProjectFinanceSection section, {
    String? after,
    String? targetId,
  }) async {
    await readGate?.future;
    if (failRead) {
      throw const DomainError(
        code: 'SERVICE_UNAVAILABLE',
        message: 'Optional finance read unavailable.',
      );
    }
    final sample = projectMap(samples[section.name]);
    return ProjectFinancePage(
      (sample['rows'] as List)
          .map(projectMap)
          .where((r) => targetId == null || r['id'] == targetId)
          .map(
            (r) => ProjectFinanceRow.fromJson(
              section,
              section == ProjectFinanceSection.expenses
                  ? {
                      ...r,
                      'version': currentVersion,
                      if (expenseStatus != null) 'status': expenseStatus,
                    }
                  : r,
              currency,
            ),
          )
          .toList(),
      null,
    );
  }

  @override
  Future<ProjectFinancePage<ProjectFinanceChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
    String? projectId,
  }) async => ProjectFinancePage([
    ProjectFinanceChoice.fromJson({
      'id': '20000000-0000-0000-0000-000000000001',
      'name': 'Synthetic named bank',
      'code': 'LAB',
      'version': 2,
      'currency_code': 'LKR',
    }),
  ], null);
  @override
  Future<ProjectMargin> margin(
    TenantContext s,
    String id,
    DateTime asOf,
    CivilDate date,
  ) async => ProjectMargin.fromJson({
    ...projectMap(samples['margin']),
    'as_of': asOf.toIso8601String(),
    'effective_date': date.value,
  });
  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    commands.add(c);
    if (failure != null) {
      throw failure!;
    }
    await commandGate?.future;
    confirmation = {
      'request_id': c.commandId,
      'command_id': c.commandId,
      'correlation_id': c.commandId,
      'warnings': [],
      'entity': {
        'tenant_id': sTenant(c),
        'legal_entity_id': c.context.legalEntityId,
        'branch_id': c.context.branchId,
        'id': c.payload['id'],
        'project_id': project,
        'version': c.expectedEntityVersion! + 1,
        'status': 'posted',
      },
    };
    return confirmation!;
  }

  String sTenant(CommandEnvelope<Map<String, Object?>> c) => c.context.tenantId;
  @override
  Future<Map<String, Object?>?> receipt(
    TenantContext s,
    String commandId,
    String action,
  ) async {
    await receiptGate?.future;
    return confirmation;
  }
}

class EvidenceRepository implements ExpenseEvidenceRepository {
  final calls = <(TenantContext, String?, String?, String)>[];
  @override
  Future<bool> authorize(
    TenantContext s,
    String? p,
    String? x,
    String cap,
  ) async {
    calls.add((s, p, x, cap));
    if (cap != expenseEvidenceView && cap != expenseEvidenceManage) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Synthetic action unavailable.',
      );
    }
    return false;
  }

  @override
  Future<ExpenseEvidencePage> documents(
    TenantContext s,
    String p,
    String x, {
    String? after,
  }) async => const ExpenseEvidencePage([], null);
  @override
  Future<ExpenseEvidenceConfirmation> command(
    CommandEnvelope<Map<String, Object?>> input,
  ) => throw UnsupportedError('No synthetic mutation.');
  @override
  Future<ExpenseEvidenceConfirmation?> receipt(
    TenantContext s,
    String id,
  ) async => null;
  @override
  Future<ExpenseEvidenceConfirmation> upload(
    CommandEnvelope<Map<String, Object?>> input,
    ExpenseEvidenceDocument doc,
    Uint8List bytes,
  ) => throw UnsupportedError('No synthetic upload.');
  @override
  Future<Uint8List> document(
    TenantContext s,
    String p,
    String x,
    ExpenseEvidenceDocument doc, {
    bool export = false,
  }) => throw UnsupportedError('No synthetic private bytes.');
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
  late Repository repo;
  late JentraLocalDatabase db;
  late Keys keys;
  late EncryptedDraftRepository encrypted;
  late ProjectFinanceController c;
  ProjectFinanceController make() => ProjectFinanceController(
    scope: scope,
    projectId: project,
    currency: 'LKR',
    precision: 2,
    repository: repo,
    permissions: allCaps,
    drafts: {
      for (final a in projectFinanceActions)
        a: projectFinanceDrafts(encrypted, a),
    },
    online: true,
    monitor: false,
  );
  setUp(() async {
    repo = Repository();
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    encrypted = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
    c = make();
    await c.initialize();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test(
    'AC-415 original expense approval loads immutable money and digest',
    () async {
      final row = c.rows.single;
      await c.begin('expense_approve', row: row);
      expect(c.form!['digest'], row.values['digest']);
      expect(c.review!.values['gross'], '0.030000');
      expect(c.expectedVersion, 3);
    },
  );
  test(
    'AC-416 uncertain exact request survives controller restart and retry',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic original posting');
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic interrupted response',
        retryable: true,
      );
      await c.send();
      final before = c.pending!.toJson();
      c.change('posting_date', '2000-01-01');
      expect(c.pending!.toJson(), before);
      c.dispose();
      c = make();
      await c.initialize();
      await c.resume(c.recovery.single);
      expect(c.pending!.toJson(), before);
      repo.failure = null;
      await c.send();
      expect(
        repo.commands[0].toJson((p) => p),
        repo.commands[1].toJson((p) => p),
      );
      expect(c.confirmed, isNotNull);
      expect(c.recovery, isEmpty);
    },
  );
  test(
    'AC-415 recovered approval reloads complete frozen expense before decision',
    () async {
      await c.begin('expense_approve', row: c.rows.single);
      await c.save();
      c.closeForm();
      await c.resume(c.recovery.single);
      expect(c.review!.values['gross'], '0.030000');
      expect(c.review!.values['digest'], c.form!['digest']);
      c.review = null;
      await c.send();
      expect(c.error, contains('Review the complete immutable expense'));
      expect(c.pending, isNull);
    },
  );
  test('AC-416 confirmed posting survives optional read failure', () async {
    await c.begin('expense_post', row: c.rows.single);
    c.change('reason', 'Synthetic known confirmation');
    repo.failRead = true;
    await c.send();
    expect(c.confirmed, isNotNull);
    expect(c.pending, isNull);
    expect(c.message, contains('Confirmed'));
  });
  test(
    'AC-416 late validated command persists acknowledgement after disposal',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Private synthetic late confirmation');
      repo.commandGate = Completer<void>();
      final sending = c.send();
      while (repo.commands.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final request = c.pending!;
      c.dispose();
      repo.commandGate!.complete();
      await sending;
      expect(c.form, isNull);
      expect(c.confirmed, isNull);
      expect(
        await ProjectFinanceCommandAcknowledgements(
          projectFinanceDrafts(encrypted, request.action),
        ).contains(request),
        isTrue,
      );
      expect(
        await projectFinanceDrafts(
          encrypted,
          request.action,
        ).load(scope, request.envelope.payload['id'] as String),
        isNull,
      );
      c = make();
      await c.initialize();
      expect(c.recovery, isEmpty);
      expect(repo.commands, hasLength(1));
    },
  );
  test(
    'AC-416 connection change during authorization prevents dispatch',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic connectivity change');
      repo.authorizeGate = Completer<void>();
      final sending = c.send();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.setOnline(false);
      c.closeForm();
      expect(c.form, isNotNull);
      repo.authorizeGate!.complete();
      await sending;
      expect(repo.commands, isEmpty);
      expect(c.pending, isNull);
      c.setOnline(true);
      await c.send();
      expect(repo.commands, hasLength(1));
      expect(c.confirmed, isNotNull);
    },
  );
  test(
    'AC-416 late own receipt persists acknowledgement after disposal',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Private synthetic receipt');
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Interrupted',
        retryable: true,
      );
      await c.send();
      final request = c.pending!;
      repo.failure = null;
      await repo.command(request.envelope);
      repo.receiptGate = Completer<void>();
      final reading = c.reconcile();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.dispose();
      repo.receiptGate!.complete();
      await reading;
      expect(
        await ProjectFinanceCommandAcknowledgements(
          projectFinanceDrafts(encrypted, request.action),
        ).contains(request),
        isTrue,
      );
      c = make();
      await c.initialize();
      expect(c.recovery, isEmpty);
      expect(c.confirmed, isNull);
    },
  );
  test('AC-416 reconnect requires fresh authority before dispatch', () async {
    await c.begin('expense_post', row: c.rows.single);
    c.change('reason', 'Synthetic rapid reconnect');
    repo.authorizeGate = Completer<void>();
    final sending = c.send();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    c.setOnline(false);
    c.setOnline(true);
    repo.authorizeGate!.complete();
    await sending;
    expect(repo.commands, isEmpty);
    expect(c.pending, isNull);
    repo.authorizeGate = null;
    await c.send();
    expect(repo.commands, hasLength(1));
    expect(c.confirmed, isNotNull);
  });
  test(
    'AC-428 protected service costs retain original zero cancellation basis',
    () async {
      await c.load(ProjectFinanceSection.serviceCosts);
      expect(c.rows, hasLength(4));
      expect(
        c.rows.where((r) => r.status == 'cancelled').single.amount!.minorUnits,
        BigInt.zero,
      );
      repo.denyCapability = 'projects.cost.view';
      await c.checkAccess();
      expect(c.denied, isTrue);
      expect(c.rows, isEmpty);
      expect(c.report, isNull);
    },
  );
  test('AC-416 durable confirmation prevents restart dispatch after cleanup failure', () async {
    await c.begin('expense_post', row: c.rows.single);
    c.change('reason', 'Private synthetic cleanup failure');
    repo.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Interrupted',
      retryable: true,
    );
    await c.send();
    final saved = c.recovery.single, request = c.pending!;
    await db.customStatement(
      "CREATE TRIGGER finance_cleanup_failure BEFORE DELETE ON encrypted_drafts WHEN OLD.entity_type='projects.finance.expense_post' BEGIN SELECT RAISE(ABORT,'synthetic_cleanup_failure'); END",
    );
    repo.failure = null;
    await c.send();
    expect(c.confirmed, isNotNull);
    expect(c.message, contains('cleanup needs retry'));
    expect(await c.canLeave(), isTrue);
    final ackIds = await encrypted.pageIds(
      tenantId: scope.tenantId,
      entityType: ProjectFinanceCommandAcknowledgements.entityType,
    );
    final ack = await encrypted.find(ackIds.single);
    expect(ack!.payload.keys.toSet(), {
      'scope',
      'action',
      'command_id',
      'idempotency_key',
      'entity_id',
      'project_id',
      'version',
      'request_digest',
    });
    expect(jsonEncode(ack.payload), isNot(contains('Private synthetic')));
    c.dispose();
    c = make();
    await c.initialize();
    expect(c.recovery, isEmpty);
    await c.resume(saved);
    await c.send();
    expect(repo.commands, hasLength(2));
    expect(
      await ProjectFinanceCommandAcknowledgements(
        projectFinanceDrafts(encrypted, request.action),
      ).contains(request),
      isTrue,
    );
    await db.customStatement('DROP TRIGGER finance_cleanup_failure');
    await c.resume(saved);
    expect(
      await projectFinanceDrafts(
        encrypted,
        request.action,
      ).load(scope, request.envelope.payload['id'] as String),
      isNull,
    );
  });
  test(
    'AC-416 known confirmation survives acknowledgement storage failure',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic acknowledgement storage failure');
      await db.customStatement(
        "CREATE TEMP TRIGGER finance_ack_insert_failure BEFORE INSERT ON encrypted_drafts WHEN NEW.entity_type='projects.finance.command.acknowledgement' BEGIN SELECT RAISE(ABORT,'Synthetic acknowledgement failure'); END",
      );
      await c.send();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNotNull);
      expect(
        c.message,
        contains('Saving the encrypted acknowledgement needs retry'),
      );
      final original = c.pending!.envelope;
      await c.send();
      expect(repo.commands, hasLength(1));
      c.dispose();
      await db.customStatement('DROP TRIGGER finance_ack_insert_failure');
      c = make();
      await c.initialize();
      expect(
        c.recovery.single.draft.pending!.envelope.commandId,
        original.commandId,
      );
      await c.resume(c.recovery.single);
      await c.reconcile();
      expect(c.confirmed, isNotNull);
      expect(repo.commands, hasLength(1));
    },
  );
  test(
    'AC-415 revocation clears protected views and preserves encrypted pending',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic protected request');
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic interrupted',
        retryable: true,
      );
      await c.send();
      final id = c.form!['id'] as String;
      repo.deny = true;
      await c.checkAccess();
      expect(c.denied, isTrue);
      expect(c.rows, isEmpty);
      expect(c.form, isNull);
      expect(c.recovery, isEmpty);
      expect(
        (await projectFinanceDrafts(
          encrypted,
          'expense_post',
        ).load(scope, id))!.pending,
        isNotNull,
      );
    },
  );
  test(
    'AC-416 stale version needs comparison and explicit replacement',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic stale version');
      repo.failure = const DomainError(
        code: 'VERSION_CONFLICT',
        message: 'Stale synthetic version',
      );
      await c.send();
      expect(c.conflict, isTrue);
      expect(c.pending, isNull);
      repo.currentVersion = 4;
      await c.compare();
      expect(c.comparison!.version, 4);
      await c.replace();
      expect(c.expectedVersion, 4);
      expect(c.conflict, isFalse);
    },
  );
  test('AC-416 disposed in-flight view cannot restore finance data', () async {
    repo.readGate = Completer<void>();
    final reading = c.load(ProjectFinanceSection.billing);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    c.dispose();
    repo.readGate!.complete();
    await reading;
    expect(c.rows, isEmpty);
    c = make();
  });
  test(
    'AC-416 recovery pages exclude another project in same actor scope',
    () async {
      final p = {
        'action': 'billing_prepare',
        'id': '10000000-0000-0000-0000-000000000010',
        'project_id': '10000000-0000-0000-0000-000000000011',
        'reason': 'Other synthetic project',
      };
      await projectFinanceDrafts(
        encrypted,
        'billing_prepare',
      ).save(scope, p['id']!, 'billing_prepare', p, 0);
      await c.initialize();
      expect(c.recovery, isEmpty);
    },
  );
  test(
    'AC-416 exact original receipt reconciliation removes pending',
    () async {
      await c.begin('expense_post', row: c.rows.single);
      c.change('reason', 'Synthetic receipt reconciliation');
      repo.failure = const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic interrupted',
        retryable: true,
      );
      await c.send();
      final sealed = c.pending!;
      repo.failure = null;
      await repo.command(sealed.envelope);
      await c.reconcile();
      expect(c.confirmed, isNotNull);
      expect(c.pending, isNull);
    },
  );
  test(
    'AC-415 resident margin is cleared when its capability is revoked',
    () async {
      await c.loadMargin(DateTime.now().toUtc(), CivilDate.parse('2026-10-02'));
      await c.load(ProjectFinanceSection.billing);
      repo.denyCapability = 'projects.margin.view';
      await c.checkAccess();
      expect(c.report, isNull);
      expect(c.denied, isTrue);
    },
  );
  test('FR426 resident selected proofs clear when private evidence authority changes', () async {
    await c.begin('expense_create');
    final expense = projectMap(
      (projectMap(samples['attachedExpenses'])['rows'] as List).single,
    );
    c.change('evidence_documents', expense['evidence_documents']);
    repo.denyCapability = 'projects.expenses.evidence.view';
    await c.checkAccess();
    expect(c.denied, isTrue);
    expect(c.form, isNull);
    expect(c.review, isNull);
    expect(c.recovery, isEmpty);
  });
  test(
    'FR426 stale private authorization cannot open evidence after reconnect',
    () async {
      await c.begin('expense_create');
      repo.evidenceGate = Completer<void>();
      final opening = c.openEvidence(c.form!['id'] as String);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.setOnline(false);
      c.setOnline(true);
      repo.evidenceGate!.complete();
      expect(await opening, isFalse);
      expect(c.denied, isFalse);
      expect(c.error, contains('Refresh current private'));
    },
  );
  testWidgets(
    'FR426 open document panel uses original expense scope and clears on revocation',
    (tester) async {
      final evidence = EvidenceRepository();
      await c.begin('expense_create');
      final expenseId = c.form!['id'] as String;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectExpenseEvidenceRepositoryProvider.overrideWithValue(
              evidence,
            ),
            encryptedDraftRepositoryProvider.overrideWithValue(encrypted),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ProjectFinanceScreen(
                projectId: project,
                projectName: 'Synthetic project',
                currency: 'LKR',
                precision: 2,
                controller: c,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Select protected documents'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select protected documents'));
      await tester.pumpAndSettle();
      final panel = tester.widget<ExpenseEvidencePanel>(
        find.byType(ExpenseEvidencePanel),
      );
      expect(panel.scope, scope);
      expect(panel.projectId, project);
      expect(panel.expenseId, expenseId);
      expect(panel.initialProofs, isEmpty);
      expect(
        evidence.calls,
        contains((scope, project, expenseId, expenseEvidenceView)),
      );
      repo.denyCapability = expenseEvidenceView;
      await c.checkAccess();
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseEvidencePanel), findsNothing);
      expect(
        find.text(
          'Protected documents cleared. Refresh current access before reopening.',
        ),
        findsOneWidget,
      );
      expect(c.form, isNull);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close documents'));
      await tester.pumpAndSettle();
    },
  );
  test('FR426 encrypted selected proof recovery is reauthorized before plaintext installation', () async {
    final wire = projectMap(
      (projectMap(samples['attachedExpenses'])['rows'] as List).single,
    );
    final form = {
      for (final k in projectFinanceFields(
        'expense_correct',
      ).difference({'action', 'reason'}))
        k: wire[k],
      'action': 'expense_correct',
      'reason': 'Synthetic protected recovery',
    };
    form['allocations'] = (wire['allocations'] as List).map((x) {
      final v = projectMap(x);
      return {'task_id': v['task_id'], 'weight': v['weight']};
    }).toList();
    await projectFinanceDrafts(encrypted, 'expense_correct').save(
      scope,
      wire['id'] as String,
      'expense_correct',
      form,
      wire['version'] as int,
    );
    c.dispose();
    repo.denyCapability = 'projects.expenses.evidence.view';
    c = ProjectFinanceController(
      scope: scope,
      projectId: project,
      currency: 'LKR',
      precision: 2,
      repository: repo,
      permissions: allCaps,
      drafts: {
        for (final action in projectFinanceActions)
          action: projectFinanceDrafts(encrypted, action),
      },
      online: true,
    );
    await c.initialize();
    expect(c.denied, isTrue);
    expect(c.recovery, isEmpty);
    expect(
      await projectFinanceDrafts(
        encrypted,
        'expense_correct',
      ).load(scope, wire['id'] as String),
      isNotNull,
    );
  });
  test('FR426 financial confirmation cannot be borrowed by a changed exact request', () async {
    await c.begin('expense_post', row: c.rows.single);
    c.change('reason', 'Synthetic exact confirmation');
    repo.failure = const DomainError(
      code: 'UNCERTAIN_RESULT',
      message: 'Synthetic interruption',
      retryable: true,
    );
    await c.send();
    final original = c.pending!;
    repo.failure = null;
    final response = await repo.command(original.envelope);
    final acknowledgement = ProjectFinanceCommandAcknowledgements(
      c.drafts[original.action]!,
    );
    await acknowledgement.save(original, response);
    expect(
      await acknowledgement.contains(
        ScopedPendingCommand.fromJson(original.toJson()),
      ),
      isTrue,
    );
    final modified = original.toJson(),
        envelope = projectMap(modified['envelope']);
    envelope['payload'] = {
      ...projectMap(envelope['payload']),
      'reason': 'Changed private request',
    };
    modified['envelope'] = envelope;
    await expectLater(
      acknowledgement.contains(ScopedPendingCommand.fromJson(modified)),
      throwsA(isA<DomainError>()),
    );
    final timestamp = original.toJson(),
        issued = projectMap(timestamp['envelope']);
    issued['client_timestamp'] = DateTime.utc(2026, 10, 6).toIso8601String();
    timestamp['envelope'] = issued;
    await expectLater(
      acknowledgement.contains(ScopedPendingCommand.fromJson(timestamp)),
      throwsA(isA<DomainError>()),
    );
  });
  test('AC-415 resident decrypted recovery is reauthorized independently of section', () async {
    await c.begin('expense_post', row: c.rows.single);
    c.change('reason', 'Private synthetic recovery');
    await c.save();
    final id = c.form!['id'] as String;
    c.closeForm();
    await c.load(ProjectFinanceSection.billing);
    expect(c.recovery.single.draft.form['posting_date'], isNotNull);
    repo.denyCapability = 'projects.expenses.post';
    await c.checkAccess();
    expect(c.denied, isTrue);
    expect(c.recovery, isEmpty);
    expect(c.form, isNull);
    expect(
      await projectFinanceDrafts(encrypted, 'expense_post').load(scope, id),
      isNotNull,
    );
  });
  testWidgets(
    'AC-414 populated 1024 finance controls remain reachable at 200 percent',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: JentraTheme.light(),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: ProjectFinanceScreen(
                  projectId: project,
                  projectName: 'Synthetic project',
                  currency: 'LKR',
                  precision: 2,
                  controller: c,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);
      expect(find.text('Prepare invoice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('New expense'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save encrypted draft'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save encrypted draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    for (final density in [JentraDensity.comfortable, JentraDensity.compact]) {
      for (final editor in [false, true]) {
        testWidgets(
          'AC-414 finance ${editor ? 'approval' : 'workspace'} ${dark ? 'dark' : 'light'} ${density.name} 200 percent preview',
          (tester) async {
            tester.view.physicalSize = const Size(1440, 2000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            if (editor) {
              repo.expenseStatus = 'submitted';
              repo.currentVersion = 2;
              await c.load(ProjectFinanceSection.expenses);
              await c.begin('expense_approve', row: c.rows.single);
            }
            final theme = dark
                ? JentraTheme.dark(density: density)
                : JentraTheme.light(density: density);
            await tester.pumpWidget(
              ProviderScope(
                child: MaterialApp(
                  theme: theme,
                  home: MediaQuery(
                    data: const MediaQueryData(
                      size: Size(1440, 2000),
                      textScaler: TextScaler.linear(2),
                    ),
                    child: Scaffold(
                      body: RepaintBoundary(
                        key: const ValueKey('finance-preview'),
                        child: ColoredBox(
                          color: theme.colorScheme.surface,
                          child: ProjectFinanceScreen(
                            projectId: project,
                            projectName: 'Synthetic project',
                            currency: 'LKR',
                            precision: 2,
                            controller: c,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (editor) {
              await tester.ensureVisible(find.text('expense approve').last);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            await expectLater(
              find.byKey(const ValueKey('finance-preview')),
              matchesGoldenFile(
                'goldens/project-finance-${editor ? 'approval' : 'workspace'}-${dark ? 'dark' : 'light'}-${density.name}-200.png',
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
  testWidgets('AC-415 denied finance removes source and actions', (
    tester,
  ) async {
    repo.deny = true;
    await c.checkAccess();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ProjectFinanceScreen(
              projectId: project,
              projectName: 'Synthetic project',
              currency: 'LKR',
              precision: 2,
              controller: c,
            ),
          ),
        ),
      ),
    );
    expect(find.text('New expense'), findsNothing);
    expect(
      find.text('Finance data cleared because access changed.'),
      findsOneWidget,
    );
  });
}
