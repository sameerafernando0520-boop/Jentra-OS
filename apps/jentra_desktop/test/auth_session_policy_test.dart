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
  var failFactorLoad = false;
  var loseEnrollmentResponse = false;
  var enrollmentRequests = 0;
  var deletedFactors = <String>[];
  var factors = <Map<String, Object?>>[];

  Map<String, Object?> factor(
    String id, {
    String status = 'verified',
    String name = 'Jentra desktop',
  }) => {
    'id': id,
    'factor_type': 'totp',
    'status': status,
    'friendly_name': name,
    'created_at': '2026-11-03T00:00:00Z',
    'updated_at': '2026-11-03T00:00:00Z',
  };

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
        'factors': factors,
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
    failFactorLoad = false;
    loseEnrollmentResponse = false;
    enrollmentRequests = 0;
    deletedFactors = [];
    factors = [factor('factor')];
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        Object body;
        if (request.url.path.endsWith('/token')) {
          if (request.url.queryParameters['grant_type'] == 'password') {
            assurance = 'aal1';
          } else if (failFactorLoad) {
            return http.Response(
              jsonEncode({'msg': 'Private authentication lookup error'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          body = session();
        } else if (request.url.path.endsWith('/factors')) {
          enrollmentRequests++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          if (factors.any(
            (f) => f['friendly_name'] == payload['friendly_name'],
          )) {
            return http.Response(
              jsonEncode({'msg': 'A factor with this friendly name exists'}),
              422,
              headers: {'content-type': 'application/json'},
            );
          }
          final id = 'setup-$enrollmentRequests';
          factors.add(
            factor(
              id,
              status: 'unverified',
              name: payload['friendly_name'] as String,
            ),
          );
          if (loseEnrollmentResponse) {
            return http.Response(
              jsonEncode({'msg': 'Private enrollment response error'}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }
          body = {
            'id': id,
            'type': 'totp',
            'totp': {
              'secret': 'SYNTHETIC-SETUP-KEY',
              'uri': 'otpauth://totp/test',
              'qr_code': '<svg/>',
            },
          };
        } else if (request.method == 'DELETE' &&
            request.url.path.contains('/factors/')) {
          final id = request.url.pathSegments.last;
          expect(
            factors.singleWhere((f) => f['id'] == id)['status'],
            'unverified',
          );
          deletedFactors.add(id);
          factors.removeWhere((f) => f['id'] == id);
          body = {'id': id};
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

  test(
    'removing unfinished setup preserves verified and other-app factors',
    () async {
      factors = [
        factor('verified'),
        factor('unfinished', status: 'unverified'),
        factor('other-app', status: 'unverified', name: 'Another app'),
      ];
      await expectLater(
        gateway.cancelTotpEnrollment('verified'),
        throwsStateError,
      );
      await expectLater(
        gateway.cancelTotpEnrollment('other-app'),
        throwsStateError,
      );
      expect(deletedFactors, isEmpty);
      await gateway.cancelTotpEnrollment('unfinished');
      expect(deletedFactors, ['unfinished']);
      expect(factors.map((f) => f['id']), ['verified', 'other-app']);
    },
  );

  test(
    'new authenticator setups never reuse an existing friendly name',
    () async {
      factors = [factor('legacy', status: 'unverified')];
      final first = await gateway.enrollTotp();
      final second = await gateway.enrollTotp();
      expect(first.factorId, isNot(second.factorId));
      expect(factors.map((f) => f['friendly_name']).toSet(), hasLength(3));
      expect(deletedFactors, isEmpty);
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

  Future<void> openMfa(WidgetTester tester, {VoidCallback? onVerified}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: JentraTheme.light(),
          home: Scaffold(body: MfaRequiredScreen(onVerified: onVerified)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('failed authenticator lookup offers retry without enrollment', (
    tester,
  ) async {
    failFactorLoad = true;
    await openMfa(tester);
    expect(find.text('Retry loading authenticators'), findsOneWidget);
    expect(find.text('Set up authenticator'), findsNothing);
    expect(find.textContaining('Private authentication'), findsNothing);
    // The refused refresh clears the SDK session. Repeating the retry must
    // handle its immediate missing-session error without a framework error.
    await tester.tap(find.text('Retry loading authenticators'));
    await tester.pumpAndSettle();
    expect(find.text('Retry loading authenticators'), findsOneWidget);
    expect(tester.takeException(), isNull);
    failFactorLoad = false;
    await gateway.signInWithPassword(
      email: 'owner@example.test',
      password: 'synthetic-password',
    );
    await tester.tap(find.text('Retry loading authenticators'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mfa-authenticator-code')),
      findsOneWidget,
    );
    expect(enrollmentRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopened unfinished setup can verify the original authenticator',
    (tester) async {
      factors = [factor('unfinished', status: 'unverified')];
      var completed = 0;
      await openMfa(tester, onVerified: () => completed++);
      expect(
        find.text('Finish your earlier authenticator setup'),
        findsOneWidget,
      );
      expect(find.text('Set up authenticator'), findsNothing);
      final input = find.byKey(const ValueKey('mfa-authenticator-code'));
      await tester.enterText(input, '123456');
      await tester.ensureVisible(find.text('Verify and continue'));
      await tester.tap(find.text('Verify and continue'));
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(verificationRequests, 1);
      expect(enrollmentRequests, 0);
      expect(deletedFactors, isEmpty);
    },
  );

  testWidgets('unfinished setup can be removed before a new setup is created', (
    tester,
  ) async {
    factors = [
      factor('unfinished', status: 'unverified'),
      factor('other-app', status: 'unverified', name: 'Another app'),
    ];
    await openMfa(tester);
    await tester.ensureVisible(find.text('Remove unfinished setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove unfinished setup'));
    await tester.pumpAndSettle();
    expect(deletedFactors, ['unfinished']);
    expect(factors.single['id'], 'other-app');
    expect(enrollmentRequests, 0);
    await tester.tap(find.text('Set up authenticator'));
    await tester.pumpAndSettle();
    expect(find.text('SYNTHETIC-SETUP-KEY'), findsOneWidget);
    expect(enrollmentRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lost enrollment response reloads the unfinished setup before retry',
    (tester) async {
      factors = [];
      loseEnrollmentResponse = true;
      await openMfa(tester);
      await tester.tap(find.text('Set up authenticator'));
      await tester.pumpAndSettle();
      expect(
        find.text('Finish your earlier authenticator setup'),
        findsOneWidget,
      );
      expect(find.text('Set up authenticator'), findsNothing);
      expect(find.textContaining('Private enrollment'), findsNothing);
      expect(enrollmentRequests, 1);
      expect(factors.single['status'], 'unverified');
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'unfinished setup stays reachable at 200% text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        factors = [factor('unfinished', status: 'unverified')];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: brightness == Brightness.dark
                  ? JentraTheme.dark()
                  : JentraTheme.light(),
              home: const Scaffold(body: MfaRequiredScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final remove = find.text('Remove unfinished setup');
        await tester.ensureVisible(remove);
        await tester.pumpAndSettle();
        expect(remove.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(deletedFactors, ['unfinished']);
        expect(find.text('Set up authenticator'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
