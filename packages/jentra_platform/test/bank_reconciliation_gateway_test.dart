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
  final requests = <http.Request>[];
  setUp(() async {
    requests.clear();
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
    gateway = SupabaseBankReconciliationGateway(client);
  });
  tearDown(() => client.dispose());
  Map<String, Object?> page(Object row) => {
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'resource': 'statement_lines',
    'bank_id': 'bank',
    'items': [row],
    'next_cursor': null,
  };
  test('read uses scoped API RPC with bounded cursor', () async {
    response = page({'id': 's1', 'amount': '9007199254.740993'});
    final r = await gateway.options(
      scope,
      'statement_lines',
      bankId: 'bank',
      after: 'cursor',
    );
    expect((r['items'] as List).length, 1);
    expect(
      requests.single.url.path,
      endsWith('/rpc/bank_reconciliation_options'),
    );
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_branch_id'], 'branch');
    expect(body['p_after'], 'cursor');
  });
  for (final bad in [100.25, '1e3', '0.0000001']) {
    test('rejects non-exact bank row $bad', () async {
      response = page({'id': 's1', 'amount': bad});
      await expectLater(
        gateway.options(scope, 'statement_lines', bankId: 'bank'),
        throwsFormatException,
      );
    });
  }
  test('read rejects scope or bank mismatch even on successful HTTP', () async {
    response = {
      ...page({'id': 's1', 'amount': '1'}),
      'branch_id': 'wrong',
    };
    await expectLater(
      gateway.options(scope, 'statement_lines', bankId: 'bank'),
      throwsFormatException,
    );
    response = {
      ...page({'id': 's1', 'amount': '1'}),
      'bank_id': 'other',
    };
    await expectLater(
      gateway.options(scope, 'statement_lines', bankId: 'bank'),
      throwsFormatException,
    );
  });
  test('rejects inconsistent match and statement balances', () async {
    response = page({
      'id': 'm',
      'statement_total': '0.3',
      'journal_total': '0.2',
      'difference': '0.099999',
    });
    await expectLater(
      gateway.options(scope, 'statement_lines', bankId: 'bank'),
      throwsFormatException,
    );
    response = page({
      'id': 's',
      'opening': '2',
      'closing': '3',
      'total': '0.999999',
    });
    await expectLater(
      gateway.options(scope, 'statement_lines', bankId: 'bank'),
      throwsFormatException,
    );
  });
  test(
    'confirmed command receipt verifies action, scope, exact balances and original request',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'command',
        idempotencyKey: 'key',
        context: scope,
        payload: {
          'action': 'import',
          'id': 'statement',
          'bank_id': 'bank',
          'identity': 'BANK-1',
          'start_date': '2026-09-21',
          'end_date': '2026-09-21',
          'opening': '0',
          'closing': '0.000001',
          'lines': [
            {
              'date': '2026-09-21',
              'reference': 'R',
              'description': 'One micro-unit',
              'amount': '0.000001',
            },
          ],
        },
        expectedEntityVersion: 0,
      );
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {
          'id': 'statement',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'bank_id': 'bank',
          'version': 1,
          'status': 'imported',
          'opening': '0',
          'closing': '0.000001',
          'total': '0.000001',
        },
      };
      await gateway.execute(command);
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_payload']['lines'][0]['amount'], '0.000001');
      expect(body['p_expected_entity_version'], 0);
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {
          'id': 'statement',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'bank_id': 'bank',
          'version': 1,
          'status': 'imported',
          'opening': 0,
          'closing': '0.000001',
          'total': '0.000001',
        },
      };
      await expectLater(
        gateway.execute(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {
          'id': 'statement',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'bank_id': 'wrong',
          'version': 1,
          'status': 'imported',
          'opening': '0',
          'closing': '0.000001',
          'total': '0.000001',
        },
      };
      await expectLater(
        gateway.execute(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'rule receipt accepts canonical exact tolerance and checks bank version',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'rules-command',
        idempotencyKey: 'rules-key',
        context: scope,
        payload: {
          'action': 'rules',
          'id': 'rule-change',
          'bank_id': 'bank',
          'tolerance': '0.25',
          'reason': 'Approved rule change',
        },
        expectedEntityVersion: 7,
      );
      response = {
        'command_id': 'rules-command',
        'request_id': 'request',
        'entity': {
          'id': 'rule-change',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'bank_id': 'bank',
          'version': 1,
          'bank_version': 8,
          'status': 'configured',
          'tolerance': '0.250000',
        },
      };
      await gateway.execute(command);
      ((response as Map)['entity'] as Map)['bank_version'] = 9;
      await expectLater(
        gateway.execute(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
}
