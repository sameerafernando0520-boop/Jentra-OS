import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '80000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), eng = uid(2), finding = uid(3);

Map<String, Object?> overview() => {
  'as_of': DateTime.now().toUtc().toIso8601String().substring(0, 10),
  'response_sla_days': 14,
  'mine': <Object?>[],
  'team': <Object?>[],
  'counts': {'due_soon': 0, 'overdue': 0, 'escalated': 0},
};

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  late SupabaseClient client;
  late SupabaseAssuranceGateway gateway;
  Object? response;
  var status = 200;
  final requests = <http.Request>[];
  CommandEnvelope<Map<String, Object?>> respond({bool accept = false}) =>
      CommandEnvelope(
        commandId: uid(20),
        idempotencyKey: uid(21),
        context: scope,
        expectedEntityVersion: 7,
        payload: {
          'action': 'respond',
          'engagement_id': eng,
          'finding_id': finding,
          'response': 'Second signatory enforced',
          'due_date': '2099-01-31',
          'accept_risk': accept,
        },
      );
  setUp(() async {
    status = 200;
    requests.clear();
    response = overview();
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
    gateway = SupabaseAssuranceGateway(client);
  });
  tearDown(() => client.dispose());

  test('work queue is read in the selected scope', () async {
    final o = await gateway.overview(scope);
    expect(o.mine, isEmpty);
    expect(requests.single.url.path, endsWith('/rpc/assurance_overview'));
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
    });
  });

  test('another actor cannot use the gateway for this scope', () async {
    final foreign = TenantContext(
      tenantId: scope.tenantId,
      actorId: uid(99),
      legalEntityId: scope.legalEntityId,
      branchId: scope.branchId,
    );
    await expectLater(
      gateway.overview(foreign),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    expect(requests, isEmpty);
  });

  test('server denials map to the client contract', () async {
    for (final (code, message, expected) in [
      ('42501', 'ASSURANCE_RECENT_MFA_REQUIRED', 'MFA_REQUIRED'),
      ('42501', 'Permission denied', 'PERMISSION_DENIED'),
      ('40001', 'ASSURANCE_VERSION_CONFLICT', 'VERSION_CONFLICT'),
      ('55000', 'ASSURANCE_TRANSITION_INVALID', 'VALIDATION_ERROR'),
      ('P0002', 'ASSURANCE_FINDING_NOT_FOUND', 'NOT_FOUND'),
      ('57014', 'canceling statement', 'UNCERTAIN_RESULT'),
    ]) {
      status = 400;
      response = {'code': code, 'message': message};
      await expectLater(
        gateway.overview(scope),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
        reason: code,
      );
    }
  });

  test(
    'respond sends the sealed key and version and verifies the receipt',
    () async {
      final c = respond();
      response = {
        'engagement_id': eng,
        'version': 8,
        'status': 'fieldwork',
        'action': 'respond',
        'aggregate_type': 'finding',
        'aggregate_id': finding,
        'to_status': 'remediating',
      };
      await gateway.respond(c);
      final body = jsonDecode(requests.single.body) as Map;
      expect(requests.single.url.path, endsWith('/rpc/assurance_command'));
      expect(body['p_idempotency_key'], uid(21));
      expect(body['p_expected_version'], 7);
      expect(body['p_payload'], c.payload);
    },
  );

  test('a receipt that does not match the request is uncertain', () async {
    for (final bad in [
      {'aggregate_id': uid(4)},
      {'version': 9},
      {'to_status': 'risk_pending'},
    ]) {
      response = {
        'engagement_id': eng,
        'version': 8,
        'status': 'fieldwork',
        'action': 'respond',
        'aggregate_type': 'finding',
        'aggregate_id': finding,
        'to_status': 'remediating',
        ...bad,
      };
      await expectLater(
        gateway.respond(respond()),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
        reason: '$bad',
      );
    }
  });

  CommandEnvelope<Map<String, Object?>> auditor(Map<String, Object?> p) =>
      CommandEnvelope(
        commandId: uid(30),
        idempotencyKey: uid(31),
        context: scope,
        expectedEntityVersion: 7,
        payload: {'engagement_id': eng, ...p},
      );

  test('auditor commands route by family and verify the aggregate', () async {
    final export = auditor({
      'action': 'export_pack',
      'export_id': uid(40),
      'report_id': uid(41),
    });
    response = {
      'engagement_id': eng,
      'version': 8,
      'status': 'issued',
      'action': 'export_pack',
      'aggregate_type': 'export',
      'aggregate_id': uid(40),
      'to_status': 'exported',
    };
    await gateway.auditorCommand(export);
    expect(
      requests.single.url.path,
      endsWith('/rpc/assurance_evidence_command'),
    );
    expect((jsonDecode(requests.single.body) as Map)['p_expected_version'], 7);
    response = {...response! as Map, 'aggregate_id': uid(42)};
    await expectLater(
      gateway.auditorCommand(export),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
    requests.clear();
    await expectLater(
      gateway.auditorCommand(auditor({'action': 'respond'})),
      throwsFormatException,
    );
    await expectLater(
      gateway.auditorCommand(
        auditor({
          'action': 'record_exception',
          'exception_id': uid(43),
          'control_id': uid(44),
          'description': 'x',
          'severity': 'high',
        }),
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });

  test('independence refusals do not read as lost access', () async {
    status = 400;
    response = {
      'code': '42501',
      'message': 'ASSURANCE_INDEPENDENT_REVIEW_REQUIRED',
    };
    await expectLater(
      gateway.auditorCommand(
        auditor({
          'action': 'dismiss_exception',
          'exception_id': uid(43),
          'reason': 'Clock skew',
        }),
      ),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'SEGREGATION_OF_DUTIES_VIOLATION',
        ),
      ),
    );
  });

  test(
    'test commands use the test API; tests are read per engagement',
    () async {
      final design = auditor({
        'action': 'design_test',
        'procedure_id': uid(60),
        'control_id': uid(61),
        'code': 'TRS-SAMPLE',
        'objective': 'Dual signature on sampled payments',
        'population_size': 400,
        'sample_start': 7,
      });
      response = {
        'engagement_id': eng,
        'version': 8,
        'status': 'fieldwork',
        'action': 'design_test',
        'aggregate_type': 'test_procedure',
        'aggregate_id': uid(60),
        'to_status': 'designed',
      };
      await gateway.auditorCommand(design);
      expect(requests.single.url.path, endsWith('/rpc/assurance_test_command'));
      requests.clear();
      response = [
        {'id': uid(60), 'status': 'designed'},
      ];
      expect(await gateway.tests(scope, eng), hasLength(1));
      expect(requests.single.url.path, endsWith('/rpc/assurance_tests'));
      expect((jsonDecode(requests.single.body) as Map)['p_engagement_id'], eng);
      response = {'not': 'a list'};
      await expectLater(gateway.tests(scope, eng), throwsFormatException);
    },
  );

  test(
    'plan commands confirm their aggregate and keep creation at 0',
    () async {
      CommandEnvelope<Map<String, Object?>> plan(int version) =>
          CommandEnvelope(
            commandId: uid(90),
            idempotencyKey: uid(91),
            context: scope,
            expectedEntityVersion: version,
            payload: {
              'action': 'create_plan',
              'plan_id': uid(92),
              'name': 'FY27 internal audit plan',
              'period_start': '2026-04-01',
              'period_end': '2027-03-31',
            },
          );
      response = {
        'aggregate_type': 'plan',
        'aggregate_id': uid(92),
        'version': 1,
        'status': 'draft',
        'action': 'create_plan',
        'to_status': 'draft',
      };
      await gateway.planCommand(plan(0));
      expect(requests.single.url.path, endsWith('/rpc/assurance_plan_command'));
      requests.clear();
      await expectLater(gateway.planCommand(plan(3)), throwsFormatException);
      expect(requests, isEmpty);
      response = {...response! as Map, 'version': 2};
      await expectLater(
        gateway.planCommand(plan(0)),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      status = 400;
      response = {
        'code': '42501',
        'message': 'ASSURANCE_INDEPENDENT_APPROVAL_REQUIRED',
      };
      await expectLater(
        gateway.planCommand(plan(0)),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'SEGREGATION_OF_DUTIES_VIOLATION',
          ),
        ),
      );
    },
  );

  test('an audit pack is read and hashed over its exact text', () async {
    final manifest = {
      'format': 'jentra.assurance.audit_pack.v1',
      'engagement': {'id': eng, 'evidence_cutoff_digest': 'c' * 64},
      'report': {'digest': 'd' * 64, 'report_version': 1},
      'evidence': [
        {
          'id': uid(50),
          'sha256': 'e' * 64,
          'byte_size': 10,
          'source_module': 'finance',
        },
      ],
    };
    final text = jsonEncode(manifest);
    final sha = (await Sha256().hash(
      utf8.encode(text),
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    response = {
      'export_id': uid(40),
      'manifest': manifest,
      'manifest_text': text,
      'manifest_sha256': sha,
      'manifest_bytes': utf8.encode(text).length,
    };
    final v = await gateway.auditPack(scope, uid(40));
    expect(v.verified, isTrue);
    expect(
      requests.single.url.path,
      endsWith('/rpc/assurance_export_manifest'),
    );
    response = {...response! as Map, 'manifest_sha256': 'f' * 64};
    expect((await gateway.auditPack(scope, uid(40))).verified, isFalse);
    await expectLater(gateway.auditPack(scope, uid(41)), throwsFormatException);
  });

  test('invalid responses are rejected before sending', () async {
    final c = respond();
    await expectLater(
      gateway.respond(
        CommandEnvelope(
          commandId: c.commandId,
          idempotencyKey: c.idempotencyKey,
          context: scope,
          expectedEntityVersion: 7,
          payload: {...c.payload, 'status': 'closed'},
        ),
      ),
      throwsFormatException,
    );
    expect(requests, isEmpty);
  });
}
