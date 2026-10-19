import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '81000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), eng = uid(2), req = uid(3), ev = uid(4);

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  final bytes = Uint8List.fromList(utf8.encode('Signed bank confirmation'));
  late String sha;
  late SupabaseClient client;
  late SupabaseAssuranceGateway gateway;
  final calls = <http.Request>[];
  late Map<String, (int, Object?)> routes;

  Map<String, Object?> verification([String outcome = 'verified']) => {
    'evidence_id': ev,
    'outcome': outcome,
    'observed_sha256': outcome == 'verified' ? sha : 'f' * 64,
    'observed_byte_size': bytes.length,
    'verified_at': '2026-10-19T09:00:01Z',
    'verifier': 'assurance-evidence-verify/v1',
  };
  Map<String, Object?> receipt() => {
    'engagement_id': eng,
    'version': 10,
    'action': 'submit_evidence',
    'aggregate_type': 'evidence_request',
    'aggregate_id': req,
    'to_status': 'submitted',
  };
  CommandEnvelope<Map<String, Object?>> command({String? digest}) =>
      CommandEnvelope(
        commandId: uid(20),
        idempotencyKey: uid(21),
        context: scope,
        expectedEntityVersion: 9,
        clientTimestamp: DateTime.utc(2026, 10, 19, 9),
        payload: manualEvidencePayload(
          tenantId: scope.tenantId,
          engagementId: eng,
          requestId: req,
          evidenceId: ev,
          fileName: 'bank-letter.pdf',
          sha256: digest ?? sha,
          byteSize: bytes.length,
          sourceAsOf: DateTime.utc(2026, 10, 19, 8),
          now: DateTime.utc(2026, 10, 19, 9),
        ),
      );

  setUp(() async {
    sha = await assuranceSha256(bytes);
    calls.clear();
    routes = {
      '/rpc/assurance_command': (200, receipt()),
      '/storage/': (200, {'Key': 'x'}),
      '/functions/v1/assurance-evidence-verify': (200, verification()),
    };
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
        calls.add(r);
        final route = routes.entries.firstWhere(
          (e) => r.url.path.contains(e.key),
          orElse: () => MapEntry('', (404, {'code': 'missing'})),
        );
        return http.Response(
          jsonEncode(route.value.$2),
          route.value.$1,
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

  String step(http.Request r) => r.url.path.contains('/rpc/')
      ? 'command'
      : r.url.path.contains('/storage/')
      ? 'upload'
      : 'verify';

  test(
    'records the command, uploads to the generated path, then verifies',
    () async {
      final v = await gateway.submitManualEvidence(
        command(),
        bytes,
        'application/pdf',
      );
      expect(v.confirms(sha256: sha, byteSize: bytes.length), isTrue);
      expect(calls.map(step), ['command', 'upload', 'verify']);
      expect(
        calls[1].url.path,
        endsWith(
          '/object/$assuranceEvidenceBucket/assurance/${scope.tenantId}/$eng/$ev',
        ),
      );
      expect(calls[1].headers['x-upsert'], 'false');
      expect(latin1.decode(calls[1].bodyBytes), contains(utf8.decode(bytes)));
      expect(jsonDecode(calls[2].body), {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'engagement_id': eng,
        'evidence_id': ev,
      });
      final body = jsonDecode(calls.first.body) as Map;
      expect(body['p_idempotency_key'], uid(21));
      expect(body['p_expected_version'], 9);
    },
  );

  test('a retry after an earlier upload continues to verification', () async {
    routes['/storage/'] = (
      409,
      {'statusCode': '409', 'error': 'Duplicate', 'message': 'exists'},
    );
    final v = await gateway.submitManualEvidence(
      command(),
      bytes,
      'application/pdf',
    );
    expect(v.verified, isTrue);
    expect(calls.map(step), ['command', 'upload', 'verify']);
  });

  test('a mismatch is reported, never treated as accepted evidence', () async {
    routes['/functions/v1/assurance-evidence-verify'] = (
      200,
      verification('mismatch'),
    );
    final v = await gateway.submitManualEvidence(
      command(),
      bytes,
      'application/pdf',
    );
    expect(v.verified, isFalse);
  });

  test('a different file than the saved submission sends nothing', () async {
    await expectLater(
      gateway.submitManualEvidence(
        command(digest: 'a' * 64),
        bytes,
        'application/pdf',
      ),
      throwsFormatException,
    );
    await expectLater(
      gateway.submitManualEvidence(
        command(),
        bytes,
        'application/x-msdownload',
      ),
      throwsFormatException,
    );
    expect(calls, isEmpty);
  });

  test(
    'a failed upload is uncertain and verification is not attempted',
    () async {
      routes['/storage/'] = (500, {'statusCode': '500', 'message': 'boom'});
      await expectLater(
        gateway.submitManualEvidence(command(), bytes, 'application/pdf'),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
        ),
      );
      expect(calls.map(step), ['command', 'upload']);
    },
  );

  test('verification refusals map to the client contract', () async {
    for (final (status, code, expected) in [
      (403, 'ASSURANCE_EVIDENCE_DENIED', 'PERMISSION_DENIED'),
      (409, 'ASSURANCE_EVIDENCE_OBJECT_MISSING', 'VALIDATION_ERROR'),
      (404, 'ASSURANCE_EVIDENCE_NOT_FOUND', 'NOT_FOUND'),
      (503, 'ASSURANCE_EVIDENCE_UNCERTAIN', 'UNCERTAIN_RESULT'),
    ]) {
      routes['/functions/v1/assurance-evidence-verify'] = (
        status,
        {'code': code},
      );
      await expectLater(
        gateway.verifyEvidence(scope, eng, ev),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
        reason: code,
      );
    }
  });

  test(
    'acceptance refused for unverified bytes reads as a validation error',
    () {
      final e = SupabaseAssuranceGateway.assuranceDenial(
        const PostgrestException(
          message: 'ASSURANCE_EVIDENCE_UNVERIFIED',
          code: '55000',
        ),
      );
      expect(e.code, 'VALIDATION_ERROR');
      expect(e.message, contains('not been verified'));
    },
  );

  test('status is read in scope and checked against its identity', () async {
    routes['/rpc/assurance_evidence_verification'] = (
      200,
      {
        'engagement_id': eng,
        'evidence_id': ev,
        'sha256': sha,
        'byte_size': bytes.length,
        'upload_required': true,
        'stored': true,
        'bytes_verified': true,
        'verification': verification(),
      },
    );
    final s = await gateway.evidenceVerification(scope, eng, ev);
    expect(s.acceptable, isTrue);
    expect(
      calls.single.url.path,
      endsWith('/rpc/assurance_evidence_verification'),
    );
    await expectLater(
      gateway.evidenceVerification(scope, eng, uid(9)),
      throwsFormatException,
    );
  });
}
