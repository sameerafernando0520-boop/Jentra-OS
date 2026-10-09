import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/features/analytics/cash_payment_dates_section.dart';
import 'package:jentra_desktop/src/features/analytics/cash_scenario_screen.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

String id(int n) => '40000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final scope = ProcessMetricScope(
  tenantId: id(1),
  legalEntityId: id(2),
  branchId: id(3),
);

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

EncryptedDraftRepository drafts(JentraLocalDatabase db) =>
    EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));

void populate(CashScenarioController c) {
  const providers = {
    'bank_cash',
    'receivables',
    'payables',
    'payroll',
    'project_reimbursements',
  };
  c.basis = DatedCashBasis(
    scope,
    'a' * 64,
    '2026-10-09',
    '2026-10-11',
    '2026-10-09T00:00:00Z',
    [
      CashControl(
        scope: scope,
        accountId: id(5),
        currency: 'LKR',
        units: BigInt.from(10000000),
        asOf: '2026-10-09T00:00:00Z',
        publicationId: id(6),
        sourceVersion: '1',
      ),
    ],
    const [],
    providers,
    {for (final p in providers) p: 'available'},
    contractRevision: 3,
  );
  c.revision = CashScenarioRevision(
    id: id(9),
    scope: scope,
    sourceHash: c.basis!.hash,
    horizonStart: c.basis!.start,
    horizonEnd: c.basis!.end,
    recordedThrough: c.basis!.recordedThrough,
    overrides: {},
  );
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  for (final dispose in [false, true]) {
    test(
      'cash read stops after delayed authorization and ${dispose ? 'disposal' : 'offline invalidation'}',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entered = Completer<void>(), response = Completer<Object?>();
        final calls = <String>[];
        final gateway = DatedCashGateway((name, _) async {
          calls.add(name);
          if (name == 'wave5_cash_authorize') {
            entered.complete();
            return response.future;
          }
          throw StateError('An invalidated read must not reach its provider.');
        });
        final c = CashScenarioController(
          scope,
          id(7),
          gateway,
          CashScenarioStore(drafts(db), gateway.authorize),
        );
        final work = c.read('2026-10-09', '2026-10-11');
        await entered.future;
        if (dispose) {
          c.dispose();
        } else {
          c.setOnline(false);
          addTearDown(c.dispose);
        }
        response.complete(id(7));
        await work;
        expect(calls, ['wave5_cash_authorize']);
        expect(c.basis, null);
      },
    );

    test(
      'payment-date read stops after delayed MFA authorization and ${dispose ? 'disposal' : 'offline invalidation'}',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entered = Completer<void>(), response = Completer<Object?>();
        final calls = <String>[];
        final gateway = CashPaymentDatesGateway((name, _) async {
          calls.add(name);
          if (name == 'wave5_cash_date_authorize') {
            entered.complete();
            return response.future;
          }
          throw StateError('An invalidated read must not reach its provider.');
        });
        final c = CashPaymentDatesController(
          scope,
          id(7),
          'payroll_obligation',
          gateway,
          Wave5CommandStore(
            drafts(db),
            (s, a) => gateway.authorize(s, a, 'payroll_obligation'),
            namespace: 'cash_dates_payroll_obligation',
          ),
        );
        final work = c.read();
        await entered.future;
        if (dispose) {
          c.dispose();
        } else {
          c.setOnline(false);
          addTearDown(c.dispose);
        }
        response.complete(id(7));
        await work;
        expect(calls, ['wave5_cash_date_authorize']);
        expect(c.sources, isEmpty);
      },
    );

    test(
      'freeze recovery survives ${dispose ? 'disposal' : 'offline invalidation'} during final removal authorization',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entered = Completer<void>(), release = Completer<void>();
        var serverSaved = false, saves = 0;
        late CashScenarioRevision original;
        final gateway = DatedCashGateway((name, _) async {
          if (name == 'wave5_cash_authorize') return id(7);
          if (name == 'wave5_cash_save') {
            serverSaved = true;
            saves++;
            return {
              'id': original.id,
              'sourceHash': original.sourceHash,
              'version': '1',
            };
          }
          throw StateError('Unexpected provider call.');
        });
        final store = CashScenarioStore(drafts(db), (_, _) async {
          if (serverSaved && !entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        });
        final c = CashScenarioController(scope, id(7), gateway, store);
        populate(c);
        original = c.revision!;
        final work = c.freeze();
        await entered.future;
        if (dispose) {
          c.dispose();
        } else {
          c.setOnline(false);
          addTearDown(c.dispose);
        }
        release.complete();
        await work;
        expect(saves, 1);
        expect(c.savedId, null);
        expect(
          (await store.restore(scope, id(7), pending: true))!.toJson(),
          original.toJson(),
        );
      },
    );

    test(
      'payment-date recovery survives ${dispose ? 'disposal' : 'offline invalidation'} during final removal authorization',
      () async {
        final db = JentraLocalDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entered = Completer<void>(), release = Completer<void>();
        var commandReturned = false, commands = 0;
        final original = <String, Object?>{
          'commandId': id(20),
          'idempotencyKey': id(21),
          'clientTimestamp': '2026-10-09T00:00:00Z',
          'action': 'prepare',
          'payload': <String, Object?>{
            'id': id(22),
            'sourceKind': 'payroll_obligation',
            'sourceId': id(23),
            'sourceHash': 'a' * 64,
            'dueDate': '2026-10-10',
            'reasonCode': 'payroll_calendar',
            'expectedVersion': '0',
          },
        };
        final gateway = CashPaymentDatesGateway((name, _) async {
          if (name == 'wave5_cash_date_authorize') return id(7);
          if (name == 'wave5_cash_date_command') {
            commandReturned = true;
            commands++;
            return {
              'entity': {
                'id': id(22),
                'version': '1',
                'proposalHash': 'b' * 64,
                'status': 'prepared',
              },
            };
          }
          throw StateError('Unexpected provider call.');
        });
        final store = Wave5CommandStore(drafts(db), (_, _) async {
          if (commandReturned && !entered.isCompleted) {
            entered.complete();
            await release.future;
          }
        }, namespace: 'cash_dates_payroll_obligation');
        await store.save(scope, id(7), original);
        final c = CashPaymentDatesController(
          scope,
          id(7),
          'payroll_obligation',
          gateway,
          store,
        );
        final work = c.retry();
        await entered.future;
        if (dispose) {
          c.dispose();
        } else {
          c.setOnline(false);
          addTearDown(c.dispose);
        }
        release.complete();
        await work;
        expect(commands, 1);
        expect(c.pending, null);
        expect(c.receipt, null);
        expect(await store.restore(scope, id(7)), original);
      },
    );
  }

  test('offline invalidation during encrypted freeze save preserves original identity and prevents dispatch', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entered = Completer<void>(), release = Completer<void>();
    var storeChecks = 0;
    final store = CashScenarioStore(drafts(db), (s, a) async {
      if (++storeChecks == 3) {
        entered.complete();
        await release.future;
      }
    });
    final calls = <String>[];
    final gateway = DatedCashGateway((name, _) async {
      calls.add(name);
      if (name == 'wave5_cash_authorize') return id(7);
      throw StateError('An invalidated freeze must not be dispatched.');
    });
    final c = CashScenarioController(scope, id(7), gateway, store);
    addTearDown(c.dispose);
    populate(c);
    final original = c.revision!;
    final work = c.freeze();
    await entered.future;
    c.setOnline(false);
    release.complete();
    await work;
    expect(calls, ['wave5_cash_authorize']);
    expect(
      (await store.restore(scope, id(7), pending: true))!.toJson(),
      original.toJson(),
    );
    expect(c.savedId, null);
  });

  test(
    'late freeze receipt retains encrypted recovery after offline invalidation',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final entered = Completer<void>(), response = Completer<Object?>();
      final calls = <String>[];
      final gateway = DatedCashGateway((name, _) async {
        calls.add(name);
        if (name == 'wave5_cash_authorize') return id(7);
        if (name == 'wave5_cash_save') {
          entered.complete();
          return response.future;
        }
        throw StateError('Unexpected provider call.');
      });
      final store = CashScenarioStore(drafts(db), (_, _) async {});
      final c = CashScenarioController(scope, id(7), gateway, store);
      addTearDown(c.dispose);
      populate(c);
      final original = c.revision!;
      final work = c.freeze();
      await entered.future;
      c.setOnline(false);
      response.complete({
        'id': original.id,
        'sourceHash': original.sourceHash,
        'version': '1',
      });
      await work;
      expect(calls, ['wave5_cash_authorize', 'wave5_cash_save']);
      expect(
        (await store.restore(scope, id(7), pending: true))!.toJson(),
        original.toJson(),
      );
      expect(c.savedId, null);
    },
  );

  test(
    'authorization loss clears the previously frozen export identity',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final gateway = DatedCashGateway(
        (_, _) async => throw StateError('revoked'),
      );
      final c = CashScenarioController(
        scope,
        id(7),
        gateway,
        CashScenarioStore(drafts(db), gateway.authorize),
      );
      addTearDown(c.dispose);
      populate(c);
      c.savedId = id(9);
      await c.read('2026-10-09', '2026-10-11');
      expect(c.basis, null);
      expect(c.revision, null);
      expect(c.savedId, null);
      expect(c.error, isNotNull);
    },
  );

  testWidgets(
    'scenario field values clear when the actor controller changes and on offline invalidation',
    (tester) async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final gateway = DatedCashGateway((_, _) async => id(7));
      CashScenarioController create(String actor) {
        final c = CashScenarioController(
          scope,
          actor,
          gateway,
          CashScenarioStore(drafts(db), (_, _) async {}),
        );
        populate(c);
        addTearDown(c.dispose);
        return c;
      }

      final first = create(id(7)), second = create(id(8));
      Future<void> show(CashScenarioController c) => tester.pumpWidget(
        ProviderScope(
          overrides: [
            cashScenarioControllerProvider.overrideWithValue(c),
            cashPaymentDatesControllerProvider('payroll_obligation')
                .overrideWithValue(null),
          ],
          child: const MaterialApp(home: Scaffold(body: CashScenarioScreen())),
        ),
      );
      await show(first);
      await tester.enterText(field('Horizon start (YYYY-MM-DD)'), '2026-10-09');
      final startInput = tester
          .widget<TextField>(field('Horizon start (YYYY-MM-DD)'))
          .controller!;
      await tester.scrollUntilVisible(
        field('Scenario remaining amount, exact decimal'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        field('Scenario remaining amount, exact decimal'),
        '123.456789',
      );
      final amountInput = tester
          .widget<TextField>(field('Scenario remaining amount, exact decimal'))
          .controller!;
      await tester.ensureVisible(field('Scenario due date (YYYY-MM-DD)'));
      await tester.enterText(
        field('Scenario due date (YYYY-MM-DD)'),
        '2026-10-10',
      );
      final dateInput = tester
          .widget<TextField>(field('Scenario due date (YYYY-MM-DD)'))
          .controller!;
      await show(second);
      await tester.pump();
      for (final input in [startInput, amountInput, dateInput]) {
        expect(input.text, isEmpty);
      }
      await tester.ensureVisible(
        field('Scenario remaining amount, exact decimal'),
      );
      await tester.enterText(
        field('Scenario remaining amount, exact decimal'),
        '999.999999',
      );
      second.setOnline(false);
      await tester.pump();
      expect(field('Scenario remaining amount, exact decimal'), findsNothing);
      // Reopening the same controller must not reveal the earlier typed amount.
      second.setOnline(true);
      populate(second);
      await tester.pump();
      expect(amountInput.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
