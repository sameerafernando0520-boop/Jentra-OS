import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
void main() {
  test(
    'encrypted scenario reopens under its actor and rechecks revocation around decryption',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: Keys()),
      );
      final scope = ProcessMetricScope(tenantId: id(1), legalEntityId: id(2));
      var allowed = true;
      Future<void> authorize(ProcessMetricScope s, String actor) async {
        if (!allowed) throw StateError('revoked');
      }

      final store = CashScenarioStore(drafts, authorize);
      final r = CashScenarioRevision(
        id: id(3),
        scope: scope,
        sourceHash: 'a' * 64,
        horizonStart: '2026-10-01',
        horizonEnd: '2026-11-01',
        recordedThrough: '2026-10-01T00:00:00Z',
        overrides: {},
      );
      await store.save(id(4), r);
      expect(
        (await CashScenarioStore(
          drafts,
          authorize,
        ).restore(scope, id(4)))!.toJson(),
        r.toJson(),
      );
      expect(await store.restore(scope, id(5)), null);
      final rows = await db.select(db.encryptedDrafts).get();
      expect(
        String.fromCharCodes(rows.single.encryptedPayload),
        isNot(contains('sourceHash')),
      );
      allowed = false;
      await expectLater(store.restore(scope, id(4)), throwsStateError);
    },
  );
}
