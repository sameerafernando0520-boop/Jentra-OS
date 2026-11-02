import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/field_confirmation_company.dart';

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
    'staff gateway calls only bounded named facades and fences actor changes',
    () async {
      String? actor = 'manager';
      final calls = <(String, FieldSalesJson)>[];
      final gate = Completer<Object?>();
      final gateway = SupabaseFieldConfirmationCompanyGateway.withRpc((
        name,
        params,
      ) async {
        calls.add((name, params));
        return name == 'field_sales_confirmation_company_command'
            ? gate.future
            : {
                'items': [],
                'next_cursor': null,
                'provider_state': 'unavailable',
              };
      }, currentActor: () => actor);
      await gateway.subjects(scope);
      await gateway.contacts(scope, 'customer', after: 'cursor');
      await gateway.challenges(scope, 'request');
      expect(calls.map((c) => c.$1), [
        'field_sales_confirmation_subjects',
        'field_sales_confirmation_contacts',
        'field_sales_confirmation_challenges',
      ]);
      expect(calls[1].$2, {
        ...scope.params,
        'p_customer_id': 'customer',
        'p_after': 'cursor',
        'p_limit': 50,
      });
      final pending = gateway.command({});
      actor = 'other';
      gate.complete({'private': 'value'});
      await expectLater(pending, throwsA(isA<FieldSalesFailure>()));
    },
  );
  test(
    'staff gateway rejects repeated page cursors and unavailable rollout never falls back',
    () async {
      final gateway = SupabaseFieldConfirmationCompanyGateway.withRpc(
        (_, _) async => {'items': [], 'next_cursor': 'cursor'},
        currentActor: () => 'manager',
      );
      await expectLater(
        gateway.subjects(scope, after: 'cursor'),
        throwsA(isA<FieldSalesFailure>()),
      );
    },
  );
  group('protected company commands', () {
    late JentraLocalDatabase db;
    late EncryptedDraftRepository repo;
    late FieldConfirmationCompanyStore store;
    var now = DateTime.utc(2026, 11, 2);
    setUp(() {
      db = JentraLocalDatabase(NativeDatabase.memory());
      repo = EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys()));
      now = DateTime.utc(2026, 11, 2);
      store = FieldConfirmationCompanyStore(repo, now: () => now);
    });
    tearDown(() async => db.close());
    final contact = {
      'id': 'contact',
      'customer_id': 'customer',
      'name': 'Private Buyer',
      'email': 'BUYER@example.invalid',
      'authority_note': 'Private authority evidence',
      'valid_until': '2026-11-10T00:00:00Z',
    };
    test(
      'contact detail is encrypted and exact original survives a restart',
      () async {
        final c = await store.prepare(
          'manager',
          scope,
          'authorize_contact',
          contact,
          expectedVersion: '9007199254740993',
        );
        expect(c.params['p_expected_entity_version'], '9007199254740993');
        final raw = await db
            .customSelect('select encrypted_payload from encrypted_drafts')
            .getSingle();
        expect(
          utf8.decode(
            raw.read<Uint8List>('encrypted_payload'),
            allowMalformed: true,
          ),
          isNot(contains('Private Buyer')),
        );
        expect(
          (await FieldConfirmationCompanyStore(
            repo,
            now: () => now,
          ).load('manager', scope))!.params,
          c.params,
        );
        expect(await store.load('other', scope), isNull);
        final p = c.payload;
        p['email'] = 'changed';
        expect(c.payload['email'], 'buyer@example.invalid');
        final receipt = {
          'command_id': c.commandId,
          'entity': {
            ...scope.params.map((k, v) => MapEntry(k.substring(2), v)),
            ...c.payload,
            'version': '9007199254740994',
            'authorized_by': 'manager',
            'active': true,
            'channel_state': 'unverified',
          },
        };
        c.validate(receipt);
        (receipt['entity'] as Map)['email'] = 'wrong@example.invalid';
        expect(() => c.validate(receipt), throwsA(isA<FieldSalesFailure>()));
        expect(await store.load('manager', scope), isNotNull);
      },
    );
    test('concurrent prepares keep only one immutable original', () async {
      final results = await Future.wait([
        store
            .prepare('manager', scope, 'authorize_contact', contact)
            .then<Object>((v) => v, onError: (Object e) => e),
        FieldConfirmationCompanyStore(repo, now: () => now)
            .prepare('manager', scope, 'revoke_contact', {
              'id': 'contact',
            }, expectedVersion: '1')
            .then<Object>((v) => v, onError: (Object e) => e),
      ]);
      expect(
        results.whereType<FieldConfirmationCompanyCommand>(),
        hasLength(1),
      );
      expect(results.whereType<FieldSalesFailure>(), hasLength(1));
    });
    test(
      'expired sensitive body is stripped and can only check its original receipt',
      () async {
        final c = await store.prepare(
          'manager',
          scope,
          'authorize_contact',
          contact,
        );
        now = now.add(const Duration(hours: 25));
        final expired = (await store.load('manager', scope))!;
        expect(expired.expired, isTrue);
        expect(jsonEncode(expired.json), isNot(contains('Private')));
        expect(() => expired.params, throwsA(isA<FieldSalesFailure>()));
        expect(expired.commandId, c.commandId);
        await store.complete(expired);
        expect(await store.load('manager', scope), isNull);
      },
    );
    test(
      'issue receipt must bind the exact reviewed request and contact revisions',
      () async {
        final c = await store.prepare('manager', scope, 'issue_order', {
          'id': 'challenge',
          'request_id': 'request',
          'request_version': '2',
          'source_digest': 'a' * 64,
          'contact_id': 'contact',
          'contact_version': '9',
        });
        final receipt = <String, dynamic>{
          'command_id': c.commandId,
          'entity': {
            ...scope.params.map((k, v) => MapEntry(k.substring(2), v)),
            ...c.payload,
            'version': '1',
            'state': 'queued_link',
          },
        };
        c.validate(receipt);
        receipt['entity']['contact_version'] = '10';
        expect(() => c.validate(receipt), throwsA(isA<FieldSalesFailure>()));
      },
    );
  });
}
