import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';

final class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

const scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  actorId: '10000000-0000-0000-0000-000000000002',
);
StaffAccountRequest request([String username = 'company_sales']) =>
    StaffAccountRequest(
      requestId: '10000000-0000-0000-0000-000000000003',
      username: username,
      displayName: 'Private staff name',
      roleIds: {'10000000-0000-0000-0000-000000000004'},
    );

void main() {
  late JentraLocalDatabase database;
  late EncryptedDraftRepository repository;
  setUp(() {
    database = JentraLocalDatabase(NativeDatabase.memory());
    repository = EncryptedDraftRepository(
      database,
      DraftCipher(keyStore: _Keys()),
    );
  });
  tearDown(() async => database.close());
  test(
    'encrypted recovery restores exact choices in a new service instance',
    () async {
      final original = request();
      await EncryptedStaffAccountRecovery(repository).save(scope, original);
      final raw = await database.select(database.encryptedDrafts).getSingle();
      expect(
        String.fromCharCodes(raw.encryptedPayload),
        isNot(contains('Private staff name')),
      );
      expect(
        String.fromCharCodes(raw.encryptedPayload),
        isNot(contains('company_sales')),
      );
      final restarted = EncryptedStaffAccountRecovery(repository);
      expect((await restarted.load(scope))!.toJson(), original.toJson());
      expect(
        await restarted.load(
          TenantContext(
            tenantId: scope.tenantId,
            actorId: '10000000-0000-0000-0000-000000000099',
          ),
        ),
        isNull,
      );
      await restarted.complete(scope, original.requestId);
      expect(await restarted.load(scope), isNull);
    },
  );
  test(
    'another request cannot overwrite or clear the saved identity',
    () async {
      final store = EncryptedStaffAccountRecovery(repository);
      await store.save(scope, request());
      await expectLater(
        store.save(scope, request('different_staff')),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        store.complete(scope, '10000000-0000-0000-0000-000000000099'),
        throwsFormatException,
      );
      expect((await store.load(scope))!.username, 'company_sales');
    },
  );
}
