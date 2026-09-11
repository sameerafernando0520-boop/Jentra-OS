import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_stock_opening_platform.dart';

class MemoryKeys implements SecretKeyStore {
  final keys = <String, String>{};
  @override
  Future<String?> read(String key) async => keys[key];
  @override
  Future<void> write(String key, String value) async {
    keys[key] = value;
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase db;
  late EncryptedDraftRepository encrypted;
  late StockOpeningDraftStore store;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(
      db,
      DraftCipher(keyStore: MemoryKeys()),
    );
    store = StockOpeningDraftStore(encrypted);
  });
  tearDown(() => db.close());
  test('recovery survives a fresh store and retains exact envelope', () async {
    await store.save(scope, 'id', {'amount': '90071992547409.123456'}, 3);
    final first = await store.prepare(scope, 'id', 'post_stock_opening', {
      'document_id': 'id',
    }, 3);
    final fresh = StockOpeningDraftStore(encrypted);
    final recovered = await fresh.load(scope, 'id');
    expect(
      recovered!.envelope.toJson((p) => p),
      first.envelope.toJson((p) => p),
    );
    expect(recovered.form['amount'], '90071992547409.123456');
  });
  test('uncertain command cannot be edited or discarded', () async {
    await store.prepare(scope, 'id', 'post_stock_opening', {
      'document_id': 'id',
    }, 3);
    await expectLater(
      store.save(scope, 'id', {}, 3),
      throwsA(isA<StockOpeningFailure>()),
    );
    await expectLater(
      store.discard(scope, 'id'),
      throwsA(isA<StockOpeningFailure>()),
    );
    await expectLater(
      store.prepare(scope, 'id', 'post_stock_opening', {
        'document_id': 'different',
      }, 3),
      throwsA(isA<StockOpeningFailure>()),
    );
  });
  test('identical concurrent prepares produce one command', () async {
    final values = await Future.wait([
      for (var i = 0; i < 5; i++)
        StockOpeningDraftStore(
          encrypted,
        ).prepare(scope, 'id', 'post_stock_opening', {'document_id': 'id'}, 2),
    ]);
    expect(values.map((v) => v.envelope.commandId).toSet(), hasLength(1));
  });
  test(
    'unknown failure retains envelope while known rollback clears it',
    () async {
      final value = await store.prepare(scope, 'id', 'post_stock_opening', {
        'document_id': 'id',
      }, 2);
      await store.failure(
        scope,
        'id',
        value.envelope.commandId,
        const StockOpeningFailure('TRANSPORT', 'Interrupted'),
      );
      expect((await store.load(scope, 'id'))!.pending, true);
      await store.failure(
        scope,
        'id',
        value.envelope.commandId,
        const StockOpeningFailure(
          'VERSION_CONFLICT',
          'Changed',
          definite: true,
        ),
      );
      final failed = (await store.load(scope, 'id'))!;
      expect(failed.pending, false);
      expect(failed.error, 'VERSION_CONFLICT');
      await expectLater(
        store.prepare(scope, 'id', 'post_stock_opening', {
          'document_id': 'id',
        }, 3),
        throwsA(isA<StockOpeningFailure>()),
      );
    },
  );
  test('scope partition includes actor, entity and branch', () async {
    await store.save(scope, 'id', {}, null);
    for (final other in [
      scope.copyWith(actorId: 'other'),
      scope.copyWith(branchId: 'other'),
      scope.copyWith(legalEntityId: 'other'),
    ]) {
      expect(await store.load(other, 'id'), isNull);
      expect((await store.recovery(other)).items, isEmpty);
    }
    expect((await store.recovery(scope)).items, ['id']);
  });
  test('completion requires the exact pending command identity', () async {
    final value = await store.prepare(scope, 'id', 'post_stock_opening', {}, 1);
    await expectLater(
      store.complete(scope, 'id', 'wrong'),
      throwsA(isA<StockOpeningFailure>()),
    );
    await store.complete(scope, 'id', value.envelope.commandId);
    expect(await store.load(scope, 'id'), isNull);
  });
}
