import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _other = '10000000-0000-0000-0000-000000000002';

Map<String, Object?> _user(String actor, {String? name}) => {
  'id': actor,
  'aud': 'authenticated',
  'role': 'authenticated',
  'email': 'member@example.test',
  'created_at': '2026-10-22T00:00:00Z',
  'user_metadata': {'locale': 'en', 'full_name': ?name},
  'app_metadata': {'provider': 'email'},
};
Map<String, Object?> _session(String actor) {
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
    'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
    'refresh_token': 'synthetic-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': _user(actor),
  };
}

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  late SupabaseClient client;
  late SupabaseFoundationGateway gateway;
  var actor = _actor;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? update;
  setUp(() {
    actor = _actor;
    update = null;
    requests.clear();
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/token')) return _json(_session(actor));
        if (request.url.path.endsWith('/user') && update != null) {
          return update!(request);
        }
        throw StateError('Unexpected synthetic endpoint');
      }),
    );
    gateway = SupabaseFoundationGateway(client);
  });
  tearDown(() => client.dispose());
  Future<void> signIn() => client.auth.signInWithPassword(
    email: 'member@example.test',
    password: 'Synthetic-password-123',
  );

  test('signed-out profile update is rejected before any request', () async {
    await expectLater(
      gateway.updateAccountDisplayName('Example Member'),
      throwsStateError,
    );
    expect(requests, isEmpty);
  });

  test('name update trims text and sends only user display metadata', () async {
    await signIn();
    update = (request) async {
      expect(request.method, 'PUT');
      final body = jsonDecode(request.body) as Map;
      expect(body['data'], {'full_name': 'Example Member'});
      expect(
        body.keys.any(
          (key) => key.toString().contains('role') || key == 'app_metadata',
        ),
        isFalse,
      );
      expect((body['data'] as Map).keys, ['full_name']);
      return _json(_user(actor, name: 'Example Member'));
    };
    final result = await gateway.updateAccountDisplayName('  Example Member  ');
    expect(result.user?.userMetadata?['full_name'], 'Example Member');
    expect(gateway.currentUser?.userMetadata?['locale'], 'en');
    expect(gateway.currentAssurance(), MfaAssurance.aal1);
  });

  test(
    'empty, oversized and control-bearing values cannot reach Auth',
    () async {
      await signIn();
      final before = requests.length;
      for (final name in [
        '',
        '   ',
        'x' * 101,
        'Name\nAdmin',
        '\tMember',
        'Member\u0085Admin',
        'Member\u2028Admin',
      ]) {
        await expectLater(
          gateway.updateAccountDisplayName(name),
          throwsA(isA<FormatException>()),
        );
      }
      expect(requests.length, before);
    },
  );

  test('100 Unicode code points remain a valid name', () async {
    await signIn();
    final name = '名' * 100;
    update = (_) async => _json(_user(actor, name: name));
    expect(
      (await gateway.updateAccountDisplayName(
        name,
      )).user?.userMetadata?['full_name'],
      name,
    );
  });

  test(
    'late profile response cannot replace another signed-in actor',
    () async {
      await signIn();
      final submitted = Completer<void>();
      final release = Completer<http.Response>();
      update = (_) {
        submitted.complete();
        return release.future;
      };
      final pending = gateway.updateAccountDisplayName('Previous Member');
      await submitted.future;
      actor = _other;
      await signIn();
      release.complete(_json(_user(_actor, name: 'Previous Member')));
      await pending;
      expect(gateway.currentUser?.id, _other);
      expect(gateway.currentUser?.userMetadata?['full_name'], isNull);
    },
  );
}
