import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '87000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1);

Map<String, Object?> spread() => {'p50': null, 'p90': null, 'samples': 0};
Map<String, Object?> rate() => {'value': null, 'samples': 0};
Map<String, Object?> empty() => {
  'from': '2026-07-22',
  'to': '2026-10-20',
  'engagements': 0,
  'metrics': {
    'stage_planning_days': spread(),
    'stage_fieldwork_days': spread(),
    'stage_reporting_days': spread(),
    'report_issuance_days': spread(),
    'evidence_waiting_days': spread(),
    'evidence_review_days': spread(),
    'evidence_first_time_right': rate(),
    'request_ageing': {'d0_7': 0, 'd8_30': 0, 'd31_plus': 0, 'samples': 0},
    'test_completion': rate(),
    'control_coverage': rate(),
    'retest_pass_rate': rate(),
    'recurrence': rate(),
    'finding_ageing_days': {
      'low': rate(),
      'medium': rate(),
      'high': rate(),
      'critical': rate(),
    },
    'overdue_remediation': {'value': 0},
    'open_high_risk_findings': {'value': 0},
    'workload': <Object?>[],
  },
};

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssuranceMetricsGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  setUp(() async {
    status = 200;
    requests.clear();
    response = empty();
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
    gateway = SupabaseAssuranceMetricsGateway(client);
  });
  tearDown(() => client.dispose());

  test('metrics are read for the scope and dates', () async {
    final m = await gateway.metrics(
      scope,
      DateTime.utc(2026, 7, 22),
      DateTime.utc(2026, 10, 20),
    );
    expect(m.engagements, 0);
    expect(m.firstTimeRight.value, isNull);
    expect(requests.single.url.path, endsWith('/rpc/assurance_metrics'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_from': '2026-07-22',
      'p_to': '2026-10-20',
    });
  });

  test('a reversed range is never sent', () async {
    await expectLater(
      gateway.metrics(
        scope,
        DateTime.utc(2026, 10, 20),
        DateTime.utc(2026, 1, 1),
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });

  test('an invalid read model and refusals are reported', () async {
    response = {...empty(), 'engagements': -1};
    await expectLater(
      gateway.metrics(
        scope,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      ),
      throwsFormatException,
    );
    status = 403;
    response = {'code': '42501', 'message': 'Permission denied'};
    await expectLater(
      gateway.metrics(
        scope,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      ),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    status = 400;
    response = {'code': '22023', 'message': 'ASSURANCE_RANGE_INVALID'};
    await expectLater(
      gateway.metrics(
        scope,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      ),
      throwsA(
        isA<DomainError>().having(
          (e) => e.message,
          'message',
          'Choose a period of at most a year.',
        ),
      ),
    );
  });

  test('a response for another period is rejected', () async {
    await expectLater(
      gateway.metrics(
        scope,
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      ),
      throwsFormatException,
    );
  });
}
