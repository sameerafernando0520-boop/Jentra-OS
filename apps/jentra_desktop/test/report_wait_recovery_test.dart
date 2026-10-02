import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/budgets/budget_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/shared/report_wait.dart';
import 'package:jentra_desktop/src/features/operations/operational_report_controller.dart';

import 'budget_workspace_test.dart' show BudgetFake;
import 'financial_statement_workspace_test.dart' show FinancialStatementFake;
import 'operational_workspace_test.dart' show OperationalFake;
import 'support/procurement_fakes.dart' show Keys;

class PausedOperational extends OperationalFake {
  final entered = Completer<void>(), release = Completer<void>();
  int pages = 0;
  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return super.generate(command);
  }

  @override
  Future<Map<String, Object?>> reportPage(
    TenantContext scope,
    String id,
    String section, {
    int after = 0,
  }) async {
    pages++;
    return super.reportPage(scope, id, section, after: after);
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
  });
  tearDown(() => db.close());

  test(
    'cancelled dated statement retains confirmation and refresh can recover it',
    () async {
      final gateway = PausedOperational();
      final c = OperationalReportController(
        scope: scope,
        kind: 'bank_reconciliation',
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      try {
        await c.initialize();
        final work = c.freeze({'as_of': '2026-09-20'});
        await gateway.entered.future;
        c.cancelReportWait();
        gateway.release.complete();
        await work;
        expect(c.busy, isFalse);
        expect(c.pending, isFalse);
        expect(c.summary, isEmpty);
        expect(gateway.pages, 0);
        await c.refresh();
        expect(c.summary['kind'], 'bank_reconciliation');
        expect(gateway.commands, hasLength(1));
      } finally {
        c.dispose();
      }
    },
  );

  group('financial report cancellation', () {
    late FinancialStatementFake gateway;
    late FinancialStatementController c;
    FinancialStatementController make() => FinancialStatementController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      online: true,
    );
    setUp(() {
      gateway = FinancialStatementFake();
      c = make();
    });
    tearDown(() => c.dispose());
    test(
      'before dispatch retains one sealed identity and sends nothing',
      () async {
        await c.initialize();
        c.addListener(() {
          if (c.reportWait.stage == 'Generating report' &&
              c.reportWait.active) {
            c.cancelReportWait();
          }
        });
        await c.generate();
        expect(gateway.commands, isEmpty);
        expect(c.pending, isTrue);
        expect(await c.canLeave(), isTrue);
        final original = c.local!.pending!.envelope.toJson((x) => x);
        c.dispose();
        c = make();
        await c.initialize();
        await c.retry();
        expect(gateway.commands.single.toJson((x) => x), original);
      },
    );
    test(
      'during response persists confirmation and skips optional evidence',
      () async {
        await c.initialize();
        gateway.generationPause = Completer<void>();
        final work = c.generate();
        await gateway.generationEntered.future;
        c.cancelReportWait();
        expect(await c.canLeave(), isTrue);
        expect(c.summary, isEmpty);
        gateway.generationPause!.complete();
        await work;
        final saved = await drafts.load(
          scope,
          FinancialStatementController.slot,
        );
        expect(saved!.pending, isNull);
        expect(saved.form['report_id'], gateway.commands.single.payload['id']);
        expect(saved.form.containsKey('summary'), isFalse);
        expect(gateway.readSections, isEmpty);
        c.dispose();
        c = make();
        await c.initialize();
        expect(c.summary['closing_debit'], '10.000000');
        expect(gateway.commands, hasLength(1));
      },
    );
    test(
      'after confirmation rejects the late page without losing the report',
      () async {
        await c.initialize();
        gateway.pagePause = Completer<void>();
        final work = c.generate();
        await gateway.pageEntered.future;
        final saved = await drafts.load(
          scope,
          FinancialStatementController.slot,
        );
        expect(saved!.pending, isNull);
        c.cancelReportWait();
        gateway.pagePause!.complete();
        await work;
        expect(c.summary, isEmpty);
        expect(c.rows, isEmpty);
        expect(c.nextOffset, isNull);
        expect(
          (await drafts.load(
            scope,
            FinancialStatementController.slot,
          ))!.form['report_id'],
          isNotNull,
        );
      },
    );
    test(
      'cancelled uncertain response replays exact envelope after restart',
      () async {
        await c.initialize();
        gateway.failure = 'UNCERTAIN_RESULT';
        gateway.generationPause = Completer<void>();
        final work = c.generate();
        await gateway.generationEntered.future;
        final original = gateway.commands.single.toJson((x) => x);
        c.cancelReportWait();
        gateway.generationPause!.complete();
        await work;
        expect(c.pending, isTrue);
        expect(c.summary, isEmpty);
        gateway.failure = null;
        gateway.generationPause = null;
        c.dispose();
        c = make();
        await c.initialize();
        await c.retry();
        expect(gateway.commands.last.toJson((x) => x), original);
        expect(c.pending, isFalse);
      },
    );
    test(
      'dispose during dispatched generation still saves authoritative receipt',
      () async {
        await c.initialize();
        gateway.generationPause = Completer<void>();
        final work = c.generate();
        await gateway.generationEntered.future;
        c.dispose();
        gateway.generationPause!.complete();
        await work;
        c = make();
        await c.initialize();
        expect(c.pending, isFalse);
        expect(c.summary['id'], gateway.commands.single.payload['id']);
        expect(gateway.commands, hasLength(1));
      },
    );
  });

  group('budget response ordering', () {
    late BudgetFake gateway;
    late BudgetController c;
    BudgetController make() => BudgetController(
      scope: scope,
      gateway: gateway,
      drafts: drafts,
      permissions: {'finance.view', 'finance.budgets.manage'},
      online: true,
    );
    setUp(() {
      gateway = BudgetFake();
      c = make();
    });
    tearDown(() => c.dispose());
    Future<void> varianceReady() async {
      gateway.versions.add({
        'id': 'approved',
        'status': 'approved',
        'budget_year': 2026,
        'period_id': 'august',
        'version': 3,
        'revision': 1,
        'currency_code': 'LKR',
        'budget_branch_id': 'branch',
        'lines': <Map<String, Object?>>[],
      });
      await c.initialize();
      c.varianceField('budget_id', 'approved');
      c.varianceField('as_of', '2026-08-31');
    }

    test(
      'late options after disconnect do not restore scope evidence',
      () async {
        gateway.accountPause = Completer<void>();
        final work = c.initialize();
        await gateway.accountEntered.future;
        c.setOnline(false);
        gateway.accountPause!.complete();
        await work;
        expect(c.verified, isFalse);
        expect(c.accounts, isEmpty);
        expect(c.periods, isEmpty);
        expect(c.budgets, isEmpty);
        expect(c.baseCurrency, isNull);
      },
    );
    test('cancelled variance confirms metadata before optional reads and survives restart', () async {
      await varianceReady();
      gateway.generationPause = Completer<void>();
      final work = c.generate();
      await gateway.generationEntered.future;
      c.cancelReportWait();
      expect(await c.canLeave(), isTrue);
      gateway.generationPause!.complete();
      await work;
      final saved = await drafts.load(scope, BudgetController.varianceSlot);
      expect(saved!.pending, isNull);
      expect(saved.form['report_id'], isNotNull);
      expect(saved.form.containsKey('actual_total'), isFalse);
      expect(gateway.sections, isEmpty);
      expect(c.summary, isEmpty);
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.summary['actual_total'], '60.000000');
      expect(gateway.generations, hasLength(1));
    });
    test(
      'late variance page after offline never restores journal amounts',
      () async {
        await varianceReady();
        gateway.pagePause = Completer<void>();
        final work = c.generate();
        await gateway.pageEntered.future;
        c.setOnline(false);
        gateway.pagePause!.complete();
        await work;
        expect(c.rows, isEmpty);
        expect(c.summary, isEmpty);
        expect(c.reports, isEmpty);
        expect(
          (await drafts.load(scope, BudgetController.varianceSlot))!.pending,
          isNull,
        );
      },
    );
    test('budget action confirmed while offline restores version without a duplicate command', () async {
      await c.initialize();
      c.field('reason', 'August operating plan');
      c.field('budget_year', 2026);
      c.field('period_id', 'august');
      c.addLine('account');
      c.amount(0, '50.000001');
      gateway.commandPause = Completer<void>();
      final work = c.act('create');
      await gateway.commandEntered.future;
      c.setOnline(false);
      gateway.commandPause!.complete();
      await work;
      final saved = await drafts.load(scope, BudgetController.editorSlot);
      expect(saved!.pending, isNull);
      expect(saved.expectedVersion, 1);
      expect(saved.form['status'], 'draft');
      expect(c.budgets, isEmpty);
      c.dispose();
      c = make();
      await c.initialize();
      expect(c.form['version'], 1);
      expect(gateway.commands, hasLength(1));
    });
  });

  testWidgets(
    'cancel is keyboard accessible with live progress at 200 percent',
    (tester) async {
      final state = ReportWaitState()
        ..begin()
        ..generating();
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: ReportWaitIndicator(state: state, onCancel: state.cancel),
              ),
            ),
          ),
        );
        final progress = tester.getSemantics(find.byType(ReportWaitIndicator));
        expect(progress.flagsCollection.isLiveRegion, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(state.cancelled, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        handle.dispose();
        await tester.binding.setSurfaceSize(null);
      }
    },
  );
}
