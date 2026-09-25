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
  late SupabasePeriodFxGateway gateway;
  Object response = {};
  int status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    requests.clear();
    response = {};
    status = 200;
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
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabasePeriodFxGateway(client);
  });
  tearDown(() => client.dispose());

  Map<String, Object?> page(String resource, Object item) => {
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'resource': resource,
    'period_id': resource == 'events' ? 'period' : null,
    'items': [item],
    'next_cursor': null,
  };

  test('period read sends scope, resource and cursor', () async {
    response = page('events', {'id': 'event'});
    final result = await gateway.periodOptions(
      scope,
      'events',
      periodId: 'period',
      after: 'cursor',
    );
    expect((result['items'] as List).single, {'id': 'event'});
    expect(
      requests.single.url.path,
      endsWith('/rpc/period_governance_options'),
    );
    final wire = jsonDecode(requests.single.body) as Map;
    expect(wire['p_branch_id'], 'branch');
    expect(wire['p_period_id'], 'period');
    expect(wire['p_after'], 'cursor');
  });

  test('FX read rejects crossed scope and imprecise rates', () async {
    response = {
      ...page('rates', {'id': 'rate', 'rate': '1.12345678901'}),
      'branch_id': 'wrong',
    };
    await expectLater(gateway.fxOptions(scope, 'rates'), throwsFormatException);
    response = page('rates', {'id': 'rate', 'rate': '1.12345678901'});
    await expectLater(gateway.fxOptions(scope, 'rates'), throwsFormatException);
    response = page('rates', {'id': 'rate', 'rate': '1.1234567890'});
    expect((await gateway.fxOptions(scope, 'rates'))['resource'], 'rates');
  });

  test('bounded FX detail rejects numeric open balances', () async {
    response = {
      'tenant_id': 'tenant',
      'legal_entity_id': 'entity',
      'branch_id': 'branch',
      'id': 'run',
      'offset': 0,
      'item_count': 1,
      'snapshot_hash': 'a' * 64,
      'items': [
        {'id': 'open', 'open_amount': 0.1, 'open_base_amount': '0.100000'},
      ],
      'next_offset': null,
    };
    await expectLater(gateway.fxDetail(scope, 'run'), throwsFormatException);
    (response as Map)['items'] = [
      {'id': 'open', 'open_amount': '0.100000', 'open_base_amount': '0.100000'},
    ];
    expect((await gateway.fxDetail(scope, 'run'))['item_count'], 1);
  });

  test(
    'governed command verifies exact source, scope and blocked outcome',
    () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'command',
        idempotencyKey: 'key',
        context: scope,
        payload: {
          'action': 'hard_lock',
          'id': 'event',
          'period_id': 'period',
          'reason': 'Close after review',
        },
        expectedEntityVersion: 2,
      );
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {
          'id': 'event',
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'period_id': 'period',
          'period_version': 2,
          'version': 1,
          'action': 'hard_lock',
          'status': 'blocked',
          'exceptions': [
            {'code': 'UNMATCHED_BANK_JOURNALS'},
          ],
        },
      };
      expect((await gateway.govern(command))['status'], 'blocked');
      expect(
        requests.single.url.path,
        endsWith('/rpc/period_governance_command'),
      );
      (response as Map)['entity']['period_id'] = 'other';
      await expectLater(
        gateway.govern(command),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );

  test('FX receipt rejects wrong run and numeric control delta', () async {
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      payload: {
        'action': 'post',
        'id': 'run',
        'period_id': 'period',
        'currency_code': 'USD',
        'exchange_rate_id': 'rate',
        'as_of': '2026-09-21',
        'reason': 'Period close rate',
      },
      expectedEntityVersion: 0,
    );
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {
        'id': 'run',
        'tenant_id': 'tenant',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
        'period_id': 'period',
        'version': 1,
        'status': 'posted',
        'currency_code': 'USD',
        'control_delta_base': 0.1,
        'exchange_rate': '1.2000000000',
      },
    };
    await expectLater(
      gateway.revalue(command),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
    (response as Map)['entity']['control_delta_base'] = '0.100000';
    expect((await gateway.revalue(command))['status'], 'posted');
  });

  test('recent MFA rejection points to the user-managed factor flow', () async {
    status = 403;
    response = {
      'code': '42501',
      'message': 'RECENT_MFA_REQUIRED',
      'details': null,
      'hint': null,
    };
    final command = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      payload: {
        'action': 'request_reopen',
        'id': 'request',
        'period_id': 'period',
        'reason': 'Review correction',
      },
      expectedEntityVersion: 2,
    );
    await expectLater(
      gateway.govern(command),
      throwsA(
        isA<DomainError>()
            .having((error) => error.code, 'code', 'MFA_REQUIRED')
            .having(
              (error) => error.message,
              'message',
              contains('account security'),
            ),
      ),
    );
  });
}
