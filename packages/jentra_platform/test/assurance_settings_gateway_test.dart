import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '84000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1);

Map<String, Object?> page() => {
  'effective': AssuranceSettings.defaults.toPayload('x')
    ..remove('level')
    ..['source'] = 'default',
  'tenant': null,
  'entity': null,
  'rules': [
    for (final c in assuranceMonitoringRuleCodes)
      {'code': c, 'description': 'Rule $c'},
  ],
};

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssuranceSettingsGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  final body = AssuranceSettings.defaults.toPayload('tenant');
  CommandEnvelope<Map<String, Object?>> command(
    Map<String, Object?> payload, {
    int? version = 0,
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
    response = page();
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
    gateway = SupabaseAssuranceSettingsGateway(client);
  });
  tearDown(() => client.dispose());

  test('settings are read in the selected scope', () async {
    final p = await gateway.settings(scope);
    expect(p.effective.source, 'default');
    expect(p.versionFor('tenant'), 0);
    expect(requests.single.url.path, endsWith('/rpc/assurance_settings'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
    });
  });

  test('an invalid read model is rejected', () async {
    response = {...page(), 'rules': 'nope'};
    await expectLater(gateway.settings(scope), throwsFormatException);
  });

  test('a confirmed write is sent with its version and key', () async {
    response = {
      'level': 'tenant',
      'version': 1,
      'effective': page()['effective'],
    };
    final r = await gateway.saveSettings(command(body));
    expect(r['version'], 1);
    expect(
      requests.single.url.path,
      endsWith('/rpc/assurance_settings_command'),
    );
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_idempotency_key': uid(21),
      'p_payload': body,
      'p_expected_version': 0,
    });
  });

  test('an unconfirmed receipt is an uncertain result', () async {
    response = {'level': 'entity', 'version': 1};
    await expectLater(
      gateway.saveSettings(command(body)),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });

  test('invalid or unversioned settings are never sent', () async {
    await expectLater(
      gateway.saveSettings(command({...body, 'due_soon_days': 0})),
      throwsFormatException,
    );
    await expectLater(
      gateway.saveSettings(command(body, version: null)),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });

  test('settings refusals explain themselves', () {
    for (final (code, message, text) in [
      (
        '22023',
        'ASSURANCE_SETTINGS_INVALID',
        'Check the highlighted settings.',
      ),
      (
        '23505',
        'ASSURANCE_PLAN_REVISION_OPEN',
        'This plan already has an open revision.',
      ),
    ]) {
      expect(
        SupabaseAssuranceGateway.assuranceDenial(
          PostgrestException(message: message, code: code),
        ).message,
        text,
      );
    }
  });
}
