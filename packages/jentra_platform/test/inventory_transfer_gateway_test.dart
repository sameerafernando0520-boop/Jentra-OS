import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseInventoryTransferGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  setUp(() async {
    requests.clear();
    response = [];
    status = 200;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': 'actor',
                    'role': 'authenticated',
                    'exp': 4102444800,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'actor',
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-13T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseInventoryTransferGateway(client);
  });
  tearDown(() => client.dispose());
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 13),
    expectedEntityVersion: 4,
    payload: {
      'id': 'document',
      'lines': [
        {'quantity': '99999999999999.999999', 'unit_price': '0.000001'},
      ],
    },
  );
  test('transfer sends scoped named RPC and exact envelope', () async {
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {'id': 'document', 'status': 'in_transit'},
    };
    await gateway.execute(command());
    final body = jsonDecode(requests.single.body) as Map;
    expect(requests.single.url.path, endsWith('/rpc/transfer_stock'));
    expect(body['p_expected_entity_version'], 4);
    expect(body['p_branch_id'], 'branch');
    expect(body['p_payload']['lines'][0]['quantity'], '99999999999999.999999');
  });
  test('wrong success identity remains uncertain', () async {
    response = {
      'command_id': 'other',
      'request_id': 'request',
      'entity': {'id': 'document'},
    };
    await expectLater(
      gateway.execute(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('state conflict is a definite rejection', () async {
    status = 409;
    response = {'code': '40001', 'message': 'VERSION_CONFLICT'};
    await expectLater(
      gateway.execute(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
      ),
    );
  });
  test('options preserve paging, warehouse and product scope', () async {
    response = {'items': []};
    await gateway.options(
      scope,
      'serials',
      warehouse: 'wh',
      product: 'p',
      after: 'cursor',
      search: 'SER',
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_resource'], 'serials');
    expect(body['p_warehouse_id'], 'wh');
    expect(body['p_product_id'], 'p');
    expect(body['p_after'], 'cursor');
  });
  test('actor mismatch sends no request', () async {
    await expectLater(
      () => gateway.page(
        const TenantContext(
          tenantId: 'tenant',
          actorId: 'another',
          legalEntityId: 'entity',
          branchId: 'branch',
        ),
      ),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  test('dated holdings retain exact reporting date and cursor', () async {
    response = {'items': []};
    await gateway.holdings(scope, '2026-09-14', after: 'last');
    expect(
      requests.single.url.path,
      endsWith('/rpc/inventory_transfer_holdings'),
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_as_of'], '2026-09-14');
    expect(body['p_after'], 'last');
  });
}
