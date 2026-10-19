import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '82000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), member = uid(2);

Map<String, Object?> access() => {
  'can_manage': true,
  'roles': <Object?>[],
  'members': [
    {
      'membership_id': member,
      'label': 'Nadeesha Perera',
      'linked': true,
      'version': 3,
      'assignments': <Object?>[],
    },
  ],
  'next_cursor': null,
};

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssuranceAccessGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  final grant = {
    'membership_id': member,
    'role_code': 'assurance_auditor',
    'granted': true,
    'scope': 'entity',
  };
  CommandEnvelope<Map<String, Object?>> command(
    Map<String, Object?> payload, {
    int? version = 3,
  }) => CommandEnvelope(
    commandId: uid(20),
    idempotencyKey: uid(21),
    context: scope,
    expectedEntityVersion: version,
    payload: payload,
  );
  setUp(() async {
    status = 200;
    requests.clear();
    response = access();
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
    gateway = SupabaseAssuranceAccessGateway(client);
  });
  tearDown(() => client.dispose());

  test('access is read in the selected scope with a cursor', () async {
    final a = await gateway.access(scope, after: uid(5));
    expect(a.members.single.label, 'Nadeesha Perera');
    expect(requests.single.url.path, endsWith('/rpc/assurance_access'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_after': uid(5),
    });
  });

  test('an invalid read model is rejected', () async {
    response = {...access(), 'members': 'nope'};
    await expectLater(gateway.access(scope), throwsFormatException);
  });

  test('a confirmed grant is sent with its version and key', () async {
    response = {...grant, 'version': 4};
    final r = await gateway.setRole(command(grant));
    expect(r['version'], 4);
    expect(requests.single.url.path, endsWith('/rpc/assurance_set_role'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_idempotency_key': uid(21),
      'p_payload': grant,
      'p_expected_version': 3,
    });
  });

  test('an unconfirmed receipt is an uncertain result', () async {
    response = {...grant, 'version': 9};
    await expectLater(
      gateway.setRole(command(grant)),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });

  test('invalid or unversioned changes are never sent', () async {
    await expectLater(
      gateway.setRole(command({...grant, 'extra': 1})),
      throwsFormatException,
    );
    await expectLater(
      gateway.setRole(command(grant, version: null)),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });

  test('server refusals map to the client contract', () async {
    for (final (code, message, expected) in [
      ('42501', 'ASSURANCE_RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
      ('42501', 'Permission denied', 'PERMISSION_DENIED'),
      ('40001', 'ASSURANCE_VERSION_CONFLICT', 'VERSION_CONFLICT'),
      ('22023', 'ASSURANCE_ROLE_UNKNOWN', 'VALIDATION_ERROR'),
      ('P0002', 'ASSURANCE_ASSIGNMENT_NOT_FOUND', 'NOT_FOUND'),
    ]) {
      status = 400;
      response = {'code': code, 'message': message};
      await expectLater(
        gateway.setRole(command(grant)),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
      );
    }
  });

  test('access-specific refusals explain themselves', () {
    expect(
      SupabaseAssuranceGateway.assuranceDenial(
        const PostgrestException(
          message: 'ASSURANCE_ROLE_UNKNOWN',
          code: '22023',
        ),
      ).message,
      'Only assurance roles can be given here.',
    );
    expect(
      SupabaseAssuranceGateway.assuranceDenial(
        const PostgrestException(
          message: 'ASSURANCE_ASSIGNMENT_NOT_FOUND',
          code: 'P0002',
        ),
      ).message,
      'That role is no longer assigned. Refresh access.',
    );
  });
}
