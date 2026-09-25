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
  late SupabaseFinancialStatementGateway gateway;
  Object response = {};
  final requests = <http.Request>[];

  setUp(() async {
    response = {};
    requests.clear();
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
        requests.add(request);
        return http.Response(
          jsonEncode(response),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseFinancialStatementGateway(client);
  });
  tearDown(() => client.dispose());

  Map<String, Object?> summary(String kind) => {
    'id': 'report',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'different-permitted-branch',
    'period_id': 'period',
    'period_start': '2026-08-01',
    'period_end': '2026-08-31',
    'comparative_period_id': null,
    'as_of': '2026-08-31',
    'base_currency_code': 'LKR',
    'generated_at': '2026-09-25T00:00:00Z',
    'status': 'generated',
    'version': 1,
    'kind': kind,
    'account_count': 4,
    'journal_count': 10,
    'period_debit': '70.000000',
    'period_credit': '70.000000',
    'closing_debit': '180.000000',
    'closing_credit': '180.000000',
    'difference': '0.000000',
    'revenue': kind == 'profit_loss' ? '50.000000' : null,
    'expenses': kind == 'profit_loss' ? '20.000000' : null,
    'net_profit': kind == 'profit_loss' ? '30.000000' : null,
    'assets': kind == 'balance_sheet' ? '150.000000' : null,
    'liabilities': kind == 'balance_sheet' ? '0.000000' : null,
    'equity': kind == 'balance_sheet' ? '100.000000' : null,
    'current_earnings': kind == 'balance_sheet' ? '50.000000' : null,
  };

  test('period options use authenticated entity, branch and cursor', () async {
    response = {
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'resource': 'periods',
      'items': [
        {
          'id': 'period',
          'name': 'August',
          'start_date': '2026-08-01',
          'end_date': '2026-08-31',
        },
      ],
      'next_cursor': null,
    };
    expect(
      (await gateway.periods(scope, after: 'earlier'))['resource'],
      'periods',
    );
    expect(
      requests.single.url.path,
      endsWith('/rpc/period_governance_options'),
    );
    final wire = jsonDecode(requests.single.body) as Map;
    expect(wire['p_tenant_id'], 'tenant');
    expect(wire['p_branch_id'], 'branch');
    expect(wire['p_after'], 'earlier');
  });

  test(
    'report list accepts entity-wide branch and rejects crossed entity',
    () async {
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'items': [summary('trial_balance')],
        'next_cursor': null,
      };
      expect((await gateway.reports(scope))['items'], hasLength(1));
      (response as Map)['items'] = [
        {...summary('trial_balance'), 'legal_entity_id': 'foreign'},
      ];
      await expectLater(gateway.reports(scope), throwsFormatException);
    },
  );

  test(
    'exact P&L and balance equations reject drift and JSON numbers',
    () async {
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'items': [summary('profit_loss')],
        'next_cursor': null,
      };
      expect((await gateway.reports(scope))['items'], hasLength(1));
      (response as Map)['items'] = [
        {...summary('profit_loss'), 'net_profit': '30.000001'},
      ];
      await expectLater(gateway.reports(scope), throwsFormatException);
      (response as Map)['items'] = [
        {...summary('balance_sheet'), 'assets': 150.0},
      ];
      await expectLater(gateway.reports(scope), throwsFormatException);
      (response as Map)['items'] = [summary('balance_sheet')];
      expect((await gateway.reports(scope))['items'], hasLength(1));
    },
  );

  test('frozen account page validates exact amount and source scope', () async {
    response = {
      'summary': summary('trial_balance'),
      'section': 'accounts',
      'account_id': 'account',
      'items': [
        {
          'id': 'account',
          'account_id': 'account',
          'code': '1000',
          'name': 'Cash',
          'account_type': 'asset',
          'opening_balance': '100.000000',
          'period_debit': '50.000000',
          'period_credit': '20.000000',
          'closing_balance': '130.000000',
          'amount': '130.000000',
          'comparative_amount': '100.000000',
        },
      ],
      'next_offset': null,
    };
    expect(
      (await gateway.page(
        scope,
        'report',
        'accounts',
        accountId: 'account',
      ))['items'],
      hasLength(1),
    );
    final wire = jsonDecode(requests.single.body) as Map;
    expect(wire['p_account_id'], 'account');
    (response as Map)['items'] = [
      {...((response as Map)['items'] as List).single as Map, 'amount': 130.0},
    ];
    await expectLater(
      gateway.page(scope, 'report', 'accounts', accountId: 'account'),
      throwsFormatException,
    );
  });

  test('generation verifies sealed receipt and exact ledger totals', () async {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      payload: {
        'id': 'report',
        'kind': 'trial_balance',
        'period_id': 'period',
        'as_of': '2026-08-31',
        'comparative_period_id': null,
      },
      expectedEntityVersion: 0,
    );
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {...summary('trial_balance'), 'branch_id': 'branch'},
    };
    expect((await gateway.generate(command))['difference'], '0.000000');
    expect(
      requests.single.url.path,
      endsWith('/rpc/generate_financial_statement'),
    );
    final wire = jsonDecode(requests.single.body) as Map;
    expect(wire['p_expected_entity_version'], 0);
    (response as Map)['entity'] = {
      ...summary('trial_balance'),
      'branch_id': 'branch',
      'period_credit': '69.999999',
    };
    await expectLater(
      gateway.generate(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
    (response as Map)['entity'] = summary('trial_balance');
    await expectLater(
      gateway.generate(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
}
