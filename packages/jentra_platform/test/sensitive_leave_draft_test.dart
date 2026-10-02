import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/jentra_people_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

import 'support/wave4_gateway_harness.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  bool forbid = false;
  int reads = 0;
  @override
  Future<String?> read(String key) async {
    reads++;
    if (forbid) throw StateError('Unexpected decryption');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Server implements WorkforceRepository {
  Map<String, Object?>? result;
  String? requested;
  @override
  Future<Map<String, Object?>?> leaveOwnReceipt(
    TenantContext scope,
    String commandId,
  ) async {
    requested = commandId;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> form() => {
  'action': 'create',
  'id': w4Id,
  'employee_id': w4Id,
  'policy_version_id': w4Revision,
  'calendar_version_id': w4Revision,
  'start_local': '2026-09-30T09:00:00',
  'start_offset_seconds': 19800,
  'end_local': '2026-09-30T17:00:00',
  'end_offset_seconds': 19800,
  'reason': 'SYNTHETIC_PRIVATE_LEAVE_REASON',
};
void main() {
  late JentraLocalDatabase db;
  late _Keys keys;
  late SensitiveLeaveDraftStore store;
  late DateTime now;
  bool denied = false;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = _Keys();
    now = DateTime.utc(2026, 9, 30);
    denied = false;
    store = SensitiveLeaveDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      (scope, employee) async {
        if (denied) {
          throw const DomainError(
            code: 'PERMISSION_DENIED',
            message: 'Current access required',
          );
        }
      },
      clock: () => now,
    );
  });
  tearDown(() => db.close());
  test(
    'recovery reads only metadata and deletes expired body before decrypt',
    () async {
      final pending = await store.prepare(
        w4Scope,
        w4Id,
        w4Id,
        'create',
        form(),
        0,
      );
      final before = keys.reads;
      keys.forbid = true;
      expect((await store.recovery(w4Scope)).single.expired, isFalse);
      expect(keys.reads, before);
      now = now.add(const Duration(hours: 24));
      final expired = (await store.recovery(w4Scope)).single;
      expect(expired.expired, isTrue);
      expect(await store.load(w4Scope, w4Id, w4Id), isNull);
      expect(keys.reads, before);
      keys.forbid = false;
      final stub = await store.receipt(w4Scope, w4Id, w4Id);
      expect(stub!['command_id'], pending.envelope.commandId);
      expect(
        stub.keys,
        unorderedEquals([
          'command_id',
          'employee_id',
          'id',
          'expected_version',
        ]),
      );
      final rows = await db.select(db.encryptedDrafts).get();
      expect(rows.single.entityType, 'sensitive_leave_receipt');
    },
  );
  test(
    'uncertain request reuses its exact sealed envelope and blocks editing',
    () async {
      final first = await store.prepare(
        w4Scope,
        w4Id,
        w4Id,
        'create',
        form(),
        0,
      );
      await store.failure(
        w4Scope,
        w4Id,
        w4Id,
        first.envelope.commandId,
        const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Retry',
          retryable: true,
        ),
      );
      final again = await store.prepare(
        w4Scope,
        w4Id,
        w4Id,
        'create',
        form(),
        0,
      );
      expect(again.toJson(), first.toJson());
      await expectLater(
        store.prepare(
          w4Scope,
          w4Id,
          w4Id,
          'create',
          form()..['reason'] = 'Changed',
          0,
        ),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
        ),
      );
      await expectLater(
        store.discard(w4Scope, w4Id, w4Id),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test('stale draft requires explicit comparison before replacement', () async {
    final first = await store.prepare(w4Scope, w4Id, w4Id, 'create', form(), 0);
    await store.failure(
      w4Scope,
      w4Id,
      w4Id,
      first.envelope.commandId,
      const DomainError(code: 'VERSION_CONFLICT', message: 'Compare'),
    );
    await expectLater(
      store.save(w4Scope, w4Id, w4Id, 'create', form(), 1),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
      ),
    );
    await store.save(w4Scope, w4Id, w4Id, 'create', form(), 1, compared: true);
    expect((await store.load(w4Scope, w4Id, w4Id))!.version, 1);
  });
  test('current denial occurs before private body decryption', () async {
    await store.save(w4Scope, w4Id, w4Id, 'create', form(), 0);
    final before = keys.reads;
    denied = true;
    await expectLater(
      store.load(w4Scope, w4Id, w4Id),
      throwsA(isA<DomainError>()),
    );
    expect(keys.reads, before);
    denied = false;
    final other = TenantContext(
      tenantId: w4Scope.tenantId,
      legalEntityId: w4Scope.legalEntityId,
      branchId: w4Scope.branchId,
      actorId: w4Id,
    );
    expect(await store.recovery(other), isEmpty);
  });
  test(
    'expired receipt is retained until its remote outcome is verified',
    () async {
      final pending = await store.prepare(
        w4Scope,
        w4Id,
        w4Id,
        'create',
        form(),
        0,
      );
      now = now.add(const Duration(hours: 24));
      await store.recovery(w4Scope);
      final server = _Server();
      expect(
        await store.reconcileExpired(w4Scope, w4Id, w4Id, server),
        isFalse,
      );
      expect(await store.receipt(w4Scope, w4Id, w4Id), isNotNull);
      server.result = {'id': w4Id, 'employee_id': w4Id, 'version': 1};
      expect(await store.reconcileExpired(w4Scope, w4Id, w4Id, server), isTrue);
      expect(server.requested, pending.envelope.commandId);
      expect(await store.receipt(w4Scope, w4Id, w4Id), isNull);
    },
  );
}
