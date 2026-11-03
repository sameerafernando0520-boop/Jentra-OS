import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/field_confirmation_company.dart';
import 'package:jentra_platform/jentra_platform.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  const scope = FieldSalesScope('tenant', 'company', 'branch');
  test(
    'company delivery mode uses only its own selectors command and receipt',
    () async {
      final calls = <String>[];
      final gateway = SupabaseFieldConfirmationCompanyGateway.withRpc(
        (name, params) async {
          calls.add(name);
          return {
            'items': [],
            'next_cursor': null,
            'provider_state': 'unavailable',
          };
        },
        currentActor: () => 'manager',
        delivery: true,
      );
      await gateway.subjects(scope);
      await gateway.contacts(scope, 'customer');
      await gateway.challenges(scope, 'delivery');
      await gateway.command({});
      await gateway.receipt(scope, 'key');
      expect(calls, [
        'field_sales_delivery_subjects',
        'field_sales_confirmation_contacts',
        'field_sales_delivery_challenges',
        'field_sales_delivery_command',
        'field_sales_delivery_receipt',
      ]);
    },
  );
  test(
    'order and delivery pending requests are encrypted under separate identities and exact version bindings',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys()));
      final orderStore = FieldConfirmationCompanyStore(repo),
          deliveryStore = FieldConfirmationCompanyStore(repo, delivery: true);
      final order = await orderStore.prepare('manager', scope, 'issue_order', {
        'id': 'order-challenge',
        'request_id': 'request',
        'request_version': '2',
        'source_digest': 'a' * 64,
        'contact_id': 'contact',
        'contact_version': '9',
      });
      final delivery = await deliveryStore
          .prepare('manager', scope, 'issue_delivery', {
            'id': 'delivery-challenge',
            'delivery_id': 'delivery',
            'delivery_version': '9007199254740993',
            'delivery_digest': 'b' * 64,
            'contact_id': 'contact',
            'contact_version': '9',
          });
      expect(
        (await orderStore.load('manager', scope))!.commandId,
        order.commandId,
      );
      expect(
        (await deliveryStore.load('manager', scope))!.commandId,
        delivery.commandId,
      );
      final receipt = <String, dynamic>{
        'command_id': delivery.commandId,
        'entity': {
          ...scope.params.map(
            (key, value) => MapEntry(key.substring(2), value),
          ),
          ...delivery.payload,
          'version': '1',
          'state': 'queued_link',
        },
      };
      delivery.validate(receipt);
      receipt['entity']['delivery_version'] = '9007199254740992';
      expect(
        () => delivery.validate(receipt),
        throwsA(isA<FieldSalesFailure>()),
      );
      await deliveryStore.complete(delivery);
      expect(await deliveryStore.load('manager', scope), isNull);
      expect(await orderStore.load('manager', scope), isNotNull);
    },
  );
  test(
    'a delivery store refuses an order action and cannot manufacture a second pending command',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys()));
      final store = FieldConfirmationCompanyStore(repo, delivery: true);
      await expectLater(
        store.prepare('manager', scope, 'issue_order', {'id': 'id'}),
        throwsA(isA<FieldSalesFailure>()),
      );
      await store.prepare('manager', scope, 'issue_delivery', {
        'id': 'challenge',
        'delivery_id': 'delivery',
        'delivery_version': '2',
        'delivery_digest': 'a' * 64,
        'contact_id': 'contact',
        'contact_version': '9',
      });
      await expectLater(
        store.prepare('manager', scope, 'revoke_delivery', {
          'id': 'challenge',
          'reason': 'Review',
        }, expectedVersion: '1'),
        throwsA(isA<FieldSalesFailure>()),
      );
    },
  );
}
