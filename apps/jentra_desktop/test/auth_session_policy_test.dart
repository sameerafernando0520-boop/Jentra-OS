import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/auth/mfa_required_screen.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late ProviderContainer container;
  var assurance = 'aal1';
  var verificationRequests = 0;

  Map<String, Object?> session() {
    final claims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': 'owner',
              'aal': assurance,
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
              if (assurance == 'aal2')
                'amr': [
                  {
                    'method': 'totp',
                    'timestamp':
                        DateTime.now()
                            .subtract(const Duration(hours: 8))
                            .millisecondsSinceEpoch ~/
                        1000,
                  },
                ],
            }),
          ),
        )
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-test-signature',
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': {
        'id': 'owner',
        'aud': 'authenticated',
        'created_at': '2026-11-03T00:00:00Z',
        'app_metadata': <String, Object?>{},
        'user_metadata': <String, Object?>{},
        'factors': [
          {
            'id': 'factor',
            'factor_type': 'totp',
            'status': 'verified',
            'created_at': '2026-11-03T00:00:00Z',
            'updated_at': '2026-11-03T00:00:00Z',
          },
        ],
      },
    };
  }

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.pump();
  }

  Future<void> verify() async {
    await gateway.verifyTotp(factorId: 'factor', code: '123456');
    await settle();
  }

  setUp(() async {
    assurance = 'aal1';
    verificationRequests = 0;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object body;
        if (request.url.path.endsWith('/token')) {
          if (request.url.queryParameters['grant_type'] == 'password') {
            assurance = 'aal1';
          }
          body = session();
        } else if (request.url.path.endsWith('/challenge')) {
          body = {'id': 'challenge', 'expires_at': 2000000000};
        } else if (request.url.path.endsWith('/verify')) {
          verificationRequests++;
          assurance = 'aal2';
          body = session();
        } else if (request.url.path.endsWith('/logout')) {
          body = <String, Object?>{};
        } else {
          throw StateError('Unexpected fixture request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseFoundationGateway(client);
    await gateway.signInWithPassword(
      email: 'owner@example.test',
      password: 'synthetic-password',
    );
    container = ProviderContainer(
      overrides: [foundationGatewayProvider.overrideWithValue(gateway)],
    );
    container.listen(sessionAssuranceProvider, (_, _) {});
    await container.read(authSessionRevisionProvider.future);
    await settle();
  });

  tearDown(() async {
    container.dispose();
    await client.dispose();
  });

  test('new password sign-in needs an authenticator code', () {
    expect(container.read(sessionAssuranceProvider), MfaAssurance.aal1);
    expect(verificationRequests, 0);
  });

  test('verified sign-in survives repeated reads and token refresh', () async {
    await verify();
    expect(container.read(sessionAssuranceProvider), MfaAssurance.aal2);
    for (var interaction = 0; interaction < 3; interaction++) {
      await client.auth.refreshSession();
      await settle();
      expect(container.read(sessionAssuranceProvider), MfaAssurance.aal2);
    }
    expect(verificationRequests, 1);
  });

  test('reopening with a saved verified session needs no new code', () async {
    await verify();
    final persisted = jsonEncode(client.auth.currentSession!.toJson());
    final restored = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        fail('Restoring an unexpired session must not verify MFA again.');
      }),
    );
    addTearDown(restored.dispose);
    await restored.auth.recoverSession(persisted);
    final restoredContainer = ProviderContainer(
      overrides: [
        foundationGatewayProvider.overrideWithValue(
          SupabaseFoundationGateway(restored),
        ),
      ],
    );
    addTearDown(restoredContainer.dispose);
    restoredContainer.listen(sessionAssuranceProvider, (_, _) {});
    await restoredContainer.read(authSessionRevisionProvider.future);
    await restoredContainer.pump();
    expect(restoredContainer.read(sessionAssuranceProvider), MfaAssurance.aal2);
    expect(verificationRequests, 1);
  });

  test(
    'sign-out clears assurance and the next sign-in needs a new code',
    () async {
      await verify();
      await gateway.signOut();
      await settle();
      expect(
        container.read(sessionAssuranceProvider),
        MfaAssurance.unauthenticated,
      );
      await gateway.signInWithPassword(
        email: 'owner@example.test',
        password: 'synthetic-password',
      );
      await settle();
      expect(container.read(sessionAssuranceProvider), MfaAssurance.aal1);
      await verify();
      expect(container.read(sessionAssuranceProvider), MfaAssurance.aal2);
      expect(verificationRequests, 2);
    },
  );

  testWidgets('authenticator prompt explains the policy and clears its code', (
    tester,
  ) async {
    var completed = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(
            body: MfaRequiredScreen(onVerified: () => completed++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verify your sign-in'), findsOneWidget);
    expect(find.textContaining('once after signing in'), findsOneWidget);
    final input = find.byKey(const ValueKey('mfa-authenticator-code'));
    await tester.enterText(input, '123456');
    await tester.ensureVisible(find.text('Verify and continue'));
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(verificationRequests, 1);
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
