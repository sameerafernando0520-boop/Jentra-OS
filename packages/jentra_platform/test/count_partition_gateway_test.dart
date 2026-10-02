import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/count_partitions.dart';
import 'package:jentra_platform/count_partitions.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness harness;
  late SupabaseCountPartitionGateway gateway;
  setUp(() async {
    harness = Wave4GatewayHarness();
    await harness.initialize();
    gateway = SupabaseCountPartitionGateway(harness.client);
  });
  tearDown(() => harness.dispose());
  Map<String, Object?> summary() => {
    'id': w4Id,
    'cutoff_at': '2026-09-30T08:00:00Z',
    'expected_identity_count': 501,
    'captured_identity_count': 501,
    'expected_partition_count': 2,
    'captured_partition_count': 2,
    'posted_partition_count': 0,
    'cancelled_partition_count': 0,
    'missing_partition_ordinals': [],
    'capture_complete': true,
    'posting_complete': false,
    'baseline_quantity': '90071992547409.123456',
    'counted_quantity': '90071992547409.123456',
    'variance_quantity': '0.000000',
    'grand_total': '0.000000',
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: w4Command,
    idempotencyKey: w4Revision,
    context: w4Scope,
    clientTimestamp: DateTime.utc(2026, 9, 30),
    payload: {
      'id': w4Id,
      'warehouse_id': 'warehouse',
      'product_id': 'product',
      'offset_account_id': 'account',
      'document_date': '2026-09-30',
      'reason': 'Physical count',
    },
  );
  test(
    'capture sends authenticated explicit scope and preserves sealed command identity',
    () async {
      harness.response = harness.confirmed(summary());
      final p = await gateway.capture(command());
      expect(p.baseline.toDecimalString(), '90071992547409.123456');
      final request = harness.requests.single;
      expect(request.url.path, endsWith('/rpc/capture_stock_count_partitions'));
      expect(request.headers['content-profile'], 'api');
      final body = jsonDecode(request.body) as Map;
      expect(body['p_tenant_id'], w4Scope.tenantId);
      expect(body['p_legal_entity_id'], w4Scope.legalEntityId);
      expect(body['p_branch_id'], w4Scope.branchId);
      expect(body['p_command_id'], w4Command);
      expect(body['p_idempotency_key'], w4Revision);
      expect(body['p_client_timestamp'], '2026-09-30T00:00:00.000Z');
    },
  );
  test(
    'mismatched receipt or false completeness is uncertain after a possible commit',
    () async {
      harness.response = harness.confirmed({...summary(), 'id': 'wrong-group'});
      await expectLater(
        gateway.capture(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      harness.response = harness.confirmed({
        ...summary(),
        'posting_complete': true,
      });
      await expectLater(
        gateway.capture(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test('current actor mismatch denies transport before any request', () async {
    await expectLater(
      gateway.page(w4Scope.copyWith(actorId: 'other'), w4Id),
      throwsA(isA<DomainError>()),
    );
    expect(harness.requests, isEmpty);
  });
  test(
    'bounded progress read carries explicit cursor and rejects excessive limits locally',
    () async {
      harness.response = summary();
      await gateway.page(w4Scope, w4Id, after: 1, limit: 1);
      final body = jsonDecode(harness.requests.single.body) as Map;
      expect(body['p_after'], 1);
      expect(body['p_limit'], 1);
      await expectLater(
        gateway.page(w4Scope, w4Id, limit: 51),
        throwsFormatException,
      );
      expect(harness.requests, hasLength(1));
    },
  );
}
