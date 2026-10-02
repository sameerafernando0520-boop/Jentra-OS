import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/close_review/close_review_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/cash_flow_mapping_controller.dart';
import 'package:jentra_desktop/src/features/report_export/report_export_controller.dart';

import 'financial_statement_workspace_test.dart' show FinancialStatementFake;
import 'tax_summary_workspace_test.dart' show TaxSummaryFake;
import 'control_reconciliation_workspace_test.dart' show Gateway;
import 'close_review_workspace_test.dart' show ReviewGateway;
import 'report_export_workspace_test.dart' show ExportGateway, Files, selection;
import 'cash_flow_mapping_workspace_test.dart' show CashFlowMappingFake;
import 'support/procurement_fakes.dart' show Keys;

class PausingMapping implements CashFlowMappingGateway {
  final delegate = CashFlowMappingFake();
  Completer<void>? pause;
  Completer<void> entered = Completer<void>();
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String asOf, {
    String? after,
  }) async {
    if (pause != null) {
      if (!entered.isCompleted) entered.complete();
      await pause!.future;
    }
    return delegate.options(scope, asOf, after: after);
  }

  @override
  Future<Map<String, Object?>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  ) => delegate.configure(command);
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
  const denials = [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ];

  for (final code in denials) {
    test(
      'financial statement removes viewed evidence on $code and restores only after fresh verification',
      () async {
        final g = FinancialStatementFake();
        final c = FinancialStatementController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          await c.initialize();
          await c.generate();
          expect(c.summary, isNotEmpty);
          g.readFailure = code;
          await c.refresh();
          expect(c.denied, isTrue);
          expect(c.verified, isFalse);
          expect(c.summary, isEmpty);
          expect(c.rows, isEmpty);
          expect(c.periods, isEmpty);
          expect(c.form, isEmpty);
          expect(c.pending, isFalse);
          expect(
            (await drafts.load(
              scope,
              FinancialStatementController.slot,
            ))?.pending,
            isNull,
          );
          g.readFailure = null;
          await c.initialize();
          expect(c.verified, isTrue);
          expect(c.denied, isFalse);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in denials) {
    test(
      'tax summary removes viewed evidence on $code and restores only after fresh verification',
      () async {
        final g = TaxSummaryFake();
        final c = TaxSummaryController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          await c.initialize();
          await c.generate();
          expect(c.summary, isNotEmpty);
          g.readFailure = code;
          await c.refresh();
          expect(c.denied, isTrue);
          expect(c.verified, isFalse);
          expect(c.summary, isEmpty);
          expect(c.rows, isEmpty);
          expect(c.periods, isEmpty);
          expect(c.form, isEmpty);
          expect(c.pending, isFalse);
          expect(
            (await drafts.load(scope, TaxSummaryController.slot))?.pending,
            isNull,
          );
          g.readFailure = null;
          await c.initialize();
          expect(c.verified, isTrue);
          expect(c.denied, isFalse);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in denials) {
    test(
      'control reconciliation removes viewed evidence on $code and restores only after fresh verification',
      () async {
        final g = Gateway();
        final c = ControlReconciliationController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
          capabilities: const {'finance.view', 'finance.controls.reconcile'},
        );
        try {
          await c.initialize();
          await c.generate();
          expect(c.summary, isNotEmpty);
          g.readFailure = code;
          await c.refreshPage();
          expect(c.accessDenied, isTrue);
          expect(c.verified, isFalse);
          expect(c.summary, isEmpty);
          expect(c.rows, isEmpty);
          expect(c.reports, isEmpty);
          expect(c.pending, isFalse);
          expect(
            (await drafts.load(
              scope,
              ControlReconciliationController.slot,
            ))?.pending,
            isNull,
          );
          g.readFailure = null;
          await c.initialize();
          expect(c.verified, isTrue);
          expect(c.accessDenied, isFalse);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in denials) {
    test(
      'close review removes viewed evidence on $code and restores only after fresh verification',
      () async {
        final g = ReviewGateway();
        final c = CloseReviewController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          await c.initialize();
          await c.open(c.reports.first);
          expect(c.summary, isNotEmpty);
          g.readFailure = code;
          await c.refreshPage();
          expect(c.accessDenied, isTrue);
          expect(c.verified, isFalse);
          expect(c.summary, isEmpty);
          expect(c.rows, isEmpty);
          expect(c.reports, isEmpty);
          expect(c.pending, isFalse);
          expect(
            (await drafts.load(scope, CloseReviewController.slot))?.pending,
            isNull,
          );
          g.readFailure = null;
          await c.initialize();
          expect(c.verified, isTrue);
          expect(c.accessDenied, isFalse);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in denials) {
    test(
      'governed export removes preview on $code without registration or local file writes',
      () async {
        final g = ExportGateway(), files = Files();
        final c = ReportExportController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          files: files,
          online: true,
        );
        try {
          await c.initialize(selection);
          expect(c.document, isNotEmpty);
          g.readFailure = code;
          await c.refresh();
          expect(c.denied, isTrue);
          expect(c.verified, isFalse);
          expect(c.document, isEmpty);
          expect(g.commands, isEmpty);
          expect(files.writes, isEmpty);
          g.readFailure = null;
          await c.initialize(selection);
          expect(c.verified, isTrue);
          expect(c.denied, isFalse);
        } finally {
          c.dispose();
        }
      },
    );
    test(
      'cash-flow classification clears account evidence on $code and preserves input recovery',
      () async {
        final g = PausingMapping();
        final c = CashFlowMappingController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          await c.initialize();
          await c.select('cash');
          c.field('category', 'cash');
          c.field('reason', 'Approved cash account classification');
          await c.save();
          g.delegate.readFailure = code;
          await c.refresh();
          expect(c.denied, isTrue);
          expect(c.verified, isFalse);
          expect(c.accounts, isEmpty);
          expect(c.cursor, isNull);
          expect(c.form, isEmpty);
          final saved = await drafts.load(
            scope,
            CashFlowMappingController.slot,
          );
          expect(saved!.form['reason'], 'Approved cash account classification');
          expect(saved.form.containsKey('accounts'), isFalse);
          expect(saved.pending, isNull);
          g.delegate.readFailure = null;
          await c.initialize();
          expect(c.verified, isTrue);
          expect(c.form['reason'], 'Approved cash account classification');
        } finally {
          c.dispose();
        }
      },
    );
  }
  for (final operation in ['initialize', 'refresh']) {
    for (final fail in [false, true]) {
      test(
        'cash-flow $operation rejects old ${fail ? "denial" : "options"} after reconnect',
        () async {
          final g = PausingMapping();
          final c = CashFlowMappingController(
            scope: scope,
            gateway: g,
            drafts: drafts,
            online: true,
          );
          try {
            if (operation == 'refresh') await c.initialize();
            g.pause = Completer<void>();
            final work = operation == 'initialize'
                ? c.initialize()
                : c.refresh();
            await g.entered.future;
            c.setOnline(false);
            c.setOnline(true);
            if (fail) g.delegate.readFailure = 'MFA_REQUIRED';
            g.pause!.complete();
            await work;
            expect(c.verified, isFalse);
            expect(c.accounts, isEmpty);
            expect(c.denied, isFalse);
            g.pause = null;
            g.delegate.readFailure = null;
            await c.initialize();
            expect(c.verified, isTrue);
            expect(c.accounts, isNotEmpty);
          } finally {
            c.dispose();
          }
        },
      );
    }
  }
  test(
    'disposed cash-flow workspace locks edits and cannot accept later options',
    () async {
      final g = PausingMapping();
      final c = CashFlowMappingController(
        scope: scope,
        gateway: g,
        drafts: drafts,
        online: true,
      );
      g.pause = Completer<void>();
      final work = c.initialize();
      await g.entered.future;
      c.dispose();
      g.pause!.complete();
      await work;
      expect(c.accounts, isEmpty);
      expect(c.verified, isFalse);
      expect(c.locked, isTrue);
      c.field('reason', 'Cannot edit disposed workspace');
      expect(c.form, isEmpty);
    },
  );
}
