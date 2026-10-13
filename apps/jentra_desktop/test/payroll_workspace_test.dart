import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
import 'package:jentra_desktop/src/features/people/payroll_controller.dart';
import 'package:jentra_desktop/src/features/people/payroll_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001',
    revision = '30000000-0000-0000-0000-000000000001',
    other = '10000000-0000-0000-0000-000000000005';
Map<String, Object?> runRow({String status = 'draft', int version = 1}) => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'name': 'September synthetic payroll',
  'status': status,
  'version': version,
  'currency_code': 'LKR',
  'start_date': '2026-09-01',
  'end_date_exclusive': '2026-10-01',
  'posting_date': '2026-09-30',
  'current_revision_id': status == 'draft' ? null : revision,
  'digest': status == 'draft' ? null : 'a' * 64,
  'employee_count': status == 'draft' ? null : 1,
  'prepared_by': status == 'draft' ? null : other,
  'submitted_by':
      {'submitted', 'approved', 'posted', 'reversed'}.contains(status)
      ? other
      : null,
  'approved_by': {'approved', 'posted', 'reversed'}.contains(status)
      ? scope.actorId
      : null,
  'posted_journal_id': {'posted', 'reversed'}.contains(status)
      ? revision
      : null,
  'reversal_journal_id': status == 'reversed' ? id : null,
  'created_by': scope.actorId,
};
PayrollEmployeeCalculation calcRow() => PayrollEmployeeCalculation.fromJson({
  'id': revision,
  'employee_id': id,
  'employee_name': 'Synthetic colleague',
  'input_digest': 'b' * 64,
  'gross': '1000.000000',
  'deductions': '100.000000',
  'employer_cost': '30.000000',
  'net': '900.000000',
}, 'LKR');

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Files implements PayrollFiles {
  String? path;
  Uint8List? result;
  @override
  Future<String?> chooseExport() async => path;
  @override
  Future<void> write(String path, Uint8List bytes) async {
    result = Uint8List.fromList(bytes);
  }
}

class _Repository implements PayrollRepository {
  Map<String, Object?> row = runRow();
  String? failure;
  bool denied = false, failReads = false;
  bool failEmployeeReads = false;
  Completer<void>? gate;
  Completer<void>? settingsGate;
  final settlementPages = <String?, WorkforcePage<Map<String, Object?>>>{};
  final settlementCursors = <String?>[];
  final sent = <CommandEnvelope<Map<String, Object?>>>[];
  final authorized = <String>[];
  int runReads = 0, selfReads = 0;
  @override
  Future<void> authorize(TenantContext s, String cap) async {
    authorized.add(cap);
    if (denied) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Payroll access changed',
      );
    }
  }

  @override
  Future<Map<String, Object?>?> settings(TenantContext s) async {
    if (settingsGate != null) await settingsGate!.future;
    return {'id': id, 'version': 2};
  }

  @override
  Future<WorkforcePage<PayrollRun>> runs(
    TenantContext s, {
    String? after,
  }) async {
    runReads++;
    if (failReads) {
      throw const DomainError(
        code: 'NETWORK_ERROR',
        message: 'List unavailable',
      );
    }
    return WorkforcePage([PayrollRun.fromJson(row)], null);
  }

  @override
  Future<WorkforcePage<PayrollRuleVersion>> rules(
    TenantContext s, {
    String? after,
  }) async => const WorkforcePage([], null);
  @override
  Future<PayrollRunDetail> detail(
    TenantContext s,
    String runId, {
    String? after,
  }) async => PayrollRunDetail(PayrollRun.fromJson(row), [
    id,
  ], WorkforcePage(row['status'] == 'draft' ? [] : [calcRow()], null));
  @override
  Future<WorkforcePage<Map<String, Object?>>> history(
    TenantContext s,
    String runId, {
    String? after,
  }) async => const WorkforcePage([], null);
  @override
  Future<WorkforcePage<Map<String, Object?>>> obligations(
    TenantContext s,
    String runId, {
    String? after,
  }) async => const WorkforcePage([], null);
  @override
  Future<WorkforcePage<Map<String, Object?>>> settlements(
    TenantContext s,
    String runId, {
    String? after,
  }) async {
    settlementCursors.add(after);
    return settlementPages[after] ?? const WorkforcePage([], null);
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> selfPayslips(
    TenantContext s, {
    String? after,
  }) async {
    selfReads++;
    return const WorkforcePage([], null);
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> payslips(
    TenantContext s,
    String employeeId, {
    String? after,
  }) async {
    if (failEmployeeReads) {
      throw const DomainError(
        code: 'NETWORK_ERROR',
        message: 'Payslips unavailable',
      );
    }
    return WorkforcePage([
      {'id': revision, 'employee_id': employeeId},
    ], null);
  }

  @override
  Future<WorkforcePage<Map<String, Object?>>> assignments(
    TenantContext s,
    String employeeId, {
    String? after,
  }) async {
    if (failEmployeeReads) {
      throw const DomainError(
        code: 'NETWORK_ERROR',
        message: 'Assignments unavailable',
      );
    }
    return WorkforcePage([
      {'id': revision, 'employee_id': employeeId},
    ], null);
  }

  @override
  Future<Map<String, Object?>> execute(
    PayrollCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    sent.add(command);
    if (gate != null) await gate!.future;
    if (failure != null) {
      throw DomainError(
        code: failure!,
        message: 'Payroll request needs attention',
        retryable: failure == 'UNCERTAIN_RESULT',
      );
    }
    final action = command.payload['action'];
    final entity = kind == PayrollCommandKind.run
        ? {
            ...row,
            'id': command.payload['id'],
            'name': command.payload['name'] ?? row['name'],
            'status': switch (action) {
              'create' => 'draft',
              'approve' => 'approved',
              'post' => 'posted',
              _ => 'prepared',
            },
            'version': command.expectedEntityVersion! + 1,
          }
        : {
            'id': command.payload['id'],
            'version': command.expectedEntityVersion! + 1,
            'tenant_id': sTenant(command),
            'legal_entity_id': command.context.legalEntityId,
            'branch_id': command.context.branchId,
            'kind': 'settings',
          };
    return {'command_id': command.commandId, 'entity': entity..remove('name')};
  }

  String sTenant(CommandEnvelope command) => command.context.tenantId;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  late _Repository repo;
  late SensitivePayrollDraftStore store;
  late PayrollController c;
  late DateTime now;
  const caps = {'people.view', 'people.employees.view', ...payrollCapabilities};
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repo = _Repository();
    now = DateTime.utc(2026, 9, 30);
    store = SensitivePayrollDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
      repo.authorize,
      clock: () => now,
    );
    c = PayrollController(
      scope: scope,
      repository: repo,
      employees: null,
      files: _Files(),
      drafts: store,
      permissions: caps,
      online: true,
      clock: () => now,
      monitor: false,
    );
  });
  tearDown(() async {
    if (c.current) c.dispose();
    await db.close();
  });
  Future<void> create() async {
    await c.begin(PayrollCommandKind.run, 'create');
    c.addEmployee(id, 'Synthetic colleague');
    c.update('reason', 'Synthetic test');
  }

  test('separate payroll and self-service permissions control navigation', () {
    expect(
      visibleJentraDestinations({'people.view'})
          .any((d) => d.path == '/people/payroll'),
      isFalse,
    );
    expect(
      visibleJentraDestinations({'people.view', 'people.payroll.payslip.self'})
          .any((d) => d.path == '/people/payroll'),
      isTrue,
    );
  });
  test(
    'uncertain posting preserves exact sealed request and disables mutation',
    () async {
      await create();
      final runId = c.form!['id'] as String;
      repo.failure = 'UNCERTAIN_RESULT';
      await c.submit();
      expect(c.pending, isNotNull);
      final before = c.form;
      c.update('reason', 'Changed');
      expect(c.form, before);
      await c.submit();
      expect(repo.sent.length, 2);
      expect(repo.sent[1].toJson((p) => p), repo.sent[0].toJson((p) => p));
      expect(
        await store.receipt(scope, PayrollCommandKind.run, runId),
        isNotNull,
      );
      await c.discard();
      expect(c.form, isNotNull);
    },
  );
  test(
    'confirmation clears encrypted recovery before optional list failure',
    () async {
      await create();
      final runId = c.form!['id'] as String;
      await c.submit();
      expect(c.confirmed, isNotNull);
      expect(await store.receipt(scope, PayrollCommandKind.run, runId), isNull);
      repo.failReads = true;
      await c.closeEditor();
      expect(c.error, 'List unavailable');
      expect(repo.sent.length, 1);
      expect(await store.recovery(scope), isEmpty);
    },
  );
  test('access revocation clears private visible data while retaining encrypted uncertainty', () async {
    await create();
    repo.failure = 'UNCERTAIN_RESULT';
    await c.submit();
    final rows = await db.select(db.encryptedDrafts).get();
    expect(rows.length, 2);
    repo.denied = true;
    await c.checkAccess();
    expect(c.current, isFalse);
    expect(c.form, isNull);
    expect(c.runs, isEmpty);
    expect((await db.select(db.encryptedDrafts).get()).length, 2);
  });
  test(
    'late response after scope disposal cannot clear original receipt',
    () async {
      await create();
      repo.gate = Completer<void>();
      final request = c.submit();
      while (repo.sent.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final runId = repo.sent.single.payload['id'] as String;
      c.dispose();
      repo.gate!.complete();
      await request;
      expect(c.form, isNull);
      expect(c.confirmed, isNull);
      expect(
        await store.receipt(scope, PayrollCommandKind.run, runId),
        isNotNull,
      );
    },
  );
  test(
    'private expiry clears editor and recovery retains only receipt',
    () async {
      await create();
      repo.failure = 'UNCERTAIN_RESULT';
      await c.submit();
      now = now.add(const Duration(hours: 24));
      await c.checkAccess();
      expect(c.form, isNull);
      expect((await store.recovery(scope)).single.expired, isTrue);
    },
  );
  test(
    'source conflict requires comparison before exact revision replacement',
    () async {
      repo.row = runRow(status: 'submitted', version: 4);
      await c.openRun(id);
      await c.begin(PayrollCommandKind.run, 'approve');
      c.update('reason', 'Synthetic approval');
      repo.failure = 'PAYROLL_INPUTS_CHANGED';
      await c.submit();
      expect(c.conflict, isTrue);
      expect(c.pending, isNull);
      await c.compare();
      expect(c.comparison?['version'], 4);
      await c.acceptComparison();
      expect(c.conflict, isFalse);
      expect(c.expectedVersion, 4);
    },
  );
  test('independent approval rejects the preparer and approval is bound to current digest', () async {
    repo.row = runRow(status: 'submitted')..['prepared_by'] = scope.actorId;
    await c.openRun(id);
    expect(c.canTransition('approve'), isFalse);
    await c.begin(PayrollCommandKind.run, 'approve');
    expect(c.form, isNull);
    repo.row = runRow(status: 'submitted');
    await c.openRun(id);
    await c.begin(PayrollCommandKind.run, 'approve');
    expect(c.form?['digest'], 'a' * 64);
    expect(c.form?['revision_id'], revision);
  });
  test(
    'late settings comparison cannot restore data after scope disposal',
    () async {
      await c.begin(PayrollCommandKind.configuration, 'settings');
      c.update('net_account_id', id);
      c.update('reason', 'Synthetic settings');
      repo.failure = 'VERSION_CONFLICT';
      await c.submit();
      expect(c.conflict, isTrue);
      repo.settingsGate = Completer<void>();
      final compare = c.compare();
      await Future<void>.delayed(Duration.zero);
      c.dispose();
      repo.settingsGate!.complete();
      await compare;
      expect(c.comparison, isNull);
      expect(c.form, isNull);
    },
  );
  test('settlement conflict scans subsequent bounded pages', () async {
    repo.row = runRow(status: 'posted');
    await c.openRun(id);
    await c.begin(
      PayrollCommandKind.settlement,
      'reverse',
      source: {'id': revision, 'status': 'recorded', 'version': 1},
    );
    c.update('reason', 'Synthetic settlement reversal');
    repo.failure = 'VERSION_CONFLICT';
    await c.submit();
    expect(c.conflict, isTrue);
    repo.settlementPages[null] = WorkforcePage([
      {'id': id, 'version': 1},
    ], id);
    repo.settlementPages[id] = WorkforcePage([
      {'id': revision, 'version': 2},
    ], null);
    repo.settlementCursors.clear();
    await c.compare();
    expect(c.comparison?['id'], revision);
    expect(c.comparison?['version'], 2);
    expect(repo.settlementCursors, [null, id]);
  });
  test('rule basis and classification retain valid exact fields', () async {
    await c.begin(PayrollCommandKind.configuration, 'publish');
    expect(c.form?['ratio_numerator'], 1);
    c.update('basis', 'earnings_ratio');
    expect(c.form?['amount'], '0.000000');
    c.update('classification', 'deduction');
    expect(c.form?['expense_account_id'], isNull);
    c.update('basis', 'hourly');
    expect(c.form?['proration'], 'none');
    expect(c.form?['ratio_denominator'], 1);
  });
  for (final basis in ['earnings_ratio', 'fixed']) {
    test(
      'HR audit: next $basis rule version preserves pay terms and uses nonoverlapping dates',
      () async {
        final rule = PayrollRuleVersion.fromJson({
          'id': revision,
          'component_id': id,
          'version': 3,
          'code': basis == 'fixed' ? 'BASE' : 'PERCENT',
          'name': 'Synthetic existing component',
          'classification': basis == 'fixed' ? 'earning' : 'deduction',
          'start_date': '2026-09-01',
          'end_date_exclusive': '2026-10-01',
          'currency_code': 'LKR',
          'basis': basis,
          'proration': basis == 'fixed' ? 'eligible_days' : 'none',
          'rounding': 'half_even',
          'precision': 3,
          'amount': basis == 'fixed' ? '1000.000000' : '0.000000',
          'ratio_numerator': basis == 'fixed' ? 1 : 8,
          'ratio_denominator': basis == 'fixed' ? 1 : 100,
          'cap': '50.000000',
          'expense_account_id': basis == 'fixed' ? other : null,
          'liability_account_id': basis == 'fixed' ? null : other,
          'reason': 'Synthetic published terms',
          'published_by': other,
          'published_at': '2026-08-31T00:00:00Z',
        });
        c.selectRule(rule);
        await c.begin(PayrollCommandKind.configuration, 'publish');
        expect(c.expectedVersion, 3);
        expect(c.form?['component_id'], id);
        expect(c.form?['id'], isNot(revision));
        expect(c.form?['ratio_numerator'], basis == 'fixed' ? 1 : 8);
        expect(c.form?['ratio_denominator'], basis == 'fixed' ? 1 : 100);
        expect(
          c.form?['proration'],
          basis == 'fixed' ? 'eligible_days' : 'none',
        );
        expect(c.form?['rounding'], 'half_even');
        expect(c.form?['precision'], 3);
        expect(c.form?['cap'], '50.000000');
        expect(c.form?['start_date'], '2026-10-01');
        expect(
          CivilDate.parse(c.form!['end_date_exclusive'] as String)
              .compareTo(rule.rule.endExclusive),
          greaterThan(0),
        );
        c.update('reason', 'Synthetic renewal');
        PayrollCommands.validate(
          PayrollCommandKind.configuration,
          c.form!,
          c.expectedVersion,
        );
      },
    );
  }
  test(
    'HR audit: failed employee switch cannot relabel another employee payslips',
    () async {
      await c.changeView(PayrollView.payslips);
      await c.selectEmployee(id, 'First colleague');
      expect(c.payslips.single['employee_id'], id);
      c.cursor = revision;
      repo.failEmployeeReads = true;
      await c.selectEmployee(other, 'Second colleague');
      expect(c.employeeId, other);
      expect(c.error, 'Payslips unavailable');
      expect(c.payslips, isEmpty);
      expect(c.selectedPayslip, isNull);
      expect(c.cursor, isNull);
    },
  );
  test(
    'HR audit: failed employee switch clears prior payroll assignments',
    () async {
      await c.changeView(PayrollView.rules);
      await c.selectEmployee(id, 'First colleague');
      expect(c.assignments.single['employee_id'], id);
      c.assignmentCursor = revision;
      repo.failEmployeeReads = true;
      await c.selectEmployee(other, 'Second colleague');
      expect(c.employeeId, other);
      expect(c.error, 'Assignments unavailable');
      expect(c.assignments, isEmpty);
      expect(c.assignmentCursor, isNull);
    },
  );
  test(
    'self-only workspace uses accepted-link self API without payroll run reads',
    () async {
      c.dispose();
      c = PayrollController(
        scope: scope,
        repository: repo,
        employees: null,
        files: _Files(),
        drafts: store,
        permissions: {'people.view', 'people.payroll.payslip.self'},
        online: true,
        monitor: false,
      );
      await c.initialize();
      expect(c.views, [PayrollView.self]);
      expect(repo.selfReads, 1);
      expect(repo.runReads, 0);
    },
  );
  testWidgets(
    'run workspace renders exact totals and permission-aware actions',
    (tester) async {
      repo.row = runRow(status: 'submitted');
      await c.initialize();
      await c.openRun(id);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayrollWorkspace(controller: c)),
        ),
      );
      expect(find.text('Synthetic development'), findsOneWidget);
      expect(find.text('Approve revision'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Synthetic colleague'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('900.000000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'run editor uses employee chooser and never asks for raw UUIDs or JSON',
    (tester) async {
      await create();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PayrollEditor(controller: c)),
        ),
      );
      expect(find.text('Add eligible employee'), findsOneWidget);
      expect(find.text('Synthetic colleague'), findsOneWidget);
      expect(find.textContaining('UUID'), findsNothing);
      expect(find.textContaining('JSON'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'payroll workspace ${dark ? 'dark' : 'light'} at 200 percent text scale',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        repo.row = runRow(status: 'submitted');
        await c.initialize();
        await c.openRun(id);
        await tester.pumpWidget(
          MaterialApp(
            theme: JentraTheme.light(),
            darkTheme: JentraTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1440, 1100),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('payroll'),
                  child: ColoredBox(
                    color: dark
                        ? JentraTheme.dark().scaffoldBackgroundColor
                        : JentraTheme.light().scaffoldBackgroundColor,
                    child: PayrollWorkspace(controller: c),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('payroll')),
          matchesGoldenFile(
            'goldens/payroll_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'payroll editor ${dark ? 'dark' : 'light'} compact at 1024 and 200 percent',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await c.begin(PayrollCommandKind.configuration, 'publish');
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? JentraTheme.dark(density: JentraDensity.compact)
                : JentraTheme.light(density: JentraDensity.compact),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1024, 720),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('payroll-editor'),
                  child: PayrollEditor(controller: c),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('payroll-editor')),
          matchesGoldenFile(
            'goldens/payroll_editor_${dark ? 'dark' : 'light'}_compact_200.png',
          ),
        );
      },
    );
    testWidgets(
      'payroll workspace ${dark ? 'dark' : 'light'} compact at 1920',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await c.initialize();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? JentraTheme.dark(density: JentraDensity.compact)
                : JentraTheme.light(density: JentraDensity.compact),
            home: Scaffold(body: PayrollWorkspace(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
