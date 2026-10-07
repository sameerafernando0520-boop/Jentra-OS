import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_projects_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const id = '20000000-0000-0000-0000-000000000001';

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

ScopedPendingCommand request({
  Map<String, Object?>? payload,
  DateTime? issuedAt,
}) => ScopedPendingCommand(
  'create',
  CommandEnvelope(
    context: scope,
    commandId: id,
    idempotencyKey: id,
    expectedEntityVersion: 0,
    clientTimestamp: issuedAt ?? DateTime.utc(2026, 10, 5),
    payload:
        payload ?? {'action': 'create', 'id': id, 'name': 'Synthetic project'},
  ),
);
Map<String, Object?> entity() => {
  'id': id,
  'tenant_id': scope.tenantId,
  'legal_entity_id': scope.legalEntityId,
  'branch_id': scope.branchId,
  'version': 1,
};
void main() {
  late JentraLocalDatabase db;
  late EncryptedDraftRepository repository;
  late ProjectCommandAcknowledgements acknowledgements;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    repository = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
    acknowledgements = ProjectCommandAcknowledgements(
      ScopedCommandDraftStore(
        repository,
        entityType: 'projects.command.create',
        fields: (_) => {'action', 'id', 'name'},
        validate: (_, _) {},
        definiteFailures: {},
      ),
    );
  });
  tearDown(() async {
    await db.close();
  });
  test(
    'exact request survives recreation without financial receipt data',
    () async {
      final original = request();
      await acknowledgements.save(original, {
        ...entity(),
        'cost': '1000',
        'name': 'Private source',
      });
      final row = (await db.select(db.encryptedDrafts).get()).single;
      expect(
        utf8.decode(row.encryptedPayload, allowMalformed: true),
        isNot(contains('Private source')),
      );
      final decoded = (await repository.find(row.id))!.payload;
      expect(decoded.keys.toSet(), {
        'scope',
        'action',
        'command_id',
        'idempotency_key',
        'entity_id',
        'version',
        'request_digest',
      });
      expect(decoded.containsKey('cost'), isFalse);
      expect(jsonEncode(decoded), isNot(contains('Private source')));
      expect(
        await acknowledgements.contains(
          ScopedPendingCommand.fromJson(original.toJson()),
        ),
        isTrue,
      );
    },
  );
  test(
    'changed body with the same identities cannot borrow confirmation',
    () async {
      await acknowledgements.save(request(), entity());
      await expectLater(
        acknowledgements.contains(
          request(
            payload: {
              'action': 'create',
              'id': id,
              'name': 'Different project',
            },
          ),
        ),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test('changed issued timestamp cannot borrow confirmation', () async {
    await acknowledgements.save(request(), entity());
    await expectLater(
      acknowledgements.contains(request(issuedAt: DateTime.utc(2026, 10, 6))),
      throwsA(isA<DomainError>()),
    );
  });
  test(
    'object key ordering does not change the original request identity',
    () async {
      await acknowledgements.save(request(), entity());
      expect(
        await acknowledgements.contains(
          request(
            payload: {
              'name': 'Synthetic project',
              'id': id,
              'action': 'create',
            },
          ),
        ),
        isTrue,
      );
    },
  );
  test('foreign scope confirmation is rejected before storage', () async {
    await expectLater(
      acknowledgements.save(request(), {...entity(), 'branch_id': id}),
      throwsA(isA<DomainError>()),
    );
    expect(await db.select(db.encryptedDrafts).get(), isEmpty);
  });
}
