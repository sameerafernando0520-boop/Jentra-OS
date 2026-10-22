import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/src/auth/pkce_exchange_http_client.dart';
import 'package:jentra_platform/src/wave3_observability.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _stalledDeadline = Duration(seconds: 30);
const _ioWatchdog = Duration(seconds: 10);

/// Controls only the first timer with the configured PKCE deadline. The actual
/// loopback I/O still runs normally, with bounded server-arrival watchdogs.
/// Expiring after arrival proves the intended stalled phase without requiring
/// the OS to establish a connection before a 120 ms wall-clock deadline.
final class _DeadlineControl {
  _ControlledTimer? _timer;

  Future<T> run<T>(Future<T> Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == _stalledDeadline && _timer == null) {
          return _timer = _ControlledTimer(callback);
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );

  void expire() {
    expect(_timer, isNotNull, reason: 'PKCE must schedule its deadline');
    expect(_timer!.isActive, isTrue);
    _timer!.fire();
  }
}

final class _ControlledTimer implements Timer {
  _ControlledTimer(this._callback);

  final void Function() _callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;

  @override
  void cancel() => _active = false;

  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    _callback();
  }
}

final class _Storage implements GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async => values.remove(key);
}

String _session() {
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
  return jsonEncode({
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
    'refresh_token': 'synthetic-refresh-only',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': '10000000-0000-0000-0000-000000000001',
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'synthetic@example.test',
      'created_at': '2026-10-09T00:00:00Z',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
    },
  });
}

SupabaseClient _client(
  String base, {
  Duration deadline = const Duration(milliseconds: 120),
}) => SupabaseClient(
  base,
  'synthetic-public-key',
  authOptions: AuthClientOptions(
    autoRefreshToken: false,
    authFlowType: AuthFlowType.pkce,
    pkceAsyncStorage: _Storage(),
  ),
  httpClient: Wave3ObservedHttpClient(
    PkceExchangeHttpClient(
      http.Client(),
      tokenUri: Uri.parse('$base/auth/v1/token'),
      deadline: deadline,
    ),
    sink: (_) {},
  ),
);

Future<void> _verifier(SupabaseClient client) async {
  await client.auth.getOAuthSignInUrl(provider: OAuthProvider.google);
}

void main() {
  for (final bodyStall in [false, true]) {
    test(
      'SDK ${bodyStall ? 'body' : 'headers'} deadline aborts without a late session',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final base = 'http://127.0.0.1:${server.port}';
        final client = _client(base, deadline: _stalledDeadline);
        final deadline = _DeadlineControl();
        final arrived = Completer<void>(),
            release = Completer<void>(),
            sent = Completer<void>();
        final events = <AuthChangeEvent>[];
        final eventsSubscription = client.auth.onAuthStateChange.listen(
          (e) => events.add(e.event),
        );
        server.listen((request) async {
          try {
            await request.drain<void>();
            request.response.headers.contentType = ContentType.json;
            final session = _session();
            if (bodyStall) {
              request.response.write(session.substring(0, 1));
              await request.response.flush();
            }
            arrived.complete();
            await release.future;
            request.response.write(bodyStall ? session.substring(1) : session);
            await request.response.close();
          } on Object {
            // Expected disconnect from the aborted local synthetic transport.
          } finally {
            if (!sent.isCompleted) sent.complete();
          }
        });
        try {
          await _verifier(client);
          final exchange = deadline.run(
            () => client.auth.exchangeCodeForSession('synthetic-code-only'),
          );
          final rejected = expectLater(
            exchange.timeout(_ioWatchdog),
            throwsA(
              isA<AuthException>().having(
                (e) => e.message,
                'safe error',
                contains('PKCE_EXCHANGE_DEADLINE_EXCEEDED'),
              ),
            ),
          );
          await arrived.future.timeout(_ioWatchdog);
          deadline.expire();
          await rejected;
          release.complete();
          await sent.future.timeout(_ioWatchdog);
          expect(client.auth.currentSession, isNull);
          expect(events, isNot(contains(AuthChangeEvent.signedIn)));
        } finally {
          if (!release.isCompleted) release.complete();
          await eventsSubscription.cancel();
          await client.dispose();
          await server.close(force: true);
        }
      },
    );
  }

  test(
    'stalled TLS handshake terminates SDK exchange without a session',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final connected = Completer<void>();
      server.listen((socket) {
        sockets.add(socket);
        socket.listen((_) {}, onError: (_) {});
        if (!connected.isCompleted) connected.complete();
      });
      final client = _client(
        'https://127.0.0.1:${server.port}',
        deadline: _stalledDeadline,
      );
      final deadline = _DeadlineControl();
      try {
        await _verifier(client);
        final rejected = expectLater(
          deadline
              .run(
                () => client.auth.exchangeCodeForSession('synthetic-code-only'),
              )
              .timeout(_ioWatchdog),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'safe error',
              contains('PKCE_EXCHANGE_DEADLINE_EXCEEDED'),
            ),
          ),
        );
        await connected.future.timeout(_ioWatchdog);
        deadline.expire();
        await rejected;
        expect(client.auth.currentSession, isNull);
      } finally {
        await client.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close();
      }
    },
  );

  test(
    'bounded successful SDK exchange installs exactly one session',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = _client(
        'http://127.0.0.1:${server.port}',
        deadline: const Duration(seconds: 2),
      );
      var requests = 0;
      server.listen((request) async {
        requests++;
        expect(request.uri.path, '/auth/v1/token');
        expect(request.uri.queryParameters['grant_type'], 'pkce');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['auth_code'], 'synthetic-code-only');
        expect(body['code_verifier'], isNotEmpty);
        request.response.headers.contentType = ContentType.json;
        request.response.write(_session());
        await request.response.close();
      });
      try {
        await _verifier(client);
        final response = await client.auth.exchangeCodeForSession(
          'synthetic-code-only',
        );
        expect(
          response.session.user.id,
          '10000000-0000-0000-0000-000000000001',
        );
        expect(client.auth.currentSession, isNotNull);
        expect(requests, 1);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );

  test('non-PKCE requests retain their original client and bytes', () async {
    late http.Request received;
    final inner = MockClient((request) async {
      received = request;
      return http.Response('ordinary', 200);
    });
    final client = PkceExchangeHttpClient(
      inner,
      tokenUri: Uri.parse('https://example.test/auth/v1/token'),
    );
    try {
      final response = await client.post(
        Uri.parse('https://example.test/auth/v1/token?grant_type=password'),
        headers: {'x-ordinary': 'yes'},
        body: 'ordinary-body',
      );
      expect(response.body, 'ordinary');
      expect(received.body, 'ordinary-body');
      expect(received.headers['x-ordinary'], 'yes');
    } finally {
      client.close();
    }
  });

  test('redirects and oversized PKCE responses never reach the SDK', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirect = true, followed = 0;
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path != '/auth/v1/token') {
        followed++;
      }
      if (redirect) {
        request.response.statusCode = 302;
        request.response.headers.set('location', '$base/foreign');
      } else {
        request.response.write('x' * 65537);
      }
      await request.response.close();
    });
    final client = _client(base, deadline: const Duration(seconds: 2));
    try {
      for (final mode in [true, false]) {
        redirect = mode;
        await _verifier(client);
        await expectLater(
          client.auth.exchangeCodeForSession('synthetic-code-only'),
          throwsA(isA<AuthException>()),
        );
        expect(client.auth.currentSession, isNull);
      }
      expect(followed, 0);
    } finally {
      await client.dispose();
      await server.close(force: true);
    }
  });
}
