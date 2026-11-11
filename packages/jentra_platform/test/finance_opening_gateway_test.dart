import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/finance_opening.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'company',
    legalEntityId: 'entity',
    branchId: 'branch',
    actorId: 'actor',
  );
  const otherActor = TenantContext(
    tenantId: 'company',
    legalEntityId: 'entity',
    branchId: 'branch',
    actorId: 'other-actor',
  );
  late SupabaseClient client;
  late FinanceOpeningGateway gateway;
  late Object response;
  late int statusCode;
  final requests = <http.Request>[];

  setUp(() async {
    requests.clear();
    response = {};
    statusCode = 200;
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
          statusCode,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseFinanceOpeningGateway(client);
  });

  tearDown(() => client.dispose());

  CommandEnvelope<Map<String, Object?>> post() => CommandEnvelope(
    commandId: 'post-command',
    idempotencyKey: 'post-key',
    context: scope,
    expectedEntityVersion: 3,
    clientTimestamp: DateTime.utc(2026, 11, 4, 8),
    payload: {'document_id': 'batch'},
  );

  test(
    'posting sends the stable command and accepts a matching receipt',
    () async {
      response = {
        'request_id': 'request',
        'command_id': 'post-command',
        'entity': {
          'id': 'batch',
          'tenant_id': 'company',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'status': 'posted',
        },
      };
      expect(await gateway.execute('post', post()), response);
      final request = requests.single;
      expect(request.url.path, endsWith('/rpc/post_finance_opening_batch'));
      expect(jsonDecode(request.body), {
        'p_tenant_id': 'company',
        'p_legal_entity_id': 'entity',
        'p_branch_id': 'branch',
        'p_command_id': 'post-command',
        'p_idempotency_key': 'post-key',
        'p_client_timestamp': '2026-11-04T08:00:00.000Z',
        'p_expected_entity_version': 3,
        'p_payload': {'document_id': 'batch'},
      });
    },
  );

  test('a mismatched branch receipt leaves the outcome unconfirmed', () async {
    response = {
      'request_id': 'request',
      'command_id': 'post-command',
      'entity': {
        'id': 'batch',
        'tenant_id': 'company',
        'legal_entity_id': 'entity',
        'branch_id': 'different-branch',
      },
    };
    await expectLater(
      gateway.execute('post', post()),
      throwsA(
        isA<FinanceOpeningFailure>()
            .having((error) => error.code, 'code', 'UNCERTAIN_RESULT')
            .having((error) => error.definite, 'definite', false),
      ),
    );
  });

  test('a request from another actor never reaches the opening API', () async {
    await expectLater(
      gateway.source(otherActor, 'legacy-document'),
      throwsA(
        isA<FinanceOpeningFailure>().having(
          (error) => error.code,
          'code',
          'PERMISSION_DENIED',
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('the database denial is definite and hides the raw message', () async {
    statusCode = 403;
    response = {'code': '42501', 'message': 'private implementation detail'};
    await expectLater(
      gateway.execute('post', post()),
      throwsA(
        isA<FinanceOpeningFailure>()
            .having((error) => error.code, 'code', 'PERMISSION_DENIED')
            .having((error) => error.definite, 'definite', true)
            .having(
              (error) => error.message,
              'message',
              isNot(contains('implementation detail')),
            ),
      ),
    );
  });

  test('structured save validation returns row issues', () async {
    statusCode = 400;
    response = {
      'code': '22023',
      'message': 'OPENING_VALIDATION_FAILED',
      'details': jsonEncode([
        {'row': 3, 'field': 'party_code', 'message': 'Customer is inactive.'},
      ]),
    };
    await expectLater(
      gateway.execute('save', post()),
      throwsA(
        isA<FinanceOpeningFailure>()
            .having((error) => error.code, 'code', 'OPENING_VALIDATION_FAILED')
            .having((error) => error.definite, 'definite', true)
            .having((error) => error.issues.single, 'issue', {
              'row': 3,
              'field': 'party_code',
              'message': 'Customer is inactive.',
            }),
      ),
    );
  });

  for (final (verb, rpc, payload, version) in [
    (
      'request_reversal',
      'prepare_finance_opening_reversal',
      <String, Object?>{
        'id': 'reversal',
        'document_id': 'batch',
        'posting_date': '2026-11-04',
        'reason': 'Wrong source balance',
      },
      0,
    ),
    (
      'transition_reversal',
      'transition_finance_opening_reversal',
      <String, Object?>{
        'document_id': 'reversal',
        'batch_id': 'batch',
        'action': 'approve',
      },
      1,
    ),
    (
      'post_reversal',
      'post_finance_opening_reversal',
      <String, Object?>{'document_id': 'reversal', 'batch_id': 'batch'},
      2,
    ),
  ]) {
    test('$verb binds the reversal receipt to its original batch', () async {
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'reversal-command',
        idempotencyKey: 'reversal-key',
        context: scope,
        expectedEntityVersion: version,
        clientTimestamp: DateTime.utc(2026, 11, 4, 8),
        payload: payload,
      );
      response = {
        'request_id': 'request',
        'command_id': command.commandId,
        'entity': {
          'id': 'reversal',
          'batch_id': 'batch',
          'tenant_id': 'company',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
        },
      };
      await gateway.execute(verb, command);
      expect(requests.single.url.path, endsWith('/rpc/$rpc'));
      final parameters = jsonDecode(requests.single.body) as Map;
      expect(parameters['p_payload'], payload);
      expect(parameters['p_command_id'], command.commandId);
      expect(parameters['p_idempotency_key'], command.idempotencyKey);
      expect(parameters['p_expected_entity_version'], version);

      (response as Map)['entity'] = {
        'id': 'reversal',
        'batch_id': 'another-batch',
        'tenant_id': 'company',
        'legal_entity_id': 'entity',
        'branch_id': 'branch',
      };
      await expectLater(
        gateway.execute(verb, command),
        throwsA(
          isA<FinanceOpeningFailure>().having(
            (error) => error.definite,
            'definite',
            false,
          ),
        ),
      );
    });
  }

  test(
    'a reversal lock refusal preserves its recognizable retry state',
    () async {
      statusCode = 409;
      response = {'code': '55P03', 'message': 'OPENING_REVERSAL_BUSY'};
      await expectLater(
        gateway.execute(
          'post_reversal',
          CommandEnvelope(
            commandId: 'retry',
            idempotencyKey: 'key',
            context: scope,
            clientTimestamp: DateTime.utc(2026, 11, 4),
            expectedEntityVersion: 2,
            payload: <String, Object?>{
              'document_id': 'reversal',
              'batch_id': 'batch',
            },
          ),
        ),
        throwsA(
          isA<FinanceOpeningFailure>()
              .having((error) => error.code, 'code', 'OPENING_REVERSAL_BUSY')
              .having((error) => error.definite, 'definite', true),
        ),
      );
    },
  );
}
