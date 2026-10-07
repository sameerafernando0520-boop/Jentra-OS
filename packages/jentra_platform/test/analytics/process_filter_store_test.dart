import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  final scope = ProcessMetricScope(
    tenantId: '10000000-0000-0000-0000-000000000001',
    legalEntityId: '20000000-0000-0000-0000-000000000001',
    branchId: '30000000-0000-0000-0000-000000000001',
  );
  final filter = ProcessMetricFilter(
    windowStart: '2026-09-01T00:00:00Z',
    windowEnd: '2026-10-01T00:00:00Z',
    asOf: '2026-10-01T00:00:00Z',
    recordedThrough: '2026-10-02T00:00:00Z',
  );
  const actor = '40000000-0000-0000-0000-000000000001';
  test(
    'recreated encrypted store restores filters, binds actor and retains no evidence rows',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: Keys()),
      );
      final store = ProcessFilterStore(drafts, (s, actorId) async {});
      await store.save(scope, actor, filter);
      final restarted = ProcessFilterStore(drafts, (s, actorId) async {});
      expect(
        (await restarted.restore(scope, actor))!.toJson(),
        filter.toJson(),
      );
      expect(
        await restarted.restore(scope, '40000000-0000-0000-0000-000000000002'),
        isNull,
      );
      final rows = await db.select(db.encryptedDrafts).get();
      expect(rows, hasLength(1));
      expect(
        String.fromCharCodes(rows.single.encryptedPayload),
        isNot(contains('windowStart')),
      );
    },
  );
  test('revocation prevents decryption of a persisted filter', () async {
    final db = JentraLocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: Keys()));
    await ProcessFilterStore(
      drafts,
      (s, actorId) async {},
    ).save(scope, actor, filter);
    var reads = 0;
    final denied = ProcessFilterStore(drafts, (s, actorId) async {
      reads++;
      throw StateError('revoked');
    });
    await expectLater(denied.restore(scope, actor), throwsStateError);
    expect(reads, 1);
  });
}
