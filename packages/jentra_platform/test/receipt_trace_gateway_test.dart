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
  late SupabaseReceiptTraceGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  const row = {
    'id': 'receipt',
    'covered': true,
    'received_quantity': '9007199254.740993',
  };
  setUp(() async {
    requests.clear();
    status = 200;
    response = {
      'items': [row],
    };
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
                'created_at': '2026-09-19T00:00:00Z',
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
    gateway = SupabaseReceiptTraceGateway(client);
  });
  tearDown(() => client.dispose());
  test('page carries scoped cursor and exact quantity strings', () async {
    final r = await gateway.page(scope, after: 'cursor');
    expect(
      (r['items'] as List).single['received_quantity'],
      '9007199254.740993',
    );
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': 'tenant',
      'p_legal_entity_id': 'entity',
      'p_branch_id': 'branch',
      'p_after': 'cursor',
    });
    expect(requests.single.url.path, endsWith('/rpc/receipt_trace_page'));
  });
  Map<String, Object?> detail() => {
    'id': 'receipt',
    'covered': true,
    'received_quantity': '10.000000',
    'held_quantity': '3.000000',
    'in_transit_quantity': '2.000000',
    'net_issued_quantity': '5.000000',
    'holdings': [
      {'quantity': '3.000000'},
    ],
    'items': [
      {'sequence': '9007199254740993', 'quantity': '-5.000000'},
    ],
    'next_cursor': '9007199254740993',
  };
  test('history bigint cursor stays a string', () async {
    response = detail();
    final r = await gateway.detail(scope, 'receipt', after: '9007199254740993');
    expect(jsonDecode(requests.single.body)['p_after'], '9007199254740993');
    expect(r['next_cursor'], '9007199254740993');
  });
  test('numeric quantities are rejected without coercion', () async {
    response = {
      'items': [
        {...row, 'received_quantity': 1.5},
      ],
    };
    await expectLater(gateway.page(scope), throwsFormatException);
  });
  test('detail belonging to a different receipt is rejected', () async {
    response = {...detail(), 'id': 'other'};
    await expectLater(gateway.detail(scope, 'receipt'), throwsFormatException);
  });
  test('unknown coverage cannot masquerade as exact holdings', () async {
    response = {...detail(), 'covered': false};
    await expectLater(gateway.detail(scope, 'receipt'), throwsFormatException);
    response = {
      ...detail(),
      'covered': false,
      'held_quantity': null,
      'in_transit_quantity': null,
      'net_issued_quantity': null,
      'holdings': [],
      'items': [],
    };
    expect((await gateway.detail(scope, 'receipt'))['held_quantity'], isNull);
  });
  test('oversized register is rejected', () async {
    response = {'items': List.filled(51, row)};
    await expectLater(gateway.page(scope), throwsFormatException);
  });
  test('actor mismatch prevents any RPC', () async {
    const other = TenantContext(
      tenantId: 'tenant',
      actorId: 'other',
      legalEntityId: 'entity',
      branchId: 'branch',
    );
    await expectLater(
      gateway.page(other),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    expect(requests, isEmpty);
  });
  test('permission errors retain a distinct revocation code', () async {
    status = 403;
    response = {'code': '42501', 'message': 'denied'};
    await expectLater(
      gateway.detail(scope, 'receipt'),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
  });
}
