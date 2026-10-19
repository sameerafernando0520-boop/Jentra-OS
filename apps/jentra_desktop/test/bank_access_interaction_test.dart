import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_controller.dart';
import 'package:jentra_desktop/src/features/bank_reconciliation/bank_reconciliation_screen.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

import 'bank_reconciliation_workspace_test.dart' show BankFake;
import 'support/procurement_fakes.dart' show Keys;

class InteractiveBank extends BankFake {
  Completer<Map<String, Object?>>? heldRead, heldCommand;
  String? heldResource;
  final reads = <(String, String?, String?)>[];
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? bankId,
    String? after,
  }) async {
    reads.add((resource, bankId, after));
    if (heldResource == resource) return heldRead!.future;
    final result = await super.options(
      scope,
      resource,
      bankId: bankId,
      after: after,
    );
    return {
      ...result,
      'items': resource == 'accounts'
          ? [
              {
                'id': 'bank',
                'code': 'MAIN',
                'name': 'Operating bank',
                'currency_code': 'LKR',
                'version': 7,
                'reconciliation_rules': {'tolerance': '0.000001'},
              },
            ]
          : resource == 'statements'
          ? [
              {
                'id': 'statement',
                'identity': 'STMT-1',
                'row_count': 1,
                'start_date': '2026-09-21',
                'end_date': '2026-09-21',
                'opening': '0',
                'total': '-0.000001',
                'closing': '-0.000001',
              },
            ]
          : resource == 'offset_accounts'
          ? [
              {'id': 'offset', 'code': '6200', 'name': 'Bank fee expense'},
            ]
          : resource == 'rates'
          ? [
              {
                'id': 'rate',
                'source_currency_code': 'USD',
                'target_currency_code': 'LKR',
                'rate': '301.000001',
                'effective_date': '2026-09-21',
              },
            ]
          : result['items'],
      if (after == null && resource == 'statement_lines')
        'next_cursor': 'statement-cursor',
    };
  }

  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    if (heldCommand != null) {
      commands.add(command);
      return heldCommand!.future;
    }
    return super.execute(command);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late QuotationDraftStore store;
  late InteractiveBank gateway;
  late BankReconciliationController c;
  BankReconciliationController make() => BankReconciliationController(
    scope: scope,
    gateway: gateway,
    drafts: store,
    capabilities: {
      'finance.view',
      'finance.bank.import',
      'finance.bank.reconcile',
      'finance.bank.manage',
      'finance.bank.adjust',
    },
    online: true,
  );
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    store = QuotationDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: Keys())),
    );
    gateway = InteractiveBank();
    c = make();
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> ready() async {
    await c.initialize();
    await c.selectBank('bank');
    c.field('posting_date', '2026-09-21');
    c.field('reason', 'Verified statement');
    c.toggle('statement_lines', 's1', true);
    c.toggle('journal_lines', 'j1', true);
    await c.save();
  }

  test('disconnect hides verified bank evidence and reconnect requires fresh verification', () async {
    await ready();
    c.setOnline(false);
    expect(c.verified, false);
    expect(c.pages, isEmpty);
    expect(c.cursors, isEmpty);
    await c.execute('match');
    expect(gateway.commands, isEmpty);
    c.setOnline(true);
    expect(c.verified, false);
    await c.initialize();
    expect(c.verified, true);
    expect(c.bankId, 'bank');
    expect(c.form['reason'], 'Verified statement');
  });
  test('obsolete bank source reply after disconnect is discarded', () async {
    await ready();
    gateway.heldResource = 'statement_lines';
    gateway.heldRead = Completer();
    final refresh = c.refresh();
    await Future<void>.delayed(Duration.zero);
    c.setOnline(false);
    gateway.heldRead!.complete({
      'items': [
        {'id': 'private-late', 'amount': '9007199254.740993'},
      ],
    });
    await refresh;
    expect(c.pages, isEmpty);
    expect(c.verified, false);
  });
  for (final denial in [
    'PERMISSION_DENIED',
    'ACCESS_DENIED',
    'MFA_REQUIRED',
    'AUTHENTICATION_REQUIRED',
  ]) {
    test(
      '$denial clears bank evidence and fresh verification restores input draft',
      () async {
        await ready();
        gateway.readFailure = denial;
        await c.refresh();
        expect(c.denied, true);
        expect(c.verified, false);
        expect(c.pages, isEmpty);
        expect(c.form, isEmpty);
        expect(
          (await store.load(
            scope,
            BankReconciliationController.slot,
          ))!.form['reason'],
          'Verified statement',
        );
        gateway.readFailure = null;
        await c.initialize();
        expect(c.denied, false);
        expect(c.verified, true);
        expect(c.form['reason'], 'Verified statement');
      },
    );
  }
  test(
    'obsolete denial cannot erase recovery inputs after connectivity change',
    () async {
      await ready();
      gateway.heldResource = 'statement_lines';
      gateway.heldRead = Completer();
      final refresh = c.refresh();
      await Future<void>.delayed(Duration.zero);
      c.setOnline(false);
      c.setOnline(true);
      gateway.heldRead!.completeError(
        const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Expired session',
        ),
      );
      await refresh;
      expect(c.denied, false);
      expect(c.form['reason'], 'Verified statement');
      expect(c.error, isNull);
    },
  );
  test('confirmed original match after disconnect clears sealed request without rehydrating sources', () async {
    await ready();
    gateway.heldCommand = Completer();
    final sending = c.execute('match');
    while (gateway.commands.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    c.setOnline(false);
    gateway.heldCommand!.complete({
      'id': gateway.commands.single.payload['id'],
    });
    await sending;
    expect(c.pending, false);
    expect(c.verified, false);
    expect(c.pages, isEmpty);
    expect(await store.load(scope, BankReconciliationController.slot), isNull);
    expect(c.message, contains('confirmed'));
    expect(gateway.reads.where((r) => r.$1 == 'accounts').length, 1);
  });
  test('exact rules use current bank optimistic version and omit selected source evidence', () async {
    await ready();
    c.field('tolerance', ' 9007199254.740993 ');
    await c.execute('rules');
    final command = gateway.commands.single;
    expect(command.context, scope);
    expect(command.expectedEntityVersion, 7);
    expect(command.payload['tolerance'], '9007199254.740993');
    expect(command.payload.keys.toSet(), {
      'action',
      'id',
      'bank_id',
      'tolerance',
      'reason',
    });
    expect(c.pending, false);
  });
  test('statement input is balanced with exact micro-unit and preserves sealed import identity', () async {
    await ready();
    await c.preview(
      Uint8List.fromList(
        utf8.encode(
          'date,reference,description,amount\n2026-09-21,R1,Fee,-0.000001',
        ),
      ),
      'csv',
      'synthetic.csv',
    );
    c.field('identity', 'STMT-1');
    c.field('start_date', '2026-09-21');
    c.field('end_date', '2026-09-21');
    c.field('closing', '-0.000001');
    gateway.failure = 'UNCERTAIN_RESULT';
    await c.execute('import');
    final first = jsonEncode(gateway.commands.single.toJson((p) => p));
    c.dispose();
    c = make();
    await c.initialize();
    gateway.failure = null;
    await c.retry();
    expect(jsonEncode(gateway.commands.last.toJson((p) => p)), first);
    expect(gateway.commands.last.payload['closing'], '-0.000001');
    expect(gateway.commands.last.payload.containsKey('file_name'), false);
  });
  for (final scenario in [
    'invalid-date',
    'future',
    'range',
    'identity',
    'balance-format',
    'out-of-range',
    'many-to-many',
    'missing-reason',
    'missing-match',
    'invalid-tolerance',
  ]) {
    test('$scenario rejects before sealing or executing', () async {
      await ready();
      var action = 'match';
      if ([
        'future',
        'range',
        'identity',
        'balance-format',
        'out-of-range',
      ].contains(scenario)) {
        action = 'import';
        await c.preview(
          Uint8List.fromList(
            utf8.encode(
              'date,reference,description,amount\n2026-09-21,R1,Fee,-0.000001',
            ),
          ),
          'csv',
          'test.csv',
        );
        c.field('identity', 'STMT');
        c.field('start_date', '2026-09-21');
        c.field('end_date', '2026-09-21');
        c.field('closing', '-0.000001');
      }
      switch (scenario) {
        case 'invalid-date':
          c.field('posting_date', '2026-02-30');
        case 'future':
          c.field('end_date', '2099-01-01');
        case 'range':
          c.field('start_date', '2026-09-22');
        case 'identity':
          c.field('identity', '');
        case 'balance-format':
          c.field('opening', '1e5');
        case 'out-of-range':
          c.field('start_date', '2026-09-20');
          c.field('end_date', '2026-09-20');
        case 'many-to-many':
          c.toggle('statement_lines', 's2', true);
          c.toggle('journal_lines', 'j2', true);
        case 'missing-reason':
          c.field('reason', '');
        case 'missing-match':
          action = 'reverse';
        case 'invalid-tolerance':
          action = 'rules';
          c.field('tolerance', '-0.000001');
      }
      await c.execute(action);
      expect(gateway.commands, isEmpty);
      expect(c.pending, false);
      expect(c.error, isNotNull);
    });
  }
  testWidgets(
    'full statement preview pages retain exact totals and import confirmation stores all rows',
    (tester) async {
      await tester.runAsync(ready);
      final csv =
          'date,reference,description,amount\n${List.generate(51, (i) => '2026-09-21,R$i,Exact fee,0.000001').join('\n')}';
      await tester.runAsync(
        () => c.preview(
          Uint8List.fromList(utf8.encode(csv)),
          'csv',
          'fifty-one.csv',
        ),
      );
      tester.view.physicalSize = const Size(1920, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BankReconciliationWorkspace(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String text) async {
        final button = find.widgetWithText(TextButton, text);
        await tester.scrollUntilVisible(
          button,
          500,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 50,
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      Future<void> field(String label, String value) async {
        final f = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.enterText(f, value);
        await tester.pump();
      }

      await field('Statement identity', 'STMT-51');
      await field('Start date · YYYY-MM-DD', '2026-09-21');
      await field('End date · YYYY-MM-DD', '2026-09-21');
      await field('Opening balance', '9007199254.740993');
      await field('Closing balance', '9007199254.741044');
      await tap('Next preview');
      expect(find.text('2026-09-21 · R50 · 0.000001'), findsOneWidget);
      await tap('Previous preview');
      expect(find.text('2026-09-21 · R0 · 0.000001'), findsOneWidget);
      await tap('Import statement');
      expect(find.text('Import this statement?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      await tap('Import statement');
      await tester.runAsync(() async {
        await tester.tap(find.text('Confirm'));
        while (c.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      final p = gateway.commands.single.payload;
      expect(p['identity'], 'STMT-51');
      expect((p['lines'] as List).length, 51);
      expect(p['opening'], '9007199254.740993');
      expect(p['closing'], '9007199254.741044');
      expect(p.containsKey('total'), false);
      expect(p.containsKey('file_name'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'bank rules and matching confirmation cancel and exact scoped confirm',
    (tester) async {
      await tester.runAsync(ready);
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BankReconciliationWorkspace(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String text) async {
        await tester.scrollUntilVisible(
          find.text(text),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text(text));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      final tolerance = find.widgetWithText(
        TextFormField,
        'New exact tolerance',
      );
      await tester.ensureVisible(tolerance);
      await tester.enterText(tolerance, '0.000001');
      await tap('Save tolerance');
      expect(find.text('Save this bank tolerance?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands, isEmpty);
      await tap('Match selected lines');
      expect(find.text('Confirm bank match?'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Confirm'));
        while (c.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(gateway.commands.single.payload['statement_line_ids'], ['s1']);
      expect(gateway.commands.single.payload['journal_line_ids'], ['j1']);
      await tap('Imported statements');
      expect(find.text('STMT-1 · 1 rows'), findsOneWidget);
      await tap('Source evidence');
      expect(find.textContaining('Statement lines: s1'), findsOneWidget);
      await tap('Reverse match');
      expect(find.text('Reverse this match?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.commands.length, 1);
      c.setOnline(false);
      await tester.pumpAndSettle();
      expect(find.text('Bank reconciliation'), findsNothing);
      expect(find.text('Verify access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
