import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> policy({String version = '1', bool active = true}) => {
  'tenant_id': 'tenant',
  'legal_entity_id': 'entity',
  'id': version == '0' ? null : 'command',
  'policy_version': version,
  'active': active,
  'basis': 'last_authoritative_positive_average',
  'cover_order': 'issue_ledger_fifo',
  'tracking_scope': 'untracked',
  'reason': version == '0' ? null : 'approved',
  'created_by': version == '0' ? null : 'actor',
  'created_at': version == '0' ? null : '2026-10-03T00:00:00Z',
};
void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseNegativeStockPolicyGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  setUp(() async {
    requests.clear();
    status = 200;
    response = policy();
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
                'created_at': '2026-10-03T00:00:00Z',
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
    gateway = SupabaseNegativeStockPolicyGateway(client);
  });
  tearDown(() => client.dispose());
  CommandEnvelope<Map<String, Object?>> command({
    TenantContext context = scope,
    String reason = 'approved',
  }) => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: context,
    expectedEntityVersion: 0,
    clientTimestamp: DateTime.utc(2026, 10, 3),
    payload: {'active': true, 'reason': reason},
  );
  test(
    'policy read scopes exact entity branch and preserves large version',
    () async {
      response = policy(version: '9007199254740993');
      final p = await gateway.readPolicy(scope);
      expect(p.version, BigInt.parse('9007199254740993'));
      expect(requests.single.url.path, endsWith('/rpc/negative_stock_policy'));
      expect(jsonDecode(requests.single.body), {
        'p_tenant_id': 'tenant',
        'p_legal_entity_id': 'entity',
        'p_branch_id': 'branch',
      });
    },
  );
  test('absent policy remains off version zero', () async {
    response = policy(version: '0', active: false);
    expect((await gateway.readPolicy(scope)).version, BigInt.zero);
  });
  test(
    'configure uses exact eight standard parameters and validates matching receipt',
    () async {
      response = <String, Object?>{
        'command_id': 'command',
        'request_id': 'request',
        'entity': policy(),
      };
      final result = await gateway.configure(command());
      expect(result.isSuccess, true);
      final body = jsonDecode(requests.single.body) as Map;
      expect(body.length, 8);
      expect(body['p_payload'], {'active': true, 'reason': 'approved'});
      expect(body['p_expected_entity_version'], 0);
      expect(body['p_client_timestamp'], '2026-10-03T00:00:00.000Z');
    },
  );
  for (final field in ['command_id', 'request_id', 'entity']) {
    test('malformed $field receipt remains uncertain', () async {
      response = <String, Object?>{
        'command_id': 'command',
        'request_id': 'request',
        'entity': policy(),
      }..[field] = null;
      expect(
        (await gateway.configure(command())).error!.code,
        'UNCERTAIN_RESULT',
      );
    });
  }
  test(
    'confirmed server reason normalization preserves original request bytes',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': policy(),
      };
      final result = await gateway.configure(command(reason: '  approved  '));
      expect(result.isSuccess, isTrue);
      expect(result.entity!.reason, 'approved');
      expect(
        (jsonDecode(requests.single.body)['p_payload'] as Map)['reason'],
        '  approved  ',
      );
    },
  );
  for (final (field, value) in [
    ('tenant_id', 'another-tenant'),
    ('legal_entity_id', 'another-entity'),
    ('id', 'another-policy-command'),
    ('created_by', 'another-actor'),
    ('policy_version', '2'),
    ('active', false),
    ('reason', 'other'),
  ]) {
    test('wrong $field cannot confirm original pending request', () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': policy()..[field] = value,
      };
      expect(
        (await gateway.configure(command())).error!.code,
        'UNCERTAIN_RESULT',
      );
    });
  }
  for (final field in ['tenant_id', 'legal_entity_id']) {
    test('policy read refuses response from another $field', () async {
      response = policy()..[field] = 'another-scope';
      await expectLater(gateway.readPolicy(scope), throwsFormatException);
      response = policy(version: '0', active: false)..[field] = 'another-scope';
      await expectLater(gateway.readPolicy(scope), throwsFormatException);
    });
  }
  test('evidence uses bounded API resource and exact string cursor', () async {
    response = {'items': [], 'next_cursor': null};
    await gateway.evidence(
      scope,
      NegativeStockEvidenceKind.covers,
      after: BigInt.parse('9007199254740993'),
    );
    final body = jsonDecode(requests.single.body);
    expect(body['p_after'], '9007199254740993');
    expect(body['p_resource'], 'covers');
  });
  for (final (sql, message, code) in [
    ('42501', 'capability required', 'PERMISSION_DENIED'),
    ('42501', 'MFA_REQUIRED', 'MFA_REQUIRED'),
    ('42501', 'RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
    ('42501', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
    ('42501', 'ACCESS_DENIED', 'ACCESS_DENIED'),
    ('40001', 'NEGATIVE_STOCK_POLICY_VERSION_CONFLICT', 'VERSION_CONFLICT'),
    ('55000', 'NEGATIVE_STOCK_COST_BASIS_UNKNOWN', 'VALIDATION_ERROR'),
    ('22023', 'NEGATIVE_STOCK_POLICY_INPUT_INVALID', 'VALIDATION_ERROR'),
    ('PGRST003', 'busy', 'UNCERTAIN_RESULT'),
  ]) {
    test('server $message remains typed $code', () async {
      status = 400;
      response = {'code': sql, 'message': message};
      final result = await gateway.configure(command());
      expect(result.error!.code, code);
      if (code == 'VALIDATION_ERROR') {
        expect(result.error!.fieldDetails['policy'], message);
      }
    });
  }
  for (final sql in ['PGRST301', 'PGRST302', 'PGRST303']) {
    test(
      'invalid JWT $sql denies policy and cost reads and configuration',
      () async {
        status = 401;
        response = {'code': sql, 'message': 'JWT authentication failed'};
        final denied = throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'AUTHENTICATION_REQUIRED',
          ),
        );
        await expectLater(gateway.readPolicy(scope), denied);
        await expectLater(
          gateway.evidence(scope, NegativeStockEvidenceKind.deficits),
          denied,
        );
        final result = await gateway.configure(command());
        expect(result.isSuccess, isFalse);
        expect(result.error!.code, 'AUTHENTICATION_REQUIRED');
        expect(result.error!.retryable, isFalse);
        expect(requests, hasLength(3));
      },
    );
  }
  test(
    'current read denial throws typed error, unsupported read contract stays explicit',
    () async {
      status = 403;
      response = {'code': '42501', 'message': 'stock.view required'};
      await expectLater(
        gateway.readPolicy(scope),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
        ),
      );
      status = 200;
      response = [];
      await expectLater(gateway.readPolicy(scope), throwsFormatException);
    },
  );
  test('different actor and missing branch refuse before transport', () async {
    await expectLater(
      gateway.readPolicy(scope.copyWith(actorId: 'replacement')),
      throwsA(isA<DomainError>()),
    );
    final result = await gateway.configure(
      command(
        context: const TenantContext(
          tenantId: 'tenant',
          actorId: 'actor',
          legalEntityId: 'entity',
        ),
      ),
    );
    expect(result.error!.code, 'PERMISSION_DENIED');
    expect(requests, isEmpty);
  });
}
