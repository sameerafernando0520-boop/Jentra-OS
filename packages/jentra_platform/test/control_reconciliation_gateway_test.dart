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
  late SupabaseControlReconciliationGateway gateway;
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
    gateway = SupabaseControlReconciliationGateway(client);
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
    'branch_name': 'Colombo',
    'kind': 'AR',
    'item_count': 1,
    'difference_count': 1,
    'status': 'generated',
    'version': 1,
    'subledger_value': '9007199254.740993',
    'gl_value': '9007199254.740990',
    'difference': '0.000003',
    'accounts': [
      {
        'id': 'account',
        'code': '1100',
        'name': 'AR control',
        'subledger_value': '9007199254.740993',
        'gl_value': '9007199254.740990',
        'difference': '0.000003',
      },
    ],
  };
  CommandEnvelope<Map<String, Object?>> command({bool reverse = false}) =>
      CommandEnvelope(
        commandId: 'command',
        idempotencyKey: 'key',
        context: scope,
        clientTimestamp: DateTime.utc(2026, 9, 21),
        expectedEntityVersion: reverse ? null : 0,
        payload: reverse
            ? {
                'allocation_id': 'allocation',
                'posting_date': '2026-09-21',
                'reason': 'Correct the target invoice',
              }
            : {'id': 'report', 'kind': 'AR', 'as_of': '2026-09-20'},
      );
  Object confirmation(Map<String, Object?> entity) => {
    'command_id': 'command',
    'request_id': 'request',
    'entity': entity,
  };
  final uncertain = throwsA(
    isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
  );
  test(
    'exact values beyond binary precision and canonical branch scope survive',
    () async {
      response = confirmation(summary());
      expect((await gateway.generate(command()))['difference'], '0.000003');
      final body = jsonDecode(requests.single.body);
      expect(body['p_branch_id'], 'branch');
      expect(body['p_expected_entity_version'], 0);
      expect(body['p_payload'], command().payload);
    },
  );
  test(
    'scope, kind, date, account totals and JSON numeric mismatch retain uncertain outcome',
    () async {
      for (final change in [
        {'id': 'other'},
        {'branch_id': 'other'},
        {'kind': 'AP'},
        {'as_of': '2026-09-19'},
        {'subledger_value': '9007199254.740992'},
        {'difference': 0.000003},
        {
          'accounts': [
            {
              'id': 'account',
              'code': '1100',
              'name': 'AR',
              'subledger_value': '1',
              'gl_value': '1',
              'difference': '0',
            },
          ],
        },
      ]) {
        response = confirmation({...summary(), ...change});
        await expectLater(gateway.generate(command()), uncertain);
      }
    },
  );
  test('invalid success receipt remains uncertain', () async {
    response = {'entity': summary()};
    await expectLater(gateway.generate(command()), uncertain);
    response = [];
    await expectLater(gateway.generate(command()), uncertain);
  });
  test('report pages enforce identity and decimal evidence', () async {
    response = {
      'summary': summary(),
      'section': 'journals',
      'evidence_key': 'account',
      'items': [
        {'id': 'line', 'value': '0.000001'},
      ],
      'next_cursor': '50',
    };
    expect(
      (await gateway.page(
        scope,
        'report',
        'journals',
        accountId: 'account',
      ))['next_cursor'],
      '50',
    );
    expect(jsonDecode(requests.last.body)['p_evidence_key'], 'account');
    (response as Map)['evidence_key'] = 'foreign';
    await expectLater(
      gateway.page(scope, 'report', 'journals', accountId: 'account'),
      throwsFormatException,
    );
    (response as Map)['evidence_key'] = 'account';
    (response as Map)['items'] = [
      {'id': 'line', 'value': 0.1},
    ];
    await expectLater(
      gateway.page(scope, 'report', 'journals', accountId: 'account'),
      throwsFormatException,
    );
  });
  test('invalid cursor and ledger kind never reach network', () async {
    await expectLater(
      gateway.page(scope, 'report', 'items', after: '-1'),
      throwsFormatException,
    );
    expect(
      () => gateway.reverse('bad', command(reverse: true)),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test('reversal uses selected governed RPC and exact confirmation', () async {
    final r = {
      'id': 'reversal',
      'allocation_id': 'allocation',
      'posting_date': '2026-09-21',
      'reason': 'Correct the target invoice',
      'source_residual': {'amount': '-1', 'base_amount': '-300.01'},
      'target_residual': {'amount': '1', 'base_amount': '299.99'},
    };
    for (final kind in ['AR', 'AP']) {
      response = confirmation(r);
      await gateway.reverse(kind, command(reverse: true));
      expect(
        requests.last.url.path,
        endsWith(
          kind == 'AR'
              ? 'reverse_customer_allocation'
              : 'reverse_supplier_allocation',
        ),
      );
    }
    response = confirmation({...r, 'allocation_id': 'other'});
    await expectLater(gateway.reverse('AR', command(reverse: true)), uncertain);
  });
  test(
    'permission rejection is definite while server failure is uncertain',
    () async {
      status = 403;
      response = {'code': '42501', 'message': 'denied'};
      await expectLater(
        gateway.generate(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
        ),
      );
      status = 500;
      response = {'code': 'XX000', 'message': 'failure'};
      await expectLater(gateway.generate(command()), uncertain);
    },
  );
  test('mismatched authenticated actor sends no request', () async {
    await expectLater(
      gateway.reports(
        const TenantContext(
          tenantId: 'tenant',
          actorId: 'other',
          legalEntityId: 'entity',
          branchId: 'branch',
        ),
      ),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    expect(requests, isEmpty);
  });
}
