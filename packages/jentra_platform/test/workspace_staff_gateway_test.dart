import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/jentra_workspace_admin_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const actor = '10000000-0000-0000-0000-000000000001';
const tenant = '20000000-0000-0000-0000-000000000001';
const requestId = '30000000-0000-0000-0000-000000000001';
const role = '40000000-0000-0000-0000-000000000001';

void main() {
  late SupabaseClient client;
  final requests = <http.Request>[];
  var functionStatus = 200;
  Object? functionBody;
  Map<String, Object?> session() {
    final claims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': actor,
              'aal': 'aal1',
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
      'refresh_token': 'synthetic-auth-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': actor,
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
      },
    };
  }

  setUp(() {
    requests.clear();
    functionStatus = 200;
    functionBody = null;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final function = request.url.path.endsWith('/workspace-staff');
        return http.Response(
          jsonEncode(function ? functionBody : session()),
          function ? functionStatus : 200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() async => client.dispose());

  test(
    'username sign-in exchanges the returned refresh credential with Auth',
    () async {
      functionBody = {'refresh_token': 'synthetic-function-refresh'};
      final gateway = SupabaseFoundationGateway(client);
      await gateway.signInWithLogin(
        login: ' Company_Sales ',
        password: 'synthetic-password',
      );
      expect(requests.map((request) => request.url.path), [
        '/functions/v1/workspace-staff',
        '/auth/v1/token',
      ]);
      expect(jsonDecode(requests.first.body), {
        'operation': 'login',
        'username': 'company_sales',
        'password': 'synthetic-password',
      });
      expect(
        jsonDecode(requests.last.body)['refresh_token'],
        'synthetic-function-refresh',
      );
      expect(gateway.currentAssurance(), MfaAssurance.aal1);
    },
  );
  test(
    'existing work-email sign-in still goes directly to Supabase Auth',
    () async {
      await SupabaseFoundationGateway(client).signInWithLogin(
        login: 'owner@example.test',
        password: 'synthetic-password',
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/auth/v1/token');
    },
  );
  test(
    'username login failure is generic and cannot install a session',
    () async {
      functionStatus = 401;
      functionBody = {'code': 'INVALID_CREDENTIALS', 'private': 'secret'};
      await expectLater(
        SupabaseFoundationGateway(
          client,
        ).signInWithLogin(login: 'company_sales', password: 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (error) => error.message,
            'message',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(client.auth.currentUser, isNull);
      expect(requests, hasLength(1));
    },
  );
  test(
    'staff creation uses a separate credential endpoint and confirms its scope',
    () async {
      await client.auth.signInWithPassword(
        email: 'owner@example.test',
        password: 'synthetic',
      );
      requests.clear();
      functionBody = {
        'request_id': requestId,
        'tenant_id': tenant,
        'username': 'company_sales',
        'status': 'active',
        'membership_id': '50000000-0000-0000-0000-000000000001',
        'user_id': '60000000-0000-0000-0000-000000000001',
      };
      await SupabaseWorkspaceStaffGateway(client).create(
        scope: const TenantContext(tenantId: tenant, actorId: actor),
        requestId: requestId,
        username: 'Company_Sales',
        displayName: 'Sales colleague',
        roleIds: {role},
        password: 'synthetic-password-only',
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/functions/v1/workspace-staff');
      expect(jsonDecode(requests.single.body)['role_ids'], [role]);
      expect(client.auth.currentUser!.id, actor);
    },
  );
  test('foreign actor cannot submit credentials', () async {
    await expectLater(
      SupabaseWorkspaceStaffGateway(client).create(
        scope: const TenantContext(tenantId: tenant, actorId: actor),
        requestId: requestId,
        username: 'company_sales',
        displayName: 'Sales colleague',
        roleIds: {role},
        password: 'synthetic-password-only',
      ),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'PERMISSION_DENIED',
        ),
      ),
    );
    expect(requests, isEmpty);
  });
}
