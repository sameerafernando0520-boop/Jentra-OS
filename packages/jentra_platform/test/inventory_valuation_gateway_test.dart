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
  late SupabaseInventoryValuationGateway gateway;
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
    gateway = SupabaseInventoryValuationGateway(client);
  });
  tearDown(() => client.dispose());
  Map<String, Object?> summary() => {
    'id': 'report',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'as_of': '2026-09-20',
    'generated_at': '2026-09-21T00:00:00Z',
    'currency_code': 'LKR',
    'entity_name': 'Jentra',
    'stock_count': 1,
    'difference_count': 1,
    'status': 'generated',
    'version': 1,
    'warehouse_value': '9007199254.740992',
    'transit_value': '0.000001',
    'inventory_value': '9007199254.740993',
    'gl_value': '9007199254.740990',
    'difference': '0.000003',
    'accounts': [
      {'id': 'account', 'code': '1100', 'name': 'Inventory'},
    ],
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 21),
    expectedEntityVersion: 0,
    payload: {
      'id': 'report',
      'as_of': '2026-09-20',
      'account_ids': ['account'],
    },
  );
  Object confirmation(Map<String, Object?> entity) => {
    'command_id': 'command',
    'request_id': 'request',
    'entity': entity,
  };
  final uncertain = throwsA(
    isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
  );
  test('generation keeps exact totals and selected account basis', () async {
    response = confirmation(summary());
    expect((await gateway.generate(command()))['difference'], '0.000003');
    final body = jsonDecode(requests.single.body);
    expect(body['p_expected_entity_version'], 0);
    expect(body['p_payload']['account_ids'], ['account']);
  });
  test(
    'changed report, date, scope or account basis cannot confirm generation',
    () async {
      for (final change in [
        {'id': 'other'},
        {'as_of': '2026-09-19'},
        {'legal_entity_id': 'other'},
        {
          'accounts': [
            {'id': 'other'},
          ],
        },
        {'inventory_value': '9007199254.740992'},
        {'difference': 0.3},
      ]) {
        response = confirmation({...summary(), ...change});
        await expectLater(gateway.generate(command()), uncertain);
      }
    },
  );
  Map<String, Object?> page() => {
    'summary': summary(),
    'section': 'stock',
    'evidence_key': null,
    'next_cursor': '50',
    'items': [
      {
        'id': 'warehouse:product',
        'quantity': '3.000000',
        'value': '10.000001',
        'average_cost': '3.333333666667',
      },
    ],
  };
  test('saved section uses pinned ID and numeric row cursor', () async {
    response = page();
    await gateway.page(scope, 'report', 'stock', after: '50');
    expect(jsonDecode(requests.single.body)['p_after'], 50);
    expect(jsonDecode(requests.single.body)['p_id'], 'report');
  });
  test('page cannot mix report identities or sections', () async {
    response = {...page(), 'section': 'journals'};
    await expectLater(
      gateway.page(scope, 'report', 'stock'),
      throwsFormatException,
    );
    response = {
      ...page(),
      'summary': {...summary(), 'id': 'other'},
    };
    await expectLater(
      gateway.page(scope, 'report', 'stock'),
      throwsFormatException,
    );
  });
  test('cost numbers cannot be coerced from JSON floating values', () async {
    response = {
      ...page(),
      'items': [
        {'id': 'row', 'quantity': '3', 'value': 10.2, 'average_cost': '3.4'},
      ],
    };
    await expectLater(
      gateway.page(scope, 'report', 'stock'),
      throwsFormatException,
    );
  });
  test('source filter retained separately from section cursor', () async {
    response = {
      'summary': summary(),
      'section': 'journals',
      'evidence_key': 'command:source',
      'items': [],
    };
    await gateway.page(
      scope,
      'report',
      'journals',
      evidenceKey: 'command:source',
    );
    expect(
      jsonDecode(requests.single.body)['p_evidence_key'],
      'command:source',
    );
  });
  test('oversized page and negative cursor are rejected', () async {
    response = {
      ...page(),
      'items': List.filled(51, {'id': 'row'}),
    };
    await expectLater(
      gateway.page(scope, 'report', 'stock'),
      throwsFormatException,
    );
    requests.clear();
    await expectLater(
      gateway.page(scope, 'report', 'stock', after: '-1'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('partial branch access is distinct from uncertain generation', () async {
    status = 403;
    response = {'code': '42501', 'message': 'Permission denied'};
    await expectLater(
      gateway.generate(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
  });
  test('wrong current actor cannot read reports', () async {
    const other = TenantContext(
      tenantId: 'tenant',
      actorId: 'other',
      legalEntityId: 'entity',
      branchId: 'branch',
    );
    await expectLater(
      gateway.options(other, 'reports'),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
}
