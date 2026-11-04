import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:jentra_platform/src/auth/browser_auth_return.dart';
import 'package:jentra_platform/src/auth/email_confirmation.dart';
import 'package:jentra_platform/src/auth/email_confirmation_stub.dart' as mail;

final class _Storage implements GotrueAsyncStorage {
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

void main() {
  const actor = '10000000-0000-0000-0000-000000000001';
  Map<String, Object?> user() => {
    'id': actor,
    'email': 'synthetic@example.test',
    'aud': 'authenticated',
    'role': 'authenticated',
    'created_at': '2026-10-29T00:00:00Z',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
  };
  Map<String, Object?> session() {
    final claims = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': actor,
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
              'aal': 'aal1',
            }),
          ),
        )
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
      'refresh_token': 'synthetic-refresh',
      'expires_in': 3600,
      'token_type': 'bearer',
      'user': user(),
    };
  }

  late SupabaseClient client;
  final requests = <http.Request>[];
  String? exchangeError;
  setUp(() {
    takeBrowserAuthReturnFailure();
    requests.clear();
    exchangeError = null;
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        authFlowType: AuthFlowType.pkce,
        pkceAsyncStorage: _Storage(),
      ),
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = request.url.path.endsWith('/signup')
            ? user()
            : request.url.path.endsWith('/resend')
            ? <String, Object?>{}
            : session();
        if (request.url.path.endsWith('/token') && exchangeError != null) {
          return http.Response(
            jsonEncode({
              'code': exchangeError,
              'msg': 'private diagnostic synthetic-code',
            }),
            400,
            headers: {
              'content-type': 'application/json',
              'x-supabase-api-version': '2024-01-01',
            },
          );
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDown(() async {
    takeBrowserAuthReturnFailure();
    await client.dispose();
  });

  test('redirect uses only current secure origin and discards route/query', () {
    expect(
      browserVerificationRedirect(
        Uri.parse(
          'https://jentra-os-desktop.web.app/#/login?redirect=/dashboard',
        ),
      ),
      'https://jentra-os-desktop.web.app/',
    );
    expect(
      browserVerificationRedirect(Uri.parse('http://127.0.0.1:8485/#/login')),
      'http://127.0.0.1:8485/',
    );
    expect(
      () => browserVerificationRedirect(Uri.parse('http://example.test/')),
      throwsA(isA<EmailConfirmationException>()),
    );
    expect(
      () =>
          browserVerificationRedirect(Uri.parse('https://name@example.test/')),
      throwsA(isA<EmailConfirmationException>()),
    );
  });
  test('ordinary navigation does not become an authentication return', () {
    expect(
      parseBrowserAuthReturn(
        Uri.parse('https://example.test/#/login?redirect=/dashboard'),
      ).present,
      isFalse,
    );
  });
  for (final value in [
    'https://example.test/?code=',
    'https://example.test/?code=a&code=b',
    'https://example.test/?code=a&redirect_to=https://other.test',
    'https://example.test/?code=one%20two',
    'https://example.test/login?code=a',
    'https://example.test/?code=a&error=access_denied',
    'https://example.test/?access_token=synthetic',
    'https://example.test/#access_token=synthetic&refresh_token=synthetic',
    'https://example.test/?code=a#refresh_token=synthetic',
    'https://example.test/#/login?code=synthetic',
    'http://example.test/?code=a',
  ]) {
    test(
      'reject unsafe callback ${Uri.parse(value).path} ${value.hashCode}',
      () async {
        final pending = parseBrowserAuthReturn(Uri.parse(value));
        expect(pending.failure, EmailConfirmationFailure.invalidLink);
        await completeBrowserAuthReturn(client, pending);
        expect(requests, isEmpty);
        expect(client.auth.currentSession, isNull);
      },
    );
  }
  test(
    'provider expiry is categorized without forwarding private descriptions',
    () async {
      await completeBrowserAuthReturn(
        client,
        parseBrowserAuthReturn(
          Uri.parse(
            'https://example.test/?error=access_denied&error_code=otp_expired&error_description=private',
          ),
        ),
      );
      expect(takeBrowserAuthReturnFailure(), EmailConfirmationFailure.expired);
      expect(takeBrowserAuthReturnFailure(), isNull);
      expect(requests, isEmpty);
    },
  );
  test('signup and resend carry the same explicit browser root', () async {
    const redirect = 'https://jentra-os-desktop.web.app/';
    await mail.createAccountAndConfirm(
      client,
      email: 'synthetic@example.test',
      password: 'Synthetic7!long',
      emailRedirectTo: redirect,
    );
    await mail.resendAndConfirmEmail(
      client,
      email: 'synthetic@example.test',
      emailRedirectTo: redirect,
    );
    expect(requests, hasLength(2));
    for (final request in requests) {
      expect(request.url.queryParameters['redirect_to'], redirect);
    }
  });
  test(
    'PKCE exchange consumes original verifier and installs returned identity',
    () async {
      await mail.createAccountAndConfirm(
        client,
        email: 'synthetic@example.test',
        password: 'Synthetic7!long',
      );
      requests.clear();
      await completeBrowserAuthReturn(
        client,
        parseBrowserAuthReturn(
          Uri.parse('https://example.test/?code=synthetic-code'),
        ),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['grant_type'], 'pkce');
      expect(jsonDecode(requests.single.body)['auth_code'], 'synthetic-code');
      expect(client.auth.currentUser?.id, actor);
      expect(takeBrowserAuthReturnFailure(), isNull);
    },
  );
  test('existing signed-in identity cannot be replaced by callback', () async {
    await client.auth.setInitialSession(jsonEncode(session()));
    requests.clear();
    await completeBrowserAuthReturn(
      client,
      const BrowserAuthReturn.code('synthetic-code'),
    );
    expect(requests, isEmpty);
    expect(client.auth.currentUser?.id, actor);
    expect(
      takeBrowserAuthReturnFailure(),
      EmailConfirmationFailure.alreadySignedIn,
    );
  });
  test(
    'failed exchange preserves signed-out state and only a safe notice',
    () async {
      await mail.createAccountAndConfirm(
        client,
        email: 'synthetic@example.test',
        password: 'Synthetic7!long',
      );
      requests.clear();
      exchangeError = 'flow_state_expired';
      await completeBrowserAuthReturn(
        client,
        const BrowserAuthReturn.code('synthetic-code'),
      );
      expect(client.auth.currentSession, isNull);
      expect(takeBrowserAuthReturnFailure(), EmailConfirmationFailure.expired);
    },
  );
}
