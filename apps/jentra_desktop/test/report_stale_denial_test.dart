import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/control_reconciliation/control_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/close_review/close_review_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/financial_statement_controller.dart';
import 'package:jentra_desktop/src/features/financial_statements/tax_summary_controller.dart';
import 'package:jentra_desktop/src/features/report_export/report_export_controller.dart';
import 'package:jentra_desktop/src/features/budgets/budget_controller.dart';
import 'package:jentra_desktop/src/features/inventory_valuation/inventory_valuation_controller.dart';

import 'financial_statement_workspace_test.dart' show FinancialStatementFake;
import 'tax_summary_workspace_test.dart' show TaxSummaryFake;
import 'control_reconciliation_workspace_test.dart' show Gateway;
import 'close_review_workspace_test.dart' show ReviewGateway;
import 'report_export_workspace_test.dart' show ExportGateway, Files, selection;
import 'budget_workspace_test.dart' show BudgetFake;
import 'inventory_valuation_workspace_test.dart' show ValuationGateway;
import 'support/procurement_fakes.dart' show Keys;

class LateControl extends Gateway {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, Object?>> reports(TenantContext s, {String? after}) async {
    entered.complete();
    await release.future;
    return super.reports(s, after: after);
  }
}

class LateValuation extends ValuationGateway {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, Object?>> options(
    TenantContext s,
    String resource, {
    String? after,
  }) async {
    entered.complete();
    await release.future;
    return super.options(s, resource, after: after);
  }
}

class LateTax implements TaxSummaryGateway {
  final delegate = TaxSummaryFake();
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, Object?>> periods(TenantContext s, {String? after}) async {
    entered.complete();
    await release.future;
    return delegate.periods(s, after: after);
  }

  @override
  Future<Map<String, Object?>> reports(TenantContext s, {String? after}) =>
      delegate.reports(s, after: after);
  @override
  Future<Map<String, Object?>> page(
    TenantContext s,
    String id, {
    int offset = 0,
    String? sourceLineId,
  }) => delegate.page(s, id, offset: offset, sourceLineId: sourceLineId);
  @override
  Future<Map<String, Object?>> controls(
    TenantContext s,
    String id,
    String section, {
    int offset = 0,
    String? accountId,
    String? evidenceKey,
  }) => delegate.controls(
    s,
    id,
    section,
    offset: offset,
    accountId: accountId,
    evidenceKey: evidenceKey,
  );
  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) => delegate.generate(c);
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

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test(
      'financial statements ignores an old $code reply after reconnect',
      () async {
        final g = FinancialStatementFake()..periodPause = Completer<void>();
        final c = FinancialStatementController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          final work = c.initialize();
          await g.periodEntered.future;
          c.setOnline(false);
          c.setOnline(true);
          g.readFailure = code;
          g.periodPause!.complete();
          await work;
          expect(c.denied, isFalse);
          expect(c.verified, isFalse);
          expect(c.error, isNull);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test('close review ignores an old $code reply after reconnect', () async {
      final g = ReviewGateway()..reportsPause = Completer<void>();
      final c = CloseReviewController(
        scope: scope,
        gateway: g,
        drafts: drafts,
        online: true,
      );
      try {
        final work = c.initialize();
        await g.reportsEntered.future;
        c.setOnline(false);
        c.setOnline(true);
        g.readFailure = code;
        g.reportsPause!.complete();
        await work;
        expect(c.accessDenied, isFalse);
        expect(c.verified, isFalse);
        expect(c.error, isNull);
      } finally {
        c.dispose();
      }
    });
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test('export ignores an old $code reply after reconnect', () async {
      final g = ExportGateway()..previewPause = Completer<void>();
      final c = ReportExportController(
        scope: scope,
        gateway: g,
        drafts: drafts,
        online: true,
        files: Files(),
      );
      try {
        final work = c.initialize(selection);
        await g.previewEntered.future;
        c.setOnline(false);
        c.setOnline(true);
        g.readFailure = code;
        g.previewPause!.complete();
        await work;
        expect(c.denied, isFalse);
        expect(c.verified, isFalse);
        expect(c.error, isNull);
      } finally {
        c.dispose();
      }
    });
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test('budget ignores an old $code reply after reconnect', () async {
      final g = BudgetFake()..accountPause = Completer<void>();
      final c = BudgetController(
        scope: scope,
        gateway: g,
        drafts: drafts,
        online: true,
        permissions: const {
          'finance.view',
          'finance.budgets.manage',
          'finance.budgets.view',
        },
      );
      try {
        final work = c.initialize();
        await g.accountEntered.future;
        c.setOnline(false);
        c.setOnline(true);
        g.readFailure = code;
        g.accountPause!.complete();
        await work;
        expect(c.denied, isFalse);
        expect(c.verified, isFalse);
        expect(c.error, isNull);
      } finally {
        c.dispose();
      }
    });
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test(
      'inventory valuation ignores an old $code reply after reconnect',
      () async {
        final g = LateValuation();
        final c = InventoryValuationController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
        );
        try {
          final work = c.initialize();
          await g.entered.future;
          c.setOnline(false);
          c.setOnline(true);
          g.readFailure = code;
          g.release.complete();
          await work;
          expect(c.accessDenied, isFalse);
          expect(c.accounts, isEmpty);
          expect(c.error, isNull);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test(
      'control reconciliation ignores an old $code reply after reconnect',
      () async {
        final g = LateControl();
        final c = ControlReconciliationController(
          scope: scope,
          gateway: g,
          drafts: drafts,
          online: true,
          capabilities: const {'finance.view', 'finance.controls.reconcile'},
        );
        try {
          final work = c.initialize();
          await g.entered.future;
          c.setOnline(false);
          c.setOnline(true);
          g.readFailure = code;
          g.release.complete();
          await work;
          expect(c.accessDenied, isFalse);
          expect(c.verified, isFalse);
          expect(c.error, isNull);
        } finally {
          c.dispose();
        }
      },
    );
  }

  for (final code in [
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
    'PERMISSION_DENIED',
  ]) {
    test('tax summary ignores an old $code reply after reconnect', () async {
      final g = LateTax();
      final c = TaxSummaryController(
        scope: scope,
        gateway: g,
        drafts: drafts,
        online: true,
      );
      try {
        final work = c.initialize();
        await g.entered.future;
        c.setOnline(false);
        c.setOnline(true);
        g.delegate.readFailure = code;
        g.release.complete();
        await work;
        expect(c.denied, isFalse);
        expect(c.verified, isFalse);
        expect(c.error, isNull);
      } finally {
        c.dispose();
      }
    });
  }
}
