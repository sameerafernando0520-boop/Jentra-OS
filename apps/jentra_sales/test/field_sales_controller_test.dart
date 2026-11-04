import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';

import 'support/field_sales_fixture.dart';

final class FailingFieldStore implements SalesKeyValueStore {
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('unavailable');
  @override
  Future<void> delete(String key) async {}
}

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
  test(
    'workspace loads full assigned portfolio and waits for explicit review',
    () async {
      await c.open();
      expect(c.customers.single['name'], contains('no transactions'));
      await c.selectCustomer('customer');
      await c.preview(fieldInput);
      expect(c.review!['pricing']['grand_total'], '1.270000');
      expect(gateway.commands, isEmpty);
      await c.submit();
      expect(c.orders.single['company_state'], 'submitted');
      expect(c.orders.single['customer_state'], 'email_link_pending');
      expect(c.orders.single['canonical_order_id'], isNull);
      expect(store.values, isEmpty);
    },
  );
  test('multiple company scopes require explicit selection', () async {
    gateway.multipleScopes = true;
    await c.open();
    expect(c.scope, isNull);
    expect(c.customers, isEmpty);
    await c.selectScope(fieldScope);
    expect(c.customers, hasLength(1));
  });
  test('missing candidate service has no synthetic fallback', () async {
    gateway.failure = const FieldSalesFailure(
      'FIELD_SALES_ROLLOUT_PENDING',
      'Not installed',
    );
    await expectLater(c.open(), throwsA(isA<FieldSalesFailure>()));
    expect(c.isOpen, isFalse);
    expect(c.customers, isEmpty);
  });
  test('protected persistence failure prevents any dispatch', () async {
    final blocked = FieldSalesController(
      gateway: gateway,
      store: FailingFieldStore(),
    );
    addTearDown(blocked.dispose);
    await blocked.open();
    await blocked.preview(fieldInput);
    await blocked.submit();
    expect(gateway.commands, isEmpty);
    expect(blocked.pending, isNull);
    expect(blocked.error, isNotNull);
  });
  test(
    'lost response survives restart; explicit retry retains exact command',
    () async {
      await c.open();
      await c.preview(fieldInput);
      gateway.submitFailure = const FieldSalesFailure(
        'OUTCOME_UNKNOWN',
        'Interrupted',
      );
      await c.submit();
      final original = c.pending!;
      expect(store.values, hasLength(1));
      final restarted = FieldSalesController(gateway: gateway, store: store);
      addTearDown(restarted.dispose);
      await restarted.open();
      expect(gateway.commands, hasLength(1));
      expect(restarted.pending!.toJson(), original.toJson());
      await restarted.reconcile();
      expect(gateway.commands, hasLength(1));
      expect(restarted.pending, isNotNull);
      gateway.submitFailure = null;
      await restarted.reconcile(retry: true);
      expect(gateway.commands.last.params, original.params);
      expect(restarted.pending, isNull);
      expect(store.values, isEmpty);
    },
  );
  test('receipt with wrong actor is never acknowledged or removed', () async {
    await c.open();
    await c.preview(fieldInput);
    gateway.badReceipt = true;
    await c.submit();
    expect(c.pending, isNotNull);
    expect(c.orders, isEmpty);
    expect(store.values, hasLength(1));
  });
  test('definite stale-source rejection requires fresh review', () async {
    await c.open();
    await c.preview(fieldInput);
    gateway.submitFailure = const FieldSalesFailure(
      '40001',
      'Review changed prices',
    );
    await c.submit();
    expect(c.pending, isNull);
    expect(c.review, isNull);
    expect(store.values, isEmpty);
    expect(c.error, contains('Review'));
  });
  test('revocation clears visible private data', () async {
    await c.open();
    gateway.failure = const FieldSalesFailure('42501', 'Access changed');
    await c.selectCustomer('customer');
    expect(c.isOpen, isFalse);
    expect(c.customers, isEmpty);
    expect(c.products, isEmpty);
    expect(c.orders, isEmpty);
  });
  test('late catalogue cannot repopulate signed-out workspace', () async {
    await c.open();
    gateway.catalogueWait = Completer();
    final loading = c.selectCustomer('customer');
    c.clear();
    gateway.catalogueWait!.complete([
      {'name': 'late private row'},
    ]);
    await loading;
    expect(c.products, isEmpty);
    expect(c.isOpen, isFalse);
  });
  test('editing while review is in flight invalidates its result', () async {
    await c.open();
    gateway.previewWait = Completer();
    final loading = c.preview(fieldInput);
    c.invalidateReview();
    gateway.previewWait!.complete(fieldReview);
    await loading;
    expect(c.review, isNull);
    expect(c.busy, isFalse);
  });
  test(
    'actor change locks old private rows even if no auth event arrives',
    () async {
      await c.open();
      gateway.catalogueWait = Completer();
      final read = c.selectCustomer('customer');
      gateway.actorId = null;
      gateway.catalogueWait!.complete([]);
      await read;
      expect(c.isOpen, isFalse);
      expect(c.customers, isEmpty);
      expect(c.orders, isEmpty);
      expect(c.busy, isFalse);
    },
  );
  test('receipt recovery preserves the current company decision', () async {
    await c.open();
    await c.preview(fieldInput);
    gateway.submitFailure = const FieldSalesFailure(
      'OUTCOME_UNKNOWN',
      'Interrupted',
    );
    await c.submit();
    final command = c.pending!;
    gateway.committed = gateway.confirmation(command);
    final approved =
        Map<String, dynamic>.from(gateway.committed!['entity'] as Map)
          ..['company_state'] = 'approved'
          ..['version'] = '2';
    gateway.currentSubjects = [approved];
    await c.reconcile();
    expect(c.orders.single['company_state'], 'approved');
    expect(c.orders.single['version'], '2');
  });
  test('protected governed draft is scoped, restored and never submitted automatically', () async {
    await c.open();
    expect(await c.saveDraft(fieldInput), isTrue);
    final restarted = FieldSalesController(gateway: gateway, store: store);
    addTearDown(restarted.dispose);
    await restarted.open();
    expect(restarted.savedDraft, fieldInput);
    expect(gateway.commands, isEmpty);
    gateway.failure = const FieldSalesFailure('42501', 'Revoked');
    await restarted.selectCustomer('customer');
    expect(restarted.savedDraft, isNull);
  });
  test(
    'expired recovery removes sensitive body and permits receipt checking only',
    () async {
      final old = FieldSalesCommand(
        actorId: 'rep',
        scope: fieldScope,
        commandId: 'command',
        key: 'key',
        at: DateTime.now()
            .subtract(const Duration(days: 2))
            .toUtc()
            .toIso8601String(),
        payload: {
          'id': 'request',
          'input': fieldInput,
          'source_digest': 'a' * 64,
        },
      );
      await store.write(
        'jentra.sales.command.v1.rep.${fieldScope.key}',
        jsonEncode(old.toJson()),
      );
      await c.open();
      expect(c.pending!.bodyExpired, isTrue);
      expect(c.pending!.payload['input'], {'customer_id': 'customer'});
      expect(store.values.values.single, isNot(contains('Company request')));
      await c.reconcile(retry: true);
      expect(gateway.commands, isEmpty);
      expect(c.pending, isNotNull);
      gateway.committed = gateway.confirmation(old);
      await c.reconcile();
      expect(c.pending, isNull);
    },
  );
}
