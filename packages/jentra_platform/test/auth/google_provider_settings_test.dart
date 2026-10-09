import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/src/auth/google_provider_settings.dart';

void main() {
  final authorize = Uri.parse(
    'https://example.test/auth/v1/authorize?code_challenge=private-verifier&redirect_to=local',
  );
  test(
    'public availability uses exact settings path and public key without session or PKCE query',
    () async {
      for (final enabled in [false, true]) {
        final result = await googleProviderEnabled(
          authorize,
          'public-only-key',
          httpClient: MockClient((request) async {
            expect(
              request.url.toString(),
              'https://example.test/auth/v1/settings',
            );
            expect(
              request.headers.keys.map((s) => s.toLowerCase()),
              isNot(contains('authorization')),
            );
            expect(request.headers['apikey'], 'public-only-key');
            expect(request.followRedirects, false);
            return http.Response(
              jsonEncode({
                'external': {'google': enabled},
              }),
              200,
            );
          }),
        );
        expect(result, enabled);
      }
    },
  );
  test(
    'denied, malformed and oversized settings never certify a provider',
    () async {
      for (final response in [
        http.Response('private', 401),
        http.Response('{}', 200),
        http.Response('x' * 16385, 200),
      ]) {
        await expectLater(
          googleProviderEnabled(
            authorize,
            'public',
            httpClient: MockClient((_) async => response),
          ),
          throwsStateError,
        );
      }
    },
  );
  test('invalid auth origins abort without making a request', () async {
    for (final uri in [
      Uri.parse('http://foreign.test/auth/v1/authorize'),
      Uri.parse('https://example.test/foreign'),
    ]) {
      await expectLater(
        googleProviderEnabled(
          uri,
          'public',
          httpClient: MockClient((_) async => fail('no request')),
        ),
        throwsStateError,
      );
    }
  });
}
