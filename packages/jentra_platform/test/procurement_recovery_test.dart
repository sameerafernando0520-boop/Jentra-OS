import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  test(
    'AC-309 recovery namespace and immutable retry are isolated from sales',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: _Keys()),
      );
      final procurement = QuotationDraftStore.procurement(repository);
      final sales = QuotationDraftStore(repository);
      const scope = TenantContext(
        tenantId: 'tenant',
        actorId: 'actor',
        legalEntityId: 'entity',
        branchId: 'branch',
      );
      const form = {'id': 'requisition', 'quantity': '90071992547409.123456'};
      await procurement.save(scope, 'editor', form);
      expect(await sales.load(scope, 'editor'), isNull);
      expect(
        await procurement.load(scope.copyWith(actorId: 'other'), 'editor'),
        isNull,
      );
      final command = await procurement.prepare(
        scope,
        'editor',
        verb: 'save',
        payload: form,
      );
      await expectLater(
        procurement.save(scope, 'editor', {'id': 'changed'}),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        procurement.prepare(
          scope,
          'editor',
          verb: 'save',
          payload: {...form, 'quantity': '1'},
        ),
        throwsA(isA<DomainError>()),
      );
      final restored = await QuotationDraftStore.procurement(
        repository,
      ).load(scope, 'editor');
      expect(restored!.pending!.toJson(), command.toJson());
      await procurement.recordFailure(
        scope,
        'editor',
        const DomainError(code: 'UNCERTAIN_RESULT', message: 'retry'),
        commandId: command.envelope.commandId,
      );
      expect(
        (await procurement.load(scope, 'editor'))!.pending!.toJson(),
        command.toJson(),
      );
      await procurement.complete(scope, 'editor', command.envelope.commandId);
      expect(await procurement.load(scope, 'editor'), isNull);
    },
  );
}
