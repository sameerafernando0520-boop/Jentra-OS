import 'dart:io';
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

Map<String, Object?> profile() => {
  'action': 'profile_save',
  'id': w4Id,
  'employee_id': w4Id,
  'revision_id': w4Revision,
  'body': {
    for (final field in hrContactFields)
      field: field == 'personal_phone' ? 'SYNTHETIC_PRIVATE_PHONE' : null,
  },
  'reason': 'Synthetic reason',
};
void main() {
  test(
    'recovery index uses only metadata and excludes other actors and capabilities',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory()), keys = _Keys();
      var now = DateTime.utc(2026, 9, 28);
      final store = PrivateHrDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
        (s, e, c) async {},
        clock: () => now,
      );
      try {
        final request = await store.prepare(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          profile(),
          0,
        );
        final before = keys.reads;
        keys.forbid = true;
        final items = await store.recovery(w4Scope, {
          'people.hr.private.manage',
        });
        expect(items.single.aggregateId, w4Id);
        expect(items.single.expiresAt, isNotNull);
        expect(keys.reads, before);
        expect(await store.recovery(w4Scope, {'people.self.view'}), isEmpty);
        final other = TenantContext(
          tenantId: w4Scope.tenantId,
          legalEntityId: w4Scope.legalEntityId,
          branchId: w4Scope.branchId,
          actorId: w4Id,
        );
        expect(
          await store.recovery(other, {'people.hr.private.manage'}),
          isEmpty,
        );
        now = now.add(const Duration(hours: 24));
        final expired = await store.recovery(w4Scope, {
          'people.hr.private.manage',
        });
        expect(expired.single.expiresAt, isNull);
        expect(keys.reads, before);
        keys.forbid = false;
        expect(
          (await store.expiredReceipt(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
          ))!['command_id'],
          request.envelope.commandId,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'encrypted private request and minimal receipt survive a SQLite restart exactly',
    () async {
      final scratch = await Directory.systemTemp.createTemp(
        'jentra-w4-private-',
      );
      final file = File(
        '${scratch.path}${Platform.pathSeparator}private.sqlite',
      );
      final keys = _Keys();
      var db = JentraLocalDatabase(NativeDatabase(file));
      Future<void> auth(
        TenantContext scope,
        String? employee,
        String cap,
      ) async {}
      try {
        var store = PrivateHrDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          auth,
        );
        final pending = await store.prepare(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          profile(),
          0,
        );
        await db.close();
        expect(
          String.fromCharCodes(file.readAsBytesSync()),
          isNot(contains('SYNTHETIC_PRIVATE_PHONE')),
        );
        db = JentraLocalDatabase(NativeDatabase(file));
        store = PrivateHrDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          auth,
        );
        expect(
          (await store.load(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
          ))!.pending!.toJson(),
          pending.toJson(),
        );
        expect(
          (await store.expiredReceipt(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
          ))!.keys,
          unorderedEquals([
            'command_id',
            'action',
            'id',
            'employee_id',
            'expected_version',
          ]),
        );
        await expectLater(
          store.discard(w4Scope, w4Id, w4Id, 'profile_save'),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
          ),
        );
      } finally {
        await db.close();
        // This is a task-created temp directory; no shared acceptance path is touched.
        await file.delete();
        for (final suffix in ['-wal', '-shm']) {
          final auxiliary = File(file.path + suffix);
          if (await auxiliary.exists()) await auxiliary.delete();
        }
        await scratch.delete();
      }
    },
  );
  test(
    'fixed TTL does not extend on edits and expires before cipher-key access',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final keys = _Keys();
      var now = DateTime.utc(2026, 9, 28);
      final repo = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
      Future<void> auth(TenantContext s, String? e, String c) async {}
      try {
        var store = PrivateHrDraftStore(repo, auth, clock: () => now);
        await store.save(w4Scope, w4Id, w4Id, 'profile_save', profile(), 0);
        final first = (await store.load(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
        ))!.expiresAt;
        now = now.add(const Duration(hours: 23));
        await store.save(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          profile()..['reason'] = 'Edited synthetic reason',
          0,
        );
        expect(
          (await store.load(w4Scope, w4Id, w4Id, 'profile_save'))!.expiresAt,
          first,
        );
        now = now.add(const Duration(hours: 1));
        keys.forbid = true;
        final before = keys.reads;
        store = PrivateHrDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          auth,
          clock: () => now,
        );
        expect(await store.load(w4Scope, w4Id, w4Id, 'profile_save'), isNull);
        expect(keys.reads, before);
        expect(
          await repo.pageIds(
            tenantId: w4Scope.tenantId,
            entityType: 'private_hr',
          ),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'current access precedes private decrypt and actor/aggregate namespaces differ',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final keys = _Keys();
      var permitted = true;
      Future<void> auth(TenantContext s, String? e, String c) async {
        if (!permitted || s.actorId != w4Scope.actorId) {
          throw const DomainError(
            code: 'PERMISSION_DENIED',
            message: 'Revoked',
          );
        }
      }

      try {
        var store = PrivateHrDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          auth,
        );
        await store.save(w4Scope, w4Id, w4Id, 'profile_save', profile(), 0);
        keys.forbid = true;
        permitted = false;
        final before = keys.reads;
        store = PrivateHrDraftStore(
          EncryptedDraftRepository(db, DraftCipher(keyStore: keys)),
          auth,
        );
        await expectLater(
          store.load(w4Scope, w4Id, w4Id, 'profile_save'),
          throwsA(isA<DomainError>()),
        );
        expect(keys.reads, before);
        permitted = true;
        expect(
          await store.load(w4Scope, w4Revision, w4Revision, 'profile_save'),
          isNull,
        );
        await expectLater(
          store.load(
            w4Scope.copyWith(actorId: w4Revision),
            w4Id,
            w4Id,
            'profile_save',
          ),
          throwsA(isA<DomainError>()),
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'uncertainty preserves exact envelope; conflict requires explicit comparison',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      final store = PrivateHrDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
        (s, e, c) async {},
      );
      try {
        final original = profile();
        final preparing = store.prepare(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          original,
          0,
        );
        (original['body'] as Map)['personal_phone'] = 'Later unsaved edit';
        final pending = await preparing;
        expect(pending.envelope.payload['body'], profile()['body']);
        await store.failure(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          pending.envelope.commandId,
          const DomainError(code: 'UNCERTAIN_RESULT', message: 'Lost response'),
        );
        expect(
          (await store.load(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
          ))!.pending!.toJson(),
          pending.toJson(),
        );
        await store.failure(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          pending.envelope.commandId,
          const DomainError(code: 'VERSION_CONFLICT', message: 'Stale'),
        );
        await expectLater(
          store.prepare(w4Scope, w4Id, w4Id, 'profile_save', profile(), 0),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'VERSION_CONFLICT',
            ),
          ),
        );
        await store.save(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          profile(),
          2,
          compared: true,
        );
        expect(
          (await store.prepare(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
            profile(),
            2,
          )).envelope.expectedEntityVersion,
          2,
        );
      } finally {
        await db.close();
      }
    },
  );
  test(
    'expired private text leaves minimal uncertain receipt and rejects silent replacement',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      var now = DateTime.utc(2026, 9, 28);
      final store = PrivateHrDraftStore(
        EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
        (s, e, c) async {},
        clock: () => now,
      );
      try {
        final pending = await store.prepare(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          profile(),
          0,
        );
        now = now.add(const Duration(hours: 24));
        expect(await store.load(w4Scope, w4Id, w4Id, 'profile_save'), isNull);
        expect(
          (await store.expiredReceipt(
            w4Scope,
            w4Id,
            w4Id,
            'profile_save',
          ))!['command_id'],
          pending.envelope.commandId,
        );
        await expectLater(
          store.prepare(w4Scope, w4Id, w4Id, 'profile_save', profile(), 0),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'PRIVATE_DRAFT_EXPIRED',
            ),
          ),
        );
        await store.complete(
          w4Scope,
          w4Id,
          w4Id,
          'profile_save',
          pending.envelope.commandId,
        );
        expect(
          await store.expiredReceipt(w4Scope, w4Id, w4Id, 'profile_save'),
          isNull,
        );
      } finally {
        await db.close();
      }
    },
  );
  test('document drafts reject bytes/paths/URLs before encryption', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    final store = PrivateHrDraftStore(
      EncryptedDraftRepository(db, DraftCipher(keyStore: _Keys())),
      (s, e, c) async {},
    );
    try {
      for (final key in ['object_path', 'signed_url', 'bytes']) {
        expect(
          () => store.save(w4Scope, w4Id, w4Revision, 'document_complete', {
            'action': 'document_complete',
            'id': w4Revision,
            'employee_id': w4Id,
            key: 'private',
          }, 1),
          throwsFormatException,
        );
      }
    } finally {
      await db.close();
    }
  });
}
