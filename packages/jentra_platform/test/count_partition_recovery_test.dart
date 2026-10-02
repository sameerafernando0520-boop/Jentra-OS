import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/count_partitions.dart';
import 'package:jentra_platform/count_partitions.dart';

class _Keys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _Gateway implements CountPartitionGateway {
  bool uncertain = true;
  final commands = <Map<String, Object?>>[];
  int reads = 0;
  CountPartitionProgress get result => CountPartitionProgress.fromJson({
    'id': 'group',
    'cutoff_at': '2026-09-30T08:00:00Z',
    'expected_identity_count': 501,
    'captured_identity_count': 501,
    'expected_partition_count': 2,
    'captured_partition_count': 2,
    'posted_partition_count': 0,
    'cancelled_partition_count': 0,
    'missing_partition_ordinals': <int>[],
    'capture_complete': true,
    'posting_complete': false,
    'baseline_quantity': '501.000000',
    'counted_quantity': '501.000000',
    'variance_quantity': '0.000000',
    'grand_total': '0.000000',
  });
  @override
  Future<CountPartitionProgress> capture(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    commands.add(command.toJson((p) => p));
    if (uncertain) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Synthetic lost response',
      );
    }
    return result;
  }

  @override
  Future<CountPartitionProgress> page(
    TenantContext scope,
    String groupId, {
    int after = 0,
    int limit = 50,
  }) async {
    reads++;
    return result;
  }
}

void main() {
  test(
    'uncertain partition capture survives restart with exact original sealed request',
    () async {
      final db = JentraLocalDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = EncryptedDraftRepository(
        db,
        DraftCipher(keyStore: _Keys()),
      );
      final gateway = _Gateway();
      const scope = TenantContext(
        tenantId: 'tenant',
        actorId: 'actor',
        legalEntityId: 'entity',
        branchId: 'branch',
      );
      CountPartitionCaptureService service(TenantContext context) =>
          CountPartitionCaptureService(
            scope: context,
            gateway: gateway,
            drafts: QuotationDraftStore(repository),
          );
      final first = service(scope);
      await first.saveDraft({
        'id': 'group',
        'warehouse_id': 'warehouse',
        'product_id': 'tracked-product',
        'offset_account_id': 'account',
        'document_date': '2026-09-30',
        'reason': 'Physical count',
      });
      await expectLater(first.capture(), throwsA(isA<DomainError>()));
      expect((await first.restore())!.pending, isNotNull);
      expect(await service(scope.copyWith(actorId: 'other')).restore(), isNull);
      await expectLater(
        first.saveDraft({
          'id': 'replacement',
          'warehouse_id': 'warehouse',
          'product_id': 'tracked-product',
          'offset_account_id': 'account',
          'document_date': '2026-09-30',
          'reason': 'Replacement',
        }),
        throwsA(isA<DomainError>()),
      );
      gateway.uncertain = false;
      final restored = service(scope);
      expect((await restored.capture()).captureComplete, isTrue);
      expect(gateway.commands[1], gateway.commands[0]);
      final confirmed = await restored.restore();
      expect(confirmed!.pending, isNull);
      expect(confirmed.form, {'confirmed_group_id': 'group'});
      await service(scope).capture();
      expect(gateway.commands.length, 2);
      expect(gateway.reads, 1);
    },
  );
}
