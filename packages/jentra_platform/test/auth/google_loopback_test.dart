import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/src/auth/google_loopback.dart';

Future<int> request(Uri uri, {String method = 'GET', String? host}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, uri);
    if (host != null) req.headers.set(HttpHeaders.hostHeader, host);
    final response = await req.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test(
    'browser disconnect cannot turn a completed SDK exchange into failure',
    () async {
      late Uri callback;
      final started = Completer<void>(),
          accepted = Completer<void>(),
          release = Completer<void>();
      final flow = GoogleLoopbackSignIn(
        port: 0,
        launch: (uri) async {
          callback = uri;
          started.complete();
          return true;
        },
        exchange: (_) async {
          accepted.complete();
          await release.future;
        },
      );
      final done = flow.run();
      await started.future;
      final socket = await Socket.connect(callback.host, callback.port);
      socket.write(
        'GET ${callback.path}?code=one HTTP/1.1\r\nHost: ${callback.authority}\r\n\r\n',
      );
      await socket.flush();
      await accepted.future;
      socket.destroy();
      release.complete();
      expect(await done.timeout(const Duration(seconds: 3)), true);
    },
  );
  test(
    'binds only loopback, random path and exact host; exchanges one code',
    () async {
      Uri? callback;
      final exchanges = <String>[];
      final started = Completer<void>();
      final flow = GoogleLoopbackSignIn(
        port: 0,
        timeout: const Duration(seconds: 3),
        launch: (uri) async {
          callback = uri;
          started.complete();
          return true;
        },
        exchange: (code) async => exchanges.add(code),
      );
      final done = flow.run();
      await started.future;
      expect(callback!.host, '127.0.0.1');
      expect(
        callback!.path,
        matches(RegExp(r'^/auth/callback/[A-Za-z0-9_-]{43}$')),
      );
      expect(
        await request(
          callback!.replace(path: '/auth/callback/wrong', query: 'code=no'),
        ),
        404,
      );
      expect(
        await request(
          callback!.replace(query: 'code=no'),
          host: 'foreign.example',
        ),
        404,
      );
      expect(
        await request(callback!.replace(query: 'code=no'), method: 'POST'),
        404,
      );
      expect(exchanges, isEmpty);
      expect(
        await request(callback!.replace(query: 'code=one-original-code')),
        200,
      );
      expect(await done, isTrue);
      expect(exchanges, ['one-original-code']);
    },
  );

  test('duplicate or token-bearing returns cannot install a session', () async {
    late Uri callback;
    var exchanges = 0;
    final started = Completer<void>();
    final flow = GoogleLoopbackSignIn(
      port: 0,
      launch: (uri) async {
        callback = uri;
        started.complete();
        return true;
      },
      exchange: (_) async {
        exchanges++;
      },
    );
    final done = flow.run();
    await started.future;
    expect(await request(callback.replace(query: 'code=a&code=b')), 400);
    expect(
      await request(callback.replace(query: 'code=a&access_token=secret')),
      400,
    );
    expect(exchanges, 0);
    expect(await request(callback.replace(query: 'code=valid')), 200);
    expect(await done, true);
    expect(exchanges, 1);
  });

  test(
    'no competing exchange and accepted exchange survives the wait deadline',
    () async {
      late Uri callback;
      final accepted = Completer<void>(),
          release = Completer<void>(),
          started = Completer<void>();
      var exchanges = 0;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        timeout: const Duration(milliseconds: 150),
        launch: (uri) async {
          callback = uri;
          started.complete();
          return true;
        },
        exchange: (_) async {
          exchanges++;
          accepted.complete();
          await release.future;
        },
      );
      final done = flow.run();
      await started.future;
      final first = request(callback.replace(query: 'code=first'));
      await accepted.future;
      expect(await request(callback.replace(query: 'code=second')), 404);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      release.complete();
      expect(await first, 200);
      expect(await done, true);
      expect(exchanges, 1);
    },
  );

  test('browser decline closes listener and never exchanges', () async {
    late Uri callback;
    final flow = GoogleLoopbackSignIn(
      port: 0,
      launch: (uri) async {
        callback = uri;
        return false;
      },
      exchange: (_) async => fail('must not exchange'),
    );
    await expectLater(flow.run(), throwsStateError);
    await expectLater(
      request(callback.replace(query: 'code=late')),
      throwsA(isA<SocketException>()),
    );
  });

  test(
    'waiting timeout closes listener; a late callback cannot exchange',
    () async {
      late Uri callback;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        timeout: const Duration(milliseconds: 50),
        launch: (uri) async {
          callback = uri;
          return true;
        },
        exchange: (_) async => fail('must not exchange'),
      );
      await expectLater(flow.run(), throwsA(isA<TimeoutException>()));
      await expectLater(
        request(callback.replace(query: 'code=late')),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'provider denial and exchange errors expose only static failure',
    () async {
      for (final query in [
        'error=access_denied&error_description=private',
        'code=broken',
      ]) {
        late Uri callback;
        final started = Completer<void>();
        final flow = GoogleLoopbackSignIn(
          port: 0,
          launch: (uri) async {
            callback = uri;
            started.complete();
            return true;
          },
          exchange: (_) async => throw Exception('private provider details'),
        );
        final done = flow.run();
        final failure = expectLater(
          done,
          throwsA(predicate((e) => !e.toString().contains('private'))),
        );
        await started.future;
        expect(await request(callback.replace(query: query)), 400);
        await failure;
      }
    },
  );

  test('port collision aborts before browser or verifier mutation', () async {
    final occupied = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final flow = GoogleLoopbackSignIn(
        port: occupied.port,
        launch: (_) async => fail('browser must not launch'),
        exchange: (_) async => fail('must not exchange'),
      );
      await expectLater(flow.run(), throwsA(isA<SocketException>()));
    } finally {
      await occupied.close(force: true);
    }
  });
}
