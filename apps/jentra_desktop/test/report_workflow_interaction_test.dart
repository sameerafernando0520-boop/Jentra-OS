import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_screen.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_screen.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_screen.dart';

import 'control_reconciliation_workspace_test.dart' as control;
import 'financial_statement_workspace_test.dart' show FinancialStatementFake;
import 'tax_summary_workspace_test.dart' show TaxSummaryFake;
import 'budget_workspace_test.dart' show BudgetFake;

import 'package:jentra_desktop/src/features/budgets/budget_controller.dart';
import 'package:jentra_desktop/src/features/budgets/budget_screen.dart';

import 'support/procurement_fakes.dart' show Keys;

Future<void> finish(WidgetTester tester, bool Function() busy) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 400 && busy(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(busy(), false, reason: 'The public interaction must complete.');
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> press(
  WidgetTester tester,
  Finder button,
  bool Function() busy,
) async {
  await tester.ensureVisible(button);
  await tester.tap(button);
  await finish(tester, busy);
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> choose(WidgetTester tester, String label, String option) async {
  final dropdown = find.widgetWithText(DropdownButtonFormField<String>, label);
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore drafts;
  final controllers = <ChangeNotifier>[];
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    drafts = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
  });
  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await db.close();
  });
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  for (final entry in FinancialStatementWorkspace.labels.entries) {
    testWidgets(
      '${entry.value} selects exact scope and supports account drill',
      (tester) async {
        final gateway = FinancialStatementFake();
        final c = FinancialStatementController(
          scope: scope,
          gateway: gateway,
          drafts: drafts,
          online: true,
        );
        controllers.add(c);
        await tester.runAsync(c.initialize);
        await mount(tester, FinancialStatementWorkspace(controller: c));
        await choose(tester, 'Statement', entry.value);
        await choose(tester, 'Fiscal period', 'August');
        await choose(tester, 'Comparison (optional)', 'July');
        await tester.enterText(field('As of (YYYY-MM-DD)'), '2026-08-20');
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'Save encrypted draft'),
          () => c.busy,
        );
        expect(gateway.commands, isEmpty);
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Generate report'),
          () => c.busy,
        );
        final command = gateway.commands.single;
        expect(command.payload, containsPair('kind', entry.key));
        expect(command.payload, containsPair('period_id', 'august'));
        expect(command.payload, containsPair('comparative_period_id', 'july'));
        expect(command.payload, containsPair('as_of', '2026-08-20'));
        expect(command.context, scope);
        expect(c.pending, false);
        expect(c.rows.single['closing_balance'], '10.000000');
        if (entry.key == 'cash_flow') {
          expect(
            find.text(
              'Blocked: classify moving accounts and reconcile cash before close.',
            ),
            findsOneWidget,
          );
          expect(c.summary['status'], 'blocked');
        }
        await press(
          tester,
          find.widgetWithText(ListTile, '1000 · Cash'),
          () => c.busy,
        );
        expect(c.section, 'journals');
        expect(c.accountId, 'cash');
        expect(c.rows.single['base_debit'], '10.000000');
        await press(
          tester,
          find.widgetWithText(TextButton, 'All accounts'),
          () => c.busy,
        );
        expect(c.accountId, isNull);
        expect(c.section, 'accounts');
        await press(
          tester,
          find.widgetWithText(TextButton, 'Refresh evidence'),
          () => c.busy,
        );
        expect(gateway.commands, hasLength(1));
        await press(
          tester,
          find.widgetWithText(OutlinedButton, 'New report'),
          () => c.busy,
        );
        expect(c.form['id'], isNot(command.payload['id']));
        expect(c.summary, isEmpty);
        expect(c.rows, isEmpty);
      },
    );
  }

  testWidgets(
    'tax branch review drills frozen source and signed control values',
    (tester) async {
      final gateway = TaxSummaryFake();
      final c = TaxSummaryController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
      );
      controllers.add(c);
      await tester.runAsync(c.initialize);
      await mount(tester, TaxSummaryWorkspace(controller: c));
      await choose(tester, 'Branch scope', 'Selected branch');
      await tester.enterText(field('As of (YYYY-MM-DD)'), '2026-08-20');
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Generate review'),
        () => c.busy,
      );
      expect(
        gateway.commands.single.payload,
        containsPair('branch_filter_id', 'branch'),
      );
      expect(
        gateway.commands.single.payload,
        containsPair('as_of', '2026-08-20'),
      );
      expect(
        find.text('NON-CERTIFIED • STATUTORY REVIEW REQUIRED'),
        findsOneWidget,
      );
      await press(
        tester,
        find.widgetWithText(ExpansionTile, '1450 · Input tax control'),
        () => c.busy,
      );
      await press(
        tester,
        find.widgetWithText(TextButton, 'Source tax'),
        () => c.busy,
      );
      expect(
        gateway.controlCalls.last,
        containsPair('account_id', 'tax-asset'),
      );
      expect(
        gateway.controlCalls.last,
        containsPair('section', 'control_sources'),
      );
      expect(c.controlRows.single['expected_base'], '-22.530000');
      await press(
        tester,
        find.widgetWithText(TextButton, 'Clear evidence filter'),
        () => c.busy,
      );
      expect(gateway.controlCalls.last['account_id'], isNull);
      await choose(tester, 'Tax-control evidence', 'Posted GL lines');
      await finish(tester, () => c.busy);
      expect(gateway.controlCalls.last['section'], 'control_journals');
      await tester.ensureVisible(find.textContaining('INPUT18').first);
      await tester.tap(find.textContaining('INPUT18').first);
      await tester.pumpAndSettle();
      expect(find.text('Frozen source lineage'), findsOneWidget);
      expect(find.text('Journal line journal-line'), findsOneWidget);
      expect(c.rows.single['tax_base'], '45.050000');
      await press(
        tester,
        find.widgetWithText(TextButton, 'Refresh evidence'),
        () => c.busy,
      );
      expect(gateway.commands, hasLength(1));
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'New review'),
        () => c.busy,
      );
      expect(c.summary, isEmpty);
    },
  );

  for (final kind in ['AR', 'AP']) {
    testWidgets(
      '$kind linked reversal cancellation and uncertain retry preserve identity',
      (tester) async {
        final gateway = control.Gateway()..kind = kind;
        final c = ControlReconciliationController(
          scope: scope,
          gateway: gateway,
          drafts: drafts,
          online: true,
          capabilities: {
            'finance.view',
            'finance.controls.reconcile',
            'finance.receipts.reverse',
            'finance.payments.reverse',
          },
        );
        controllers.add(c);
        await tester.runAsync(c.initialize);
        c.field('kind', kind);
        c.field('as_of', '2026-09-21');
        await tester.runAsync(c.generate);
        await mount(tester, ControlReconciliationWorkspace(controller: c));
        final chips = find.widgetWithText(ChoiceChip, 'Allocations');
        await tester.scrollUntilVisible(
          chips,
          450,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await press(tester, chips, () => c.busy);
        await tester.scrollUntilVisible(
          find.widgetWithText(TextButton, 'Prepare reversal'),
          450,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await press(
          tester,
          find.widgetWithText(TextButton, 'Prepare reversal'),
          () => c.busy,
        );
        await tester.ensureVisible(field('Reason for correction'));
        await tester.enterText(
          field('Reason for correction'),
          '  Correct settlement against original item  ',
        );
        await tester.enterText(
          field('Reversal posting date (YYYY-MM-DD)'),
          '2026-09-22',
        );
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Review reversal'),
          () => c.busy,
        );
        expect(find.text('Reverse this allocation?'), findsOneWidget);
        await press(
          tester,
          find.widgetWithText(TextButton, 'Cancel'),
          () => c.busy,
        );
        expect(gateway.reversals, isEmpty);
        gateway.failure = 'UNCERTAIN_RESULT';
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Review reversal'),
          () => c.busy,
        );
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Reverse allocation'),
          () => c.busy,
        );
        expect(c.pending, true);
        final original = gateway.reversals.single.toJson((v) => v);
        expect(gateway.reversals.single.payload, {
          'allocation_id': 'allocation',
          'posting_date': '2026-09-22',
          'reason': 'Correct settlement against original item',
        });
        expect(gateway.kinds.single, kind);
        gateway.failure = null;
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Retry saved reversal'),
          () => c.busy,
        );
        await press(
          tester,
          find.widgetWithText(FilledButton, 'Reverse allocation'),
          () => c.busy,
        );
        expect(gateway.reversals.last.toJson((v) => v), original);
        expect(c.pending, false);
        expect(c.correction, isEmpty);
        await tester.scrollUntilVisible(
          find.widgetWithText(TextButton, 'More rows'),
          450,
          maxScrolls: 30,
          scrollable: find.byType(Scrollable).first,
        );
        await press(
          tester,
          find.widgetWithText(TextButton, 'More rows'),
          () => c.busy,
        );
        expect(gateway.reads.last['after'], '50');
        expect(c.rows, hasLength(2));
      },
    );
  }

  testWidgets(
    'budget exact version submission enforces separate approver and freezes variance drill',
    (tester) async {
      final gateway = BudgetFake();
      final author = BudgetController(
        scope: scope,
        gateway: gateway,
        drafts: drafts,
        online: true,
        permissions: {
          'finance.view',
          'finance.budgets.manage',
          'finance.budgets.approve',
        },
      );
      controllers.add(author);
      await tester.runAsync(author.initialize);
      await mount(tester, BudgetWorkspace(controller: author));
      await choose(tester, 'Period (or full year)', 'August · 2026-08-01');
      await tester.enterText(field('Budget year'), '2026');
      await tester.enterText(field('Currency code'), 'lkr');
      await tester.enterText(
        field('Reason for this action'),
        ' Approved exact budget ',
      );
      await press(
        tester,
        find.widgetWithText(ActionChip, '4000 · Revenue'),
        () => author.busy,
      );
      await tester.enterText(field('Exact amount'), '9007199254.740993');
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'Save encrypted drafts'),
        () => author.busy,
      );
      expect(gateway.commands, isEmpty);
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Create draft'),
        () => author.busy,
      );
      final created = gateway.commands.single;
      expect(created.payload, containsPair('period_id', 'august'));
      expect(created.payload, containsPair('currency_code', 'LKR'));
      expect(
        (created.payload['lines'] as List).single['amount'],
        '9007199254.740993',
      );
      expect(created.payload['reason'], 'Approved exact budget');
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Submit for approval'),
        () => author.busy,
      );
      expect(author.form['status'], 'submitted');
      expect(
        find.widgetWithText(FilledButton, 'Approve version'),
        findsNothing,
        reason: 'A submitter with approve capability must still be denied self approval.',
      );
      final approver = BudgetController(
        scope: const TenantContext(
          tenantId: 'tenant',
          actorId: 'approver',
          legalEntityId: 'entity',
          branchId: 'branch',
        ),
        gateway: gateway,
        drafts: drafts,
        online: true,
        permissions: {'finance.view', 'finance.budgets.approve'},
      );
      controllers.add(approver);
      await tester.runAsync(approver.initialize);
      await tester.runAsync(
        () => approver.openBudget(created.payload['id'] as String),
      );
      await mount(tester, BudgetWorkspace(controller: approver));
      await tester.enterText(
        field('Reason for this action'),
        ' Independent review ',
      );
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Approve version'),
        () => approver.busy,
      );
      expect(gateway.commands.last.context.actorId, 'approver');
      expect(gateway.commands.last.expectedEntityVersion, 2);
      expect(gateway.commands.last.payload['action'], 'approve');
      expect(gateway.commands.last.payload['reason'], 'Independent review');
      expect(approver.form['status'], 'approved');
      await choose(
        tester,
        'Approved budget version',
        '2026 · LKR · revision 1',
      );
      await tester.enterText(field('As of (YYYY-MM-DD)'), '2026-08-20');
      await press(
        tester,
        find.widgetWithText(FilledButton, 'Generate frozen variance'),
        () => approver.busy,
      );
      expect(
        gateway.generations.single.payload['budget_id'],
        created.payload['id'],
      );
      expect(gateway.generations.single.payload['as_of'], '2026-08-20');
      expect(approver.summary['variance_total'], '10.000000');
      await press(
        tester,
        find.widgetWithText(ListTile, '4000 · Revenue').last,
        () => approver.busy,
      );
      expect(approver.section, 'journals');
      expect(approver.budgetLineId, 'line');
      expect(approver.rows.single['base_credit'], '60.000000');
      await press(
        tester,
        find.widgetWithText(TextButton, 'Clear account filter'),
        () => approver.busy,
      );
      expect(approver.section, 'lines');
      expect(approver.budgetLineId, isNull);
      await press(
        tester,
        find.widgetWithText(OutlinedButton, 'New variance'),
        () => approver.busy,
      );
      expect(approver.summary, isEmpty);
      expect(gateway.generations, hasLength(1));
    },
  );
}
