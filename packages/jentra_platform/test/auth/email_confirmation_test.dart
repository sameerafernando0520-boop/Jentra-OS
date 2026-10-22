import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:jentra_platform/src/auth/email_confirmation_io.dart' as native;
import 'package:supabase_flutter/supabase_flutter.dart';

const _email = 'new-member@example.test';
const _password = 'Synthetic-password-123';
const _actor = '10000000-0000-0000-0000-000000000001';

final class _PkceStorage implements GotrueAsyncStorage {
  final values = <String, String>{};
  var writes = 0;

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

Map<String, Object?> _user() => {
  'id': _actor,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': _email,
  'created_at': '2026-10-21T00:00:00Z',
  'app_metadata': {
    'provider': 'email',
    'providers': ['email'],
  },
  'user_metadata': <String, Object?>{},
  'identities': <Object?>[],
};

Map<String, Object?> _session() {
  final claims = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': _actor,
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
    'user': _user(),
  };
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {
    'content-type': 'application/json',
    'x-supabase-api-version': '2024-01-01',
  },
);

Matcher _failure(EmailConfirmationFailure value) =>
    isA<EmailConfirmationException>().having(
      (e) => e.failure,
      'failure',
      value,
    );

Future<int> _request(Uri uri) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(uri)).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => _active ? 0 : 1;
  @override
  void cancel() => _active = false;
  void elapse() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  late _PkceStorage storage;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? respond;

  setUp(() {
    storage = _PkceStorage();
    requests.clear();
    respond = null;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: storage,
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        return await (respond?.call(request) ??
            Future.error(StateError('unexpected request')));
      }),
    );
    gateway = SupabaseFoundationGateway(client);
  });
  tearDown(() => client.dispose());

  test(
    'signup binds before send, supplies private redirect, and exchanges PKCE',
    () async {
      late Uri callback;
      final sent = Completer<void>();
      final stages = <String>[];
      respond = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/auth/v1/signup') {
          callback = Uri.parse(request.url.queryParameters['redirect_to']!);
          expect(callback.host, '127.0.0.1');
          expect(
            callback.path,
            matches(RegExp(r'^/auth/callback/[A-Za-z0-9_-]{43}$')),
          );
          expect(await _request(callback.replace(path: '/wrong')), 404);
          expect(body['email'], _email);
          expect(body['password'], _password);
          expect(body['code_challenge'], isNotEmpty);
          expect(body['code_challenge_method'], 's256');
          expect(body.containsKey('role'), isFalse);
          return _json(_user());
        }
        expect(request.url.path, '/auth/v1/token');
        expect(request.url.queryParameters, {'grant_type': 'pkce'});
        expect(body['auth_code'], 'synthetic-auth-code');
        expect(body['code_verifier'], isNotEmpty);
        return _json(_session());
      };
      final done = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        onEmailSent: () {
          stages.add('sent');
          sent.complete();
        },
        onExchangeStarted: () => stages.add('exchange'),
      );
      await sent.future.timeout(const Duration(seconds: 10));
      expect(client.auth.currentSession, isNull);
      expect(
        await _request(callback.replace(query: 'code=synthetic-auth-code')),
        200,
      );
      expect((await done).session?.user.id, _actor);
      expect(stages, ['sent', 'exchange']);
      expect(requests.length, 2);
      expect(gateway.currentAssurance(), MfaAssurance.aal1);
    },
  );

  test(
    'resend after cancellation creates a new callback and verifier',
    () async {
      final callbacks = <Uri>[];
      final challenges = <String>[];
      respond = (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/auth/v1/token') return _json(_session());
        callbacks.add(Uri.parse(request.url.queryParameters['redirect_to']!));
        challenges.add(body['code_challenge']! as String);
        if (request.url.path == '/auth/v1/resend') {
          expect(body['type'], 'signup');
          expect(body.containsKey('password'), isFalse);
          return _json(<String, Object?>{});
        }
        return _json(_user());
      };
      final cancelled = EmailConfirmationCancellation();
      final firstSent = Completer<void>();
      final first = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        cancellation: cancelled,
        onEmailSent: firstSent.complete,
      );
      final rejected = expectLater(
        first,
        throwsA(_failure(EmailConfirmationFailure.cancelled)),
      );
      await firstSent.future.timeout(const Duration(seconds: 10));
      cancelled.cancel();
      await rejected;
      final secondSent = Completer<void>();
      final second = native.resendAndConfirmEmail(
        client,
        email: _email,
        useLoopback: true,
        port: 0,
        onEmailSent: secondSent.complete,
      );
      await secondSent.future.timeout(const Duration(seconds: 10));
      expect(callbacks[0].path, isNot(callbacks[1].path));
      expect(challenges[0], isNot(challenges[1]));
      expect(
        await _request(callbacks[1].replace(query: 'code=resend-code')),
        200,
      );
      expect((await second).session, isNotNull);
      expect(requests.map((r) => r.url.path), [
        '/auth/v1/signup',
        '/auth/v1/resend',
        '/auth/v1/token',
      ]);
    },
  );

  test(
    'auto-confirm session completes without waiting or announcing email',
    () async {
      var sent = 0;
      respond = (_) async => _json(_session());
      final result = await native
          .createAccountAndConfirm(
            client,
            email: _email,
            password: _password,
            useLoopback: true,
            port: 0,
            onEmailSent: () => sent++,
          )
          .timeout(const Duration(seconds: 10));
      expect(result.session?.user.id, _actor);
      expect(sent, 0);
      expect(requests.single.url.path, '/auth/v1/signup');
    },
  );

  test('pre-cancellation does not send or write a PKCE verifier', () async {
    final cancellation = EmailConfirmationCancellation()..cancel();
    await expectLater(
      native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        cancellation: cancellation,
      ),
      throwsA(_failure(EmailConfirmationFailure.cancelled)),
    );
    expect(storage.writes, 0);
    expect(requests, isEmpty);
  });

  test(
    'auto-confirm SDK session owns outcome after pending-send cancellation',
    () async {
      final cancellation = EmailConfirmationCancellation();
      final requested = Completer<void>();
      final release = Completer<http.Response>();
      respond = (_) {
        requested.complete();
        return release.future;
      };
      final done = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        cancellation: cancellation,
      );
      await requested.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      release.complete(_json(_session()));
      expect((await done).session?.user.id, _actor);
      expect(client.auth.currentUser?.id, _actor);
    },
  );

  test(
    'early accepted exchange survives late signup response without stage regression',
    () async {
      final requested = Completer<void>();
      final release = Completer<http.Response>();
      final exchangeRequested = Completer<void>();
      final releaseExchange = Completer<http.Response>();
      final stages = <String>[];
      late Uri callback;
      respond = (request) {
        if (request.url.path == '/auth/v1/token') {
          exchangeRequested.complete();
          return releaseExchange.future;
        }
        callback = Uri.parse(request.url.queryParameters['redirect_to']!);
        requested.complete();
        return release.future;
      };
      final done = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        onEmailSent: () => stages.add('sent'),
        onExchangeStarted: () => stages.add('exchange'),
      );
      await requested.future.timeout(const Duration(seconds: 10));
      final browser = _request(
        callback.replace(query: 'code=early-confirmation'),
      );
      await exchangeRequested.future.timeout(const Duration(seconds: 10));
      release.complete(_json(_user()));
      await Future<void>.delayed(Duration.zero);
      expect(stages, ['exchange']);
      releaseExchange.complete(_json(_session()));
      expect(await browser, 200);
      expect((await done).session?.user.id, _actor);
      expect(stages, ['exchange']);
    },
  );

  test(
    'waiting deadline preserves TimeoutException and closes callback',
    () async {
      const deadlineDuration = Duration(minutes: 14);
      late _ManualTimer deadline;
      late Uri callback;
      final sent = Completer<void>();
      respond = (request) async {
        callback = Uri.parse(request.url.queryParameters['redirect_to']!);
        return _json(_user());
      };
      final done = runZoned(
        () => native.createAccountAndConfirm(
          client,
          email: _email,
          password: _password,
          useLoopback: true,
          port: 0,
          timeout: deadlineDuration,
          onEmailSent: sent.complete,
        ),
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) =>
              duration == deadlineDuration
              ? deadline = _ManualTimer(callback)
              : parent.createTimer(zone, duration, callback),
        ),
      );
      final rejected = expectLater(done, throwsA(isA<TimeoutException>()));
      await sent.future.timeout(const Duration(seconds: 10));
      deadline.elapse();
      await rejected;
      await expectLater(
        _request(callback.replace(query: 'code=late')),
        throwsA(isA<SocketException>()),
      );
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'cancellation waits for send to settle and rejects late callback',
    () async {
      final cancellation = EmailConfirmationCancellation();
      final requested = Completer<void>();
      final release = Completer<http.Response>();
      late Uri callback;
      respond = (request) {
        callback = Uri.parse(request.url.queryParameters['redirect_to']!);
        requested.complete();
        return release.future;
      };
      final done = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        cancellation: cancellation,
      );
      var finished = false;
      unawaited(
        done.then<void>(
          (_) => finished = true,
          onError: (Object _) {
            finished = true;
          },
        ),
      );
      final rejected = expectLater(
        done,
        throwsA(_failure(EmailConfirmationFailure.cancelled)),
      );
      await requested.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(await _request(callback.replace(query: 'code=stale')), 404);
      release.complete(_json(_user()));
      await rejected;
      expect(requests.length, 1);
      expect(client.auth.currentSession, isNull);
    },
  );

  test('accepted exchange waits for SDK outcome after cancellation', () async {
    final cancellation = EmailConfirmationCancellation();
    final sent = Completer<void>();
    final exchanging = Completer<void>();
    final release = Completer<http.Response>();
    late Uri callback;
    respond = (request) {
      if (request.url.path == '/auth/v1/token') return release.future;
      callback = Uri.parse(request.url.queryParameters['redirect_to']!);
      return Future.value(_json(_user()));
    };
    final done = native.createAccountAndConfirm(
      client,
      email: _email,
      password: _password,
      useLoopback: true,
      port: 0,
      cancellation: cancellation,
      onEmailSent: sent.complete,
      onExchangeStarted: exchanging.complete,
    );
    await sent.future.timeout(const Duration(seconds: 10));
    final browser = _request(callback.replace(query: 'code=accepted'));
    await exchanging.future.timeout(const Duration(seconds: 10));
    cancellation.cancel();
    release.complete(_json(_session()));
    expect(await browser, 200);
    expect((await done).session?.user.id, _actor);
  });

  test(
    'occupied callback port fails before verifier or email request',
    () async {
      final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        await expectLater(
          native.createAccountAndConfirm(
            client,
            email: _email,
            password: _password,
            useLoopback: true,
            port: occupied.port,
          ),
          throwsA(_failure(EmailConfirmationFailure.callbackUnavailable)),
        );
        expect(requests, isEmpty);
        expect(storage.writes, 0);
      } finally {
        await occupied.close(force: true);
      }
    },
  );

  test('send errors are sanitized recognized categories', () async {
    respond = (_) async => _json({
      'code': 'signup_disabled',
      'msg': 'private-provider-detail',
    }, status: 400);
    await expectLater(
      native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
      ),
      throwsA(
        allOf(
          _failure(EmailConfirmationFailure.signupUnavailable),
          predicate((e) => !e.toString().contains('private')),
        ),
      ),
    );
    expect(client.auth.currentSession, isNull);
  });

  test(
    'exchange error keeps safe SDK category without provider text',
    () async {
      final sent = Completer<void>();
      late Uri callback;
      respond = (request) async {
        if (request.url.path == '/auth/v1/token') {
          return _json({
            'code': 'bad_code_verifier',
            'msg': 'private-code-value',
          }, status: 400);
        }
        callback = Uri.parse(request.url.queryParameters['redirect_to']!);
        return _json(_user());
      };
      final done = native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: true,
        port: 0,
        onEmailSent: sent.complete,
      );
      final rejected = expectLater(
        done,
        throwsA(
          allOf(
            _failure(EmailConfirmationFailure.exchangeFailed),
            predicate((e) => !e.toString().contains('private')),
          ),
        ),
      );
      await sent.future.timeout(const Duration(seconds: 10));
      expect(await _request(callback.replace(query: 'code=broken')), 400);
      await rejected;
      expect(client.auth.currentSession, isNull);
    },
  );

  test(
    'original email link verifies token hash without following redirect',
    () async {
      respond = (request) async {
        expect(request.method, 'POST');
        expect(request.url.origin, 'https://example.test');
        expect(request.url.path, '/auth/v1/verify');
        expect(request.url.queryParameters, isEmpty);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['token_hash'], 'pkce_synthetic-token-hash');
        expect(body['type'], 'signup');
        expect(body.containsKey('email'), isFalse);
        expect(body.containsKey('token'), isFalse);
        expect(body['redirect_to'], isNull);
        return _json(_session());
      };
      final response = await gateway.confirmEmailFromLink(
        link:
            'https://example.test/auth/v1/verify?token=pkce_synthetic-token-hash&type=signup&redirect_to=https%3A%2F%2Funtrusted.example',
      );
      expect(response.session?.user.id, _actor);
      expect(storage.writes, 0);
      expect(requests.length, 1);
    },
  );

  test('invalid, foreign and non-signup links make no Auth request', () async {
    for (final link in [
      '',
      'not a URL',
      'http://example.test/auth/v1/verify?token=x&type=signup',
      'https://foreign.test/auth/v1/verify?token=x&type=signup',
      'https://example.test:444/auth/v1/verify?token=x&type=signup',
      'https://name@example.test/auth/v1/verify?token=x&type=signup',
      'https://example.test/other?token=x&type=signup',
      'https://example.test/auth/v1/verify?token=x&type=signup#fragment',
      'https://example.test/auth/v1/verify?token=x&token=y&type=signup',
      'https://example.test/auth/v1/verify?token=x&type=signup&type=recovery',
      'https://example.test/auth/v1/verify?token=x&type=recovery',
      'https://example.test/auth/v1/verify?token=x&type=invite',
      'https://example.test/auth/v1/verify?token=x&type=email_change',
      'https://example.test/auth/v1/verify?token=&type=signup',
      'https://example.test/auth/v1/verify?token=x%20y&type=signup',
      'https://example.test/auth/v1/verify?code=x',
      'https://example.test/auth/v1/verify?token=x&type=signup&access_token=y',
      'https://example.test/auth/v1/verify?token=${'x' * 8200}&type=signup',
    ]) {
      await expectLater(
        gateway.confirmEmailFromLink(link: link),
        throwsA(_failure(EmailConfirmationFailure.invalidLink)),
      );
    }
    expect(requests, isEmpty);
    expect(client.auth.currentSession, isNull);
  });

  test(
    'already signed-in guards prevent every new flow replacing session',
    () async {
      await client.auth.setInitialSession(jsonEncode(_session()));
      await expectLater(
        gateway.createAccountAndConfirm(email: _email, password: _password),
        throwsA(_failure(EmailConfirmationFailure.alreadySignedIn)),
      );
      await expectLater(
        gateway.resendAndConfirmEmail(email: _email),
        throwsA(_failure(EmailConfirmationFailure.alreadySignedIn)),
      );
      await expectLater(
        gateway.confirmEmailFromLink(
          link: 'https://example.test/auth/v1/verify?token=x&type=signup',
        ),
        throwsA(_failure(EmailConfirmationFailure.alreadySignedIn)),
      );
      expect(requests, isEmpty);
      expect(client.auth.currentUser?.id, _actor);
    },
  );

  test('only recognized SDK error codes produce specific guidance', () {
    for (final entry in {
      'email_not_confirmed': EmailConfirmationFailure.emailNotConfirmed,
      'otp_expired': EmailConfirmationFailure.expired,
      'over_email_send_rate_limit': EmailConfirmationFailure.rateLimited,
      'over_request_rate_limit': EmailConfirmationFailure.rateLimited,
      'email_provider_disabled': EmailConfirmationFailure.signupUnavailable,
      'weak_password': EmailConfirmationFailure.weakPassword,
      'email_exists': EmailConfirmationFailure.failed,
      'user_already_exists': EmailConfirmationFailure.failed,
      'unknown': EmailConfirmationFailure.failed,
    }.entries) {
      expect(
        emailConfirmationFailure(AuthException('private', code: entry.key)),
        entry.value,
      );
    }
    expect(
      emailConfirmationFailure(StateError('email_not_confirmed')),
      EmailConfirmationFailure.failed,
    );
  });

  test(
    'non-Windows fallback announces pending confirmation without listener',
    () async {
      var sent = 0;
      respond = (request) async {
        expect(request.url.queryParameters, isEmpty);
        return _json(_user());
      };
      final result = await native.createAccountAndConfirm(
        client,
        email: _email,
        password: _password,
        useLoopback: false,
        onEmailSent: () => sent++,
      );
      expect(result.session, isNull);
      expect(sent, 1);
    },
  );
}
