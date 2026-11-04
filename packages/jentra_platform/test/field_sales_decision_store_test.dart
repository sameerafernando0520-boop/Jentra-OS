import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

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
  const s = FieldSalesScope('tenant', 'entity', 'branch');
  final row = <String, dynamic>{
    'id': 'request',
    'version': '9007199254740993',
    'source_digest': 'a' * 64,
  };
  late JentraLocalDatabase db;
  late EncryptedDraftRepository repo;
  late FieldSalesDecisionStore store;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repo = EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys()));
    store = FieldSalesDecisionStore(repo);
  });
  tearDown(() async => db.close());
  test(
    'company decision is encrypted, actor-scoped and immutable across restart',
    () async {
      final command = await store.prepare(
        'manager',
        s,
        row,
        'approve',
        'Private company reason',
      );
      final raw = await db
          .customSelect('select encrypted_payload from encrypted_drafts')
          .getSingle();
      expect(
        utf8.decode(
          raw.read<Uint8List>('encrypted_payload'),
          allowMalformed: true,
        ),
        isNot(contains('Private company reason')),
      );
      final reopened = await FieldSalesDecisionStore(repo).load('manager', s);
      expect(reopened!.params, command.params);
      expect(reopened.params['p_expected_entity_version'], '9007199254740993');
      expect(await store.load('other-manager', s), isNull);
      await expectLater(
        store.prepare('manager', s, row, 'reject', 'Changed'),
        throwsA(isA<FieldSalesFailure>()),
      );
    },
  );
  test('parallel company prepares seal only one original decision', () async {
    final outcomes = await Future.wait([
      store
          .prepare('manager', s, row, 'approve', 'First')
          .then<Object>((v) => v, onError: (Object e) => e),
      FieldSalesDecisionStore(repo)
          .prepare('manager', s, row, 'reject', 'Second')
          .then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(outcomes.whereType<FieldSalesDecision>(), hasLength(1));
    expect(outcomes.whereType<FieldSalesFailure>(), hasLength(1));
  });
  test(
    'receipt binds company actor, exact revision/digest and independent customer state',
    () async {
      final command = await store.prepare(
        'manager',
        s,
        row,
        'approve',
        'Approved reason',
      );
      final receipt = <String, dynamic>{
        'command_id': command.commandId,
        'entity': {
          'id': 'request',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'source_digest': 'a' * 64,
          'decision_by': 'manager',
          'decision_reason': 'Approved reason',
          'company_state': 'approved',
          'version': '9007199254740994',
          'customer_state': 'email_link_pending',
          'canonical_state': 'draft',
          'canonical_order_id': 'order',
        },
      };
      command.validate(receipt);
      receipt['entity']['decision_by'] = 'rep';
      expect(
        () => command.validate(receipt),
        throwsA(isA<FieldSalesFailure>()),
      );
      expect(await store.load('manager', s), isNotNull);
      await store.complete(command);
      expect(await store.load('manager', s), isNull);
    },
  );
}
