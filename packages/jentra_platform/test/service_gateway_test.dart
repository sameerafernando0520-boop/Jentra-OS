import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';
import 'package:jentra_platform/jentra_service_platform.dart';
import 'support/wave4_gateway_harness.dart';

void main() {
  final samples = serviceMap(
    jsonDecode(
      File(
        'test/fixtures/service_rollback_projections.json',
      ).readAsStringSync(),
    ),
  );
  late Wave4GatewayHarness h;
  late SupabaseServiceGateway gateway;
  setUp(() async {
    h = Wave4GatewayHarness();
    await h.initialize();
    gateway = SupabaseServiceGateway(h.client);
  });
  tearDown(() async {
    await h.dispose();
  });
  for (final entry in samples.entries) {
    test('actual rollback ${entry.key} crosses typed gateway', () async {
      final response = serviceMap(entry.value),
          record = serviceMap(response['record']);
      final scope = TenantContext(
        tenantId: record['tenant_id'] as String,
        legalEntityId: record['legal_entity_id'] as String,
        branchId: record['branch_id'] as String,
        actorId: w4Scope.actorId,
      );
      final name = entry.key.split('-').first,
          kind = ServiceKind.values.byName(name);
      h.response = response;
      final result = await gateway.detail(scope, kind, record['id'] as String);
      expect(result.record.id, record['id']);
      expect(result.events, isNotEmpty);
      if (entry.key == 'labor-approved') {
        expect(result.record.toJson()['amount'], '123.460000');
        expect(result.record.toJson()['billable_amount'], '250.000000');
      }
      if (entry.key == 'labor-redacted') {
        expect(result.record.toJson().containsKey('amount'), false);
      }
      expect(h.requests.last.url.path, '/rest/v1/rpc/service_detail');
    });
  }
  test('private field and scope substitution are rejected', () async {
    final sample = serviceMap(samples['labor-approved']),
        row = serviceMap(sample['record']);
    final scope = TenantContext(
      tenantId: row['tenant_id'] as String,
      legalEntityId: row['legal_entity_id'] as String,
      branchId: row['branch_id'] as String,
      actorId: w4Scope.actorId,
    );
    h.response = {
      ...sample,
      'record': {...row, 'salary': 'private'},
    };
    await expectLater(
      gateway.detail(scope, ServiceKind.labor, row['id'] as String),
      throwsFormatException,
    );
    h.response = {
      ...sample,
      'record': {...row, 'branch_id': w4Id},
    };
    await expectLater(
      gateway.detail(scope, ServiceKind.labor, row['id'] as String),
      throwsFormatException,
    );
  });
  test('provider failures are actionable', () async {
    for (final code in [
      'SERVICE_PARTS_PROVIDER_UNAVAILABLE',
      'SERVICE_BILLING_ADAPTER_UNAVAILABLE',
      'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE',
    ]) {
      h.status = 400;
      h.response = {
        'code': '55000',
        'message': code,
        'details': null,
        'hint': null,
      };
      await expectLater(
        gateway.authorize(w4Scope, 'service.view'),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', code)),
      );
    }
  });
  test('account change discards late read', () async {
    h.gate = Completer<void>();
    final read = gateway.authorize(w4Scope, 'service.view');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await h.client.auth.signOut();
    h.gate!.complete();
    await expectLater(
      read,
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'AUTHENTICATION_REQUIRED',
        ),
      ),
    );
  });
  test('unknown command response preserves uncertainty', () async {
    h.response = {'unexpected': true};
    final p = {
      'action': 'equipment',
      'id': w4Id,
      'reason': 'Synthetic',
      'code': 'EQ-1',
      'name': 'Synthetic pump',
      'identity': 'SERIAL-1',
      'kind': 'customer',
      'customer_id': w4Revision,
      'provider_id': null,
    };
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: w4Command,
      idempotencyKey: w4Command,
      context: w4Scope,
      payload: p,
      clientTimestamp: DateTime.utc(2026, 10, 1),
      expectedEntityVersion: 0,
    );
    await expectLater(
      gateway.execute('equipment', command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
}
