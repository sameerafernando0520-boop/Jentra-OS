import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_screen.dart';

import 'bank_reconciliation_workspace_test.dart' show BankFake;
import 'support/procurement_fakes.dart' show Keys;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late BankFake gateway;
  late BankReconciliationController bank;
  var disposed = false;
  setUp(() {
    disposed = false;
    db = JentraLocalDatabase(NativeDatabase.memory());
    gateway = BankFake();
    bank = BankReconciliationController(
      scope: scope,
      gateway: gateway,
      online: true,
      drafts: QuotationDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
      ),
      capabilities: {'finance.view', 'finance.bank.reconcile'},
    );
  });
  tearDown(() async {
    if (!disposed) bank.dispose();
    await db.close();
  });

  for (final kind in ['disconnect', 'reconnect', 'denial', 'dispose']) {
    testWidgets('bank match confirmation cannot survive $kind', (tester) async {
      await tester.runAsync(() async {
        await bank.initialize();
        await bank.selectBank('bank');
        bank.field('posting_date', '2026-09-21');
        bank.field('reason', 'Original scoped matching');
        bank.toggle('statement_lines', 's1', true);
        bank.toggle('journal_lines', 'j1', true);
      });
      tester.view.physicalSize = const Size(1600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BankReconciliationWorkspace(controller: bank)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Match selected lines'));
      await tester.tap(find.text('Match selected lines'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm bank match?'), findsOneWidget);
      if (kind == 'dispose') {
        bank.dispose();
        disposed = true;
      } else if (kind == 'denial') {
        gateway.readFailure = 'PERMISSION_DENIED';
        await tester.runAsync(() => bank.page('statement_lines'));
        gateway.readFailure = null;
      } else {
        bank.setOnline(false);
        if (kind == 'reconnect') bank.setOnline(true);
      }
      await tester.pumpAndSettle();
      if (kind == 'reconnect' || kind == 'denial') {
        await tester.runAsync(bank.initialize);
        await tester.pumpAndSettle();
      }
      expect(find.text('Confirm bank match?'), findsNothing);
      expect(find.text('Confirm'), findsNothing);
      expect(find.text('Reference access changed'), findsOneWidget);
      expect(gateway.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
