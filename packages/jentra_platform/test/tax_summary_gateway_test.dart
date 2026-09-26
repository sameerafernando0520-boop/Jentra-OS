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
  late SupabaseTaxSummaryGateway gateway;
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
    gateway = SupabaseTaxSummaryGateway(client);
  });
  tearDown(() => client.dispose());

  Map<String, Object?> summary() => {
    'id': 'report',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'branch_filter_id': 'branch',
    'period_id': 'period',
    'period_start': '2026-09-01',
    'period_end': '2026-09-30',
    'as_of': '2026-09-25',
    'generated_at': '2026-09-26T00:00:00Z',
    'base_currency_code': 'LKR',
    'status': 'blocked',
    'version': 1,
    'notice': 'NON-CERTIFIED • STATUTORY REVIEW REQUIRED',
    'line_count': 2,
    'blocked_count': 1,
    'blockers': [
      {
        'source_type': 'supplier_bill',
        'source_id': 'bill',
        'source_line_id': 'old-line',
        'code': 'MISSING_DEFINITION_VERSION',
      },
    ],
    'output_tax_base': '0.000000',
    'input_tax_base': '45.050000',
    'withholding_tax_base': '0.000000',
    'zero_taxable_base': '0.000000',
    'exempt_taxable_base': '0.000000',
    'unverified_tax_base': '45.050000',
  };

  Map<String, Object?> line() => {
    'source_type': 'supplier_bill',
    'source_id': 'bill',
    'source_line_id': 'line',
    'branch_id': 'branch',
    'journal_entry_id': 'journal',
    'posting_date': '2026-09-13',
    'currency_code': 'LKR',
    'base_currency_code': 'LKR',
    'definition_id': 'definition',
    'definition_version': '1',
    'tax_code': 'INPUT18',
    'tax_kind': 'input',
    'tax_rate': '18.000000',
    'taxable_amount': '250.250000',
    'tax_amount': '45.050000',
    'taxable_base': '250.250000',
    'tax_base': '45.050000',
    'expected_tax_base': '45.050000',
    'review_code': null,
    'journal_lines': [
      {
        'id': 'journal-line',
        'journal_entry_id': 'journal',
        'account_id': 'tax-asset',
        'transaction_debit': '45.050000',
        'transaction_credit': '0.000000',
        'base_debit': '45.050000',
        'base_credit': '0.000000',
      },
    ],
  };

  test('report list keeps branch and statutory blocker contract', () async {
    response = {
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'items': [summary()],
      'next_cursor': null,
    };
    expect((await gateway.reports(scope))['items'], hasLength(1));
    expect(requests.single.url.path, endsWith('/rpc/tax_summary_reports'));
    expect((jsonDecode(requests.single.body) as Map)['p_branch_id'], 'branch');
    (response as Map)['items'] = [
      {...summary(), 'branch_id': 'other'},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
    (response as Map)['items'] = [
      {...summary(), 'input_tax_base': 45.05},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
    (response as Map)['items'] = [
      {...summary(), 'notice': 'Certified'},
    ];
    await expectLater(gateway.reports(scope), throwsFormatException);
  });

  test('source drill preserves journal lineage and bounded filter', () async {
    response = {
      'summary': summary(),
      'items': [line()],
      'next_offset': null,
    };
    expect(
      (await gateway.page(scope, 'report', sourceLineId: 'line'))['items'],
      hasLength(1),
    );
    expect(
      (jsonDecode(requests.single.body) as Map)['p_source_line_id'],
      'line',
    );
    (response as Map)['items'] = [
      {...line(), 'source_line_id': 'foreign'},
    ];
    await expectLater(
      gateway.page(scope, 'report', sourceLineId: 'line'),
      throwsFormatException,
    );
    (response as Map)['items'] = [
      {
        ...line(),
        'journal_lines': [
          {
            ...(line()['journal_lines'] as List).single as Map,
            'base_debit': 45.05,
          },
        ],
      },
    ];
    await expectLater(gateway.page(scope, 'report'), throwsFormatException);
  });

  test('generation rejects a changed sealed request', () async {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      expectedEntityVersion: 0,
      payload: {
        'id': 'report',
        'period_id': 'period',
        'as_of': '2026-09-25',
        'branch_filter_id': 'branch',
      },
    );
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': summary(),
    };
    expect((await gateway.generate(command))['status'], 'blocked');
    (response as Map)['entity'] = {...summary(), 'as_of': '2026-09-24'};
    await expectLater(
      gateway.generate(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });

  test(
    'tax-control drill checks cumulative arithmetic and scoped frozen filters',
    () async {
      final account = <String, Object?>{
        'id': 'tax-asset',
        'account_id': 'tax-asset',
        'code': '1450',
        'name': 'Input tax control',
        'account_type': 'asset',
        'source_opening_base': '10.000000',
        'gl_opening_base': '10.000000',
        'source_period_base': '22.520000',
        'gl_period_base': '22.530000',
        'source_closing_base': '32.520000',
        'gl_closing_base': '32.530000',
        'difference': '-0.010000',
      };
      final frozen = {
        ...summary(),
        'version': 2,
        'controls': [account],
        'control_status': 'blocked',
        'control_source_count': 3,
        'control_journal_count': 4,
        'control_difference_count': 1,
        'control_review_count': 0,
        'control_unassigned_source_count': 0,
        'unattributed_journal_count': 1,
        'control_source_base': '32.520000',
        'control_gl_base': '32.530000',
        'control_difference': '-0.010000',
      };
      response = {
        'summary': frozen,
        'section': 'controls',
        'account_filter_id': 'tax-asset',
        'evidence_key': null,
        'items': [account],
        'next_offset': null,
      };
      expect(
        (await gateway.controls(
          scope,
          'report',
          'controls',
          accountId: 'tax-asset',
        ))['items'],
        hasLength(1),
      );
      expect(requests.single.url.path, endsWith('/rpc/tax_control_page'));
      (response as Map)['items'] = [
        {...account, 'source_closing_base': '32.530000'},
      ];
      await expectLater(
        gateway.controls(scope, 'report', 'controls', accountId: 'tax-asset'),
        throwsFormatException,
      );
      (response as Map)['items'] = [account];
      (response as Map)['summary'] = {...frozen, 'control_gl_base': 32.53};
      await expectLater(
        gateway.controls(scope, 'report', 'controls', accountId: 'tax-asset'),
        throwsFormatException,
      );
      (response as Map)['summary'] = frozen;
      (response as Map)['account_filter_id'] = 'other';
      await expectLater(
        gateway.controls(scope, 'report', 'controls', accountId: 'tax-asset'),
        throwsFormatException,
      );
    },
  );

  test(
    'unattributed tax difference retains exact source key and cannot drift',
    () async {
      final frozen = {
        ...summary(),
        'version': 2,
        'controls': <Object?>[],
        'control_status': 'blocked',
        'control_source_count': 1,
        'control_journal_count': 1,
        'control_difference_count': 1,
        'control_review_count': 1,
        'control_unassigned_source_count': 1,
        'unattributed_journal_count': 0,
        'control_source_base': '0.000000',
        'control_gl_base': '0.000000',
        'control_difference': '0.000000',
      };
      const key = 'supplier_bill:bill:missing-line';
      final difference = {
        'id': 'unassigned:$key',
        'account_id': null,
        'evidence_key': key,
        'expected_base': '45.050000',
        'posted_base': '0.000000',
        'difference': '45.050000',
      };
      response = {
        'summary': frozen,
        'section': 'control_differences',
        'account_filter_id': null,
        'evidence_key': key,
        'items': [difference],
        'next_offset': null,
      };
      expect(
        (await gateway.controls(
          scope,
          'report',
          'control_differences',
          evidenceKey: key,
        ))['items'],
        hasLength(1),
      );
      (response as Map)['items'] = [
        {...difference, 'difference': '45.040000'},
      ];
      await expectLater(
        gateway.controls(
          scope,
          'report',
          'control_differences',
          evidenceKey: key,
        ),
        throwsFormatException,
      );
      final sent = requests.length;
      await expectLater(
        gateway.controls(scope, 'report', 'unknown'),
        throwsFormatException,
      );
      expect(requests, hasLength(sent));
    },
  );
}
