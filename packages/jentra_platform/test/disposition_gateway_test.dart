import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/disposition.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseDispositionGateway gateway;
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
    gateway = SupabaseDispositionGateway(client);
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
  Map<String, Object?> document({String state = 'draft'}) => {
    'id': 'document',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'version': 5,
    'status': state,
    'currency_code': 'LKR',
    'grand_total': '30.037037',
    if (state == 'posted') 'journal_entry_id': 'journal',
    if (state == 'posted') 'stock_movement_id': 'movement',
    'lines': [
      {
        'line_id': 'line',
        'product_id': 'product',
        'tracking_mode': 'none',
        'quantity': '3',
        'base_quantity': '3',
        'carrying_value': '30.037037',
        'serial_ids': [],
      },
    ],
  };
  for (final pair in {
    'save': 'upsert_stock_disposition',
    'submit': 'transition_stock_disposition',
    'approve': 'transition_stock_disposition',
    'post': 'post_stock_disposition',
  }.entries) {
    test('${pair.key} uses the correct governed disposition RPC', () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': document(
          state: switch (pair.key) {
            'submit' => 'pending_approval',
            'approve' => 'approved',
            'post' => 'posted',
            _ => 'draft',
          },
        ),
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
  test('disposition malformed success retains uncertainty', () async {
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
  test('disposition detail uses the named scoped bounded read', () async {
    response = document();
    await gateway.detail(scope, 'document');
    expect(requests.single.url.path, endsWith('/rpc/stock_disposition_detail'));
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_branch_id'], 'branch');
    expect(body['p_id'], 'document');
  });
  test('wrong scope and numeric carrying value fail closed on reads', () async {
    response = {...document(), 'branch_id': 'foreign'};
    await expectLater(
      gateway.detail(scope, 'document'),
      throwsA(isA<DomainError>()),
    );
    response = {...document(), 'grand_total': 30.037037};
    await expectLater(
      gateway.detail(scope, 'document'),
      throwsA(isA<DomainError>()),
    );
  });
  test(
    'duplicate page identities and unsupported picker are rejected',
    () async {
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'items': [document(), document()],
        'next_cursor': null,
      };
      await expectLater(gateway.page(scope), throwsA(isA<DomainError>()));
      requests.clear();
      await expectLater(
        gateway.options(scope, 'private'),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    },
  );
  test('wrong version or lifecycle never confirms a saved command', () async {
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {...document(), 'version': 7},
    };
    await expectLater(
      gateway.execute('save', command()),
      throwsA(isA<DomainError>()),
    );
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': document(state: 'approved'),
    };
    await expectLater(
      gateway.execute('save', command()),
      throwsA(isA<DomainError>()),
    );
  });
  test(
    'disposition valuation drift is a definite validation rejection',
    () async {
      status = 400;
      response = {
        'code': '55000',
        'message': 'DISPOSITION_REAPPROVAL_REQUIRED',
      };
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
    },
  );

  // Read authentication preserves typed scope denials; command precedence is unchanged.
  test(
    'read entrypoint 1 redacts typed access and expired-token errors',
    () async {
      for (final rejection in [
        ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
        ('42501', 'PRIVATE database table', 'PERMISSION_DENIED'),
        ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
        ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
        ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
        (
          'PGRST301',
          'PRIVATE signature diagnostics',
          'AUTHENTICATION_REQUIRED',
        ),
        ('PGRST302', 'PRIVATE role diagnostics', 'AUTHENTICATION_REQUIRED'),
        ('PGRST303', 'PRIVATE claims diagnostics', 'AUTHENTICATION_REQUIRED'),
      ]) {
        status = rejection.$1.startsWith('PGRST') ? 401 : 403;
        response = {
          'code': rejection.$1,
          'message': rejection.$2,
          'details': 'PRIVATE SQL and host',
          'hint': 'PRIVATE internal remediation',
        };
        await expectLater(
          gateway.page(scope),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'typed rejection', rejection.$3)
                .having(
                  (e) => e.message,
                  'public message',
                  isNot(contains('PRIVATE')),
                ),
          ),
        );
        final body = jsonDecode(requests.last.body) as Map;
        expect(body['p_tenant_id'], 'tenant');
        expect(body['p_legal_entity_id'], 'entity');
        expect(body['p_branch_id'], 'branch');
      }
    },
  );
  test(
    'read entrypoint 2 redacts typed access and expired-token errors',
    () async {
      for (final rejection in [
        ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
        ('42501', 'PRIVATE database table', 'PERMISSION_DENIED'),
        ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
        ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
        ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
        (
          'PGRST301',
          'PRIVATE signature diagnostics',
          'AUTHENTICATION_REQUIRED',
        ),
        ('PGRST302', 'PRIVATE role diagnostics', 'AUTHENTICATION_REQUIRED'),
        ('PGRST303', 'PRIVATE claims diagnostics', 'AUTHENTICATION_REQUIRED'),
      ]) {
        status = rejection.$1.startsWith('PGRST') ? 401 : 403;
        response = {
          'code': rejection.$1,
          'message': rejection.$2,
          'details': 'PRIVATE SQL and host',
          'hint': 'PRIVATE internal remediation',
        };
        await expectLater(
          gateway.options(scope, 'warehouses'),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'typed rejection', rejection.$3)
                .having(
                  (e) => e.message,
                  'public message',
                  isNot(contains('PRIVATE')),
                ),
          ),
        );
        final body = jsonDecode(requests.last.body) as Map;
        expect(body['p_tenant_id'], 'tenant');
        expect(body['p_legal_entity_id'], 'entity');
        expect(body['p_branch_id'], 'branch');
      }
    },
  );
  test(
    'read entrypoint 3 redacts typed access and expired-token errors',
    () async {
      for (final rejection in [
        ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
        ('42501', 'PRIVATE database table', 'PERMISSION_DENIED'),
        ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
        ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
        ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
        (
          'PGRST301',
          'PRIVATE signature diagnostics',
          'AUTHENTICATION_REQUIRED',
        ),
        ('PGRST302', 'PRIVATE role diagnostics', 'AUTHENTICATION_REQUIRED'),
        ('PGRST303', 'PRIVATE claims diagnostics', 'AUTHENTICATION_REQUIRED'),
      ]) {
        status = rejection.$1.startsWith('PGRST') ? 401 : 403;
        response = {
          'code': rejection.$1,
          'message': rejection.$2,
          'details': 'PRIVATE SQL and host',
          'hint': 'PRIVATE internal remediation',
        };
        await expectLater(
          gateway.detail(scope, 'document'),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'typed rejection', rejection.$3)
                .having(
                  (e) => e.message,
                  'public message',
                  isNot(contains('PRIVATE')),
                ),
          ),
        );
        final body = jsonDecode(requests.last.body) as Map;
        expect(body['p_tenant_id'], 'tenant');
        expect(body['p_legal_entity_id'], 'entity');
        expect(body['p_branch_id'], 'branch');
      }
    },
  );
  test(
    'command error classification retains its existing SQLSTATE precedence',
    () async {
      for (final rejection in [
        ('P0001', 'MFA_REQUIRED', 'VALIDATION_ERROR'),
        ('42501', 'MFA_REQUIRED', 'PERMISSION_DENIED'),
        ('40001', 'MFA_REQUIRED', 'VERSION_CONFLICT'),
        ('PGRST301', 'AUTHENTICATION_REQUIRED', 'UNCERTAIN_RESULT'),
      ]) {
        status = 400;
        response = {'code': rejection.$1, 'message': rejection.$2};
        await expectLater(
          gateway.execute('post', command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'command precedence',
              rejection.$3,
            ),
          ),
        );
      }
    },
  );
}
