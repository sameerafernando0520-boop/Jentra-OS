import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseOperationalGateway gateway;
  Object response = {};
  final requests = <http.Request>[];
  setUp(() async {
    requests.clear();
    response = {
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'kind': 'supplier_bill',
      'basis': 'current',
      'filters': <String, Object?>{},
      'items': [
        {
          'id': 'bill',
          'total': '900719925474.099999',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
        },
      ],
      'next_cursor': null,
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
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'actor',
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseOperationalGateway(client);
  });
  tearDown(() async => client.dispose());

  test('current list binds scope, filter and lossless exact amount', () async {
    (response as Map)['filters'] = {'status': 'posted'};
    final r = await gateway.currentPage(
      scope,
      'supplier_bill',
      filters: {'status': 'posted'},
    );
    expect((r['items'] as List).first['total'], '900719925474.099999');
    expect(requests.single.url.path, endsWith('/rpc/wave3_document_page'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': 'tenant',
      'p_legal_entity_id': 'entity',
      'p_branch_id': 'branch',
      'p_kind': 'supplier_bill',
      'p_filters': {'status': 'posted'},
      'p_after': null,
    });
  });
  test('numeric money and substituted scope fail closed', () async {
    (response as Map)['items'] = [
      {
        'id': 'bill',
        'total': 900719925474.1,
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
      },
    ];
    await expectLater(
      gateway.currentPage(scope, 'supplier_bill'),
      throwsFormatException,
    );
    (response as Map)['items'] = [
      {
        'id': 'bill',
        'total': '1.000000',
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
      },
    ];
    (response as Map)['branch_id'] = 'other';
    await expectLater(
      gateway.currentPage(scope, 'supplier_bill'),
      throwsFormatException,
    );
  });
  test('unapproved kind cannot become an arbitrary table read', () async {
    await expectLater(
      gateway.currentPage(scope, 'auth.users'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('file rejection carries its sealed scope, reason and version', () async {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: '00000000-0000-4000-8000-000000000010',
      idempotencyKey: '00000000-0000-4000-8000-000000000011',
      context: scope,
      payload: {
        'id': '00000000-0000-4000-8000-000000000012',
        'aggregate_type': 'supplier_bill',
        'aggregate_id': '00000000-0000-4000-8000-000000000013',
        'reason': 'Wrong source document',
      },
      expectedEntityVersion: 2,
    );
    response = {
      'command_id': command.commandId,
      'request_id': '00000000-0000-4000-8000-000000000014',
      'entity': {
        'id': command.payload['id'],
        'aggregate_type': command.payload['aggregate_type'],
        'aggregate_id': command.payload['aggregate_id'],
        'status': 'rejected',
        'version': 3,
      },
    };
    expect((await gateway.rejectAttachment(command))['status'], 'rejected');
    expect(requests.single.url.path, endsWith('/rpc/reject_wave3_attachment'));
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_payload'], command.payload);
    expect(body['p_expected_entity_version'], 2);
    expect(body['p_idempotency_key'], command.idempotencyKey);
    ((response as Map)['entity'] as Map)['aggregate_id'] = 'foreign';
    await expectLater(
      gateway.rejectAttachment(command),
      throwsA(isA<DomainError>()),
    );
  });
  test(
    'dashboard rejects an untrusted destination and numeric count',
    () async {
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'cards': [
          <String, Object?>{
            'kind': 'supplier_bill',
            'count': '4',
            'basis': 'current_actionable',
            'destination': '/procurement',
            'tenant_id': 'tenant',
            'legal_entity_id': 'entity',
            'branch_id': 'branch',
          },
        ],
      };
      expect((await gateway.dashboard(scope))['cards'], hasLength(1));
      ((response as Map)['cards'] as List).first['destination'] =
          'https://evil.example';
      await expectLater(gateway.dashboard(scope), throwsFormatException);
      ((response as Map)['cards'] as List).first['destination'] =
          '/procurement';
      ((response as Map)['cards'] as List).first['count'] = 4;
      await expectLater(gateway.dashboard(scope), throwsFormatException);
    },
  );
  test(
    'dashboard metrics bind scope, dated basis, destination and exact amounts',
    () async {
      final metric = <String, Object?>{
        'kind': 'ap_aging',
        'basis': 'dated_open_items',
        'destination': '/procurement/payments',
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'generated_at': '2026-09-30T00:00:00Z',
        'as_of': '2026-09-30',
        'data': {
          'buckets': [
            <String, Object?>{
              'currency_code': 'LKR',
              'bucket': 'current',
              'amount': '9007199254740.123456',
            },
          ],
        },
      };
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'cards': [],
        'metrics': [metric],
      };
      expect((await gateway.dashboard(scope))['metrics'], hasLength(1));
      metric['branch_id'] = 'foreign';
      await expectLater(gateway.dashboard(scope), throwsFormatException);
      metric['branch_id'] = 'branch';
      metric['destination'] = '/private';
      await expectLater(gateway.dashboard(scope), throwsFormatException);
      metric['destination'] = '/procurement/payments';
      metric['basis'] = 'current';
      await expectLater(gateway.dashboard(scope), throwsFormatException);
      metric['basis'] = 'dated_open_items';
      (((metric['data'] as Map)['buckets'] as List).first as Map)['amount'] =
          0.1;
      await expectLater(gateway.dashboard(scope), throwsFormatException);
    },
  );
}
