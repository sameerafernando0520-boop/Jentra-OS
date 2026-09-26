import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_screen.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

import 'support/procurement_fakes.dart' show Keys;

final class TaxSummaryFake implements TaxSummaryGateway {
  String? failure, readFailure;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final saved = <Map<String, Object?>>[];
  final controlCalls = <Map<String, Object?>>[];
  Completer<void>? periodPause, pagePause, controlPause, generationPause;
  final periodEntered = Completer<void>();
  final pageEntered = Completer<void>();
  final controlEntered = Completer<void>();
  final generationEntered = Completer<void>();

  Map<String, Object?> control() => {
    'id': 'tax-asset',
    'account_id': 'tax-asset',
    'code': '1450',
    'name': 'Input tax control',
    'account_type': 'asset',
    'source_opening_base': '0.000000',
    'gl_opening_base': '0.000000',
    'source_period_base': '90.100000',
    'gl_period_base': '90.100000',
    'source_closing_base': '90.100000',
    'gl_closing_base': '90.100000',
    'difference': '0.000000',
  };

  void checkRead() {
    if (readFailure != null) {
      throw DomainError(code: readFailure!, message: readFailure!);
    }
  }

  @override
  Future<Map<String, Object?>> periods(
    TenantContext scope, {
    String? after,
  }) async {
    checkRead();
    if (periodPause != null) {
      if (!periodEntered.isCompleted) periodEntered.complete();
      await periodPause!.future;
    }
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

  Map<String, Object?> summary(Map<String, Object?> payload) => {
    'id': payload['id'],
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'branch_filter_id': payload['branch_filter_id'],
    'period_id': 'august',
    'period_start': '2026-08-01',
    'period_end': '2026-08-31',
    'as_of': payload['as_of'],
    'generated_at': '2026-09-26T00:00:00Z',
    'base_currency_code': 'LKR',
    'status': 'blocked',
    'version': 2,
    'notice': 'NON-CERTIFIED • STATUTORY REVIEW REQUIRED',
    'line_count': 2,
    'blocked_count': 1,
    'blockers': [
      {
        'source_type': 'supplier_bill',
        'source_id': 'old-bill',
        'source_line_id': 'old-line',
        'code': 'MISSING_DEFINITION_VERSION',
      },
    ],
    'output_tax_base': '0.000000',
    'input_tax_base': '45.050000',
    'withholding_tax_base': '0.000000',
    'zero_taxable_base': '0.000000',
    'exempt_taxable_base': '0.000000',
    'unverified_tax_base': '45.050000',
    'controls': [control()],
    'control_status': 'reconciled',
    'control_source_count': 2,
    'control_journal_count': 2,
    'control_difference_count': 0,
    'control_review_count': 0,
    'control_unassigned_source_count': 0,
    'unattributed_journal_count': 0,
    'control_source_base': '90.100000',
    'control_gl_base': '90.100000',
    'control_difference': '0.000000',
  };

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    checkRead();
    return {'items': saved, 'next_cursor': null};
  }

  @override
  Future<Map<String, Object?>> controls(
    TenantContext scope,
    String reportId,
    String section, {
    int offset = 0,
    String? accountId,
    String? evidenceKey,
  }) async {
    checkRead();
    controlCalls.add({
      'report_id': reportId,
      'section': section,
      'offset': offset,
      'account_id': accountId,
      'evidence_key': evidenceKey,
    });
    if (controlPause != null) {
      if (!controlEntered.isCompleted) controlEntered.complete();
      await controlPause!.future;
    }
    return {
      'summary': saved.firstWhere((row) => row['id'] == reportId),
      'section': section,
      'account_filter_id': accountId,
      'evidence_key': evidenceKey,
      'items': section == 'controls'
          ? [control()]
          : [
              {
                'id': 'return-line',
                'account_id': accountId,
                'evidence_key': evidenceKey,
                'source_type': 'purchase_return',
                'source_id': 'return',
                'source_line_id': 'return-line',
                'branch_id': 'branch',
                'posting_date': '2026-08-15',
                'journal_entry_id': 'return-journal',
                'expected_base': '-22.530000',
                'posted_base': '-22.530000',
                'review_code': null,
              },
            ],
      'next_offset': null,
    };
  }

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
    final result = summary(command.payload);
    saved.add(result);
    return result;
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String reportId, {
    int offset = 0,
    String? sourceLineId,
  }) async {
    checkRead();
    if (pagePause != null) {
      if (!pageEntered.isCompleted) pageEntered.complete();
      await pagePause!.future;
    }
    return {
      'summary': saved.where((row) => row['id'] == reportId).first,
      'items': [
        {
          'source_type': 'supplier_bill',
          'source_id': 'bill',
          'source_line_id': 'line',
          'branch_id': 'branch',
          'journal_entry_id': 'journal',
          'posting_date': '2026-08-13',
          'currency_code': 'LKR',
          'base_currency_code': 'LKR',
          'definition_id': 'definition',
          'definition_version': '1',
          'tax_code': 'INPUT18',
          'tax_kind': 'input',
          'tax_rate': '18.000000',
          'taxable_amount': '250.250000',
          'tax_amount': '45.050000',
          'taxable_base': '250.250000',
          'tax_base': '45.050000',
          'expected_tax_base': '45.050000',
          'review_code': null,
          'journal_lines': [
            {
              'id': 'journal-line',
              'account_id': 'tax-asset',
              'base_debit': '45.050000',
              'base_credit': '0.000000',
            },
          ],
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
  late TaxSummaryFake gateway;
  late TaxSummaryController controller;
  TaxSummaryController make({bool online = true}) => TaxSummaryController(
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
    gateway = TaxSummaryFake();
    controller = make();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test(
    'uncertain tax review replays same sealed envelope after restart',
    () async {
      await controller.initialize();
      controller.field('branch_filter_id', 'branch');
      gateway.failure = 'UNCERTAIN_RESULT';
      await controller.generate();
      expect(controller.pending, true);
      final sealed = gateway.commands.single.toJson((value) => value);
      controller.dispose();
      controller = make();
      await controller.initialize();
      controller.field('as_of', '2026-08-15');
      expect(controller.form['as_of'], '2026-08-31');
      gateway.failure = null;
      await controller.retry();
      expect(gateway.commands.last.toJson((value) => value), sealed);
      expect(controller.pending, false);
      expect(controller.summary['blocked_count'], 1);
      expect(controller.rows.single['journal_entry_id'], 'journal');
    },
  );

  test('revoked finance read clears posted evidence', () async {
    await controller.initialize();
    await controller.generate();
    expect(controller.rows, isNotEmpty);
    expect(controller.controlRows, isNotEmpty);
    gateway.readFailure = 'PERMISSION_DENIED';
    await controller.refresh();
    expect(controller.denied, true);
    expect(controller.summary, isEmpty);
    expect(controller.rows, isEmpty);
    expect(controller.controlRows, isEmpty);
    expect(controller.form, isEmpty);
  });

  test('late initialization cannot verify access after a disconnect', () async {
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
    expect(controller.summary, isEmpty);
    gateway.periodPause = null;
    await controller.initialize();
    expect(controller.verified, true);
    expect(gateway.commands, isEmpty);
  });

  test('late source page cannot restore cleared tax evidence', () async {
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
    expect(controller.controlRows, isEmpty);
    expect(controller.reports, isEmpty);
  });

  test('late control drill cannot restore cleared tax evidence', () async {
    await controller.initialize();
    await controller.generate();
    gateway.controlPause = Completer<void>();
    final reading = controller.controlDrill('control_journals');
    await gateway.controlEntered.future;
    controller.setOnline(false);
    controller.setOnline(true);
    gateway.controlPause!.complete();
    await reading;
    expect(controller.verified, false);
    expect(controller.summary, isEmpty);
    expect(controller.controlRows, isEmpty);
    expect(controller.rows, isEmpty);
  });

  test(
    'confirmed report persists while offline without exposing evidence',
    () async {
      await controller.initialize();
      gateway.generationPause = Completer<void>();
      final posting = controller.generate();
      await gateway.generationEntered.future;
      controller.setOnline(false);
      gateway.generationPause!.complete();
      await posting;
      final stored = (await drafts.load(scope, TaxSummaryController.slot))!;
      expect(stored.pending, isNull);
      expect(stored.form['status'], 'generated');
      expect(stored.form['report_id'], gateway.commands.single.payload['id']);
      expect(controller.verified, false);
      expect(controller.summary, isEmpty);
      expect(controller.rows, isEmpty);
      controller.setOnline(true);
      gateway.generationPause = null;
      await controller.initialize();
      expect(controller.selectedReportId, stored.form['report_id']);
      expect(gateway.commands, hasLength(1));
    },
  );

  test(
    'confirmation after route disposal preserves encrypted report identity',
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

  test(
    'tax-control drill preserves saved report and account/source filter',
    () async {
      await controller.initialize();
      await controller.generate();
      final reportId = controller.selectedReportId;
      expect(controller.controlRows.single['difference'], '0.000000');
      await controller.controlDrill(
        'control_sources',
        accountId: 'tax-asset',
        evidenceKey: 'purchase_return:return:return-line',
      );
      expect(gateway.controlCalls.last['report_id'], reportId);
      expect(gateway.controlCalls.last['account_id'], 'tax-asset');
      expect(
        gateway.controlCalls.last['evidence_key'],
        'purchase_return:return:return-line',
      );
      expect(controller.controlRows.single['expected_base'], '-22.530000');
      controller.setOnline(false);
      expect(controller.controlRows, isEmpty);
      expect(controller.summary, isEmpty);
    },
  );

  test(
    'offline recovery retains encrypted draft without showing results',
    () async {
      await controller.initialize();
      controller.field('as_of', '2026-08-20');
      await controller.save();
      controller.dispose();
      controller = make(online: false);
      await controller.initialize();
      expect(controller.verified, false);
      expect(controller.reports, isEmpty);
      controller.setOnline(true);
      await controller.initialize();
      expect(controller.form['as_of'], '2026-08-20');
    },
  );

  test('tax destination requires finance read', () {
    expect(
      visibleJentraDestinations({}).any((x) => x.path == '/finance/tax'),
      false,
    );
    expect(
      visibleJentraDestinations({
        'finance.view',
      }).any((x) => x.path == '/finance/tax'),
      true,
    );
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'} tax review at 200% text', (
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
            child: Scaffold(body: TaxSummaryWorkspace(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tax review'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TaxSummaryWorkspace),
        matchesGoldenFile(
          'goldens/tax_review_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
    testWidgets('${dark ? 'dark' : 'light'} blocked tax drill at 200% text', (
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
            child: Scaffold(body: TaxSummaryWorkspace(controller: controller)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -780),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Blocked: 1 lines'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(TaxSummaryWorkspace),
        matchesGoldenFile(
          'goldens/tax_review_drill_${dark ? 'dark' : 'light'}_200.png',
        ),
      );
    });
    testWidgets(
      '${dark ? 'dark' : 'light'} tax control account drill at 200% text',
      (tester) async {
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
                body: TaxSummaryWorkspace(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final account = find.byType(ExpansionTile).first;
        await tester.ensureVisible(account);
        await tester.tap(account);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Source tax'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(TaxSummaryWorkspace),
          matchesGoldenFile(
            'goldens/tax_control_${dark ? 'dark' : 'light'}_200.png',
          ),
        );
      },
    );
  }
}
