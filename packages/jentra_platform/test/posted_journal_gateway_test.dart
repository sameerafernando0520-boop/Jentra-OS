import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> journalResponse({int count = 2, int after = 0}) => {
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': 'b',
  'journal_id': 'j',
  'after_line': after,
  'journal': {
    'id': 'j',
    'tenant_id': 't',
    'legal_entity_id': 'e',
    'branch_id': 'source-b',
    'branch_name': 'Historical branch',
    'branch_status': 'inactive',
    'document_number': 'J-001',
    'posting_date': '2026-09-20',
    'fiscal_period_id': 'p',
    'status': 'posted',
    'currency_code': 'USD',
    'base_currency_code': 'LKR',
    'exchange_rate': '1.2345678912',
    'rule_version': 1,
    'source_type': 'manual_journal',
    'source_id': 'source',
    'command_id': 'command',
    'request_id': 'request',
    'correlation_id': 'correlation',
    'created_by': 'actor',
    'created_at': '2026-09-20T00:00:00Z',
    'base_debit': '900719925474.099999',
    'base_credit': '900719925474.099999',
    'transaction_debit': '123.456789',
    'transaction_credit': '123.456789',
    'line_count': count,
    'label_basis': 'current_catalogue',
    'stock_cost_access_required': false,
  },
  'items': [
    for (var i = after + 1; i <= count && i <= after + 50; i++)
      {
        'id': 'line-$i',
        'tenant_id': 't',
        'legal_entity_id': 'e',
        'branch_id': 'source-b',
        'journal_entry_id': 'j',
        'line_number': i,
        'account_id': 'account-$i',
        'account_code': '100$i',
        'account_name': 'Accrued freight',
        'account_status': 'retired',
        'currency_code': 'USD',
        'posting_date': '2026-09-20',
        'party_id': null,
        'source_line_id': 'source-line-$i',
        'base_debit': i.isOdd
            ? (count == 2 ? '900719925474.099999' : '0.000001')
            : '0.000000',
        'base_credit': i.isEven
            ? (count == 2 ? '900719925474.099999' : '0.000001')
            : '0.000000',
        'transaction_debit': i.isOdd ? '123.456789' : '0.000000',
        'transaction_credit': i.isEven ? '123.456789' : '0.000000',
        'cost_centre_id': null,
        'project_id': null,
        'dimension_snapshot': null,
      },
  ],
  'next_cursor': count > after + 50 ? after + 50 : null,
};

void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'actor',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late SupabaseClient client;
  late SupabasePostedJournalGateway gateway;
  Object response = {};
  var status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    status = 200;
    requests.clear();
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
    gateway = SupabasePostedJournalGateway(client);
    response = journalResponse();
  });
  tearDown(() async => client.dispose());

  Map header() => (response as Map)['journal'] as Map;
  Map first() => ((response as Map)['items'] as List).first as Map;
  Future<Map<String, Object?>> read() => gateway.page(scope, 'j');

  test(
    'scoped RPC keeps exact amounts, ten-place FX and historical branch',
    () async {
      final r = await read();
      expect((r['journal'] as Map)['base_debit'], '900719925474.099999');
      expect((r['journal'] as Map)['exchange_rate'], '1.2345678912');
      expect(jsonDecode(requests.single.body), {
        'p_tenant_id': 't',
        'p_legal_entity_id': 'e',
        'p_branch_id': 'b',
        'p_journal_id': 'j',
        'p_after_line': 0,
      });
      expect(
        requests.single.url.path,
        endsWith('/rpc/posted_journal_evidence'),
      );
    },
  );
  test('JSON numeric money is rejected', () async {
    first()['base_debit'] = 900719925474.1;
    await expectLater(read(), throwsFormatException);
  });
  test('excess FX precision and nonpositive rate are rejected', () async {
    for (final value in ['1.23456789123', '0', '-1']) {
      header()['exchange_rate'] = value;
      await expectLater(read(), throwsFormatException);
    }
  });
  test('scope substitution and journal relabeling fail', () async {
    for (final key in ['tenant_id', 'legal_entity_id', 'journal_id']) {
      response = journalResponse();
      (response as Map)[key] = 'other';
      await expectLater(read(), throwsFormatException);
    }
    response = journalResponse();
    first()['branch_id'] = 'other';
    await expectLater(read(), throwsFormatException);
  });
  test('unbalanced header and line amount sides fail', () async {
    header()['base_credit'] = '1';
    await expectLater(read(), throwsFormatException);
    response = journalResponse();
    first()['base_credit'] = '1';
    await expectLater(read(), throwsFormatException);
  });
  test('partial first page cannot masquerade as complete journal', () async {
    (response as Map)['items'] = [first()];
    await expectLater(read(), throwsFormatException);
  });
  test('contiguous bounded pages bind validated integer cursor', () async {
    response = journalResponse(count: 102);
    expect((await read())['next_cursor'], 50);
    response = journalResponse(count: 102, after: 50);
    expect((await gateway.page(scope, 'j', afterLine: 50))['next_cursor'], 100);
    (response as Map)['next_cursor'] = '100';
    await expectLater(
      gateway.page(scope, 'j', afterLine: 50),
      throwsFormatException,
    );
  });
  test('duplicate and out-of-order lines cannot be returned', () async {
    final second = ((response as Map)['items'] as List)[1] as Map;
    second['id'] = first()['id'];
    await expectLater(read(), throwsFormatException);
    response = journalResponse();
    first()['line_number'] = 2;
    await expectLater(read(), throwsFormatException);
  });
  test(
    'dimension identity belongs to journal actual branch and frozen version',
    () async {
      first()['cost_centre_id'] = 'cc';
      first()['dimension_snapshot'] = {
        'cost_centre': {
          'id': 'cc',
          'tenant_id': 't',
          'legal_entity_id': 'e',
          'branch_id': 'source-b',
          'kind': 'cost_centre',
          'version': 1,
          'code': 'CC-1',
          'name': 'Original name',
        },
      };
      await read();
      ((first()['dimension_snapshot'] as Map)['cost_centre']
              as Map)['branch_id'] =
          'b';
      await expectLater(read(), throwsFormatException);
    },
  );
  test('invalid cursor and another actor send no RPC', () async {
    await expectLater(
      gateway.page(scope, 'j', afterLine: -1),
      throwsFormatException,
    );
    await expectLater(
      gateway.page(
        const TenantContext(
          tenantId: 't',
          actorId: 'other',
          legalEntityId: 'e',
          branchId: 'b',
        ),
        'j',
      ),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  test('permission and MFA errors retain distinct domain outcomes', () async {
    status = 403;
    response = {'code': '42501', 'message': 'JOURNAL_UNAVAILABLE'};
    await expectLater(
      read(),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    response = {'code': '42501', 'message': 'RECENT_MFA_REQUIRED'};
    await expectLater(
      read(),
      throwsA(isA<DomainError>().having((e) => e.code, 'code', 'MFA_REQUIRED')),
    );
  });
  test('oversized journal and unsupported label basis fail', () async {
    header()['line_count'] = 10001;
    await expectLater(read(), throwsFormatException);
    response = journalResponse();
    header()['label_basis'] = 'historical';
    await expectLater(read(), throwsFormatException);
  });
}
