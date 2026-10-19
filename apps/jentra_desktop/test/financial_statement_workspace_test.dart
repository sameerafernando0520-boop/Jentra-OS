import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

final class FinancialStatementFake implements FinancialStatementGateway {
  String? failure, readFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final readSections = <String>[];
  Completer<void>? periodPause, pagePause, generationPause;
  final periodEntered = Completer<void>();
  final pageEntered = Completer<void>();
  final generationEntered = Completer<void>();

  @override
  Future<Map<String, Object?>> periods(
    TenantContext scope, {
    String? after,
  }) async {
    if (periodPause != null) {
      if (!periodEntered.isCompleted) periodEntered.complete();
      await periodPause!.future;
    }
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [
        {
          'id': 'july',
          'name': 'July',
          'start_date': '2026-07-01',
          'end_date': '2026-07-31',
        },
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
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    return {
      'items': [if (commands.isNotEmpty) summary(commands.last.payload)],
      'next_cursor': null,
    };
  }

  Map<String, Object?> summary(Map<String, Object?> payload) => {
    'id': payload['id'],
    'kind': payload['kind'],
    'period_id': payload['period_id'],
    'period_start': '2026-07-01',
    'period_end': '2026-07-31',
    'comparative_period_id': null,
    'comparative_start': null,
    'comparative_end': null,
    'as_of': payload['as_of'],
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'base_currency_code': 'LKR',
    'generated_at': '2026-09-25T00:00:00Z',
    'status': payload['kind'] == 'cash_flow' ? 'blocked' : 'generated',
    'account_count': 2,
    'journal_count': 2,
    'period_debit': '10.000000',
    'period_credit': '10.000000',
    'closing_debit': '10.000000',
    'closing_credit': '10.000000',
    'difference': '0.000000',
    if (payload['kind'] == 'cash_flow')
      'cash_flow': {
        'period_profit': '30.000000',
        'noncash_adjustments': '0.000000',
        'working_capital_change': '-5.000000',
        'operating_cash': '25.000000',
        'investing_cash': '0.000000',
        'financing_cash': '0.000000',
        'net_cash_change': '25.000000',
        'opening_cash': '100.000000',
        'closing_cash': '125.000000',
        'cash_delta': '25.000000',
        'difference': '0.000000',
        'unmapped_count': 1,
        'no_mapped_cash': false,
        'unmapped_accounts': [
          {
            'id': 'receivable',
            'code': '1200',
            'name': 'Receivable',
            'unclassified_movement': '-5.000000',
          },
        ],
      },
  };

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    if (generationPause != null) {
      if (!generationEntered.isCompleted) generationEntered.complete();
      await generationPause!.future;
    }
    if (failure != null) throw DomainError(code: failure!, message: failure!);
    return summary(command.payload);
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId,
    String section, {
    int offset = 0,
    String? accountId,
  }) async {
    if (pagePause != null) {
      if (!pageEntered.isCompleted) pageEntered.complete();
      await pagePause!.future;
    }
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
    readSections.add(section);
    return {
      'summary': summary(commands.last.payload),
      'section': section,
      'account_id': accountId,
      'items': [
        if (section == 'accounts')
          {
            'id': 'cash',
            'account_id': 'cash',
            'code': '1000',
            'name': 'Cash',
            'account_type': 'asset',
            if (commands.last.payload['kind'] == 'cash_flow')
              'cash_flow_category': 'cash',
            'closing_balance': '10.000000',
            'amount': '10.000000',
          }
        else
          {
            'id': 'line',
            'account_id': accountId ?? 'cash',
            'document_number': 'JR-1',
            'posting_date': '2026-07-01',
            'base_debit': '10.000000',
            'base_credit': '0.000000',
            'source_type': 'fixture',
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
  late FinancialStatementFake gateway;
  late FinancialStatementController controller;
  FinancialStatementController make({bool online = true}) =>
      FinancialStatementController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: online,
      );
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(database, DraftCipher(keyStore: Keys())),
    );
    gateway = FinancialStatementFake();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'uncertain generation survives encrypted restart with same envelope',
    () async {
      await controller.initialize();
      controller.field('period_id', 'august');
      controller.field('kind', 'trial_balance');
      controller.field('comparative_period_id', 'july');
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.generate();
      expect(controller.pending, true);
      final original = gateway.commands.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      expect(controller.form['comparative_period_id'], 'july');
      controller.field('as_of', '2026-08-20');
      expect(controller.form['as_of'], '2026-08-31');
      gateway.failure = null;
      await controller.retry();
      expect(gateway.commands.last.toJson((value) => value), original);
      expect(controller.pending, false);
      expect(controller.summary['id'], (original['payload'] as Map)['id']);
    },
  );

  test('invalid cutoff stays local and sends no command', () async {
    await controller.initialize();
    controller.field('as_of', '2030-01-01');
    await controller.generate();
    expect(controller.error, contains('within the selected period'));
    expect(gateway.commands, isEmpty);
  });

  test(
    'late statement initialization cannot verify restored connectivity',
    () async {
      gateway.periodPause = Completer<void>();
      final reading = controller.initialize();
      await gateway.periodEntered.future;
      controller.setOnline(false);
      controller.setOnline(true);
      gateway.periodPause!.complete();
      await reading;
      expect(controller.verified, false);
      expect(controller.periods, isEmpty);
      expect(controller.reports, isEmpty);
      gateway.periodPause = null;
      await controller.initialize();
      expect(controller.verified, true);
    },
  );

  test('late statement page cannot restore cleared journal evidence', () async {
    await controller.initialize();
    await controller.generate();
    gateway.pagePause = Completer<void>();
    final reading = controller.refresh();
    await gateway.pageEntered.future;
    controller.setOnline(false);
    controller.setOnline(true);
    gateway.pagePause!.complete();
    await reading;
    expect(controller.verified, false);
    expect(controller.summary, isEmpty);
    expect(controller.rows, isEmpty);
  });

  test(
    'statement confirmation survives disposal before local acknowledgement',
    () async {
      await controller.initialize();
      gateway.generationPause = Completer<void>();
      final posting = controller.generate();
      await gateway.generationEntered.future;
      controller.dispose();
      controller = make();
      gateway.generationPause!.complete();
      await posting;
      await controller.initialize();
      expect(controller.form['status'], 'generated');
      expect(
        controller.selectedReportId,
        gateway.commands.single.payload['id'],
      );
      expect(controller.pending, false);
      expect(gateway.commands, hasLength(1));
    },
  );

  test('offline recovery hides saved evidence until verification', () async {
    await controller.initialize();
    controller.field('period_id', 'august');
    await controller.save();
    controller.dispose();
    controller = make(online: false);
    await controller.initialize();
    expect(controller.verified, false);
    expect(controller.periods, isEmpty);
    expect(controller.reports, isEmpty);
    controller.setOnline(true);
    await controller.initialize();
    expect(controller.form['period_id'], 'august');
  });

  test('revoked finance read removes previously viewed report data', () async {
    await controller.initialize();
    await controller.generate();
    expect(controller.summary, isNotEmpty);
    gateway.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.denied, true);
    expect(controller.summary, isEmpty);
    expect(controller.rows, isEmpty);
    expect(controller.form, isEmpty);
  });

  test(
    'account drill reads saved journal lines for selected account',
    () async {
      await controller.initialize();
      await controller.generate();
      await controller.chooseSection('journals', account: 'cash');
      expect(controller.accountId, 'cash');
      expect(controller.rows.single['document_number'], 'JR-1');
      expect(gateway.readSections.last, 'journals');
    },
  );

  test('financial statement navigation requires finance view', () {
    expect(
      visibleJentraDestinations({})
          .any((item) => item.path == '/finance/statements'),
      false,
    );
    expect(
      visibleJentraDestinations({'finance.view'})
          .any((item) => item.path == '/finance/statements'),
      true,
    );
  });

  testWidgets('blocked indirect cash flow names unmapped account', (
    tester,
  ) async {
    await controller.initialize();
    controller.field('kind', 'cash_flow');
    await controller.generate();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FinancialStatementWorkspace(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Blocked: classify moving accounts'),
      findsOneWidget,
    );
    expect(find.textContaining('1200 · Receivable'), findsOneWidget);
    expect(find.text('Net cash change'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop statement workspace is usable at 200% text', (
    tester,
  ) async {
    await controller.initialize();
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: FinancialStatementWorkspace(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Financial statements'), findsOneWidget);
    expect(find.text('Generate report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'} report workspace at 200% text', (
      tester,
    ) async {
      await controller.initialize();
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
            child: Scaffold(
              body: FinancialStatementWorkspace(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(FinancialStatementWorkspace),
        matchesGoldenFile(
          'goldens/financial_statements_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'} blocked cash-flow report at 200% text',
      (tester) async {
        await controller.initialize();
        controller.field('kind', 'cash_flow');
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
              child: Scaffold(
                body: FinancialStatementWorkspace(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(FinancialStatementWorkspace),
          matchesGoldenFile(
            'goldens/cash_flow_report_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
