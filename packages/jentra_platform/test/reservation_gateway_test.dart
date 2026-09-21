import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseReservationGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  setUp(() async {
    requests.clear();
    response = [];
    status = 200;
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
                'created_at': '2026-09-13T00:00:00Z',
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
    gateway = SupabaseReservationGateway(client);
  });
  tearDown(() => client.dispose());
  test('dated reservation report keeps exact UTC cutoff and cursor', () async {
    response = {'items': []};
    await gateway.asOf(scope, '2026-09-19T12:00:00.123456Z', after: 'page2');
    expect(requests.single.url.path, endsWith('/rpc/stock_reservations_as_of'));
    final body = jsonDecode(requests.single.body);
    expect(body['p_as_of'], '2026-09-19T12:00:00.123456Z');
    expect(body['p_after'], 'page2');
  });
  CommandEnvelope<Map<String, Object?>> command({
    TenantContext context = scope,
  }) => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: context,
    clientTimestamp: DateTime.utc(2026, 9, 18),
    expectedEntityVersion: 8,
    payload: {
      'id': 'reservation',
      'mode': 'manual',
      'reason': 'Review complete',
    },
  );
  test('release preserves authenticated scope version and envelope', () async {
    response = {
      'command_id': 'command',
      'request_id': 'request',
      'entity': {
        'id': 'reservation',
        'version': 9,
        'base_quantity': '9007199254.740993',
        'status': 'released',
        'released_at': '2026-09-19T12:00:00Z',
      },
    };
    final result = await gateway.release(command());
    expect(
      requests.single.url.path,
      endsWith('/rpc/release_stock_reservation'),
    );
    final body = jsonDecode(requests.single.body);
    expect(body['p_expected_entity_version'], 8);
    expect(body['p_branch_id'], 'branch');
    expect(body['p_idempotency_key'], 'key');
    expect(result['base_quantity'], '9007199254.740993');
  });
  test('mismatched receipt is uncertain', () async {
    response = {
      'command_id': 'other',
      'request_id': 'request',
      'entity': {'id': 'reservation'},
    };
    await expectLater(
      gateway.release(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test(
    'matching identity without a complete release state stays uncertain',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {'id': 'reservation'},
      };
      await expectLater(
        gateway.release(command()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
    },
  );
  test(
    'receipt cannot silently confirm the wrong mode or next version',
    () async {
      for (final overrides in [
        {'status': 'expired'},
        {'version': 11},
        {'base_quantity': 7},
      ]) {
        response = {
          'command_id': 'command',
          'request_id': 'request',
          'entity': {
            'id': 'reservation',
            'version': 9,
            'status': 'released',
            'base_quantity': '7.000000',
            'released_at': '2026-09-19T12:00:00Z',
            ...overrides,
          },
        };
        await expectLater(
          gateway.release(command()),
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
  test('actor mismatch is rejected before network', () async {
    await expectLater(
      gateway.release(
        command(
          context: const TenantContext(
            tenantId: 'tenant',
            actorId: 'other',
            legalEntityId: 'entity',
            branchId: 'branch',
          ),
        ),
      ),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  test('queue and history use separate scoped cursors', () async {
    response = {'items': []};
    await gateway.queue(scope, filter: 'expired', after: 'cursor');
    await gateway.history(scope, 'reservation', beforeVersion: 4);
    expect(jsonDecode(requests[0].body)['p_filter'], 'expired');
    expect(jsonDecode(requests[0].body)['p_after'], 'cursor');
    expect(jsonDecode(requests[1].body)['p_id'], 'reservation');
    expect(jsonDecode(requests[1].body)['p_before_version'], 4);
  });
  for (final entry in {
    '40001': 'VERSION_CONFLICT',
    '42501': 'PERMISSION_DENIED',
    '55000': 'VALIDATION_ERROR',
    '08006': 'UNCERTAIN_RESULT',
  }.entries) {
    test(
      '${entry.key} distinguishes definite failure from uncertainty',
      () async {
        response = {'code': entry.key, 'message': 'failure'};
        status = 400;
        await expectLater(
          gateway.release(command()),
          throwsA(
            isA<DomainError>().having((e) => e.code, 'code', entry.value),
          ),
        );
      },
    );
  }
}
