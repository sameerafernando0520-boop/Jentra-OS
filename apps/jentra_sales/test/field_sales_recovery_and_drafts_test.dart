import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';

import 'support/field_sales_fixture.dart';

const _recoveryKey = 'jentra.sales.command.v1.rep.tenant.entity.branch';
const _draftKey = 'jentra.sales.order-draft.v1.rep.tenant.entity.branch';

FieldSalesCommand _command(Duration age) => FieldSalesCommand(
  actorId: 'rep',
  scope: fieldScope,
  commandId: 'command',
  key: 'key',
  at: DateTime.now().subtract(age).toUtc().toIso8601String(),
  payload: {'id': 'request', 'input': fieldInput, 'source_digest': 'a' * 64},
);

Map<String, dynamic> _inputFor(String customer, String notes) =>
    Map<String, dynamic>.from(fieldInput)
      ..['customer_id'] = customer
      ..['notes'] = notes;

void main() {
  late FakeFieldSalesGateway gateway;
  late MemorySalesStore store;
  late FieldSalesController c;
  setUp(() {
    gateway = FakeFieldSalesGateway();
    store = MemorySalesStore();
    c = FieldSalesController(gateway: gateway, store: store);
  });
  tearDown(() => c.dispose());

  test('storage keys in this test match the controller', () async {
    expect(_recoveryKey, 'jentra.sales.command.v1.rep.${fieldScope.key}');
    expect(_draftKey, 'jentra.sales.order-draft.v1.rep.${fieldScope.key}');
  });

  group('expired submission', () {
    test('is cleared once the company confirms it holds no record', () async {
      await store.write(
        _recoveryKey,
        jsonEncode(_command(const Duration(days: 2)).toJson()),
      );
      await c.open();
      expect(c.pending!.bodyExpired, isTrue);
      expect(c.canDiscardPending, isTrue);

      await c.discardExpired();

      expect(c.pending, isNull);
      expect(store.values, isEmpty);
      expect(gateway.commands, isEmpty, reason: 'nothing is resent');
      expect(c.error, contains('Nothing was ordered'));
      expect(c.error, contains('command'), reason: 'keeps the reference');

      await c.selectCustomer('customer');
      await c.preview(fieldInput);
      await c.submit();
      expect(c.orders.single['company_state'], 'submitted');
    });

    test('is recorded, not cleared, when the company did receive it', () async {
      final old = _command(const Duration(days: 2));
      await store.write(_recoveryKey, jsonEncode(old.toJson()));
      await c.open();
      gateway.committed = gateway.confirmation(old);

      await c.discardExpired();

      expect(c.pending, isNull);
      expect(c.orders.single['id'], 'request');
      expect(c.error, isNull);
    });

    test('stays when the check cannot be completed', () async {
      await store.write(
        _recoveryKey,
        jsonEncode(_command(const Duration(days: 2)).toJson()),
      );
      await c.open();
      gateway.receiptFailure = const FieldSalesFailure(
        'OUTCOME_UNKNOWN',
        'Offline',
      );

      await c.discardExpired();

      expect(c.pending, isNotNull);
      expect(store.values.keys, [_recoveryKey]);
      expect(c.error, 'Offline');
    });

    test(
      'a submission that can still be retried cannot be discarded',
      () async {
        await c.open();
        await c.selectCustomer('customer');
        await c.preview(fieldInput);
        gateway.submitFailure = const FieldSalesFailure(
          'OUTCOME_UNKNOWN',
          'No reply',
        );
        await c.submit();
        gateway
          ..submitFailure = null
          ..committed = null;
        expect(c.pending, isNotNull);
        expect(c.canDiscardPending, isFalse);

        await c.discardExpired();

        expect(c.pending, isNotNull);
        expect(store.values.keys, [_recoveryKey]);
      },
    );

    test('a just-expired body waits before it can be discarded', () async {
      // The customer left the portfolio seconds after sending: the body is
      // removed at once, but the request may still be arriving.
      final recent = _command(const Duration(seconds: 30));
      final wire = recent.toJson()
        ..['payload'] = {
          'id': 'request',
          'input': _inputFor('removed-customer', ''),
          'source_digest': 'a' * 64,
        };
      await store.write(_recoveryKey, jsonEncode(wire));
      await c.open();
      expect(c.pending!.bodyExpired, isTrue);
      expect(c.canDiscardPending, isFalse);

      await c.discardExpired();

      expect(c.pending, isNotNull);
    });
  });

  group('drafts', () {
    setUp(() => gateway.secondCustomer = true);

    test('each customer keeps its own draft', () async {
      await c.open();
      expect(await c.saveDraft(_inputFor('customer', 'First')), isTrue);
      expect(await c.saveDraft(_inputFor('customer2', 'Second')), isTrue);

      final restarted = FieldSalesController(gateway: gateway, store: store);
      addTearDown(restarted.dispose);
      await restarted.open();

      expect(restarted.draftFor('customer')!['notes'], 'First');
      expect(restarted.draftFor('customer2')!['notes'], 'Second');
      expect(restarted.draftFor('unknown'), isNull);
      await restarted.selectCustomer('customer');
      expect(restarted.savedDraft!['notes'], 'First');
      await restarted.selectCustomer('customer2');
      expect(restarted.savedDraft!['notes'], 'Second');
    });

    test('submitting consumes only that customer\'s draft', () async {
      await c.open();
      await c.saveDraft(_inputFor('customer', 'First'));
      await c.saveDraft(_inputFor('customer2', 'Second'));
      await c.selectCustomer('customer');
      await c.preview(_inputFor('customer', 'First'));
      await c.submit();

      expect(c.draftFor('customer'), isNull);
      expect(c.draftFor('customer2')!['notes'], 'Second');
      final restarted = FieldSalesController(gateway: gateway, store: store);
      addTearDown(restarted.dispose);
      await restarted.open();
      expect(restarted.draftFor('customer'), isNull);
      expect(restarted.draftFor('customer2')!['notes'], 'Second');
    });

    test('a draft saved by the earlier app version is kept', () async {
      await store.write(
        _draftKey,
        jsonEncode({
          'schema': 1,
          'actor_id': 'rep',
          'scope': fieldScope.key,
          'saved_at': DateTime.now().toUtc().toIso8601String(),
          'input': _inputFor('customer', 'Legacy'),
        }),
      );
      await c.open();
      expect(c.draftFor('customer')!['notes'], 'Legacy');
      expect(await c.saveDraft(_inputFor('customer2', 'Second')), isTrue);
      expect(c.draftFor('customer')!['notes'], 'Legacy');
    });

    test('expired and unassigned drafts are dropped, others stay', () async {
      String at(Duration age) =>
          DateTime.now().subtract(age).toUtc().toIso8601String();
      await store.write(
        _draftKey,
        jsonEncode({
          'schema': 2,
          'actor_id': 'rep',
          'scope': fieldScope.key,
          'drafts': [
            {
              'saved_at': at(const Duration(hours: 25)),
              'input': _inputFor('customer', 'Too old'),
            },
            {
              'saved_at': at(const Duration(hours: 1)),
              'input': _inputFor('customer2', 'Current'),
            },
            {
              'saved_at': at(const Duration(hours: 1)),
              'input': _inputFor('removed-customer', 'Unassigned'),
            },
          ],
        }),
      );
      await c.open();
      expect(c.draftFor('customer'), isNull);
      expect(c.draftFor('customer2')!['notes'], 'Current');
      expect(store.values[_draftKey], isNot(contains('Too old')));
      expect(store.values[_draftKey], isNot(contains('Unassigned')));
    });
  });

  test('an open order is saved as a draft when access expires', () async {
    final leased = FieldSalesController(
      gateway: gateway,
      store: store,
      lease: const Duration(milliseconds: 20),
    );
    addTearDown(leased.dispose);
    await leased.open();
    leased.unsavedOrder = () => _inputFor('customer', 'Typed before expiry');

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(leased.isOpen, isFalse);
    expect(leased.error, contains('lease expired'));
    final restarted = FieldSalesController(gateway: gateway, store: store);
    addTearDown(restarted.dispose);
    await restarted.open();
    expect(restarted.draftFor('customer')!['notes'], 'Typed before expiry');
    expect(gateway.commands, isEmpty, reason: 'a draft is never submitted');
  });

  test('access expiry with nothing typed saves nothing', () async {
    final leased = FieldSalesController(
      gateway: gateway,
      store: store,
      lease: const Duration(milliseconds: 20),
    );
    addTearDown(leased.dispose);
    await leased.open();
    leased.unsavedOrder = () => null;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(leased.isOpen, isFalse);
    expect(store.values, isEmpty);
  });
}
