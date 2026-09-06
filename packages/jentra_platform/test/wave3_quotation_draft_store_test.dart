import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

class MemoryKeys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'a',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late JentraLocalDatabase database;
  late EncryptedDraftRepository encrypted;
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    encrypted = EncryptedDraftRepository(
      database,
      DraftCipher(keyStore: MemoryKeys()),
    );
  });
  tearDown(() => database.close());

  test(
    'AC-303 pending envelope survives restart and cannot be silently replaced',
    () async {
      final store = QuotationDraftStore(encrypted);
      await store.save(scope, 'new', {'notes': 'unsent'}, expectedVersion: 7);
      final first = await store.prepare(
        scope,
        'new',
        verb: 'save',
        payload: {'notes': 'unsent'},
        expectedVersion: 7,
      );
      final restarted = QuotationDraftStore(encrypted);
      final second = await restarted.prepare(
        scope,
        'new',
        verb: 'save',
        payload: {'notes': 'unsent'},
        expectedVersion: 7,
      );
      expect(second.toJson(), first.toJson());
      expect((await restarted.load(scope, 'new'))?.form, {'notes': 'unsent'});
      await expectLater(
        restarted.save(scope, 'new', {'notes': 'changed'}),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'COMMAND_PENDING'),
        ),
      );
      await expectLater(
        restarted.prepare(
          scope,
          'new',
          verb: 'save',
          payload: {'notes': 'changed'},
          expectedVersion: 7,
        ),
        throwsA(isA<DomainError>()),
      );
    },
  );

  test(
    'AC-303 local drafts are isolated by actor entity branch and tenant',
    () async {
      final store = QuotationDraftStore(encrypted);
      await store.save(scope, 'q', {'notes': 'private'});
      for (final other in [
        scope.copyWith(actorId: 'other'),
        scope.copyWith(tenantId: 'other'),
        scope.copyWith(legalEntityId: 'other'),
        scope.copyWith(branchId: 'other'),
      ]) {
        expect(await store.load(other, 'q'), isNull);
      }
    },
  );

  test(
    'AC-303 conflict preserves edits and requires explicit resolution',
    () async {
      final store = QuotationDraftStore(encrypted);
      await store.save(scope, 'q', {'notes': 'local'}, expectedVersion: 7);
      await store.prepare(
        scope,
        'q',
        verb: 'save',
        payload: {'notes': 'local'},
        expectedVersion: 7,
      );
      await store.recordFailure(
        scope,
        'q',
        const DomainError(code: 'VERSION_CONFLICT', message: 'stale'),
        commandId: (await store.load(scope, 'q'))!.pending!.envelope.commandId,
      );
      final restored = await store.load(scope, 'q');
      expect(restored?.form, {'notes': 'local'});
      expect(restored?.expectedVersion, 7);
      expect(restored?.errorCode, 'VERSION_CONFLICT');
      await expectLater(
        store.prepare(
          scope,
          'q',
          verb: 'save',
          payload: {'notes': 'local'},
          expectedVersion: 7,
        ),
        throwsA(isA<DomainError>()),
      );
      await store.save(
        scope,
        'q',
        {'notes': 'explicit merge'},
        expectedVersion: 8,
        resolveConflict: true,
      );
      expect((await store.load(scope, 'q'))?.errorCode, isNull);
    },
  );

  test(
    'AC-303 uncertain responses preserve the original encrypted envelope',
    () async {
      final store = QuotationDraftStore(encrypted);
      final command = await store.prepare(
        scope,
        'q',
        verb: 'accept',
        payload: {'amount': '90071992547409.123456'},
        expectedVersion: 7,
      );
      for (final code in ['NETWORK_ERROR', 'CONTRACT_ERROR', 'SERVER_ERROR']) {
        await store.recordFailure(
          scope,
          'q',
          DomainError(code: code, message: 'uncertain'),
          commandId: command.envelope.commandId,
        );
        expect(
          (await store.load(scope, 'q'))?.pending?.toJson(),
          command.toJson(),
        );
      }
      await expectLater(store.discard(scope, 'q'), throwsA(isA<DomainError>()));
      await expectLater(
        store.complete(scope, 'q', 'wrong-command'),
        throwsA(isA<DomainError>()),
      );
      await store.complete(scope, 'q', command.envelope.commandId);
      expect(await store.load(scope, 'q'), isNull);
    },
  );

  test(
    'AC-303 concurrent prepares and reordered maps retain one sealed request',
    () async {
      final store = QuotationDraftStore(encrypted);
      final input = <String, Object?>{
        'nested': {'amount': '1.000000'},
        'id': 'quote',
      };
      final commands = await Future.wait(
        List.generate(
          5,
          (_) => store.prepare(scope, 'q', verb: 'save', payload: input),
        ),
      );
      expect(commands.map((c) => c.envelope.commandId).toSet(), hasLength(1));
      (input['nested']! as Map)['amount'] = '2.000000';
      final replay = await store.prepare(
        scope,
        'q',
        verb: 'save',
        payload: {
          'id': 'quote',
          'nested': {'amount': '1.000000'},
        },
      );
      expect(replay.toJson(), commands.first.toJson());
    },
  );

  test(
    'AC-303 known lifecycle rejections release the request and retain edits',
    () async {
      final store = QuotationDraftStore(encrypted);
      await store.save(scope, 'q', {'notes': 'preserved'}, expectedVersion: 7);
      await store.prepare(
        scope,
        'q',
        verb: 'accept',
        payload: {'id': 'quote'},
        expectedVersion: 7,
      );
      await store.recordFailure(
        scope,
        'q',
        const DomainError(
          code: 'QUOTATION_NOT_ACCEPTABLE',
          message: 'not approved',
        ),
        commandId: (await store.load(scope, 'q'))!.pending!.envelope.commandId,
      );
      final draft = await store.load(scope, 'q');
      expect(draft?.pending, isNull);
      expect(draft?.form, {'notes': 'preserved'});
    },
  );

  test('AC-303 a late failure cannot release a newer command', () async {
    final store = QuotationDraftStore(encrypted);
    final first = await store.prepare(
      scope,
      'q',
      verb: 'save',
      payload: {'id': 'one'},
    );
    await store.complete(scope, 'q', first.envelope.commandId);
    final second = await store.prepare(
      scope,
      'q',
      verb: 'save',
      payload: {'id': 'two'},
    );
    await expectLater(
      store.recordFailure(
        scope,
        'q',
        const DomainError(code: 'VALIDATION_ERROR', message: 'old response'),
        commandId: first.envelope.commandId,
      ),
      throwsA(isA<DomainError>()),
    );
    expect((await store.load(scope, 'q'))?.pending?.toJson(), second.toJson());
  });
}
