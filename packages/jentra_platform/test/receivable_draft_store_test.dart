import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';

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
  late ReceivableDraftStore store;
  setUp(() {
    db = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(
      db,
      DraftCipher(keyStore: MemoryKeys()),
    );
    store = ReceivableDraftStore(encrypted);
  });
  tearDown(() => db.close());
  test('recovery survives a fresh store and retains exact envelope', () async {
    await store.save(scope, 'sales_invoice:id', {
      'amount': '90071992547409.123456',
    }, 3);
    final first = await store.prepare(
      scope,
      'sales_invoice:id',
      'post_sales_invoice',
      {'document_id': 'id'},
      3,
    );
    final fresh = ReceivableDraftStore(encrypted);
    final recovered = await fresh.load(scope, 'sales_invoice:id');
    expect(
      recovered!.envelope.toJson((p) => p),
      first.envelope.toJson((p) => p),
    );
    expect(recovered.form['amount'], '90071992547409.123456');
  });
  test('uncertain command cannot be edited or discarded', () async {
    await store.prepare(scope, 'sales_invoice:id', 'post_sales_invoice', {
      'document_id': 'id',
    }, 3);
    await expectLater(
      store.save(scope, 'sales_invoice:id', {}, 3),
      throwsA(isA<ReceivableFailure>()),
    );
    await expectLater(
      store.discard(scope, 'sales_invoice:id'),
      throwsA(isA<ReceivableFailure>()),
    );
    await expectLater(
      store.prepare(scope, 'sales_invoice:id', 'post_sales_invoice', {
        'document_id': 'different',
      }, 3),
      throwsA(isA<ReceivableFailure>()),
    );
  });
  test('identical concurrent prepares produce one command', () async {
    final values = await Future.wait([
      for (var i = 0; i < 5; i++)
        ReceivableDraftStore(encrypted).prepare(
          scope,
          'delivery:id',
          'post_delivery',
          {'document_id': 'id'},
          2,
        ),
    ]);
    expect(values.map((v) => v.envelope.commandId).toSet(), hasLength(1));
  });
  test(
    'unknown failure retains envelope while known rollback clears it',
    () async {
      final value = await store.prepare(scope, 'delivery:id', 'post_delivery', {
        'document_id': 'id',
      }, 2);
      await store.failure(
        scope,
        'delivery:id',
        value.envelope.commandId,
        const ReceivableFailure('TRANSPORT', 'Interrupted'),
      );
      expect((await store.load(scope, 'delivery:id'))!.pending, true);
      await store.failure(
        scope,
        'delivery:id',
        value.envelope.commandId,
        const ReceivableFailure('VERSION_CONFLICT', 'Changed', definite: true),
      );
      final failed = (await store.load(scope, 'delivery:id'))!;
      expect(failed.pending, false);
      expect(failed.error, 'VERSION_CONFLICT');
      await expectLater(
        store.prepare(scope, 'delivery:id', 'post_delivery', {
          'document_id': 'id',
        }, 3),
        throwsA(isA<ReceivableFailure>()),
      );
    },
  );
  test('scope partition includes actor, entity and branch', () async {
    await store.save(scope, 'delivery:id', {}, null);
    for (final other in [
      scope.copyWith(actorId: 'other'),
      scope.copyWith(branchId: 'other'),
      scope.copyWith(legalEntityId: 'other'),
    ]) {
      expect(await store.load(other, 'delivery:id'), isNull);
      expect((await store.recovery(other)).items, isEmpty);
    }
    expect((await store.recovery(scope)).items, ['delivery:id']);
  });
  test('completion requires the exact pending command identity', () async {
    final value = await store.prepare(
      scope,
      'delivery:id',
      'post_delivery',
      {},
      1,
    );
    await expectLater(
      store.complete(scope, 'delivery:id', 'wrong'),
      throwsA(isA<ReceivableFailure>()),
    );
    await store.complete(scope, 'delivery:id', value.envelope.commandId);
    expect(await store.load(scope, 'delivery:id'), isNull);
  });
}
