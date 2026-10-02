import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/budgets/budget_controller.dart';
import 'package:jentra_desktop/src/features/budgets/budget_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

final class BudgetFake implements BudgetGateway {
  String? failure, readFailure;
  Completer<void>? accountPause, pagePause, generationPause, commandPause;
  final accountEntered = Completer<void>(),
      pageEntered = Completer<void>(),
      generationEntered = Completer<void>(),
      commandEntered = Completer<void>();
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final generations = <CommandEnvelope<Map<String, Object?>>>[];
  final sections = <String>[];
  final versions = <Map<String, Object?>>[];
  final savedReports = <Map<String, Object?>>[];

  void checkRead() {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
  }

  @override
  Future<Map<String, Object?>> accounts(
    TenantContext scope, {
    String? after,
    String search = '',
  }) async {
    if (accountPause != null) {
      if (!accountEntered.isCompleted) accountEntered.complete();
      await accountPause!.future;
    }
    checkRead();
    return {
      'items': [
        {
          'id': 'account',
          'code': '4000',
          'name': 'Revenue',
          'account_type': 'revenue',
        },
      ],
      'next_cursor': null,
      'base_currency_code': 'LKR',
    };
  }

  @override
  Future<Map<String, Object?>> periods(
    TenantContext scope, {
    String? after,
  }) async {
    checkRead();
    return {
      'items': [
        {
          'id': 'august',
          'name': 'August',
          'start_date': '2026-08-01',
          'end_date': '2026-08-31',
        },
      ],
      'next_cursor': null,
    };
  }

  @override
  Future<Map<String, Object?>> budgets(
    TenantContext scope, {
    String? after,
  }) async {
    checkRead();
    return {'items': versions, 'next_cursor': null};
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    checkRead();
    return {'items': savedReports, 'next_cursor': null};
  }

  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (commandPause != null) {
      if (!commandEntered.isCompleted) commandEntered.complete();
      await commandPause!.future;
    }
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    final payload = command.payload;
    final action = payload['action'];
    final source = versions
        .where(
          (row) =>
              row['id'] ==
              (action == 'revise' ? payload['source_id'] : payload['id']),
        )
        .firstOrNull;
    final result = <String, Object?>{
      'id': payload['id'],
      'root_id': source?['root_id'] ?? payload['id'],
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'budget_branch_id': source?['budget_branch_id'] ?? 'branch',
      'revision': action == 'revise'
          ? (source?['revision'] as int? ?? 0) + 1
          : source?['revision'] ?? 1,
      'period_id': source?['period_id'] ?? payload['period_id'],
      'budget_year': source?['budget_year'] ?? payload['budget_year'],
      'currency_code': source?['currency_code'] ?? payload['currency_code'],
      'lines': payload['lines'] ?? source?['lines'],
      'reason': payload['reason'],
      'created_by': source?['created_by'] ?? 'actor',
      'submitted_by': action == 'submit' ? 'actor' : source?['submitted_by'],
      'status': switch (action) {
        'submit' => 'submitted',
        'approve' => 'approved',
        'reject' => 'rejected',
        _ => 'draft',
      },
      'version': action == 'create' || action == 'revise'
          ? 1
          : (source?['version'] as int? ?? 0) + 1,
    };
    versions.removeWhere((row) => row['id'] == result['id']);
    versions.add(result);
    return result;
  }

  Map<String, Object?> summary(Map<String, Object?> payload) => {
    'id': payload['id'],
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'budget_id': payload['budget_id'],
    'as_of': payload['as_of'],
    'currency_code': 'LKR',
    'currency_basis': 'base_all_posted',
    'journal_count': 1,
    'budget_total': '50.000000',
    'actual_total': '60.000000',
    'variance_total': '10.000000',
    'variance_percent': '20.000000',
  };
  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    generations.add(command);
    if (generationPause != null) {
      if (!generationEntered.isCompleted) generationEntered.complete();
      await generationPause!.future;
    }
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    final result = summary(command.payload);
    savedReports.add(result);
    return result;
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId,
    String section, {
    int offset = 0,
    String? budgetLineId,
  }) async {
    if (pagePause != null) {
      if (!pageEntered.isCompleted) pageEntered.complete();
      await pagePause!.future;
    }
    checkRead();
    sections.add(section);
    return {
      'summary': savedReports.where((row) => row['id'] == reportId).first,
      'section': section,
      'budget_line_id': budgetLineId,
      'items': section == 'lines'
          ? [
              {
                'id': 'line',
                'account_id': 'account',
                'code': '4000',
                'name': 'Revenue',
                'budget_amount': '50.000000',
                'actual_amount': '60.000000',
                'variance': '10.000000',
                'source_count': 1,
              },
            ]
          : [
              {
                'id': 'journal-line',
                'budget_line_id': 'line',
                'posting_date': '2026-08-12',
                'document_number': 'J-1',
                'source_type': 'synthetic',
                'source_id': 'source',
                'base_debit': '0.000000',
                'base_credit': '60.000000',
              },
            ],
      'next_offset': null,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    const base = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${base}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${base}Manrope-SemiBold.ttf')))
        .load();
  });
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late JentraLocalDatabase database;
  late QuotationDraftStore drafts;
  late BudgetFake gateway;
  late BudgetController controller;
  BudgetController make({
    bool online = true,
    Set<String> permissions = const {'finance.view', 'finance.budgets.manage'},
  }) => BudgetController(
    scope: scope,
    gateway: gateway,
    drafts: drafts,
    permissions: permissions,
    online: online,
  );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = BudgetFake();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  void ready() {
    controller.field('reason', 'Approved August operating plan');
    controller.addLine('account');
    controller.amount(0, '50.000000');
    controller.field('period_id', 'august');
    controller.field('budget_year', 2026);
  }

  test(
    'uncertain create replays same encrypted envelope after restart',
    () async {
      await controller.initialize();
      ready();
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.act('create');
      expect(controller.pending, true);
      final sealed = gateway.commands.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      expect(
        (controller.form['lines'] as List).single,
        containsPair('amount', '50.000000'),
      );
      controller.amount(0, '51');
      expect(
        (controller.form['lines'] as List).single,
        containsPair('amount', '50.000000'),
      );
      gateway.failure = null;
      await controller.retryBudget();
      expect(gateway.commands.last.toJson((value) => value), sealed);
      expect(controller.pending, false);
      expect(controller.form['status'], 'draft');
    },
  );

  test('invalid amount stays local and sends no command', () async {
    await controller.initialize();
    ready();
    controller.amount(0, '50.1234567');
    await controller.act('create');
    expect(controller.error, contains('exact nonnegative amount'));
    expect(gateway.commands, isEmpty);
  });

  test(
    'independent approval and revision preserve the approved version',
    () async {
      await controller.initialize();
      ready();
      await controller.act('create');
      await controller.act('submit');
      expect(controller.form['status'], 'submitted');
      await controller.act('approve');
      expect(gateway.commands, hasLength(2));
      controller.dispose();
      controller = make(
        permissions: {'finance.view', 'finance.budgets.approve'},
      );
      await controller.initialize();
      await controller.openBudget(gateway.versions.single['id'] as String);
      controller.decisionReason('Independent approval');
      await controller.act('approve');
      expect(controller.form['status'], 'approved');
      expect(controller.form['version'], 3);
      final approvedId = controller.form['id'];
      controller.dispose();
      controller = make();
      await controller.initialize();
      await controller.openBudget(approvedId as String);
      await controller.revise();
      expect(controller.form['source_id'], approvedId);
      controller.field('reason', 'Revised operating plan');
      await controller.act('revise');
      expect(gateway.commands.last.expectedEntityVersion, 3);
      expect(controller.form['revision'], 2);
      expect(
        gateway.versions
            .where((row) => row['id'] == approvedId)
            .single['status'],
        'approved',
      );
    },
  );

  test(
    'uncertain variance replays exact request and drills frozen journals',
    () async {
      gateway.versions.add({
        'id': 'approved',
        'root_id': 'approved',
        'status': 'approved',
        'revision': 1,
        'version': 3,
        'budget_year': 2026,
        'period_id': 'august',
        'currency_code': 'LKR',
        'budget_branch_id': 'branch',
        'lines': [
          {'id': 'line', 'account_id': 'account', 'amount': '50.000000'},
        ],
      });
      await controller.initialize();
      controller.varianceField('budget_id', 'approved');
      controller.varianceField('as_of', '2026-08-31');
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.generate();
      expect(controller.variancePending, true);
      final sealed = gateway.generations.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      gateway.failure = null;
      await controller.retryVariance();
      expect(gateway.generations.last.toJson((value) => value), sealed);
      await controller.chooseSection('journals', lineId: 'line');
      expect(controller.rows.single['document_number'], 'J-1');
      expect(gateway.sections.last, 'journals');
    },
  );

  test('revoked read clears previously viewed figures and sources', () async {
    gateway.versions.add({
      'id': 'approved',
      'root_id': 'approved',
      'status': 'approved',
      'revision': 1,
      'version': 3,
      'budget_year': 2026,
      'period_id': 'august',
      'currency_code': 'LKR',
      'budget_branch_id': 'branch',
      'lines': [
        {'id': 'line', 'account_id': 'account', 'amount': '50.000000'},
      ],
    });
    await controller.initialize();
    controller.varianceField('budget_id', 'approved');
    controller.varianceField('as_of', '2026-08-31');
    await controller.generate();
    expect(controller.summary, isNotEmpty);
    gateway.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.denied, true);
    expect(controller.summary, isEmpty);
    expect(controller.rows, isEmpty);
    expect(controller.form, isEmpty);
  });

  test('offline restore retains drafts but hides server evidence', () async {
    await controller.initialize();
    ready();
    await controller.saveEncrypted();
    controller.dispose();
    controller = make(online: false);
    await controller.initialize();
    expect(controller.verified, false);
    expect(controller.budgets, isEmpty);
    controller.setOnline(true);
    await controller.initialize();
    expect((controller.form['lines'] as List), hasLength(1));
  });

  test('navigation requires finance read', () {
    expect(
      visibleJentraDestinations({})
          .any((item) => item.path == '/finance/budgets'),
      false,
    );
    expect(
      visibleJentraDestinations({'finance.view'})
          .any((item) => item.path == '/finance/budgets'),
      true,
    );
  });

  testWidgets('budget workspace remains usable at 200% text', (tester) async {
    await controller.initialize();
    ready();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: BudgetWorkspace(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Budgets & variance'), findsOneWidget);
    expect(find.text('Create draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'} budget workspace at 200% text', (
      tester,
    ) async {
      await controller.initialize();
      ready();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: BudgetWorkspace(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(BudgetWorkspace),
        matchesGoldenFile('goldens/budgets_${dark ? 'dark' : 'light'}_200.png'),
      );
    });
    testWidgets('${dark ? 'dark' : 'light'} frozen variance at 200% text', (
      tester,
    ) async {
      gateway.versions.add({
        'id': 'approved',
        'root_id': 'approved',
        'status': 'approved',
        'revision': 1,
        'version': 3,
        'budget_year': 2026,
        'period_id': 'august',
        'currency_code': 'LKR',
        'budget_branch_id': 'branch',
        'lines': [
          {'id': 'line', 'account_id': 'account', 'amount': '50.000000'},
        ],
      });
      await controller.initialize();
      controller.varianceField('budget_id', 'approved');
      controller.varianceField('as_of', '2026-08-31');
      await controller.generate();
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? JentraTheme.dark() : JentraTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: BudgetWorkspace(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Frozen variance at 2026-08-31'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -380),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(BudgetWorkspace),
        matchesGoldenFile(
          'goldens/budget_variance_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }
}
