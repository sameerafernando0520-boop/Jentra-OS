import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_sales/src/data/sales_gateway.dart';
import 'package:jentra_sales/src/data/sales_store.dart';
import 'package:jentra_sales/src/models.dart';
import 'package:jentra_sales/src/field_sales_controller.dart';
import 'package:jentra_sales/src/sales_controller.dart';

import 'support/field_sales_fixture.dart';

AuthResponse response() {
  final user = User(
    id: 'rep',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-10-31T00:00:00Z',
  );
  return AuthResponse(
    user: user,
    session: Session(
      accessToken: 'synthetic',
      refreshToken: 'synthetic',
      tokenType: 'bearer',
      user: user,
      expiresIn: 3600,
    ),
  );
}

class _Account implements SalesAccountGateway {
  final login = Completer<void>();
  int logouts = 0;
  @override
  Future<void> signIn(String email, String password) => login.future;
  @override
  Future<void> signOut() async {
    logouts++;
  }
}

void main() {
  group('Admin-created Sales credentials', () {
    late SupabaseClient client;
    final requests = <http.Request>[];
    var functionStatus = 200;
    setUp(() {
      requests.clear();
      functionStatus = 200;
      client = SupabaseClient(
        'https://example.test',
        'synthetic-public',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final isFunction = request.url.path.endsWith('/workspace-staff');
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': '10000000-0000-0000-0000-000000000001',
                    'exp':
                        DateTime.now()
                            .add(const Duration(hours: 1))
                            .millisecondsSinceEpoch ~/
                        1000,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode(
              isFunction
                  ? functionStatus == 200
                        ? {'refresh_token': 'synthetic-function-refresh'}
                        : {'code': 'INVALID_CREDENTIALS'}
                  : {
                      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
                      'refresh_token': 'synthetic-auth-refresh',
                      'expires_in': 3600,
                      'token_type': 'bearer',
                      'user': {
                        'id': '10000000-0000-0000-0000-000000000001',
                        'aud': 'authenticated',
                        'created_at': '2026-11-03T00:00:00Z',
                        'app_metadata': <String, Object?>{},
                        'user_metadata': <String, Object?>{},
                      },
                    },
            ),
            isFunction ? functionStatus : 200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    });
    tearDown(() async => client.dispose());

    test('username authenticates through the staff endpoint and installs its session', () async {
      final account = SupabaseSalesAccountGateway(
        client,
        enableCandidate: true,
      );
      await account.signIn(' Company_Sales ', 'synthetic-password');
      expect(requests.map((request) => request.url.path), [
        '/functions/v1/workspace-staff',
        '/auth/v1/token',
      ]);
      expect(jsonDecode(requests.first.body), {
        'operation': 'login',
        'username': 'company_sales',
        'password': 'synthetic-password',
      });
      expect(requests.last.url.queryParameters['grant_type'], 'refresh_token');
      expect(
        jsonDecode(requests.last.body)['refresh_token'],
        'synthetic-function-refresh',
      );
      expect(client.auth.currentSession, isNotNull);
      await account.signOut();
      expect(client.auth.currentSession, isNull);
    });

    test('existing work email still signs in directly through Auth', () async {
      await SupabaseSalesAccountGateway(
        client,
        enableCandidate: true,
      ).signIn(' owner@example.test ', 'synthetic-password');
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/auth/v1/token');
      expect(requests.single.url.queryParameters['grant_type'], 'password');
      expect(jsonDecode(requests.single.body)['email'], 'owner@example.test');
      expect(client.auth.currentSession, isNotNull);
    });

    test('rejected staff credentials cannot install a session', () async {
      functionStatus = 401;
      await expectLater(
        SupabaseSalesAccountGateway(
          client,
          enableCandidate: true,
        ).signIn('company_sales', 'wrong'),
        throwsA(
          isA<SalesFailure>().having(
            (error) => error.code,
            'code',
            'SIGN_IN_FAILED',
          ),
        ),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/functions/v1/workspace-staff');
      expect(client.auth.currentSession, isNull);
    });
  });
  test(
    'late credential completion is cleaned up and cannot overlap a new attempt',
    () async {
      final login = Completer<AuthResponse>();
      bool installed = false;
      int calls = 0;
      final account = SupabaseSalesAccountGateway.withAuth(
        enableCandidate: true,
        signInTimeout: const Duration(milliseconds: 5),
        signIn: (_, _) {
          calls++;
          return login.future;
        },
        signOut: () async {
          installed = false;
        },
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having(
            (e) => e.code,
            'code',
            'CONNECTION_UNAVAILABLE',
          ),
        ),
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having((e) => e.code, 'code', 'SIGN_IN_PENDING'),
        ),
      );
      expect(calls, 1);
      installed = true;
      login.complete(response());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(installed, isFalse);
    },
  );
  test(
    'leaving while sign-in is pending cannot reopen a governed workspace',
    () async {
      final account = _Account(),
          store = MemorySalesStore(),
          gateway = FakeFieldSalesGateway();
      final field = FieldSalesController(gateway: gateway, store: store);
      addTearDown(field.dispose);
      final c = SalesController(store: store, account: account, field: field);
      addTearDown(c.dispose);
      final login = c.signIn('synthetic@sales.invalid', 'synthetic');
      await c.leave();
      account.login.complete();
      await login;
      expect(field.isOpen, isFalse);
      expect(field.customers, isEmpty);
      expect(c.preview, isFalse);
      expect(account.logouts, greaterThanOrEqualTo(1));
    },
  );
  test(
    'default account mode clears the session and retains rollout-pending state',
    () async {
      var signedOut = false;
      final account = SupabaseSalesAccountGateway.withAuth(
        signIn: (_, _) async => response(),
        signOut: () async {
          signedOut = true;
        },
      );
      await expectLater(
        account.signIn('synthetic@sales.invalid', 'synthetic'),
        throwsA(
          isA<SalesFailure>().having(
            (e) => e.code,
            'code',
            'FIELD_SALES_ROLLOUT_PENDING',
          ),
        ),
      );
      expect(signedOut, isTrue);
    },
  );
}
