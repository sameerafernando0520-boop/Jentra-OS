import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const w4Scope = TenantContext(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '10000000-0000-0000-0000-000000000002',
  branchId: '10000000-0000-0000-0000-000000000003',
  actorId: '10000000-0000-0000-0000-000000000004',
);
const w4Id = '20000000-0000-0000-0000-000000000001';
const w4Revision = '30000000-0000-0000-0000-000000000001';
const w4Command = '40000000-0000-0000-0000-000000000001';

/// Fake token and HTTP responses only. Never connects to development Auth.
final class Wave4GatewayHarness {
  late final SupabaseClient client;
  Object response = {};
  int status = 200;
  Completer<void>? gate;
  Future<http.Response?> Function(http.Request)? onRequest;
  final requests = <http.Request>[];
  Future<void> initialize() async {
    client = SupabaseClient(
      'https://wave4.example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': w4Scope.actorId,
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
                'id': w4Scope.actorId,
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
        final special = await onRequest?.call(request);
        if (special != null) return special;
        if (request.url.path.contains('/rpc/')) {
          await gate?.future;
        }
        return http.Response(
          jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@synthetic.test',
      password: 'synthetic-only',
    );
  }

  Map<String, Object?> scope() => {
    'tenant_id': w4Scope.tenantId,
    'legal_entity_id': w4Scope.legalEntityId,
    'branch_id': w4Scope.branchId,
  };
  Map<String, Object?> confirmed(Map<String, Object?> entity) => {
    'request_id': w4Command,
    'command_id': w4Command,
    'correlation_id': w4Command,
    'entity': entity,
    'warnings': [],
  };
  Future<void> dispose() => client.dispose();
}
