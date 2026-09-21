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
  late SupabaseManualJournalGateway gateway;
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
    gateway = SupabaseManualJournalGateway(client);
  });
  tearDown(() => client.dispose());
  Map<String, Object?> document() => {
    'id': 'journal',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'version': 1,
    'status': 'draft',
    'grand_total': '9007199254.740993',
    'base_total': '9007199254.740993',
    'lines': [
      {
        'line_id': 'line1',
        'account_id': 'a',
        'debit': '9007199254.740993',
        'credit': '0',
        'amount': '9007199254.740993',
        'base_amount': '9007199254.740993',
      },
      {
        'line_id': 'line2',
        'account_id': 'b',
        'debit': '0',
        'credit': '9007199254.740993',
        'amount': '-9007199254.740993',
        'base_amount': '-9007199254.740993',
      },
    ],
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    clientTimestamp: DateTime.utc(2026, 9, 21),
    context: scope,
    expectedEntityVersion: 0,
    payload: {'id': 'journal'},
  );
  Map<String, Object?> receipt() => {
    'command_id': 'command',
    'request_id': 'request',
    'entity': document(),
  };
  test(
    'exact manual journal keeps scaled values beyond binary precision',
    () async {
      response = receipt();
      final d = await gateway.execute('save', command());
      expect(d['grand_total'], '9007199254.740993');
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_expected_entity_version'], 0);
      expect(requests.single.url.path, endsWith('upsert_manual_journal'));
    },
  );
  test(
    'numeric, mismatched totals and missing source lines stay uncertain',
    () async {
      for (final d in [
        {...document(), 'grand_total': 9007199254.740993},
        {...document(), 'base_total': '1'},
        {...document(), 'lines': []},
      ]) {
        response = {...receipt(), 'entity': d};
        await expectLater(
          gateway.execute('save', command()),
          throwsA(
            isA<DomainError>().having(
              (e) => e.code,
              'code',
              'UNCERTAIN_RESULT',
            ),
          ),
        );
      }
    },
  );
  test(
    'wrong scope, identity, version and command are never acknowledged',
    () async {
      for (final d in [
        {...document(), 'branch_id': 'elsewhere'},
        {...document(), 'id': 'other'},
        {...document(), 'version': 2},
      ]) {
        response = {...receipt(), 'entity': d};
        await expectLater(
          gateway.execute('save', command()),
          throwsA(isA<DomainError>()),
        );
      }
      response = {...receipt(), 'command_id': 'other'};
      await expectLater(
        gateway.execute('save', command()),
        throwsA(isA<DomainError>()),
      );
    },
  );
  test('same-side and inconsistent transaction lines are rejected', () async {
    final d = document(), lines = d['lines'] as List;
    (lines[0] as Map)['credit'] = '1';
    response = {...receipt(), 'entity': d};
    await expectLater(
      gateway.execute('save', command()),
      throwsA(isA<DomainError>()),
    );
  });
  test('scoped detail and register paging retain source identity', () async {
    response = document();
    expect((await gateway.detail(scope, 'journal'))['id'], 'journal');
    response = {'items': [], 'next_cursor': 'cursor'};
    await gateway.options(
      scope,
      'reports',
      after: 'previous',
      search: 'accrual',
    );
    final b = jsonDecode(requests.last.body) as Map;
    expect(b['p_branch_id'], 'branch');
    expect(b['p_after'], 'previous');
    expect(b['p_search'], 'accrual');
  });
  test('oversized register rejected', () async {
    response = {'items': List.filled(51, {})};
    await expectLater(gateway.options(scope, 'reports'), throwsFormatException);
  });
  test('balanced response cannot change requested account amounts', () async {
    final base = command();
    final c = CommandEnvelope<Map<String, Object?>>(
      commandId: base.commandId,
      idempotencyKey: base.idempotencyKey,
      clientTimestamp: base.clientTimestamp,
      context: scope,
      expectedEntityVersion: 0,
      payload: {
        'id': 'journal',
        'lines': [
          {'line_id': 'line1', 'account_id': 'a', 'debit': '1', 'credit': '0'},
          {'line_id': 'line2', 'account_id': 'b', 'debit': '0', 'credit': '1'},
        ],
      },
    );
    response = receipt();
    await expectLater(
      gateway.execute('save', c),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test('posted details require ledger evidence', () async {
    response = {
      ...document(),
      'status': 'posted',
      'journal_entry_id': 'j',
      'ledger_lines': [],
    };
    await expectLater(gateway.detail(scope, 'journal'), throwsFormatException);
  });
  test('permission and version failures remain classified', () async {
    for (final pair in [
      ('42501', 'PERMISSION_DENIED'),
      ('40001', 'VERSION_CONFLICT'),
    ]) {
      status = 400;
      response = {'code': pair.$1, 'message': 'failure'};
      await expectLater(
        gateway.execute('save', command()),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', pair.$2)),
      );
    }
  });
  test('wrong actor fails before HTTP', () async {
    const other = TenantContext(
      tenantId: 'tenant',
      actorId: 'other',
      legalEntityId: 'entity',
      branchId: 'branch',
    );
    await expectLater(
      gateway.options(other, 'reports'),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
}
