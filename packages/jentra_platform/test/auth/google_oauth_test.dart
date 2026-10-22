import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/src/auth/google_oauth_io.dart' as google;
import 'package:jentra_platform/src/auth/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _PkceStorage implements GotrueAsyncStorage {
  var writes = 0;

  @override
  Future<String?> getItem({required String key}) async => null;

  @override
  Future<void> setItem({required String key, required String value}) async {
    writes++;
  }

  @override
  Future<void> removeItem({required String key}) async {}
}

Matcher failure(GoogleSignInFailure value) =>
    isA<GoogleSignInException>().having((e) => e.failure, 'failure', value);

void main() {
  late _PkceStorage storage;
  late SupabaseClient client;

  setUp(() {
    storage = _PkceStorage();
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: storage,
      ),
      httpClient: MockClient((_) async => fail('no Auth request expected')),
    );
  });
  tearDown(() => client.dispose());

  test('disabled provider cannot write a verifier or start OAuth', () async {
    await expectLater(
      google.signInWithGoogle(
        client,
        settingsHttpClient: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://example.test/auth/v1/settings',
          );
          expect(request.headers['apikey'], 'synthetic-public-key');
          expect(request.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode({
              'external': {'google': false},
            }),
            200,
          );
        }),
      ),
      throwsA(failure(GoogleSignInFailure.providerDisabled)),
    );
    expect(storage.writes, 0);
    expect(client.auth.currentSession, isNull);
  });

  test('unavailable provider settings cannot write a verifier', () async {
    for (final response in [
      http.Response('private-provider-detail', 401),
      http.Response('{}', 200),
      http.Response('invalid-json', 200),
    ]) {
      await expectLater(
        google.signInWithGoogle(
          client,
          settingsHttpClient: MockClient((_) async => response),
        ),
        throwsA(
          allOf(
            failure(GoogleSignInFailure.settingsUnavailable),
            predicate((e) => !e.toString().contains('private-provider-detail')),
          ),
        ),
      );
      expect(storage.writes, 0);
    }
  });

  test('settings transport errors have a fixed safe failure', () async {
    await expectLater(
      google.signInWithGoogle(
        client,
        settingsHttpClient: MockClient((_) async {
          throw StateError('private-network-detail');
        }),
      ),
      throwsA(
        allOf(
          failure(GoogleSignInFailure.settingsUnavailable),
          predicate((e) => !e.toString().contains('private-network-detail')),
        ),
      ),
    );
    expect(storage.writes, 0);
  });

  test('cancelled preflight makes no request and writes no verifier', () async {
    final cancellation = GoogleSignInCancellation()..cancel();
    await expectLater(
      google.signInWithGoogle(
        client,
        cancellation: cancellation,
        settingsHttpClient: MockClient(
          (_) async => fail('no settings request'),
        ),
      ),
      throwsA(failure(GoogleSignInFailure.cancelled)),
    );
    expect(storage.writes, 0);
  });

  test(
    'cancelling pending settings cannot write a verifier after a late reply',
    () async {
      final cancellation = GoogleSignInCancellation();
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      final action = google.signInWithGoogle(
        client,
        cancellation: cancellation,
        settingsHttpClient: MockClient((_) {
          requested.complete();
          return pending.future;
        }),
      );
      final rejected = expectLater(
        action,
        throwsA(failure(GoogleSignInFailure.cancelled)),
      );
      await requested.future.timeout(const Duration(seconds: 10));
      cancellation.cancel();
      await rejected;
      pending.complete(
        http.Response(
          jsonEncode({
            'external': {'google': true},
          }),
          200,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(storage.writes, 0);
      expect(client.auth.currentSession, isNull);
    },
  );

  test('cancellation notification is idempotent', () async {
    final cancellation = GoogleSignInCancellation();
    expect(cancellation.isCancelled, isFalse);
    var notifications = 0;
    final notification = cancellation.whenCancelled.then(
      (_) => notifications++,
    );
    cancellation.cancel();
    cancellation.cancel();
    await notification;
    expect(cancellation.isCancelled, isTrue);
    expect(notifications, 1);
  });
}
