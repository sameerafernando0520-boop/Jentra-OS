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
    headers: {'content-type': 'application/json'},
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
    bool connected = true,
    Size size = const Size(1440, 900),
    Brightness brightness = Brightness.light,
    double scale = 1,
    GlobalKey? boundary,
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
          builder: (_, _) => LoginScreen(googleSignIn: google),
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

  testWidgets('Google failure gives safe provider configuration guidance', (
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
    expect(find.textContaining('Google must be enabled'), findsOneWidget);
    expect(find.textContaining('Windows callback allowed'), findsOneWidget);
    expect(find.textContaining('private-provider-diagnostic'), findsNothing);
    expect(requests, isEmpty);
  });

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
