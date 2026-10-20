import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '89000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1);

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssurancePeopleGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    status = 200;
    requests.clear();
    response = {
      'members': [
        {'user_id': uid(2), 'label': 'Nadeesha Perera'},
      ],
      'truncated': false,
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
    gateway = SupabaseAssurancePeopleGateway(client);
  });
  tearDown(() => client.dispose());

  test('people are read in scope', () async {
    final p = await gateway.people(scope);
    expect(p.members.single.label, 'Nadeesha Perera');
    expect(requests.single.url.path, endsWith('/rpc/assurance_people'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
    });
  });

  test('an e-mail label and a refusal are reported', () async {
    response = {
      'members': [
        {'user_id': uid(2), 'label': 'someone@example.com'},
      ],
      'truncated': false,
    };
    await expectLater(gateway.people(scope), throwsFormatException);
    status = 403;
    response = {'code': '42501', 'message': 'ASSURANCE_ACCESS_DENIED'};
    await expectLater(
      gateway.people(scope),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
  });
}
