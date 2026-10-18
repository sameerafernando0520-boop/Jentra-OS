import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '80000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), eng = uid(2), finding = uid(3);

Map<String, Object?> overview() => {
  'as_of': DateTime.now().toUtc().toIso8601String().substring(0, 10),
  'response_sla_days': 14,
  'mine': <Object?>[],
  'team': <Object?>[],
  'counts': {'due_soon': 0, 'overdue': 0, 'escalated': 0},
};

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssuranceGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  CommandEnvelope<Map<String, Object?>> respond({bool accept = false}) =>
      CommandEnvelope(
        commandId: uid(20),
        idempotencyKey: uid(21),
        context: scope,
        expectedEntityVersion: 7,
        payload: {
          'action': 'respond',
          'engagement_id': eng,
          'finding_id': finding,
          'response': 'Second signatory enforced',
          'due_date': '2099-01-31',
          'accept_risk': accept,
        },
      );
  setUp(() async {
    status = 200;
    requests.clear();
    response = overview();
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
                    'sub': actor,
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
                'id': actor,
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
    gateway = SupabaseAssuranceGateway(client);
  });
  tearDown(() => client.dispose());

  test('work queue is read in the selected scope', () async {
    final o = await gateway.overview(scope);
    expect(o.mine, isEmpty);
    expect(requests.single.url.path, endsWith('/rpc/assurance_overview'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
    });
  });

  test('another actor cannot use the gateway for this scope', () async {
    final foreign = TenantContext(
      tenantId: scope.tenantId,
      actorId: uid(99),
      legalEntityId: scope.legalEntityId,
      branchId: scope.branchId,
    );
    await expectLater(
      gateway.overview(foreign),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    expect(requests, isEmpty);
  });

  test('server denials map to the client contract', () async {
    for (final (code, message, expected) in [
      ('42501', 'ASSURANCE_RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
      ('42501', 'Permission denied', 'PERMISSION_DENIED'),
      ('40001', 'ASSURANCE_VERSION_CONFLICT', 'VERSION_CONFLICT'),
      ('55000', 'ASSURANCE_TRANSITION_INVALID', 'VALIDATION_ERROR'),
      ('P0002', 'ASSURANCE_FINDING_NOT_FOUND', 'NOT_FOUND'),
      ('57014', 'canceling statement', 'UNCERTAIN_RESULT'),
    ]) {
      status = 400;
      response = {'code': code, 'message': message};
      await expectLater(
        gateway.overview(scope),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
        reason: code,
      );
    }
  });

  test(
    'respond sends the sealed key and version and verifies the receipt',
    () async {
      final c = respond();
      response = {
        'engagement_id': eng,
        'version': 8,
        'status': 'fieldwork',
        'action': 'respond',
        'aggregate_type': 'finding',
        'aggregate_id': finding,
        'to_status': 'remediating',
      };
      await gateway.respond(c);
      final body = jsonDecode(requests.single.body) as Map;
      expect(requests.single.url.path, endsWith('/rpc/assurance_command'));
      expect(body['p_idempotency_key'], uid(21));
      expect(body['p_expected_version'], 7);
      expect(body['p_payload'], c.payload);
    },
  );

  test('a receipt that does not match the request is uncertain', () async {
    for (final bad in [
      {'aggregate_id': uid(4)},
      {'version': 9},
      {'to_status': 'risk_pending'},
    ]) {
      response = {
        'engagement_id': eng,
        'version': 8,
        'status': 'fieldwork',
        'action': 'respond',
        'aggregate_type': 'finding',
        'aggregate_id': finding,
        'to_status': 'remediating',
        ...bad,
      };
      await expectLater(
        gateway.respond(respond()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
        reason: '$bad',
      );
    }
  });

  test('invalid responses are rejected before sending', () async {
    final c = respond();
    await expectLater(
      gateway.respond(
        CommandEnvelope(
          commandId: c.commandId,
          idempotencyKey: c.idempotencyKey,
          context: scope,
          expectedEntityVersion: 7,
          payload: {...c.payload, 'status': 'closed'},
        ),
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
}
