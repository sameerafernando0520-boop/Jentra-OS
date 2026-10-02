import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_receivables.dart';
import 'package:jentra_platform/jentra_receivables_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseReceivablesGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  Object? transportFailure;
  var status = 200;
  setUp(() {
    requests.clear();
    response = [];
    transportFailure = null;
    status = 200;
    client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((r) async {
        requests.add(r);
        if (transportFailure != null) throw transportFailure!;
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseReceivablesGateway(client);
  });
  tearDown(() => client.dispose());
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 7),
    expectedEntityVersion: 3,
    payload: {'document_id': 'invoice'},
  );
  test('register scopes all dimensions and uses bounded keyset', () async {
    await gateway.page(
      scope,
      ReceivableKind.invoice,
      cursor: 'after',
      status: 'posted',
    );
    final q = requests.single.url.queryParameters;
    expect(q['tenant_id'], 'eq.tenant');
    expect(q['legal_entity_id'], 'eq.entity');
    expect(q['branch_id'], 'eq.branch');
    expect(q['id'], 'gt.after');
    expect(q['limit'], '51');
    expect(q['status'], 'eq.posted');
    expect(requests.single.headers['accept-profile'], 'api');
  });
  test('missing scope rejects before transport', () async {
    await expectLater(
      gateway.page(scope.copyWith(clearBranch: true), ReceivableKind.invoice),
      throwsA(isA<ReceivableFailure>()),
    );
    expect(requests, isEmpty);
  });
  test('mutation sends persisted envelope unchanged', () async {
    response = {
      'request_id': 'request',
      'command_id': 'command',
      'entity': {'id': 'invoice'},
    };
    final result = await gateway.command('post_sales_invoice', command());
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_command_id'], 'command');
    expect(body['p_idempotency_key'], 'key');
    expect(body['p_expected_entity_version'], 3);
    expect(body['p_client_timestamp'], '2026-09-07T00:00:00.000Z');
    expect(result['request_id'], 'request');
  });
  test('malformed success remains uncertain', () async {
    response = {
      'entity': {'id': 'invoice'},
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>().having((e) => e.definite, 'definite', false),
      ),
    );
  });
  test('version conflict is a definite database rollback', () async {
    status = 409;
    response = {
      'code': '40001',
      'message': 'VERSION_CONFLICT',
      'details': null,
      'hint': null,
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>()
            .having((e) => e.code, 'code', 'VERSION_CONFLICT')
            .having((e) => e.definite, 'definite', true),
      ),
    );
  });
  test('server outage does not release saved command', () async {
    status = 503;
    response = {
      'code': 'PGRST000',
      'message': 'Unavailable',
      'details': null,
      'hint': null,
    };
    await expectLater(
      gateway.command('post_sales_invoice', command()),
      throwsA(
        isA<ReceivableFailure>().having((e) => e.definite, 'definite', false),
      ),
    );
  });
  test('reference and RPC allowlists reject arbitrary resources', () async {
    await expectLater(
      gateway.references(scope, 'memberships'),
      throwsA(isA<ReceivableFailure>()),
    );
    await expectLater(
      gateway.command('delete_tenant', command()),
      throwsA(isA<ReceivableFailure>()),
    );
    expect(requests, isEmpty);
  });
  test('statement transmits exact chosen as-of date and buckets', () async {
    response = {'rows': []};
    await gateway.statement(scope, 'customer', 'USD', '2026-09-06', [
      15,
      30,
      60,
    ]);
    final body = jsonDecode(requests.single.body) as Map;
    expect(body['p_as_of'], '2026-09-06');
    expect(body['p_buckets'], [15, 30, 60]);
  });

  final reads = <String, Future<Object?> Function()>{
    'register': () => gateway.page(scope, ReceivableKind.invoice),
    'document': () => gateway.find(scope, ReceivableKind.invoice, 'invoice'),
    'references': () => gateway.references(scope, 'parties'),
    'statement': () =>
        gateway.statement(scope, 'customer', 'USD', '2026-09-06', [15, 30, 60]),
  };
  test(
    'document lookup is bounded and rejects missing or ambiguous evidence',
    () async {
      response = [];
      await expectLater(
        gateway.find(scope, ReceivableKind.invoice, 'invoice'),
        throwsA(
          isA<ReceivableFailure>().having((e) => e.code, 'code', 'NOT_FOUND'),
        ),
      );
      expect(requests.single.url.queryParameters['limit'], '2');
      response = [
        {'detail': {}},
        {'detail': {}},
      ];
      await expectLater(
        gateway.find(scope, ReceivableKind.invoice, 'invoice'),
        throwsA(
          isA<ReceivableFailure>().having(
            (e) => e.code,
            'code',
            'READ_INVALID',
          ),
        ),
      );
    },
  );
  for (final read in reads.entries) {
    test(
      '${read.key} normalizes permission denial and hides server details',
      () async {
        status = 403;
        response = {
          'code': '42501',
          'message': 'SECRET table and customer identity',
          'details': 'SECRET scope',
          'hint': 'SECRET hint',
        };
        await expectLater(
          read.value(),
          throwsA(
            isA<ReceivableFailure>()
                .having((e) => e.code, 'code', 'PERMISSION_DENIED')
                .having((e) => e.definite, 'definite', true)
                .having(
                  (e) => e.toString(),
                  'public message',
                  isNot(contains('SECRET')),
                ),
          ),
        );
      },
    );
    test(
      '${read.key} normalizes transport uncertainty without private exceptions',
      () async {
        transportFailure = StateError('SECRET socket and customer identity');
        await expectLater(
          read.value(),
          throwsA(
            isA<ReceivableFailure>()
                .having((e) => e.code, 'code', 'READ_UNAVAILABLE')
                .having(
                  (e) => e.toString(),
                  'public message',
                  isNot(contains('SECRET')),
                ),
          ),
        );
      },
    );
  }
  for (final code in ['PGRST301', 'PGRST302', 'PGRST303']) {
    test('$code becomes a fixed authentication read state', () async {
      status = 401;
      response = {
        'code': code,
        'message': 'SECRET token claims',
        'details': null,
        'hint': null,
      };
      await expectLater(
        gateway.page(scope, ReceivableKind.invoice),
        throwsA(
          isA<ReceivableFailure>()
              .having((e) => e.code, 'code', 'AUTHENTICATION_REQUIRED')
              .having(
                (e) => e.toString(),
                'public message',
                isNot(contains('SECRET')),
              ),
        ),
      );
    });
  }
  test('known MFA denial is preserved without private diagnostics', () async {
    status = 403;
    response = {
      'code': 'P0001',
      'message': 'MFA_REQUIRED',
      'details': 'SECRET claims',
      'hint': null,
    };
    await expectLater(
      gateway.references(scope, 'parties'),
      throwsA(
        isA<ReceivableFailure>()
            .having((e) => e.code, 'code', 'MFA_REQUIRED')
            .having(
              (e) => e.toString(),
              'public message',
              isNot(contains('SECRET')),
            ),
      ),
    );
  });
  test('unknown server rejection has a fixed public read state', () async {
    status = 500;
    response = {
      'code': 'PGRST000',
      'message': 'SECRET relation error',
      'details': null,
      'hint': null,
    };
    await expectLater(
      gateway.statement(scope, 'customer', 'USD', '2026-09-06', [15, 30, 60]),
      throwsA(
        isA<ReceivableFailure>()
            .having((e) => e.code, 'code', 'READ_REJECTED')
            .having(
              (e) => e.toString(),
              'public message',
              isNot(contains('SECRET')),
            ),
      ),
    );
  });
  test(
    'malformed statement and register evidence cannot be accepted',
    () async {
      response = [];
      await expectLater(
        gateway.statement(scope, 'customer', 'USD', '2026-09-06', [15, 30, 60]),
        throwsA(
          isA<ReceivableFailure>().having(
            (e) => e.code,
            'code',
            'READ_INVALID',
          ),
        ),
      );
      response = [
        {'detail': 'SECRET malformed object'},
      ];
      await expectLater(
        gateway.page(scope, ReceivableKind.invoice),
        throwsA(
          isA<ReceivableFailure>()
              .having((e) => e.code, 'code', 'READ_INVALID')
              .having(
                (e) => e.toString(),
                'public message',
                isNot(contains('SECRET')),
              ),
        ),
      );
    },
  );
}
