import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/src/auth/google_loopback.dart';
import 'package:jentra_platform/src/auth/google_sign_in.dart';

Matcher failure(GoogleSignInFailure value) =>
    isA<GoogleSignInException>().having((e) => e.failure, 'failure', value);

const _waitingDeadline = Duration(seconds: 30);

/// Keep real socket I/O, but advance the waiting timer only after its phase is
/// reached. OS scheduling must not decide whether a code arrived before 150 ms.
final class _WaitingDeadlineControl {
  _WaitingTimer? timer;

  Future<T> run<T>(Future<T> Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == _waitingDeadline && timer == null) {
          return timer = _WaitingTimer(callback);
        }
        return parent.createTimer(zone, duration, callback);
      },
    ),
  );
}

final class _WaitingTimer implements Timer {
  _WaitingTimer(this.callback);

  final void Function() callback;
  bool _active = true;
  int _tick = 0;

  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;

  void elapse() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

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
      final deadline = _WaitingDeadlineControl();
      var exchanges = 0;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        timeout: _waitingDeadline,
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
      final done = deadline.run(flow.run);
      await started.future.timeout(const Duration(seconds: 10));
      expect(deadline.timer?.isActive, isTrue);
      final first = request(callback.replace(query: 'code=first'));
      await accepted.future.timeout(const Duration(seconds: 10));
      expect(await request(callback.replace(query: 'code=second')), 404);
      expect(deadline.timer?.isActive, isFalse);
      deadline.timer!.elapse();
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
    await expectLater(
      flow.run(),
      throwsA(failure(GoogleSignInFailure.browserUnavailable)),
    );
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
      for (final entry in {
        'error=access_denied&error_description=private':
            GoogleSignInFailure.cancelled,
        'error=server_error&error_description=private':
            GoogleSignInFailure.callbackRejected,
        'code=broken': GoogleSignInFailure.exchangeFailed,
      }.entries) {
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
        final rejection = expectLater(
          done,
          throwsA(
            allOf(
              failure(entry.value),
              predicate((e) => !e.toString().contains('private')),
            ),
          ),
        );
        await started.future;
        expect(await request(callback.replace(query: entry.key)), 400);
        await rejection;
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
      await expectLater(
        flow.run(),
        throwsA(failure(GoogleSignInFailure.callbackUnavailable)),
      );
    } finally {
      await occupied.close(force: true);
    }
  });

  test('cancel before start never opens a browser or exchange', () async {
    final cancellation = GoogleSignInCancellation()..cancel();
    final flow = GoogleLoopbackSignIn(
      port: 0,
      cancellation: cancellation,
      launch: (_) async => fail('must not launch'),
      exchange: (_) async => fail('must not exchange'),
    );
    await expectLater(
      flow.run(),
      throwsA(failure(GoogleSignInFailure.cancelled)),
    );
  });

  test(
    'cancel closes waiting listener and rejects a stale browser return',
    () async {
      final cancellation = GoogleSignInCancellation();
      final launched = Completer<void>();
      late Uri callback;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        cancellation: cancellation,
        launch: (uri) async {
          callback = uri;
          launched.complete();
          return true;
        },
        exchange: (_) async => fail('must not exchange'),
      );
      final result = flow.run();
      final rejected = expectLater(
        result,
        throwsA(failure(GoogleSignInFailure.cancelled)),
      );
      await launched.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      cancellation.cancel();
      await rejected;
      await expectLater(
        request(callback.replace(query: 'code=stale')),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'accepted exchange announces its stage and ignores cancellation',
    () async {
      final cancellation = GoogleSignInCancellation();
      final launched = Completer<void>();
      final accepted = Completer<void>();
      final release = Completer<void>();
      final sequence = <String>[];
      late Uri callback;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        cancellation: cancellation,
        onExchangeStarted: () => sequence.add('announced'),
        launch: (uri) async {
          callback = uri;
          launched.complete();
          return true;
        },
        exchange: (_) async {
          sequence.add('exchange');
          accepted.complete();
          await release.future;
        },
      );
      final result = flow.run();
      await launched.future.timeout(const Duration(seconds: 10));
      final response = request(callback.replace(query: 'code=accepted'));
      await accepted.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(sequence, ['announced', 'exchange']);
      release.complete();
      expect(await response, 200);
      expect(await result, isTrue);
    },
  );

  test(
    'cancel waits for pending launcher cleanup before allowing a retry',
    () async {
      final cancellation = GoogleSignInCancellation();
      final launched = Completer<void>();
      final launchResult = Completer<bool>();
      late Uri callback;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        cancellation: cancellation,
        launch: (uri) {
          callback = uri;
          launched.complete();
          return launchResult.future;
        },
        exchange: (_) async => fail('must not exchange'),
      );
      final result = flow.run();
      var returned = false;
      unawaited(
        result.then<void>(
          (_) => returned = true,
          onError: (Object _) {
            returned = true;
          },
        ),
      );
      final rejected = expectLater(
        result.timeout(const Duration(seconds: 10)),
        throwsA(failure(GoogleSignInFailure.cancelled)),
      );
      await launched.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(returned, isFalse);
      expect(await request(callback.replace(query: 'code=stale')), 404);
      launchResult.completeError(StateError('private late launcher error'));
      await rejected;
      expect(returned, isTrue);
      await expectLater(
        request(callback.replace(query: 'code=stale')),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test(
    'accepted exchange owns the result even if launcher later fails',
    () async {
      final launched = Completer<void>();
      final launchResult = Completer<bool>();
      final accepted = Completer<void>();
      final release = Completer<void>();
      late Uri callback;
      final flow = GoogleLoopbackSignIn(
        port: 0,
        launch: (uri) {
          callback = uri;
          launched.complete();
          return launchResult.future;
        },
        exchange: (_) async {
          accepted.complete();
          await release.future;
        },
      );
      final result = flow.run();
      await launched.future.timeout(const Duration(seconds: 10));
      final response = request(callback.replace(query: 'code=accepted'));
      await accepted.future.timeout(const Duration(seconds: 10));
      launchResult.completeError(StateError('private late launcher error'));
      await Future<void>.delayed(Duration.zero);
      release.complete();
      expect(await response, 200);
      expect(await result, isTrue);
    },
  );

  test('a competing run fails before a second browser launch', () async {
    final cancellation = GoogleSignInCancellation();
    final launched = Completer<void>();
    var launches = 0;
    final flow = GoogleLoopbackSignIn(
      port: 0,
      cancellation: cancellation,
      launch: (_) async {
        launches++;
        launched.complete();
        return true;
      },
      exchange: (_) async => fail('must not exchange'),
    );
    final result = flow.run();
    final rejected = expectLater(
      result,
      throwsA(failure(GoogleSignInFailure.cancelled)),
    );
    await launched.future.timeout(const Duration(seconds: 10));
    await expectLater(
      flow.run(),
      throwsA(failure(GoogleSignInFailure.alreadyPending)),
    );
    cancellation.cancel();
    await rejected;
    expect(launches, 1);
  });
}
