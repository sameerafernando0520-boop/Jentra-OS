import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_controller.dart';
import 'package:jentra_desktop/src/features/procurement/supplier_payment_screen.dart';

import 'supplier_payment_interaction_test.dart' show PaymentEvidence;
import 'support/procurement_fakes.dart' show Keys;

// Synthetic transport receipts exercise client recovery, not installed posting.
class LifecycleGateway extends PaymentEvidence {
  Map<String, Object?> proposal = {
    'id': 'proposal',
    'version': 5,
    'status': 'draft',
    'document_number': 'PP-LIFECYCLE',
    'document_date': '2026-09-30',
    'currency_code': 'USD',
    'base_currency_code': 'LKR',
    'total': '9007199254.740993',
    'base_total': '99999999999.999999',
    'created_by': 'independent-preparer',
    'supplier_id': 'supplier',
    'cash_bank_account_id': 'bank',
    'lines': [
      {
        'open_item_id': 'bill',
        'document_number': 'SB-EXACT',
        'kind': 'bill',
        'amount': '9007199254.740993',
        'due_date': '2026-09-30',
      },
    ],
  };
  Map<String, Object?>? payment;
  final receipts = <String, Map<String, Object?>>{};
  int postingCommits = 0;
  bool loseFirstPostingReply = false;

  @override
  Future<CursorPage<Map<String, Object?>>> proposals(
    TenantContext scope, {
    String? after,
  }) async => CursorPage(items: [proposal], limit: 50);

  @override
  Future<CursorPage<Map<String, Object?>>> payments(
    TenantContext scope, {
    String? after,
  }) async => CursorPage(items: [?payment], limit: 50);

  @override
  Future<Map<String, Object?>> transitionProposal(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    operations.add('transition');
    final next = switch (command.payload['action']) {
      'submit' => 'pending_approval',
      'recall' => 'draft',
      'cancel' => 'cancelled',
      _ => command.payload['decision'] as String,
    };
    proposal = {
      ...proposal,
      'status': next,
      'version': command.expectedEntityVersion! + 1,
    };
    return proposal;
  }

  @override
  Future<Map<String, Object?>> postPayment(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command);
    operations.add('post');
    if (receipts[command.commandId] case final receipt?) return receipt;
    postingCommits++;
    payment = {
      ...proposal,
      'id': 'recorded-payment',
      'document_number': 'SP-LIFECYCLE',
      'status': 'posted',
      'version': 1,
      'open_item_id': 'payment-open-item',
      'reference': command.payload['reference'],
      'reconciliation_status': 'unreconciled',
      'allocations': [],
    };
    receipts[command.commandId] = payment!;
    if (loseFirstPostingReply) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Posting reply lost. Retry the saved command.',
      );
    }
    return payment!;
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late Keys keys;
  late QuotationDraftStore drafts;
  late LifecycleGateway gateway;
  late SupplierPaymentController c;
  SupplierPaymentController controller() => SupplierPaymentController(
    scope: scope,
    gateway: gateway,
    references: gateway,
    drafts: drafts,
    online: true,
    canPost: true,
    canApprove: true,
    canAllocate: true,
    canReverse: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    drafts = QuotationDraftStore.procurement(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
    );
    gateway = LifecycleGateway()..uncertain = false;
    c = controller();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (c.busy && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.busy, isFalse, reason: 'Workspace action must finish.');
    });
    await tester.pumpAndSettle();
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(c.initialize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SupplierPaymentWorkspace(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await settle(tester);
  }

  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  testWidgets(
    'proposal approval and lost payment reply recover exact command after restart',
    (tester) async {
      await mount(tester);
      await tap(tester, 'PP-LIFECYCLE · draft');
      expect(
        find.text('SB-EXACT · bill · 9007199254.740993 · Due 2026-09-30'),
        findsOneWidget,
      );
      await tap(tester, 'Submit for approval');
      expect(c.selected!['status'], 'pending_approval');
      expect(gateway.commands.last.expectedEntityVersion, 5);
      await tap(tester, 'Approve proposal');
      expect(c.selected!['status'], 'approved');
      expect(gateway.commands.last.payload['decision'], 'approved');
      expect(gateway.commands.last.expectedEntityVersion, 6);
      await tap(tester, 'Record payment');
      await tap(tester, 'Cancel');
      expect(gateway.operations, ['transition', 'transition']);
      gateway.loseFirstPostingReply = true;
      await tap(tester, 'Record payment');
      await tester.enterText(
        field('Payment reference'),
        ' BANK/EXACT-9007199254.740993 ',
      );
      await tap(tester, 'Confirm');
      expect(gateway.postingCommits, 1);
      expect(c.local!.pending, isNotNull);
      expect(find.text('Saved payment action'), findsOneWidget);
      final sealed = jsonEncode(gateway.commands.last.toJson((p) => p));
      expect(gateway.commands.last.expectedEntityVersion, 7);
      expect(gateway.commands.last.payload, {
        'document_id': 'proposal',
        'reference': 'BANK/EXACT-9007199254.740993',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      drafts = QuotationDraftStore.procurement(
        EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      );
      c = controller();
      await mount(tester);
      expect(jsonEncode(c.local!.pending!.envelope.toJson((p) => p)), sealed);
      await tap(tester, 'Retry saved command');
      expect(jsonEncode(gateway.commands.last.toJson((p) => p)), sealed);
      expect(gateway.postingCommits, 1);
      expect(c.local, isNull);
      expect(
        await tester.runAsync(
          () => drafts.load(scope, SupplierPaymentController.slot),
        ),
        isNull,
      );
      expect(
        find.text('Reference: BANK/EXACT-9007199254.740993'),
        findsOneWidget,
      );
      expect(find.text('Bank reconciliation: unreconciled'), findsOneWidget);
      expect(
        find.text('Supplier payment recorded. Awaiting bank reconciliation.'),
        findsOneWidget,
      );
      await tap(tester, 'Open payment allocations');
      expect(c.itemDetail!['item'], containsPair('id', 'payment-open-item'));
    },
  );

  testWidgets(
    'editing proposal validates precision and preserves replacement items in encrypted restart',
    (tester) async {
      await mount(tester);
      await tap(tester, 'PP-LIFECYCLE · draft');
      await tap(tester, 'Edit proposal');
      expect(c.version, 5);
      await tester.enterText(field('Amount to allocate'), '0.0000001');
      await tap(tester, 'Save proposal');
      expect(gateway.commands, isEmpty);
      // edit() persists the original draft without reloading c.local. Rejected
      // precision must leave that durable draft present and unsealed.
      final rejectedDraft = await tester.runAsync(
        () => drafts.load(scope, SupplierPaymentController.slot),
      );
      expect(rejectedDraft, isNotNull);
      expect(rejectedDraft!.pending, isNull);
      expect(rejectedDraft.expectedVersion, 5);
      await tap(tester, 'Find due bills and credits');
      expect(c.eligible, isNotEmpty);
      await tap(tester, 'Choose payment bank');
      await tap(tester, 'REF · payment_banks');
      expect(c.form!['lines'], isEmpty);
      expect(c.eligible, isEmpty);
      expect(c.itemCursor, isNull);
      await tap(tester, 'Find due bills and credits');
      await tap(tester, 'SB-EXACT · bill');
      await tap(tester, 'Remove item');
      expect(c.form!['lines'], isEmpty);
      await tap(tester, 'SB-EXACT · bill');
      await tester.enterText(field('Amount to allocate'), '0.000001');
      await tap(tester, 'Save on this device');
      final saved = await tester.runAsync(
        () => drafts.load(scope, SupplierPaymentController.slot),
      );
      expect(saved!.expectedVersion, 5);
      expect((saved.form['lines'] as List).single['amount'], '0.000001');
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      drafts = QuotationDraftStore.procurement(
        EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      );
      c = controller();
      await mount(tester);
      expect(c.version, 5);
      expect((c.form!['lines'] as List).single['amount'], '0.000001');
      await tap(tester, 'Save proposal');
      expect(gateway.commands.single.expectedEntityVersion, 5);
      expect((gateway.commands.single.payload['lines'] as List).single, {
        'open_item_id': 'bill',
        'amount': '0.000001',
      });
      expect(c.local, isNull);
    },
  );

  for (final decision in [
    ('Reject proposal', 'pending_approval', 'rejected', 'reject'),
    ('Recall for editing', 'approved', 'draft', 'recall'),
    ('Cancel proposal', 'draft', 'cancelled', 'cancel'),
  ]) {
    testWidgets(
      '${decision.$1} requires an explicit reason and sends original version',
      (tester) async {
        gateway.proposal = {...gateway.proposal, 'status': decision.$2};
        await mount(tester);
        await tap(tester, 'PP-LIFECYCLE · ${decision.$2}');
        await tap(tester, decision.$1);
        await tap(tester, 'Cancel');
        expect(gateway.commands, isEmpty);
        expect(c.form, isNull);
        await tap(tester, decision.$1);
        await tester.enterText(
          field('Reason'),
          ' Supplier instruction: revise the due allocation ',
        );
        await tap(tester, 'Confirm');
        expect(gateway.commands, hasLength(1));
        expect(gateway.commands.single.expectedEntityVersion, 5);
        expect(gateway.commands.single.payload['document_id'], 'proposal');
        expect(
          gateway.commands.single.payload['reason'],
          'Supplier instruction: revise the due allocation',
        );
        expect(
          gateway.commands.single.payload[decision.$4 == 'reject'
              ? 'decision'
              : 'action'],
          decision.$4 == 'reject' ? 'rejected' : decision.$4,
        );
        expect(c.selected!['status'], decision.$3);
        expect(c.local, isNull);
      },
    );
  }

  testWidgets(
    'prepared proposal exposes independent approval requirement without sending',
    (tester) async {
      gateway.proposal = {
        ...gateway.proposal,
        'status': 'pending_approval',
        'prepared_by': 'a',
      };
      await mount(tester);
      await tap(tester, 'PP-LIFECYCLE · pending_approval');
      expect(
        find.text('An independent approver must review this proposal.'),
        findsOneWidget,
      );
      final approve = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Approve proposal'),
      );
      final reject = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Reject proposal'),
      );
      expect(approve.onPressed, isNull);
      expect(reject.onPressed, isNull);
      expect(gateway.commands, isEmpty);
      expect(c.local, isNull);
    },
  );
}
