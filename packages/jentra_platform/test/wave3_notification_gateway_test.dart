import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  late Wave4GatewayHarness harness;
  late SupabaseWave3NotificationGateway gateway;
  setUp(() async {
    harness = Wave4GatewayHarness();
    await harness.initialize();
    gateway = SupabaseWave3NotificationGateway(harness.client);
  });
  tearDown(() => harness.dispose());
  test(
    'diagnostic depth verifies current scope and bounded exact metadata',
    () async {
      final valid = <String, Object?>{
        'tenant_id': w4Scope.tenantId,
        'legal_entity_id': w4Scope.legalEntityId,
        'branch_id': w4Scope.branchId,
        'dead_letter_depth': '2',
        'observed_at': '2026-09-30T00:00:00Z',
      };
      harness.response = valid;
      expect((await gateway.diagnostics(w4Scope))['dead_letter_depth'], '2');
      expect(
        harness.requests.last.url.path,
        endsWith('/rpc/wave3_observability_status'),
      );
      for (final patch in <Map<String, Object?>>[
        {'tenant_id': 'foreign'},
        {'legal_entity_id': 'foreign'},
        {'branch_id': 'foreign'},
        {'dead_letter_depth': 2},
        {'dead_letter_depth': '-1'},
        {'dead_letter_depth': '10001'},
        {'observed_at': 'invalid'},
        {'private_payload': 'hidden'},
      ]) {
        harness.response = {...valid, ...patch};
        await expectLater(gateway.diagnostics(w4Scope), throwsFormatException);
      }
    },
  );
  Map<String, Object?> scope() => {
    'tenant_id': w4Scope.tenantId,
    'legal_entity_id': w4Scope.legalEntityId,
    'branch_id': w4Scope.branchId,
  };
  CommandEnvelope<Map<String, Object?>> configure() => CommandEnvelope(
    commandId: w4Command,
    idempotencyKey: w4Revision,
    context: w4Scope,
    clientTimestamp: DateTime.utc(2026, 9, 29),
    expectedEntityVersion: 3,
    payload: {
      'id': w4Id,
      'recipient_id': w4Scope.actorId,
      'event_class': 'posting',
      'enabled': false,
    },
  );
  test(
    'administrator pages bind scope, versions and bounded continuation',
    () async {
      harness.response = {
        ...scope(),
        'resource': 'subscriptions',
        'items': [
          {
            'id': w4Id,
            'recipient_id': w4Scope.actorId,
            'event_class': 'posting',
            'enabled': true,
            'version': 3,
          },
        ],
        'next_cursor': w4Id,
      };
      expect(
        (await gateway.page(w4Scope, 'subscriptions'))['items'],
        hasLength(1),
      );
      expect(
        (jsonDecode(harness.requests.single.body) as Map)['p_branch_id'],
        w4Scope.branchId,
      );
      (harness.response as Map)['branch_id'] = 'foreign';
      await expectLater(
        gateway.page(w4Scope, 'subscriptions'),
        throwsFormatException,
      );
    },
  );
  test(
    'configuration preserves version and original command receipt',
    () async {
      final command = configure();
      harness.response = harness.confirmed({
        ...scope(),
        ...command.payload,
        'version': 4,
      });
      expect((await gateway.execute('configure', command))['enabled'], isFalse);
      final body = jsonDecode(harness.requests.single.body) as Map;
      expect(body['p_expected_entity_version'], 3);
      expect(body['p_payload'], command.payload);
      expect(body['p_command_id'], w4Command);
      ((harness.response as Map)['entity'] as Map)['version'] = 5;
      await expectLater(
        gateway.execute('configure', command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'due scan only confirms a valid bounded explicit continuation',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: w4Command,
        idempotencyKey: w4Revision,
        context: w4Scope,
        clientTimestamp: DateTime.utc(2026, 9, 29),
        payload: {'kind': 'AP', 'as_of': '2026-09-29'},
      );
      final entity = {
        ...scope(),
        'id': w4Command,
        'kind': 'AP',
        'as_of': '2026-09-29',
        'examined': 100,
        'emitted': 4,
        'has_more': true,
        'next_after': w4Id,
      };
      harness.response = harness.confirmed(entity);
      expect((await gateway.execute('scan', command))['has_more'], isTrue);
      entity['next_after'] = null;
      await expectLater(
        gateway.execute('scan', command),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test('foreign actor and unsupported pages send no request', () async {
    const foreign = TenantContext(
      tenantId: 't',
      actorId: 'foreign',
      legalEntityId: 'e',
      branchId: 'b',
    );
    await expectLater(
      gateway.page(foreign, 'subscriptions'),
      throwsA(isA<DomainError>()),
    );
    await expectLater(
      gateway.page(w4Scope, 'private_hr'),
      throwsFormatException,
    );
    expect(harness.requests, isEmpty);
  });
}
