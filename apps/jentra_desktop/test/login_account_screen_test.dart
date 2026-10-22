import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_design_system/jentra_design_system.dart';
import 'package:jentra_desktop/src/app_providers.dart';
import 'package:jentra_desktop/src/features/auth/login_screen.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const email = 'new-member@example.test';
const password = 'synthetic-password-only';
const actor = '10000000-0000-0000-0000-000000000001';

// The production Flutter client provides PKCE storage. A raw SupabaseClient
// must provide it explicitly too; signup otherwise fails before HTTP.
final class _PkceStorage implements GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

Map<String, Object?> user() => {
  'id': actor,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': email,
  'created_at': '2026-10-09T00:00:00Z',
  'app_metadata': {
    'provider': 'email',
    'providers': ['email'],
  },
  'user_metadata': <String, Object?>{},
  'identities': <Object?>[],
};

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
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-test-signature',
    'refresh_token': 'synthetic-refresh-only',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': user(),
  };
}

void main() {
  setUpAll(() async {
    const fonts = 'packages/jentra_design_system/assets/fonts/';
    await (FontLoader(JentraTypography.sansFamily)
          ..addFont(rootBundle.load('${fonts}Manrope-Regular.ttf'))
          ..addFont(rootBundle.load('${fonts}Manrope-SemiBold.ttf')))
        .load();
    await (FontLoader(
      JentraTypography.monoFamily,
    )..addFont(rootBundle.load('${fonts}IBMPlexMono-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late _PkceStorage pkce;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;

  http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {
      'content-type': 'application/json',
      'x-supabase-api-version': '2024-01-01',
    },
  );

  setUp(() {
    requests.clear();
    respond = null;
    pkce = _PkceStorage();
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: pkce,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (respond != null) return respond!(request);
        if (request.url.path.endsWith('/signup')) return jsonResponse(user());
        if (request.url.path.endsWith('/resend')) return jsonResponse({});
        if (request.url.path.endsWith('/token')) return jsonResponse(session());
        throw StateError('Unexpected mock route: ${request.url.path}');
      }),
    );
    gateway = SupabaseFoundationGateway(client);
  });
  tearDown(() async => client.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Future<bool> Function()? google,
    Future<bool> Function(
      GoogleSignInCancellation cancellation,
      void Function() onExchangeStarted,
    )?
    googleFlow,
    EmailConfirmationAction? emailConfirmationFlow,
    Future<void> Function(String link)? confirmEmailLink,
    bool connected = true,
    Size size = const Size(1440, 900),
    Brightness brightness = Brightness.light,
    double scale = 1,
    GlobalKey? boundary,
    RuntimeConfig? runtimeConfiguration,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      initialLocation: '/login?redirect=%2Ftarget',
      routes: [
        GoRoute(
          path: '/login',
          builder: (_, _) => LoginScreen(
            googleSignIn: google,
            googleSignInFlow: googleFlow,
            emailConfirmationFlow:
                emailConfirmationFlow ??
                ({
                  required email,
                  required password,
                  required resend,
                  required cancellation,
                  required onEmailSent,
                  required onExchangeStarted,
                }) async {
                  if (resend) {
                    await client.auth.resend(
                      type: OtpType.signup,
                      email: email,
                    );
                  } else {
                    await gateway.createAccount(
                      email: email,
                      password: password!,
                    );
                  }
                  onEmailSent();
                },
            confirmEmailLink: confirmEmailLink,
          ),
        ),
        GoRoute(
          path: '/target',
          builder: (_, _) =>
              const Scaffold(body: Text('Destination workspace')),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (runtimeConfiguration != null)
            runtimeConfigProvider.overrideWithValue(runtimeConfiguration),
          foundationGatewayProvider.overrideWithValue(
            connected ? gateway : null,
          ),
        ],
        child: MaterialApp.router(
          theme: brightness == Brightness.dark
              ? JentraTheme.dark()
              : JentraTheme.light(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Email delivery starts a cooldown timer. Unmount before router/client
    // teardown so every attempt and timer is cancelled by the screen itself.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  Finder field(String name) => find.byKey(ValueKey('login-$name'));
  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(field(name));
    await tester.pumpAndSettle();
    await tester.tap(field(name));
    await tester.pump();
  }

  Future<void> fill(WidgetTester tester, {bool creating = false}) async {
    await tester.enterText(field('email'), ' $email ');
    await tester.enterText(field('password'), password);
    if (creating) await tester.enterText(field('confirmation'), password);
  }

  testWidgets(
    'login branding follows production environment without invented region',
    (tester) async {
      await mount(
        tester,
        runtimeConfiguration: const RuntimeConfig(
          environment: 'production',
          supabaseUrl: 'https://example.test',
          supabasePublishableKey: 'synthetic-public-key',
        ),
      );
      expect(find.text('Production workspace'), findsOneWidget);
      expect(find.textContaining('Mumbai region'), findsNothing);
      expect(find.textContaining('Synthetic data only'), findsNothing);
      expect(requests, isEmpty);
      expect(client.auth.currentUser, isNull);
    },
  );

  testWidgets(
    'signup validates email, length and confirmation before any request',
    (tester) async {
      await mount(tester);
      await tap(tester, 'change-mode');
      await tester.enterText(field('email'), 'invalid');
      await tester.enterText(field('password'), 'short');
      await tester.enterText(field('confirmation'), 'different');
      await tap(tester, 'submit');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('The passwords must match.'), findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsWidgets);
      expect(requests, isEmpty);
      expect(client.auth.currentUser, isNull);
    },
  );

  testWidgets(
    'signup posts only auth data and returns to sign-in with cleared passwords',
    (tester) async {
      await mount(tester);
      await tap(tester, 'change-mode');
      await fill(tester, creating: true);
      await tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/auth/v1/signup');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['email'], email);
      expect(body['password'], password);
      expect(body['code_challenge_method'], 's256');
      expect(body['code_challenge'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(pkce.values, hasLength(1));
      expect(
        body.keys.any((key) => key.contains('role') || key.contains('tenant')),
        isFalse,
      );
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.textContaining('If this address can be registered'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(field('email')).controller!.text,
        email,
      );
      expect(
        tester.widget<TextFormField>(field('password')).controller!.text,
        isEmpty,
      );
      expect(client.auth.currentUser, isNull);
      await tap(tester, 'change-mode');
      expect(
        tester.widget<TextFormField>(field('password')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextFormField>(field('confirmation')).controller!.text,
        isEmpty,
      );
    },
  );

  testWidgets('signup failures keep the form and hide provider details', (
    tester,
  ) async {
    respond = (_) async => jsonResponse({
      'msg': 'private-provider-diagnostic $password',
      'code': 'signup_disabled',
    }, status: 400);
    await mount(tester);
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/signup');
    expect(find.text('Create your account'), findsOneWidget);
    expect(
      find.textContaining('Account creation could not complete.'),
      findsOneWidget,
    );
    expect(find.textContaining('private-provider-diagnostic'), findsNothing);
    expect(
      tester.widget<TextFormField>(field('password')).controller!.text,
      password,
    );
  });

  testWidgets('password sign-in retains the requested route', (tester) async {
    await mount(tester);
    await fill(tester);
    await tap(tester, 'submit');
    await tester.pumpAndSettle();
    expect(find.text('Destination workspace'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.url.queryParameters['grant_type'], 'password');
  });

  testWidgets(
    'pending signup rejects duplicate keyboard submission and Google launch',
    (tester) async {
      final pending = Completer<http.Response>();
      respond = (_) => pending.future;
      var googleCalls = 0;
      await mount(
        tester,
        google: () async {
          googleCalls++;
          return true;
        },
      );
      await tap(tester, 'change-mode');
      await fill(tester, creating: true);
      final submit = tester
          .widget<TextField>(
            find.descendant(
              of: field('confirmation'),
              matching: find.byType(TextField),
            ),
          )
          .onSubmitted!;
      submit(password);
      submit(password);
      await tester.pump(const Duration(milliseconds: 30));
      expect(requests, hasLength(1));
      expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
      expect(tester.widget<TextButton>(field('change-mode')).onPressed, isNull);
      expect(tester.widget<TextFormField>(field('email')).enabled, isFalse);
      expect(googleCalls, 0);
      pending.complete(jsonResponse(user()));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('Welcome back'), findsOneWidget);
    },
  );

  testWidgets('email send and confirmation wait disable competing auth', (
    tester,
  ) async {
    final release = Completer<void>();
    late VoidCallback emailSent;
    var calls = 0;
    await mount(
      tester,
      emailConfirmationFlow:
          ({
            required email,
            required password,
            required resend,
            required cancellation,
            required onEmailSent,
            required onExchangeStarted,
          }) {
            calls++;
            expect(email, 'new-member@example.test');
            expect(password, 'synthetic-password-only');
            expect(resend, isFalse);
            emailSent = onEmailSent;
            return release.future;
          },
    );
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    expect(find.text('Requesting your confirmation email…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
    expect(tester.widget<TextButton>(field('change-mode')).onPressed, isNull);
    expect(tester.widget<TextFormField>(field('email')).enabled, isFalse);
    final submit = tester
        .widget<TextField>(
          find.descendant(
            of: field('confirmation'),
            matching: find.byType(TextField),
          ),
        )
        .onSubmitted!;
    submit(password);
    await tester.pump();
    expect(calls, 1);
    emailSent();
    await tester.pump();
    expect(find.text('Waiting for your email confirmation…'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(field('password')).controller!.text,
      isEmpty,
    );
    expect(
      tester.widget<OutlinedButton>(field('email-resend')).onPressed,
      isNull,
    );
    expect(tester.widget<TextButton>(field('email-signin')).onPressed, isNull);
    expect(
      tester.widget<TextButton>(field('email-link-help')).onPressed,
      isNull,
    );
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
    release.complete();
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    expect(client.auth.currentSession, isNull);
  });

  testWidgets('email cancellation waits for channel cleanup before retry', (
    tester,
  ) async {
    final release = Completer<void>();
    var observedCancellation = false;
    await mount(
      tester,
      emailConfirmationFlow:
          ({
            required email,
            required password,
            required resend,
            required cancellation,
            required onEmailSent,
            required onExchangeStarted,
          }) async {
            onEmailSent();
            await cancellation.whenCancelled;
            observedCancellation = true;
            await release.future;
            throw const EmailConfirmationException(
              EmailConfirmationFailure.cancelled,
            );
          },
    );
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    await tap(tester, 'email-cancel');
    expect(observedCancellation, isTrue);
    expect(find.text('Stopping…'), findsOneWidget);
    expect(tester.widget<TextButton>(field('email-cancel')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
    release.complete();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Waiting for email confirmation stopped.'),
      findsOneWidget,
    );
    expect(field('email-cancel'), findsNothing);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNotNull);
    expect(requests, isEmpty);
  });

  testWidgets('accepted email exchange cannot be cancelled or resubmitted', (
    tester,
  ) async {
    final release = Completer<void>();
    late EmailConfirmationCancellation attempt;
    var calls = 0;
    await mount(
      tester,
      emailConfirmationFlow:
          ({
            required email,
            required password,
            required resend,
            required cancellation,
            required onEmailSent,
            required onExchangeStarted,
          }) {
            calls++;
            attempt = cancellation;
            onEmailSent();
            onExchangeStarted();
            return release.future;
          },
    );
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    expect(find.text('Completing confirmation…'), findsOneWidget);
    expect(tester.widget<TextButton>(field('email-cancel')).onPressed, isNull);
    expect(
      tester.widget<OutlinedButton>(field('email-resend')).onPressed,
      isNull,
    );
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
    final submit = tester
        .widget<TextField>(
          find.descendant(
            of: field('password'),
            matching: find.byType(TextField),
          ),
        )
        .onSubmitted!;
    submit(password);
    await tester.pump();
    expect(calls, 1);
    expect(attempt.isCancelled, isFalse);
    release.completeError(
      const EmailConfirmationException(EmailConfirmationFailure.exchangeFailed),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Email confirmation could not finish.'),
      findsOneWidget,
    );
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNotNull);
    expect(requests, isEmpty);
  });

  testWidgets('after restart resend is available with only the email', (
    tester,
  ) async {
    await mount(tester);
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    await tester.pumpAndSettle();
    expect(
      find.text('Wait a minute before requesting another email.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    requests.clear();
    await tester.enterText(field('email'), ' $email ');
    expect(
      tester.widget<TextFormField>(field('password')).controller!.text,
      isEmpty,
    );
    await tap(tester, 'email-help');
    expect(
      tester.widget<OutlinedButton>(field('email-resend')).onPressed,
      isNotNull,
    );
    final semantics = tester.ensureSemantics();
    await tester.pump();
    try {
      expect(
        find.bySemanticsLabel('Resend confirmation email'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
    await tap(tester, 'email-resend');
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/resend');
    final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(body['email'], email);
    expect(body['type'], 'signup');
    expect(body.containsKey('password'), isFalse);
    expect(
      body.keys.any((key) => key.contains('role') || key.contains('tenant')),
      isFalse,
    );
    expect(
      find.textContaining('If this address can be registered'),
      findsOneWidget,
    );
  });

  testWidgets('unconfirmed password sign-in offers safe email recovery', (
    tester,
  ) async {
    respond = (request) async {
      if (request.url.path.endsWith('/resend')) return jsonResponse({});
      return jsonResponse({
        'msg': 'private-provider-diagnostic $password',
        'code': 'email_not_confirmed',
      }, status: 400);
    };
    await mount(tester);
    await fill(tester);
    await tap(tester, 'submit');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Confirm your email before signing in.'),
      findsOneWidget,
    );
    expect(find.textContaining('private-provider-diagnostic'), findsNothing);
    expect(
      tester.widget<OutlinedButton>(field('email-resend')).onPressed,
      isNotNull,
    );
    await tap(tester, 'email-resend');
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(requests.last.url.path, '/auth/v1/resend');
    final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
    expect(body['email'], email);
    expect(body.containsKey('password'), isFalse);
  });

  testWidgets(
    'manual email link clears its secret before exchange and hides expiry details',
    (tester) async {
      const link =
          'https://example.test/auth/v1/verify?token=synthetic-secret-token&type=signup';
      final release = Completer<void>();
      String? received;
      await mount(
        tester,
        confirmEmailLink: (value) {
          received = value;
          return release.future;
        },
      );
      await tap(tester, 'email-help');
      await tap(tester, 'email-link-help');
      await tester.enterText(field('email-link'), link);
      await tap(tester, 'email-link-confirm');
      final input = tester.widget<TextField>(field('email-link'));
      expect(received, link);
      expect(input.controller!.text, isEmpty);
      expect(input.obscureText, isTrue);
      expect(input.enableSuggestions, isFalse);
      expect(input.autofillHints, isEmpty);
      expect(input.enabled, isFalse);
      expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
      release.completeError(
        const AuthException(
          'private-provider-diagnostic synthetic-secret-token',
          code: 'otp_expired',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'This confirmation link has expired or has already been used.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('private-provider-diagnostic'), findsNothing);
      expect(find.textContaining('synthetic-secret-token'), findsNothing);
      expect(
        tester.widget<TextField>(field('email-link')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<OutlinedButton>(field('email-link-confirm')).onPressed,
        isNotNull,
      );
      expect(requests, isEmpty);
    },
  );

  testWidgets('completed manual email confirmation retains the requested route', (
    tester,
  ) async {
    const link =
        'https://example.test/auth/v1/verify?token=synthetic-secret-token&type=signup';
    await mount(
      tester,
      confirmEmailLink: (value) async {
        expect(value, link);
        await client.auth.signInWithPassword(email: email, password: password);
      },
    );
    await tap(tester, 'email-help');
    await tap(tester, 'email-link-help');
    await tester.enterText(field('email-link'), link);
    await tap(tester, 'email-link-confirm');
    await tester.pumpAndSettle();
    expect(find.text('Destination workspace'), findsOneWidget);
    expect(client.auth.currentUser?.id, actor);
  });

  testWidgets(
    'email confirmation timeout restores auth and enforces resend cooldown',
    (tester) async {
      await mount(
        tester,
        emailConfirmationFlow:
            ({
              required email,
              required password,
              required resend,
              required cancellation,
              required onEmailSent,
              required onExchangeStarted,
            }) async {
              onEmailSent();
              throw TimeoutException('private-provider-diagnostic');
            },
      );
      await tap(tester, 'change-mode');
      await fill(tester, creating: true);
      await tap(tester, 'submit');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Waiting for confirmation timed out.'),
        findsOneWidget,
      );
      expect(find.textContaining('private-provider-diagnostic'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(field('google')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<TextButton>(field('email-signin')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<OutlinedButton>(field('email-resend')).onPressed,
        isNull,
      );
      await tester.pump(const Duration(seconds: 60));
      expect(
        tester.widget<OutlinedButton>(field('email-resend')).onPressed,
        isNotNull,
      );
      expect(requests, isEmpty);
    },
  );

  testWidgets('leaving login cancels its email confirmation attempt', (
    tester,
  ) async {
    late EmailConfirmationCancellation attempt;
    await mount(
      tester,
      emailConfirmationFlow:
          ({
            required email,
            required password,
            required resend,
            required cancellation,
            required onEmailSent,
            required onExchangeStarted,
          }) async {
            attempt = cancellation;
            onEmailSent();
            await cancellation.whenCancelled;
            throw const EmailConfirmationException(
              EmailConfirmationFailure.cancelled,
            );
          },
    );
    await tap(tester, 'change-mode');
    await fill(tester, creating: true);
    await tap(tester, 'submit');
    expect(attempt.isCancelled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(attempt.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
    expect(client.auth.currentSession, isNull);
    expect(requests, isEmpty);
  });

  testWidgets(
    'pending Google disables other actions and failed launch can be retried',
    (tester) async {
      final pending = Completer<bool>();
      var calls = 0;
      await mount(
        tester,
        google: () {
          calls++;
          return pending.future;
        },
      );
      await fill(tester);
      final submit = tester
          .widget<TextField>(
            find.descendant(
              of: field('password'),
              matching: find.byType(TextField),
            ),
          )
          .onSubmitted!;
      await tap(tester, 'google');
      submit(password);
      await tester.pump();
      expect(find.text('Waiting for Google…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
      expect(tester.widget<TextButton>(field('change-mode')).onPressed, isNull);
      expect(requests, isEmpty);
      expect(calls, 1);
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The browser could not open.'),
        findsOneWidget,
      );
      expect(
        tester.widget<OutlinedButton>(field('google')).onPressed,
        isNotNull,
      );
      expect(find.text('Waiting for Google…'), findsNothing);
    },
  );

  testWidgets('unexpected Google failure gives safe retry guidance', (
    tester,
  ) async {
    await mount(
      tester,
      google: () async {
        throw StateError('private-provider-diagnostic $password');
      },
    );
    await tap(tester, 'google');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Try again or sign in with your work email.'),
      findsOneWidget,
    );
    expect(find.textContaining('Google must be enabled'), findsNothing);
    expect(find.textContaining('private-provider-diagnostic'), findsNothing);
    expect(requests, isEmpty);
  });

  for (final scenario in {
    GoogleSignInFailure.providerDisabled:
        'not available for this workspace yet',
    GoogleSignInFailure.settingsUnavailable: 'Check your internet connection',
    GoogleSignInFailure.browserUnavailable: 'The browser could not open',
    GoogleSignInFailure.callbackUnavailable:
        'Another sign-in window may be open',
    GoogleSignInFailure.exchangeFailed: 'Google returned to the app',
    GoogleSignInFailure.callbackRejected: 'Google sign-in was not completed',
  }.entries) {
    testWidgets(
      'Google ${scenario.key.name} gives specific recovery guidance',
      (tester) async {
        await mount(
          tester,
          google: () async => throw GoogleSignInException(scenario.key),
        );
        await tap(tester, 'google');
        await tester.pumpAndSettle();
        expect(find.textContaining(scenario.value), findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(field('google')).onPressed,
          isNotNull,
        );
        expect(find.text('Destination workspace'), findsNothing);
        expect(requests, isEmpty);
      },
    );
  }

  testWidgets('cancelling waits for the return channel to close before retry', (
    tester,
  ) async {
    final release = Completer<void>();
    var cancellationObserved = false;
    await mount(
      tester,
      googleFlow: (cancellation, onExchangeStarted) async {
        await cancellation.whenCancelled;
        cancellationObserved = true;
        await release.future;
        throw const GoogleSignInException(GoogleSignInFailure.cancelled);
      },
    );
    await tap(tester, 'google');
    await tester.ensureVisible(field('google-cancel'));
    await tester.tap(field('google-cancel'));
    await tester.pump();
    expect(cancellationObserved, isTrue);
    expect(find.text('Cancelling…'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
    expect(tester.widget<TextButton>(field('google-cancel')).onPressed, isNull);
    release.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('Google sign-in cancelled.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNotNull);
    expect(field('google-cancel'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets(
    'accepted Google exchange cannot be cancelled or submitted twice',
    (tester) async {
      final release = Completer<bool>();
      late GoogleSignInCancellation cancellation;
      await mount(
        tester,
        googleFlow: (attempt, onExchangeStarted) {
          cancellation = attempt;
          onExchangeStarted();
          return release.future;
        },
      );
      await tap(tester, 'google');
      expect(find.text('Completing sign-in…'), findsOneWidget);
      expect(
        tester.widget<TextButton>(field('google-cancel')).onPressed,
        isNull,
      );
      expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNull);
      expect(cancellation.isCancelled, isFalse);
      release.completeError(
        const GoogleSignInException(GoogleSignInFailure.exchangeFailed),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Google returned to the app'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(field('google')).onPressed,
        isNotNull,
      );
      expect(requests, isEmpty);
    },
  );

  testWidgets('Google timeout restores sign-in controls', (tester) async {
    await mount(
      tester,
      google: () async {
        throw TimeoutException('private detail');
      },
    );
    await tap(tester, 'google');
    await tester.pumpAndSettle();
    expect(find.textContaining('Google sign-in timed out.'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(field('google')).onPressed, isNotNull);
    expect(find.textContaining('private detail'), findsNothing);
  });

  testWidgets('a completed Google session preserves the requested route', (
    tester,
  ) async {
    await mount(
      tester,
      google: () async {
        await client.auth.signInWithPassword(email: email, password: password);
        return true;
      },
    );
    await tap(tester, 'google');
    await tester.pumpAndSettle();
    expect(find.text('Destination workspace'), findsOneWidget);
    expect(client.auth.currentUser?.id, actor);
  });

  testWidgets('late browser failure after disposal cannot update the screen', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await mount(tester, google: () => pending.future);
    await tap(tester, 'google');
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('synthetic cancellation'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(requests, isEmpty);
  });

  testWidgets('leaving the login screen cancels its waiting Google attempt', (
    tester,
  ) async {
    late GoogleSignInCancellation cancellation;
    await mount(
      tester,
      googleFlow: (attempt, onExchangeStarted) async {
        cancellation = attempt;
        await attempt.whenCancelled;
        throw const GoogleSignInException(GoogleSignInFailure.cancelled);
      },
    );
    await tap(tester, 'google');
    expect(cancellation.isCancelled, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancellation.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
    expect(client.auth.currentSession, isNull);
    expect(requests, isEmpty);
  });

  testWidgets('email confirmation recovery panel fits at 200% text', (
    tester,
  ) async {
    final boundary = GlobalKey();
    final dir = Platform.environment['W5_AUTH_FRAME_DIR'];
    Future<void> captureFrame(String name) async {
      if (dir == null) return;
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(dir).create(recursive: true);
        await File('$dir/$name.png').writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await mount(
      tester,
      boundary: boundary,
      size: const Size(1024, 720),
      scale: 2,
    );
    await tap(tester, 'email-help');
    await tap(tester, 'email-link-help');
    await tester.ensureVisible(find.text('Confirm your email'));
    await tester.pumpAndSettle();
    await captureFrame('auth-email-confirmation-overview-1024-720-light-200');
    for (final key in [
      'email-resend',
      'email-signin',
      'email-link',
      'email-link-confirm',
    ]) {
      await tester.ensureVisible(field(key));
      await tester.pumpAndSettle();
      expect(field(key).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(tester.widget<TextField>(field('email-link')).obscureText, isTrue);
    expect(requests, isEmpty);
    await captureFrame('auth-email-confirmation-1024-720-light-200');
  });

  for (final creating in [false, true]) {
    final mode = creating ? 'create' : 'signin';
    testWidgets('auth fresh render $mode at 200% text', (tester) async {
      final boundary = GlobalKey();
      await mount(
        tester,
        connected: false,
        boundary: boundary,
        size: const Size(1024, 720),
        brightness: creating ? Brightness.dark : Brightness.light,
        scale: 2,
      );
      if (creating) await tap(tester, 'change-mode');
      await tester.ensureVisible(field('email'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(requests, isEmpty);
      expect(field('confirmation'), creating ? findsOneWidget : findsNothing);
      final dir = Platform.environment['W5_AUTH_FRAME_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(dir).create(recursive: true);
          await File(
            '$dir/auth-$mode-1024-720-${creating ? 'dark' : 'light'}-200.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
