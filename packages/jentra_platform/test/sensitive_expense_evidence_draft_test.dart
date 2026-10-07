import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_expense_evidence_platform.dart';
import 'support/wave4_gateway_harness.dart';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  bool forbid = false;
  int reads = 0;
  @override
  Future<String?> read(String key) async {
    reads++;
    if (forbid) throw StateError('Unexpected private decrypt');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late JentraLocalDatabase db;
  late Keys keys;
  late SensitiveExpenseEvidenceDraftStore store;
  late DateTime now;
  bool deny = false;
  Map<String, Object?> payload() => {
    'action': 'reserve',
    'id': w4Id,
    'project_id': w4Id,
    'expense_id': w4Revision,
    'purpose': 'PRIVATE_EVIDENCE_PURPOSE',
    'mime': 'text/plain',
    'byte_size': 4,
    'checksum': 'b' * 64,
  };
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = Keys();
    now = DateTime.utc(2026, 10, 5);
    deny = false;
    store = SensitiveExpenseEvidenceDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      (s, p, x, c) async {
        if (deny) {
          throw const DomainError(
            code: 'PERMISSION_DENIED',
            message: 'Scope changed',
          );
        }
      },
      clock: () => now,
    );
  });
  tearDown(() => db.close());
  test(
    'private metadata is encrypted and file bytes never enter draft',
    () async {
      await store.save(w4Scope, payload(), 0);
      final rows = await db.select(db.encryptedDrafts).get();
      expect(
        String.fromCharCodes(
          rows.single.encryptedPayload,
        ).contains('PRIVATE_EVIDENCE_PURPOSE'),
        false,
      );
      await expectLater(
        store.save(w4Scope, {
          ...payload(),
          'bytes': [1, 2],
        }, 0),
        throwsFormatException,
      );
    },
  );
  test(
    'authorization precedes private decryption on recovery and receipts',
    () async {
      await store.save(w4Scope, payload(), 0);
      await store.seal(w4Scope, w4Id, w4Revision, w4Id, expenseEvidenceManage);
      final old = keys.reads;
      deny = true;
      keys.forbid = true;
      await expectLater(
        store.read(w4Scope, w4Id, w4Revision, w4Id, expenseEvidenceManage),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        store.receipt(w4Scope, w4Id, w4Revision, w4Id, expenseEvidenceManage),
        throwsA(isA<DomainError>()),
      );
      expect(keys.reads, old);
    },
  );
  test(
    'sealing persists immutable exact identity and rejects replacement',
    () async {
      await store.save(w4Scope, payload(), 0);
      final first = await store.seal(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      final retry = await store.seal(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      expect(retry.toJson(), first.toJson());
      await expectLater(
        store.save(w4Scope, {...payload(), 'purpose': 'changed'}, 0),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PENDING_COMMAND'),
        ),
      );
    },
  );
  test(
    'expiry is fixed and uncertain minimal receipt survives body expiry',
    () async {
      await store.save(w4Scope, payload(), 0);
      now = now.add(const Duration(hours: 23));
      await store.save(w4Scope, payload(), 0);
      final sealed = await store.seal(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      now = now.add(const Duration(hours: 2));
      expect(
        await store.read(
          w4Scope,
          w4Id,
          w4Revision,
          w4Id,
          expenseEvidenceManage,
        ),
        null,
      );
      final receipt = await store.receipt(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      expect(receipt!['command_id'], sealed.envelope.commandId);
      expect(receipt.containsKey('purpose'), false);
      expect(
        await store.recoveryIds(
          w4Scope,
          w4Id,
          w4Revision,
          expenseEvidenceManage,
        ),
        [w4Id],
      );
    },
  );
  test('policy recovery has an independent entity namespace', () async {
    await store.save(w4Scope, {
      'action': 'policy_create',
      'id': w4Id,
      'retention_days': 30,
      'purpose': 'PRIVATE_POLICY_PURPOSE',
    }, 0);
    await store.seal(w4Scope, null, null, w4Id, expenseEvidenceRetention);
    expect(
      await store.recoveryIds(w4Scope, null, null, expenseEvidenceRetention),
      [w4Id],
    );
    expect(
      await store.recoveryIds(
        w4Scope,
        w4Id,
        w4Revision,
        expenseEvidenceRetention,
      ),
      isEmpty,
    );
    expect(
      await store.read(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceRetention,
      ),
      null,
    );
  });
  test(
    'unrelated confirmation cannot clear original pending receipt',
    () async {
      await store.save(w4Scope, payload(), 0);
      final pending = await store.seal(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      final row = {
        'request_id': w4Command,
        'command_id': w4Command,
        'correlation_id': w4Command,
        'warnings': [],
        'entity': {
          'tenant_id': w4Scope.tenantId,
          'legal_entity_id': w4Scope.legalEntityId,
          'branch_id': w4Scope.branchId,
          'id': w4Id,
          'version': 1,
          'digest': 'a' * 64,
          'record_version': 1,
          'status': 'reserved',
          'project_id': w4Id,
          'expense_id': w4Revision,
          'action': 'reserve',
        },
      };
      await expectLater(
        store.acknowledge(
          w4Scope,
          w4Id,
          w4Revision,
          w4Id,
          expenseEvidenceManage,
          ExpenseEvidenceConfirmation.fromJson(row),
        ),
        throwsFormatException,
      );
      expect(
        (await store.receipt(
          w4Scope,
          w4Id,
          w4Revision,
          w4Id,
          expenseEvidenceManage,
        ))!['command_id'],
        pending.envelope.commandId,
      );
      await expectLater(
        store.discard(w4Scope, w4Id, w4Revision, w4Id, expenseEvidenceManage),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test(
    'definite version conflict retains comparison body and its original expiry',
    () async {
      await store.save(w4Scope, payload(), 0);
      await store.seal(w4Scope, w4Id, w4Revision, w4Id, expenseEvidenceManage);
      await store.releaseRejected(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
        const DomainError(code: 'VERSION_CONFLICT', message: 'Changed'),
      );
      final draft = await store.read(
        w4Scope,
        w4Id,
        w4Revision,
        w4Id,
        expenseEvidenceManage,
      );
      expect(draft!.pending, null);
      expect(draft.payload, payload());
      expect(draft.expiresAt, DateTime.utc(2026, 10, 6));
      expect(
        await store.receipt(
          w4Scope,
          w4Id,
          w4Revision,
          w4Id,
          expenseEvidenceManage,
        ),
        null,
      );
    },
  );
}
