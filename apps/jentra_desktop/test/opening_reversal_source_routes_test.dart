import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_screen.dart';
import 'package:jentra_desktop/src/features/receivables/receivable_statement.dart';
import 'package:jentra_desktop/src/features/receivables/receivables_controller.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';

import 'receivable_statement_access_test.dart' show StatementFake;
import 'receivables_controller_test.dart' as receivables;
import 'supplier_payment_interaction_test.dart' show PaymentEvidence;
import 'support/procurement_fakes.dart' show Keys;

const _enabled = bool.fromEnvironment('FINANCE_OPENING_IMPORT_ENABLED');

class _ReceivableReversal extends StatementFake {
  int commerceReads = 0;

  @override
  Future<ReceivableDocument> find(
    TenantContext scope,
    ReceivableKind kind,
    String id,
  ) {
    commerceReads++;
    return super.find(scope, kind, id);
  }

  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope,
    String customer,
    String currency,
    String asOf,
    List<int> buckets,
  ) async {
    final original = await super.statement(
      scope,
      customer,
      currency,
      asOf,
      buckets,
    );
    final row = ((original['rows']! as List).single as Map)
        .cast<String, Object?>();
    return {
      ...original,
      'rows': [
        {
          ...row,
          'source_type': 'opening_receivable_reversal',
          'source_id': 'reversal-source',
        },
      ],
    };
  }
}

class _PayableReversal extends PaymentEvidence {
  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope, {
    required String supplierId,
    required String currency,
    required String asOf,
    required List<int> buckets,
  }) async {
    final original = await super.statement(
      scope,
      supplierId: supplierId,
      currency: currency,
      asOf: asOf,
      buckets: buckets,
    );
    final row = ((original['rows']! as List).first as Map)
        .cast<String, Object?>();
    return {
      ...original,
      'rows': [
        {
          ...row,
          'source_type': 'opening_payable_reversal',
          'source_id': 'reversal-source',
        },
      ],
    };
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

GoRouter _router(Widget workspace, String side) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(body: workspace),
    ),
    GoRoute(
      path: '/finance/opening-balances/source/:id',
      builder: (_, state) => Scaffold(
        body: Text('$side reversal source ${state.pathParameters['id']}'),
      ),
    ),
  ],
);

void main() {
  testWidgets(
    'AR reversal source opens its opening record through the dated statement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final repository = _ReceivableReversal();
      final controller = ReceivablesController(
        scope: receivables.scope,
        capabilities: {...receivables.permissions, 'finance.openings.view'},
        repository: repository,
        drafts: ReceivableDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
        ),
        online: true,
      );
      final router = _router(
        SingleChildScrollView(
          child: ReceivableStatement(controller: controller),
        ),
        'AR',
      );
      addTearDown(() async {
        router.dispose();
        controller.dispose();
        await db.close();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Choose customer').first);
      await _tap(tester, find.text('CUS-1 · Historical customer'));
      await _tap(tester, find.text('Run statement'));
      expect(find.textContaining('Opening customer reversal'), findsOneWidget);
      await _tap(tester, find.text('Source'));
      expect(find.text('AR reversal source reversal-source'), findsOneWidget);
      expect(repository.commerceReads, 0);
      expect(tester.takeException(), isNull);
    },
    skip: !_enabled,
  );

  testWidgets(
    'AP reversal source opens its opening record through the dated statement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const scope = TenantContext(
        tenantId: 'tenant',
        actorId: 'actor',
        legalEntityId: 'entity',
        branchId: 'branch',
      );
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final gateway = _PayableReversal()..uncertain = false;
      final controller = SupplierPaymentController(
        scope: scope,
        gateway: gateway,
        references: gateway,
        drafts: QuotationDraftStore.procurement(
          EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
        ),
        online: true,
        canPost: true,
        canApprove: true,
        canAllocate: true,
        canReverse: true,
      );
      final router = _router(
        SupplierPaymentWorkspace(controller: controller),
        'AP',
      );
      addTearDown(() async {
        router.dispose();
        controller.dispose();
        await db.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            businessCapabilitiesProvider.overrideWith(
              (ref) async => {'finance.openings.view'},
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Supplier statement and AP aging'));
      await _tap(tester, find.text('Choose statement supplier'));
      await _tap(tester, find.text('REF · payment_suppliers'));
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Statement as of',
        ),
        '2026-09-30',
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Currency code',
        ),
        'USD',
      );
      await _tap(tester, find.text('Load dated statement'));
      expect(find.textContaining('Opening supplier reversal'), findsOneWidget);
      await _tap(tester, find.byTooltip('Open opening source'));
      expect(find.text('AP reversal source reversal-source'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: !_enabled,
  );
}
