import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_platform/jentra_payroll_platform.dart';
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

class _Server implements PayrollCorrectionRepository {
  Map<String, Object?>? result;
  String? capability, command;
  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String commandId,
    String cap,
  ) async {
    command = commandId;
    capability = cap;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _kind = PayrollCorrectionCommandKind.correction;
Map<String, Object?> _form() => {
  'action': 'prepare',
  'id': w4Id,
  'original_calculation_id': w4Revision,
  'posting_date': '2026-10-02',
  'reason': 'SYNTHETIC_PRIVATE_PAYROLL_REASON',
  'replacements': [
    {
      'seal_id': w4Id,
      'before_revision_id': w4Revision,
      'expected_version': 1,
      'paid_seconds': 1800,
    },
  ],
};
Map<String, Object?> _confirmation(String command) => {
  'command_id': command,
  'entity': {
    'id': w4Id,
    'version': 1,
    'tenant_id': w4Scope.tenantId,
    'legal_entity_id': w4Scope.legalEntityId,
    'branch_id': w4Scope.branchId,
  },
};
void main() {
  late JentraLocalDatabase db;
  late _Keys keys;
  late SensitivePayrollCorrectionDraftStore store;
  late DateTime now;
  final authorized = <String>[];
  String? denied;
  Completer<void>? gate;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    keys = _Keys();
    now = DateTime.utc(2026, 9, 30);
    denied = null;
    gate = null;
    authorized.clear();
    store = SensitivePayrollCorrectionDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
      (scope, cap) async {
        authorized.add(cap);
        if (gate != null) {
          final wait = gate!;
          gate = null;
          await wait.future;
        }
        if (denied == cap) {
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
    'fixed expiry removes private body before decrypt, retaining minimal encrypted receipt',
    () async {
      final pending = await store.prepare(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
      );
      final before = keys.reads;
      keys.forbid = true;
      expect((await store.recovery(w4Scope)).single.expired, isFalse);
      expect(keys.reads, before);
      now = now.add(const Duration(hours: 24));
      expect((await store.recovery(w4Scope)).single.expired, isTrue);
      expect(await store.load(w4Scope, _kind, w4Id), isNull);
      expect(keys.reads, before);
      keys.forbid = false;
      final stub = await store.receipt(w4Scope, _kind, w4Id);
      expect(stub!['command_id'], pending.envelope.commandId);
      expect(
        stub.keys,
        unorderedEquals([
          'command_id',
          'kind',
          'id',
          'capability',
          'expected_version',
        ]),
      );
      final rows = await db.select(db.encryptedDrafts).get();
      expect(rows.single.entityType, 'sensitive_payroll_correction_receipt');
      expect(rows.single.id, isNot(contains('SYNTHETIC_PRIVATE')));
    },
  );
  test(
    'an uncertain request reuses the exact envelope and cannot be edited, discarded or bypassed with another action',
    () async {
      final first = await store.prepare(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
      );
      await store.failure(
        w4Scope,
        _kind,
        w4Id,
        first.envelope.commandId,
        const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Retry',
          retryable: true,
        ),
      );
      expect(
        (await store.prepare(
          w4Scope,
          _kind,
          w4Id,
          'prepare',
          _form(),
          0,
        )).toJson(),
        first.toJson(),
      );
      for (final attempt in [
        () => store.save(
          w4Scope,
          _kind,
          w4Id,
          'prepare',
          _form()..['reason'] = 'Changed',
          0,
        ),
        () => store.prepare(w4Scope, _kind, w4Id, 'post', {
          'action': 'post',
          'id': w4Id,

          'digest': 'a' * 64,
          'reason': 'Post',
        }, 1),
        () => store.discard(w4Scope, _kind, w4Id),
      ]) {
        await expectLater(
          attempt(),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
          ),
        );
      }
    },
  );
  test(
    'source changes require comparison and do not extend private expiry',
    () async {
      final first = await store.prepare(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
      );
      final expiry = (await store.load(w4Scope, _kind, w4Id))!.expiresAt;
      await store.failure(
        w4Scope,
        _kind,
        w4Id,
        first.envelope.commandId,
        const DomainError(code: 'VERSION_CONFLICT', message: 'Compare'),
      );
      expect(await store.receipt(w4Scope, _kind, w4Id), isNull);
      await expectLater(
        store.save(w4Scope, _kind, w4Id, 'prepare', _form(), 0),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
        ),
      );
      now = now.add(const Duration(hours: 8));
      await store.save(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
        compared: true,
      );
      expect((await store.load(w4Scope, _kind, w4Id))!.expiresAt, expiry);
    },
  );
  test(
    'original action permission is checked before decryption and scope prevents discovery',
    () async {
      await store.save(w4Scope, _kind, w4Id, 'prepare', _form(), 0);
      denied = 'people.payroll.correction.prepare';
      final before = keys.reads;
      await expectLater(
        store.load(w4Scope, _kind, w4Id),
        throwsA(isA<DomainError>()),
      );
      expect(keys.reads, before);
      final other = TenantContext(
        tenantId: w4Scope.tenantId,
        legalEntityId: w4Scope.legalEntityId,
        branchId: w4Scope.branchId,
        actorId: w4Id,
      );
      expect(await store.recovery(other), isEmpty);
    },
  );
  test(
    'posting recovery checks posting permission, never substitutes directory or payroll view',
    () async {
      await store.prepare(w4Scope, _kind, w4Id, 'post', {
        'action': 'post',
        'id': w4Id,

        'digest': 'a' * 64,
        'reason': 'Synthetic post',
      }, 3);
      authorized.clear();
      await store.load(w4Scope, _kind, w4Id);
      expect(authorized, everyElement('people.payroll.post'));
      denied = 'people.payroll.post';
      final before = keys.reads;
      await expectLater(
        store.receipt(w4Scope, _kind, w4Id),
        throwsA(isA<DomainError>()),
      );
      expect(keys.reads, before);
    },
  );
  test('prepare snapshots before authorization awaits', () async {
    final input = _form(), wait = Completer<void>();
    gate = wait;
    final future = store.prepare(w4Scope, _kind, w4Id, 'prepare', input, 0);
    input['reason'] = 'Mutated';
    (input['replacements'] as List).clear();
    wait.complete();
    final sealed = await future;
    expect(
      sealed.envelope.payload['reason'],
      'SYNTHETIC_PRIVATE_PAYROLL_REASON',
    );
    expect(sealed.envelope.payload['replacements'], hasLength(1));
  });
  test(
    'expired uncertainty remains until exact remote identity, version and command match',
    () async {
      final first = await store.prepare(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
      );
      now = now.add(const Duration(hours: 24));
      await store.recovery(w4Scope);
      final server = _Server();
      expect(
        await store.reconcileExpired(w4Scope, _kind, w4Id, server),
        isFalse,
      );
      await expectLater(
        store.prepare(w4Scope, _kind, w4Id, 'prepare', _form(), 0),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'PRIVATE_DRAFT_EXPIRED',
          ),
        ),
      );
      server.result = _confirmation(first.envelope.commandId)
        ..['entity'] = {
          ...(_confirmation(first.envelope.commandId)['entity']
              as Map<String, Object?>),
          'version': 2,
        };
      await expectLater(
        store.reconcileExpired(w4Scope, _kind, w4Id, server),
        throwsA(isA<DomainError>()),
      );
      expect(await store.receipt(w4Scope, _kind, w4Id), isNotNull);
      server.result = _confirmation(first.envelope.commandId);
      expect(
        await store.reconcileExpired(w4Scope, _kind, w4Id, server),
        isTrue,
      );
      expect(server.command, first.envelope.commandId);
      expect(server.capability, 'people.payroll.correction.prepare');
      expect(await store.recovery(w4Scope), isEmpty);
    },
  );
  test(
    'unknown transport failure retains uncertainty and public draft fields are allowlisted',
    () async {
      final first = await store.prepare(
        w4Scope,
        _kind,
        w4Id,
        'prepare',
        _form(),
        0,
      );
      await store.failure(
        w4Scope,
        _kind,
        w4Id,
        first.envelope.commandId,
        const DomainError(code: 'NETWORK_ERROR', message: 'Unknown'),
      );
      expect((await store.load(w4Scope, _kind, w4Id))!.pending, isNotNull);
      expect(
        () => store.save(
          w4Scope,
          _kind,
          w4Revision,
          'prepare',
          _form()
            ..['id'] = w4Revision
            ..['private_bank_account'] = 'Secret',
          0,
        ),
        throwsFormatException,
      );
    },
  );
}
