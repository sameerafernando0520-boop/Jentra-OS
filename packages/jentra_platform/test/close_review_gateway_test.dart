import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> reviewSummary() => {
  'id': 'review',
  'tenant_id': 't',
  'legal_entity_id': 'e',
  'branch_id': 'b',
  'version': 1,
  'scope': 'all_entity_branches',
  'status': 'blocked',
  'entity_name': 'Jentra',
  'currency_code': 'LKR',
  'period_id': 'period',
  'period_name': 'September',
  'period_state': 'open',
  'period_version': 2,
  'period_start': '2026-09-01',
  'as_of': '2026-09-25',
  'generated_at': '2026-09-26T00:00:00Z',
  'control_count': 1,
  'difference_count': 1,
  'blocker_count': 1,
  'branch_count': 2,
  'branches': [
    {'id': 'b', 'name': 'Colombo'},
    {'id': 'retired', 'name': 'Retired branch'},
  ],
};
Map<String, Object?> reviewControl() => {
  'id': 'GRNI:b',
  'component_key': 'GRNI:b',
  'kind': 'GRNI',
  'name': 'GRNI · Colombo',
  'branch_id': 'b',
  'currency_code': 'LKR',
  'status': 'difference',
  'subledger_value': '9007199254.740993',
  'gl_value': '9007199254.740990',
  'difference': '0.000003',
  'difference_count': 1,
  'accounts': [
    {'id': 'account', 'code': '2300', 'name': 'Original GRNI'},
  ],
};
void main() {
  const scope = TenantContext(
    tenantId: 't',
    actorId: 'actor',
    legalEntityId: 'e',
    branchId: 'b',
  );
  late SupabaseClient client;
  late SupabaseCloseReviewGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  Map<String, Object?> page(
    String section,
    List<Map<String, Object?>> items, {
    String? key,
    String? cursor,
  }) => {
    'summary': reviewSummary(),
    'section': section,
    'component_key': key,
    'items': items,
    'next_cursor': cursor,
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 26),
    expectedEntityVersion: 0,
    payload: {'id': 'review', 'period_id': 'period', 'as_of': '2026-09-25'},
  );
  setUp(() async {
    status = 200;
    requests.clear();
    response = page('controls', [reviewControl()]);
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
    gateway = SupabaseCloseReviewGateway(client);
  });
  tearDown(() => client.dispose());
  test('scoped generation verifies exact sealed identity', () async {
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': reviewSummary(),
    };
    expect((await gateway.generate(command()))['scope'], 'all_entity_branches');
    expect(jsonDecode(requests.single.body)['p_expected_entity_version'], 0);
    expect(
      requests.single.headers['Content-Profile'] ??
          requests.single.headers['content-profile'],
      'api',
    );
  });
  test(
    'unverifiable generation remains uncertain for identical retry',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {...reviewSummary(), 'period_id': 'other'},
      };
      await expectLater(
        gateway.generate(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'control arithmetic retains tiny differences above JS integer precision',
    () async {
      expect(
        ((await gateway.page(scope, 'review', 'controls'))['items'] as List)
            .single['difference'],
        '0.000003',
      );
    },
  );
  test('numeric JSON and divergent totals are rejected', () async {
    for (final change in [
      {'subledger_value': 9007199254.740993},
      {'difference': '0'},
    ]) {
      response = page('controls', [
        {...reviewControl(), ...change},
      ]);
      await expectLater(
        gateway.page(scope, 'review', 'controls'),
        throwsFormatException,
      );
    }
  });
  test('scope mismatch and false ready summary are rejected', () async {
    for (final change in [
      {'legal_entity_id': 'other'},
      {'status': 'ready'},
      {'branch_count': 1},
    ]) {
      response = {
        ...page('controls', [reviewControl()]),
        'summary': {...reviewSummary(), ...change},
      };
      await expectLater(
        gateway.page(scope, 'review', 'controls'),
        throwsFormatException,
      );
    }
  });
  test(
    'retired entity branch is retained but foreign branch is denied',
    () async {
      response = page('controls', [
        {...reviewControl(), 'branch_id': 'retired'},
      ]);
      await gateway.page(scope, 'review', 'controls');
      response = page('controls', [
        {...reviewControl(), 'branch_id': 'other'},
      ]);
      await expectLater(
        gateway.page(scope, 'review', 'controls'),
        throwsFormatException,
      );
    },
  );
  test('cash bridge is checked independently from total equation', () async {
    final cash = {
      ...reviewControl(),
      'kind': 'CASH',
      'statement_closing': '100',
      'unmatched_bank': '10',
      'unmatched_book': '20',
      'subledger_value': '110',
      'gl_value': '109',
      'difference': '1',
    };
    response = page('controls', [cash]);
    await gateway.page(scope, 'review', 'controls');
    response = page('controls', [
      {...cash, 'statement_closing': '101'},
    ]);
    await expectLater(
      gateway.page(scope, 'review', 'controls'),
      throwsFormatException,
    );
  });
  test(
    'missing immutable command identity and after-cutoff source denied',
    () async {
      final source = {
        'id': 'source',
        'component_key': 'GRNI:b',
        'origin': 'journal',
        'source_type': 'supplier_bill',
        'source_id': 'bill',
        'value': '-0.730000',
        'posting_date': '2026-09-24',
        'command_id': 'command',
      };
      response = page('sources', [source]);
      await gateway.page(scope, 'review', 'sources');
      for (final change in [
        {'command_id': null},
        {'posting_date': '2026-09-26'},
      ]) {
        response = page('sources', [
          {...source, ...change},
        ]);
        await expectLater(
          gateway.page(scope, 'review', 'sources'),
          throwsFormatException,
        );
      }
    },
  );
  test('filtered source response cannot change component', () async {
    response = page('differences', [
      {'id': 'difference', 'component_key': 'AP:b', 'difference': '0.000003'},
    ], key: 'GRNI:b');
    await expectLater(
      gateway.page(scope, 'review', 'differences', componentKey: 'GRNI:b'),
      throwsFormatException,
    );
  });
  test(
    'stable 50-row cursor must exactly advance from requested offset',
    () async {
      response = page('blockers', [
        for (var i = 0; i < 50; i++) {'id': 'issue$i', 'code': 'CHECK_FAILED'},
      ], cursor: '100');
      await gateway.page(scope, 'review', 'blockers', after: '50');
      response = page('blockers', [
        {'id': 'issue', 'code': 'CHECK_FAILED'},
      ], cursor: '100');
      await expectLater(
        gateway.page(scope, 'review', 'blockers', after: '50'),
        throwsFormatException,
      );
    },
  );
  test('invalid cursor and section never send an HTTP request', () async {
    await expectLater(
      gateway.page(scope, 'review', 'sources', after: '50001'),
      throwsFormatException,
    );
    await expectLater(
      gateway.page(scope, 'review', 'sql'),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
  test(
    'recent MFA denial is distinct and clears controller evidence',
    () async {
      status = 403;
      response = {'code': '42501', 'message': 'RECENT_MFA_REQUIRED'};
      await expectLater(
        gateway.reports(scope),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'MFA_REQUIRED'),
        ),
      );
    },
  );
  test('unauthenticated actor scope never issues a read', () async {
    await expectLater(
      gateway.reports(
        const TenantContext(
          tenantId: 't',
          actorId: 'other',
          legalEntityId: 'e',
          branchId: 'b',
        ),
      ),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
}
