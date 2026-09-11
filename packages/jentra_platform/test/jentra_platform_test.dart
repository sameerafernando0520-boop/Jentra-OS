import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class _MemoryKeyStore implements SecretKeyStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Simulated credential write failure');
    values[key] = value;
  }
}

void main() {
  test('runtime config is safe when backend is absent — AC-1', () {
    const config = RuntimeConfig(
      environment: 'development',
      supabaseUrl: '',
      supabasePublishableKey: '',
    );
    expect(config.isSupabaseConfigured, isFalse);
  });

  test(
    'draft payloads are authenticated and encrypted — FR-12 / AC-5',
    () async {
      final cipher = DraftCipher(keyStore: _MemoryKeyStore());
      const source = '{"supplier":"Ceylon Parts","amount":"2500.00"}';

      final encrypted = await cipher.encrypt(source);

      expect(
        utf8.decode(encrypted, allowMalformed: true),
        isNot(contains(source)),
      );
      expect(await cipher.decrypt(encrypted), source);
    },
  );

  test('tampered draft payload is rejected — NFR-4', () async {
    final cipher = DraftCipher(keyStore: _MemoryKeyStore());
    final encrypted = await cipher.encrypt('{"draft":true}');
    encrypted[encrypted.length - 1] ^= 1;

    expect(
      () => cipher.decrypt(encrypted),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('simultaneous first saves use one durable encryption key', () async {
    final keys = _MemoryKeyStore();
    final cipher = DraftCipher(keyStore: keys);
    final encrypted = await Future.wait([
      for (var i = 0; i < 8; i++) cipher.encrypt('offline draft $i'),
    ]);
    final restarted = DraftCipher(keyStore: keys);
    expect(await Future.wait(encrypted.map(restarted.decrypt)), [
      for (var i = 0; i < 8; i++) 'offline draft $i',
    ]);
  });

  test(
    'credential failure is retryable without retaining an unsaved key',
    () async {
      final keys = _MemoryKeyStore()..failWrites = true;
      final cipher = DraftCipher(keyStore: keys);
      await expectLater(cipher.encrypt('not saved'), throwsStateError);
      expect(keys.values, isEmpty);
      keys.failWrites = false;
      final encrypted = await cipher.encrypt('saved after retry');
      expect(
        await DraftCipher(keyStore: keys).decrypt(encrypted),
        'saved after retry',
      );
    },
  );

  test(
    'partial encrypted drafts survive restart and retain conflict versions — AC-217',
    () async {
      final database = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final cipher = DraftCipher(keyStore: _MemoryKeyStore());
      final firstSession = EncryptedDraftRepository(database, cipher);

      await firstSession.save(
        id: 'account-draft-1',
        tenantId: 'tenant-a',
        entityType: BusinessSetupResource.accounts.name,
        payload: const {'code': '1010', 'name': ''},
        localVersion: 2,
        serverVersion: 7,
      );

      final restartedSession = EncryptedDraftRepository(database, cipher);
      final restored = await restartedSession.find('account-draft-1');
      expect(restored?.payload, const {'code': '1010', 'name': ''});
      expect(restored?.syncState, DraftSyncState.localOnly);

      await restartedSession.markConflict(
        id: 'account-draft-1',
        serverVersion: 9,
      );
      final conflicted = await restartedSession.find('account-draft-1');
      expect(conflicted?.localVersion, 2);
      expect(conflicted?.serverVersion, 9);
      expect(conflicted?.syncState, DraftSyncState.conflicted);
    },
  );

  test(
    'reference cache is tenant-scoped, encrypted, and replaceable — AC-217',
    () async {
      final database = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = EncryptedReferenceCacheRepository(
        database,
        DraftCipher(keyStore: _MemoryKeyStore()),
      );
      final timestamp = DateTime.utc(2026, 9);
      final source = SetupRecord(
        resource: BusinessSetupResource.accounts,
        id: 'account-1000',
        tenantId: 'tenant-a',
        legalEntityId: 'entity-a',
        code: '1000',
        name: 'Cash and cash equivalents',
        status: 'active',
        version: 3,
        createdAt: timestamp,
        updatedAt: timestamp,
        fields: const {'account_type': 'asset'},
      );

      await repository.replaceResource(
        tenantId: 'tenant-a',
        resource: BusinessSetupResource.accounts,
        records: [source],
      );

      final raw = await database.select(database.referenceCacheEntries).get();
      expect(raw, hasLength(1));
      expect(
        utf8.decode(raw.single.encryptedPayload, allowMalformed: true),
        isNot(contains('Cash and cash equivalents')),
      );
      expect(
        await repository.readResource(
          tenantId: 'tenant-b',
          resource: BusinessSetupResource.accounts,
        ),
        isEmpty,
      );
      final cached = await repository.readResource(
        tenantId: 'tenant-a',
        resource: BusinessSetupResource.accounts,
        legalEntityId: 'entity-a',
      );
      expect(cached.single.code, '1000');
      expect(cached.single.version, 3);

      await repository.replaceResource(
        tenantId: 'tenant-a',
        resource: BusinessSetupResource.accounts,
        records: const [],
      );
      expect(
        await repository.readResource(
          tenantId: 'tenant-a',
          resource: BusinessSetupResource.accounts,
        ),
        isEmpty,
      );
    },
  );

  test('reference cache rejects a cross-tenant record — NFR-210', () async {
    final database = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = EncryptedReferenceCacheRepository(
      database,
      DraftCipher(keyStore: _MemoryKeyStore()),
    );
    final timestamp = DateTime.utc(2026, 9);

    expect(
      () => repository.replaceResource(
        tenantId: 'tenant-a',
        resource: BusinessSetupResource.units,
        records: [
          SetupRecord(
            resource: BusinessSetupResource.units,
            id: 'unit-1',
            tenantId: 'tenant-b',
            code: 'EA',
            name: 'Each',
            status: 'active',
            version: 1,
            createdAt: timestamp,
            updatedAt: timestamp,
            fields: const {},
          ),
        ],
      ),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'CACHE_TENANT_MISMATCH',
        ),
      ),
    );
  });
}
