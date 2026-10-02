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
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_desktop/src/features/projects/project_finance_controller.dart';
import 'package:jentra_desktop/src/features/projects/project_finance_screen.dart';
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
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  Map<String, Object?>? confirmation;
  int currentVersion = 3;
  @override
  Future<void> authorize(TenantContext s, String cap) async {
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
  ) async => confirmation;
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
