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
  late SupabaseBudgetGateway gateway;
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
    gateway = SupabaseBudgetGateway(client);
  });
  tearDown(() => client.dispose());

  Map<String, Object?> line() => {
    'id': 'line',
    'account_id': 'account',
    'amount': '50.000000',
    'cost_centre_id': null,
    'project_id': null,
  };
  Map<String, Object?> budget() => {
    'id': 'budget',
    'root_id': 'budget',
    'revision': 1,
    'period_id': 'period',
    'budget_year': 2026,
    'budget_branch_id': 'branch',
    'currency_code': 'LKR',
    'status': 'approved',
    'version': 3,
    'reason': 'Approved plan',
    'lines': [line()],
  };
  Map<String, Object?> summary() => {
    'id': 'report',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'budget_id': 'budget',
    'budget_revision': 1,
    'budget_branch_id': 'branch',
    'period_start': '2026-08-01',
    'period_end': '2026-08-31',
    'as_of': '2026-08-31',
    'generated_at': '2026-09-25T00:00:00Z',
    'currency_code': 'LKR',
    'base_currency_code': 'LKR',
    'currency_basis': 'base_all_posted',
    'status': 'generated',
    'version': 1,
    'line_count': 1,
    'journal_count': 2,
    'budget_total': '50.000000',
    'actual_total': '60.000000',
    'variance_total': '10.000000',
    'variance_percent': '20.000000',
  };
  Map<String, Object?> page(String section) => {
    'summary': summary(),
    'section': section,
    'budget_line_id': 'line',
    'items': section == 'lines'
        ? [
            {
              'id': 'line',
              'account_id': 'account',
              'code': '4000',
              'name': 'Revenue',
              'source_count': 2,
              'budget_amount': '50.000000',
              'actual_amount': '60.000000',
              'variance': '10.000000',
              'variance_percent': '20.000000',
            },
          ]
        : [
            {
              'id': 'journal-line',
              'budget_line_id': 'line',
              'journal_entry_id': 'journal',
              'posting_date': '2026-08-12',
              'source_type': 'synthetic',
              'base_debit': '0.000000',
              'base_credit': '60.000000',
              'transaction_debit': '0.000000',
              'transaction_credit': '60.000000',
            },
          ],
    'next_offset': null,
  };

  test(
    'scoped budget page rejects foreign branch and JSON-number amounts',
    () async {
      response = {
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'items': [budget()],
        'next_cursor': null,
      };
      expect((await gateway.budgets(scope))['items'], hasLength(1));
      expect(requests.single.url.path, endsWith('/rpc/budget_options'));
      expect(
        (jsonDecode(requests.single.body) as Map)['p_branch_id'],
        'branch',
      );
      (response as Map)['items'] = [
        {...budget(), 'budget_branch_id': 'other'},
      ];
      await expectLater(gateway.budgets(scope), throwsFormatException);
      (response as Map)['items'] = [
        {
          ...budget(),
          'lines': [
            {...line(), 'amount': 50.0},
          ],
        },
      ];
      await expectLater(gateway.budgets(scope), throwsFormatException);
    },
  );

  test('frozen variance validates totals and branch scope', () async {
    response = {
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'items': [summary()],
      'next_cursor': null,
    };
    expect((await gateway.reports(scope))['items'], hasLength(1));
    (response as Map)['items'] = [
      {...summary(), 'variance_total': '9.999999'},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
    (response as Map)['items'] = [
      {...summary(), 'branch_id': 'other'},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
    (response as Map)['items'] = [
      {...summary(), 'actual_total': 60.0},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
  });

  test('account drill rejects mismatched source and exact drift', () async {
    response = page('journals');
    expect(
      (await gateway.page(
        scope,
        'report',
        'journals',
        budgetLineId: 'line',
      ))['items'],
      hasLength(1),
    );
    final wire = jsonDecode(requests.single.body) as Map;
    expect(wire['p_budget_line_id'], 'line');
    (response as Map)['items'] = [
      {
        ...((page('journals')['items'] as List).single as Map),
        'budget_line_id': 'other',
      },
    ];
    await expectLater(
      gateway.page(scope, 'report', 'journals', budgetLineId: 'line'),
      throwsFormatException,
    );
    response = page('lines');
    (response as Map)['items'] = [
      {
        ...((page('lines')['items'] as List).single as Map),
        'variance': '9.999999',
      },
    ];
    await expectLater(
      gateway.page(scope, 'report', 'lines', budgetLineId: 'line'),
      throwsFormatException,
    );
  });

  test(
    'command receipt checks sealed action and exact canonical amount',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'command',
        idempotencyKey: 'key',
        context: scope,
        expectedEntityVersion: 0,
        payload: {
          'action': 'create',
          'id': 'budget',
          'lines': [
            {...line(), 'amount': '50'},
          ],
          'reason': 'Approved plan',
        },
      );
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {
          ...budget(),
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'status': 'draft',
          'version': 1,
          'line_count': 1,
        },
      };
      expect((await gateway.command(command))['status'], 'draft');
      expect(requests.single.url.path, endsWith('/rpc/budget_command'));
      (response as Map)['entity'] = {
        ...((response as Map)['entity'] as Map),
        'lines': [
          {...line(), 'amount': '50.000001'},
        ],
      };
      await expectLater(
        gateway.command(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );

  test('generation receipt rejects changed budget identity', () async {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      expectedEntityVersion: 0,
      payload: {'id': 'report', 'budget_id': 'budget', 'as_of': '2026-08-31'},
    );
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': summary(),
    };
    expect((await gateway.generate(command))['variance_total'], '10.000000');
    (response as Map)['entity'] = {...summary(), 'budget_id': 'different'};
    await expectLater(
      gateway.generate(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });

  Map<String, Object?> basis(String id, {String? branch}) => {
    'id': id,
    'kind': 'cost_centre',
    'version': 1,
    'code': 'CC-1',
    'name': 'Distribution',
    'tenant_id': scope.tenantId,
    'legal_entity_id': scope.legalEntityId,
    'branch_id': branch,
  };
  Map<String, Object?> dimensionalLine(String id, String cost) => {
    ...line(),
    'id': id,
    'cost_centre_id': cost,
    'dimension_snapshot': {'cost_centre': basis(cost)},
  };
  test(
    'governed budget permits repeated account only for disjoint identities',
    () async {
      final rows = [
        dimensionalLine('line', 'cost-a'),
        dimensionalLine('line-b', 'cost-b'),
      ];
      response = {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'items': [
          {...budget(), 'lines': rows},
        ],
        'next_cursor': null,
      };
      expect(((await gateway.budgets(scope))['items'] as List).length, 1);
      rows[1] = {
        ...rows[1],
        'cost_centre_id': null,
        'dimension_snapshot': null,
      };
      await expectLater(gateway.budgets(scope), throwsFormatException);
    },
  );
  test('budget receipt cannot replace a selected governed identity', () async {
    final rows = [dimensionalLine('line', 'cost-a')];
    final c = CommandEnvelope<Map<String, Object?>>(
      context: scope,
      commandId: 'command',
      idempotencyKey: 'key',
      expectedEntityVersion: 0,
      payload: {'id': 'budget', 'action': 'create', 'lines': rows},
    );
    final confirmed = {
      ...budget(),
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'status': 'draft',
      'version': 1,
      'line_count': 1,
      'lines': rows,
    };
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': confirmed,
    };
    await gateway.command(c);
    confirmed['lines'] = [dimensionalLine('line', 'different')];
    await expectLater(
      gateway.command(c),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test(
    'entity variance retains branch-specific actual attribution without claiming a branch plan',
    () async {
      final r = page('journals');
      r['summary'] = {...summary(), 'budget_branch_id': null};
      r['items'] = [
        {
          ...((r['items'] as List).first as Map),
          'branch_id': 'other-entity-branch',
          'cost_centre_id': 'other-centre',
          'dimension_snapshot': {
            'cost_centre': basis('other-centre', branch: 'other-entity-branch'),
          },
        },
      ];
      response = r;
      await gateway.page(scope, 'report', 'journals', budgetLineId: 'line');
    },
  );
}
