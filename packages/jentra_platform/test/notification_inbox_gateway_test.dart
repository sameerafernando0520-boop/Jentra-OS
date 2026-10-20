import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '86000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), tenant = uid(10);

Map<String, Object?> notice(int n, {String status = 'unread'}) => {
  'id': uid(n),
  'tenant_id': tenant,
  'notification_type': 'assurance.reminder',
  'title': 'Evidence request overdue',
  'body': 'Treasury review: an evidence request is overdue.',
  'aggregate_type': 'assurance_engagement',
  'aggregate_id': uid(50),
  'status': status,
  'read_at': null,
  'version': 2,
  'created_at': '2026-10-20T07:30:00Z',
};

void main() {
  final scope = TenantContext(
    tenantId: tenant,
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    status = 200;
    requests.clear();
    response = <Object?>[];
    client = SupabaseClient(
      'https://example.test',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        if (r.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': actor,
                    'role': 'authenticated',
                    'exp': 4102444800,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': actor,
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-01T00:00:00Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
  });
  tearDown(() => client.dispose());

  group('inbox', () {
    late SupabaseNotificationInboxGateway gateway;
    setUp(() => gateway = SupabaseNotificationInboxGateway(client));

    test('the latest notices are read newest first for the tenant', () async {
      response = [notice(2), notice(3, status: 'read')];
      final list = await gateway.latest(tenant);
      expect(list.map((n) => n.unread), [true, false]);
      final q = requests.single.url;
      expect(q.path, endsWith('/rest/v1/my_notifications'));
      expect(q.queryParameters['tenant_id'], 'eq.$tenant');
      expect(
        q.queryParameters['order'],
        matches(RegExp(r'^created_at\.desc(\.nullslast)?,id\.desc')),
      );
      expect(q.queryParameters['limit'], '20');
    });

    test('the unread count reads only unread ids, capped at 100', () async {
      response = [
        for (var i = 0; i < 3; i++) {'id': uid(20 + i)},
      ];
      expect(await gateway.unreadCount(tenant), 3);
      final q = requests.single.url;
      expect(q.queryParameters['status'], 'eq.unread');
      expect(q.queryParameters['select'], 'id');
      expect(q.queryParameters['limit'], '100');
    });

    test('marking read sends the version and a fresh key', () async {
      response = {'id': uid(2)};
      await gateway.markRead(tenant, InboxNotice.fromJson(notice(2)));
      final body = jsonDecode(requests.single.body) as Map;
      expect(requests.single.url.path, endsWith('/rpc/mark_notification_read'));
      expect(body['p_tenant_id'], tenant);
      expect(body['p_notification_id'], uid(2));
      expect(body['p_expected_version'], 2);
      expect(body['p_idempotency_key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('a changed notice is a version conflict', () async {
      status = 409;
      response = {'code': '40001', 'message': 'version conflict'};
      await expectLater(
        gateway.markRead(tenant, InboxNotice.fromJson(notice(2))),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
        ),
      );
    });

    test('a malformed list is rejected', () async {
      response = [
        {...notice(2), 'status': 'archived'},
      ];
      await expectLater(gateway.latest(tenant), throwsFormatException);
    });
  });

  group('reminder scan', () {
    late SupabaseAssuranceReminderGateway gateway;
    setUp(() => gateway = SupabaseAssuranceReminderGateway(client));

    test('a scan is sent in scope with its cursor and key', () async {
      response = {
        'examined': 100,
        'emitted': 4,
        'has_more': true,
        'next_after': uid(30),
      };
      final r = await gateway.scan(scope, uid(40), after: uid(29));
      expect(r.nextAfter, uid(30));
      expect(
        requests.single.url.path,
        endsWith('/rpc/assurance_scan_reminders'),
      );
      expect(jsonDecode(requests.single.body), {
        'p_tenant_id': tenant,
        'p_legal_entity_id': uid(11),
        'p_branch_id': uid(12),
        'p_idempotency_key': uid(40),
        'p_payload': {'after_id': uid(29)},
      });
    });

    test('refusals map to the client contract', () async {
      status = 403;
      response = {'code': '42501', 'message': 'Permission denied'};
      await expectLater(
        gateway.scan(scope, uid(40)),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
        ),
      );
    });
  });
}
