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
  late SupabaseStockCountGateway gateway;
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
    gateway = SupabaseStockCountGateway(client);
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
  for (final pair in {
    'save': 'upsert_stock_count',
    'submit': 'transition_stock_count',
    'approve': 'transition_stock_count',
    'post': 'post_stock_adjustment',
  }.entries) {
    test('${pair.key} uses the correct governed count RPC', () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {'id': 'document', 'version': 5},
      };
      await gateway.execute(pair.key, command());
      expect(requests.single.url.path, endsWith('/rpc/${pair.value}'));
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_expected_entity_version'], 4);
      expect(
        body['p_payload']['lines'][0]['quantity'],
        '99999999999999.999999',
      );
    });
  }
  test('count malformed success retains uncertainty', () async {
    response = {
      'entity': {'id': 'document'},
    };
    await expectLater(
      gateway.execute('save', command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('count detail uses the named scoped bounded read', () async {
    response = {'id': 'document', 'lines': []};
    await gateway.detail(scope, 'document');
    expect(requests.single.url.path, endsWith('/rpc/stock_count_detail'));
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_branch_id'], 'branch');
    expect(body['p_id'], 'document');
  });
  test('count valuation drift is a definite validation rejection', () async {
    status = 400;
    response = {'code': '55000', 'message': 'COUNT_REAPPROVAL_REQUIRED'};
    await expectLater(
      gateway.execute('post', command()),
      throwsA(
        isA<DomainError>().having(
          (e) => e.message,
          'message',
          contains('fresh approval'),
        ),
      ),
    );
  });
}
