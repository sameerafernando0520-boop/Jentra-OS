import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';

final class Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String k) async => values[k];
  @override
  Future<void> write(String k, String v) async {
    values[k] = v;
  }
}

const actor = '40000000-0000-0000-0000-000000000001';
final scope = ProcessMetricScope(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '20000000-0000-0000-0000-000000000001',
);
final envelope = <String, Object?>{
  'commandId': '50000000-0000-0000-0000-000000000001',
  'idempotencyKey': '60000000-0000-0000-0000-000000000001',
  'clientTimestamp': '2026-10-06T00:00:00Z',
  'action': 'freeze',
  'payload': {'horizonStart': '2026-10-01', 'horizonEnd': '2026-11-01'},
};
void main() {
  test(
    'closed database reopens encrypted original command and isolates namespaces',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'jentra-w5-recovery-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final file = File('${temp.path}/owned-test.sqlite'), keys = Keys();
      Future<void> authorize(ProcessMetricScope s, String a) async {
        if (a != actor) throw StateError('wrong actor');
      }

      var db = JentraLocalDatabase(NativeDatabase(file));
      var drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
      await Wave5CommandStore(
        drafts,
        authorize,
        namespace: 'pipeline',
      ).save(scope, actor, envelope);
      final encrypted =
          (await db.select(db.encryptedDrafts).get()).single.encryptedPayload;
      expect(
        String.fromCharCodes(encrypted),
        isNot(contains(envelope['commandId'])),
      );
      await db.close();
      db = JentraLocalDatabase(NativeDatabase(file));
      addTearDown(db.close);
      drafts = EncryptedDraftRepository(db, DraftCipher(keyStore: keys));
      final store = Wave5CommandStore(drafts, authorize, namespace: 'pipeline');
      expect(await store.restore(scope, actor), envelope);
      expect(
        await Wave5CommandStore(
          drafts,
          authorize,
          namespace: 'proposal',
        ).restore(scope, actor),
        isNull,
      );
      await expectLater(
        store.restore(scope, '40000000-0000-0000-0000-000000000002'),
        throwsStateError,
      );
      await store.remove(scope, actor);
      expect(await store.restore(scope, actor), isNull);
    },
  );
  test(
    'revocation before and after decryption rejects recovered commands',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: Keys()),
      );
      final store = Wave5CommandStore(
        drafts,
        (_, _) async {},
        namespace: 'pipeline',
      );
      await store.save(scope, actor, envelope);
      var reads = 0;
      final revoked = Wave5CommandStore(drafts, (_, _) async {
        if (++reads == 2) throw StateError('revoked');
      }, namespace: 'pipeline');
      await expectLater(revoked.restore(scope, actor), throwsStateError);
      expect(reads, 2);
    },
  );
  test(
    'unsupported, executable and malformed recovery parameters never persist',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final drafts = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: Keys()),
      );
      final store = Wave5CommandStore(
        drafts,
        (_, _) async {},
        namespace: 'pipeline',
      );
      for (final bad in [
        {...envelope, 'secret': 'forbidden'},
        {...envelope, 'action': 'sql'},
        {
          ...envelope,
          'payload': {'horizonStart': '2026-11-01', 'horizonEnd': '2026-10-01'},
        },
        {...envelope, 'commandId': 'invalid'},
      ]) {
        await expectLater(store.save(scope, actor, bad), throwsFormatException);
      }
      final billing = Wave5CommandStore(
        drafts,
        (_, _) async {},
        namespace: 'subscription',
      );
      billing.validate({
        ...envelope,
        'action': 'schedule',
        'payload': {
          'expectedVersion': '9007199254740993',
          'plan': 'starter',
          'seats': '2',
          'trialStart': '2026-10-06T00:00:00Z',
          'trialEnd': '2026-10-07T00:00:00Z',
        },
      });
      expect(
        () => billing.validate({
          ...envelope,
          'action': 'schedule',
          'payload': {
            'expectedVersion': '1',
            'plan': 'starter',
            'seats': '10001',
            'trialStart': '2026-10-06T00:00:00Z',
            'trialEnd': '2026-10-07T00:00:00Z',
          },
        }),
        throwsFormatException,
      );
      expect(await db.select(db.encryptedDrafts).get(), isEmpty);
    },
  );
}
