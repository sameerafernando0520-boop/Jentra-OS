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
  late SupabaseBankReconciliationGateway gateway;
  Object? response;
  int status = 200;
  bool unavailable = false;
  final requests = <http.Request>[];
  setUp(() async {
    requests.clear();
    status = 200;
    unavailable = false;
    response = {};
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
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        if (unavailable) throw StateError('private transport debug');
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
    gateway = SupabaseBankReconciliationGateway(client);
  });
  tearDown(() async {
    await client.dispose();
  });
  for (final item in [
    ('P0001', 'PERMISSION_DENIED', 'PERMISSION_DENIED'),
    ('P0001', 'ACCESS_DENIED', 'ACCESS_DENIED'),
    ('P0001', 'MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
    ('P0001', 'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_REQUIRED'),
    ('42501', 'private database policy', 'PERMISSION_DENIED'),
    ('PGRST301', 'private expired token', 'AUTHENTICATION_REQUIRED'),
    ('PGRST302', 'private absent token', 'AUTHENTICATION_REQUIRED'),
    ('PGRST303', 'private invalid token', 'AUTHENTICATION_REQUIRED'),
    ('22000', 'private rejected input', 'READ_REJECTED'),
    ('XX000', 'private query detail', 'READ_UNAVAILABLE'),
  ]) {
    test('bank option read normalizes ${item.$1} ${item.$2}', () async {
      status = 400;
      response = {
        'code': item.$1,
        'message': item.$2,
        'details': 'private row data',
        'hint': 'private stack',
      };
      await expectLater(
        gateway.options(
          scope,
          'statement_lines',
          bankId: 'bank',
          after: 'cursor',
        ),
        throwsA(
          isA<DomainError>()
              .having((e) => e.code, 'code', item.$3)
              .having((e) => e.message, 'redacted', isNot(contains('private'))),
        ),
      );
      final payload = jsonDecode(requests.single.body) as Map;
      expect(payload['p_tenant_id'], 'tenant');
      expect(payload['p_bank_id'], 'bank');
      expect(payload['p_after'], 'cursor');
    });
  }
  test('malformed or wrong scope bank read is fixed READ_INVALID', () async {
    for (final value in [
      [],
      {
        'tenant_id': 'other',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'resource': 'accounts',
        'bank_id': null,
        'items': [],
      },
    ]) {
      response = value;
      await expectLater(
        gateway.options(scope, 'accounts'),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'READ_INVALID'),
        ),
      );
    }
  });
  test('transport exception never exposes debug data', () async {
    unavailable = true;
    await expectLater(
      gateway.options(scope, 'accounts'),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'READ_UNAVAILABLE')
            .having((e) => e.message, 'redacted', isNot(contains('private'))),
      ),
    );
  });
  test('command error precedence remains existing version conflict', () async {
    status = 400;
    response = {'code': '40001', 'message': 'PERMISSION_DENIED'};
    final command = CommandEnvelope<Map<String, Object?>>(
      context: scope,
      commandId: 'command',
      idempotencyKey: 'key',
      expectedEntityVersion: 0,
      payload: {'action': 'match', 'id': 'match', 'bank_id': 'bank'},
    );
    await expectLater(
      gateway.execute(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
      ),
    );
  });
}
