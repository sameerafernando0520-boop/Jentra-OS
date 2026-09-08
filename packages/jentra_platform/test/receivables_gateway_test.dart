import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseReceivablesGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  setUp(() {
    requests.clear();
    response = [];
    status = 200;
    client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseReceivablesGateway(client);
  });
  tearDown(() => client.dispose());
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 7),
    expectedEntityVersion: 3,
    payload: {'document_id': 'invoice'},
  );
  test('register scopes all dimensions and uses bounded keyset', () async {
    await gateway.page(
      scope,
      ReceivableKind.invoice,
      cursor: 'after',
      status: 'posted',
    );
    final q = requests.single.url.queryParameters;
    expect(q['tenant_id'], 'eq.tenant');
    expect(q['legal_entity_id'], 'eq.entity');
    expect(q['branch_id'], 'eq.branch');
    expect(q['id'], 'gt.after');
    expect(q['limit'], '51');
    expect(q['status'], 'eq.posted');
    expect(requests.single.headers['accept-profile'], 'api');
  });
  test('missing scope rejects before transport', () async {
    await expectLater(
      gateway.page(scope.copyWith(clearBranch: true), ReceivableKind.invoice),
      throwsA(isA<ReceivableFailure>()),
    );
    expect(requests, isEmpty);
  });
  test('mutation sends persisted envelope unchanged', () async {
    response = {
      'request_id': 'request',
      'command_id': 'command',
      'entity': {'id': 'invoice'},
    };
    final result = await gateway.command('post_sales_invoice', command());
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_command_id'], 'command');
    expect(body['p_idempotency_key'], 'key');
    expect(body['p_expected_entity_version'], 3);
    expect(body['p_client_timestamp'], '2026-09-07T00:00:00.000Z');
    expect(result['request_id'], 'request');
  });
  test('malformed success remains uncertain', () async {
    response = {
      'entity': {'id': 'invoice'},
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>().having((e) => e.definite, 'definite', false),
      ),
    );
  });
  test('version conflict is a definite database rollback', () async {
    status = 409;
    response = {
      'code': '40001',
      'message': 'VERSION_CONFLICT',
      'details': null,
      'hint': null,
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>()
            .having((e) => e.code, 'code', 'VERSION_CONFLICT')
            .having((e) => e.definite, 'definite', true),
      ),
    );
  });
  test('server outage does not release saved command', () async {
    status = 503;
    response = {
      'code': 'PGRST000',
      'message': 'Unavailable',
      'details': null,
      'hint': null,
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>().having((e) => e.definite, 'definite', false),
      ),
    );
  });
  test('reference and RPC allowlists reject arbitrary resources', () async {
    await expectLater(
      gateway.references(scope, 'memberships'),
      throwsA(isA<ReceivableFailure>()),
    );
    await expectLater(
      gateway.command('delete_tenant', command()),
      throwsA(isA<ReceivableFailure>()),
    );
    expect(requests, isEmpty);
  });
  test('statement transmits exact chosen as-of date and buckets', () async {
    response = {'rows': []};
    await gateway.statement(scope, 'customer', 'USD', '2026-09-06', [
      15,
      30,
      60,
    ]);
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_as_of'], '2026-09-06');
    expect(body['p_buckets'], [15, 30, 60]);
  });
}
