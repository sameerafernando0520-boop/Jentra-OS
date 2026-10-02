import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  const id = '11111111-1111-4111-8111-111111111111';
  late SupabaseClient client;
  late SupabaseProcurementGateway gateway;
  final requests = <http.Request>[];
  var status = 200;
  Object? response;
  Map<String, Object?> row() => {
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'id': id,
    'detail': {
      'id': id,
      'version': 2,
      'status': 'draft',
      'lines': [
        {'quantity': '1.000001', 'unit_price': '9007199254.740993'},
      ],
    },
  };
  setUp(() async {
    requests.clear();
    status = 200;
    response = [row()];
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
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
                'created_at': '2026-10-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(request);
        return http.Response(
          jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseProcurementGateway(client);
  });
  tearDown(() => client.dispose());
  final kinds = {
    'purchase_requisition': 'purchase_requisitions',
    'purchase_order': 'purchase_orders',
    'supplier_bill': 'supplier_bills',
  };
  for (final entry in kinds.entries) {
    test(
      '${entry.key} reads one authenticated exact scoped current document',
      () async {
        final result = await gateway.conflictDocument(scope, entry.key, id);
        expect(
          (result['lines'] as List).single['unit_price'],
          '9007199254.740993',
        );
        final request = requests.single;
        expect(request.url.path, '/rest/v1/${entry.value}');
        expect(request.headers['accept-profile'], 'api');
        expect(request.url.queryParameters['id'], 'eq.$id');
        expect(request.url.queryParameters['tenant_id'], 'eq.tenant');
        expect(request.url.queryParameters['legal_entity_id'], 'eq.entity');
        expect(request.url.queryParameters['branch_id'], 'eq.branch');
        expect(request.url.queryParameters['limit'], '1');
        expect(request.method, 'GET');
      },
    );
  }
  for (final kind in ['unknown', 'purchase_order']) {
    test('rejects invalid identity or kind before a request: $kind', () async {
      await expectLater(
        gateway.conflictDocument(
          scope,
          kind,
          kind == 'unknown' ? id : 'invalid',
        ),
        throwsA(isA<DomainError>()),
      );
      expect(requests, isEmpty);
    });
  }
  test('missing current record is explicit', () async {
    response = [];
    await expectLater(
      gateway.conflictDocument(scope, 'purchase_order', id),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'READ_REJECTED'),
      ),
    );
  });
  for (final field in ['tenant_id', 'legal_entity_id', 'branch_id', 'id']) {
    test('rejects mismatched $field in response', () async {
      response = [
        {...row(), field: 'other'},
      ];
      await expectLater(
        gateway.conflictDocument(scope, 'purchase_order', id),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'READ_INVALID'),
        ),
      );
    });
  }
  test('rejects floating financial values', () async {
    response = [
      {
        ...row(),
        'detail': {
          'id': id,
          'version': 2,
          'lines': [
            {'quantity': 1.000001},
          ],
        },
      },
    ];
    await expectLater(
      gateway.conflictDocument(scope, 'purchase_order', id),
      throwsA(isA<DomainError>().having((e) => e.code, 'code', 'READ_INVALID')),
    );
  });
  test('rejects truncated or oversized line documents', () async {
    response = [
      {
        ...row(),
        'detail': {
          'id': id,
          'version': 2,
          'lines': List.filled(501, {'quantity': '1'}),
        },
      },
    ];
    await expectLater(
      gateway.conflictDocument(scope, 'purchase_order', id),
      throwsA(isA<DomainError>()),
    );
  });
  test('typed denial has fixed public message', () async {
    status = 403;
    response = {'code': '42501', 'message': 'private server schema detail'};
    await expectLater(
      gateway.conflictDocument(scope, 'purchase_order', id),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'PERMISSION_DENIED')
            .having(
              (e) => e.message.contains('private server'),
              'redacted',
              false,
            ),
      ),
    );
  });
}
