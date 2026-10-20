import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String uid(int n) => '88000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final actor = uid(1), eng = uid(2), ev = uid(4);
const signed =
    'https://example.test/storage/v1/object/sign/assurance/x?token=t';

void main() {
  final scope = TenantContext(
    tenantId: uid(10),
    actorId: actor,
    legalEntityId: uid(11),
    branchId: uid(12),
  );
  final bytes = Uint8List.fromList(utf8.encode('signed bank letter v2'));
  late String sha;
  late SupabaseClient client;
  late SupabaseAssuranceEvidenceDownloadGateway gateway;
  final calls = <http.Request>[];
  late (int, Object?) function;
  late List<int> stored;
  var fileStatus = 200;

  Map<String, Object?> link({Map<String, Object?> change = const {}}) => {
    'evidence_id': ev,
    'url': signed,
    'expires_in': 60,
    'sha256': sha,
    'byte_size': bytes.length,
    ...change,
  };

  setUp(() async {
    sha = await assuranceSha256(bytes);
    calls.clear();
    function = (200, link());
    stored = bytes;
    fileStatus = 200;
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
        return http.Response(
          jsonEncode(function.$2),
          function.$1,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@example.test',
      password: 'synthetic-only',
    );
    gateway = SupabaseAssuranceEvidenceDownloadGateway(
      client,
      files: MockClient((r) async {
        calls.add(r);
        return http.Response.bytes(stored, fileStatus, request: r);
      }),
    );
  });
  tearDown(() => client.dispose());

  test('the file is fetched from the signed link and matched', () async {
    final f = await gateway.download(scope, eng, ev);
    expect(f.bytes, bytes);
    expect(f.sha256, sha);
    expect(
      calls.first.url.path,
      endsWith('/functions/v1/assurance-evidence-download'),
    );
    expect(jsonDecode(calls.first.body), {
      'tenant_id': scope.tenantId,
      'legal_entity_id': scope.legalEntityId,
      'branch_id': scope.branchId,
      'engagement_id': eng,
      'evidence_id': ev,
    });
    expect(calls.last.url.toString(), signed);
    expect(calls.last.headers.containsKey('Authorization'), isFalse);
  });

  test('altered, shorter or longer bytes are never returned', () async {
    for (final b in [
      utf8.encode('tampered bank letter!'),
      utf8.encode('signed bank letter'),
      utf8.encode('signed bank letter v2 and more'),
    ]) {
      stored = b;
      await expectLater(
        gateway.download(scope, eng, ev),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'EVIDENCE_MISMATCH'),
        ),
      );
    }
  });

  test('a digest other than the one the reviewer saw is refused', () async {
    await expectLater(
      gateway.download(scope, eng, ev, expectedSha256: 'c' * 64),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'EVIDENCE_MISMATCH'),
      ),
    );
    expect(calls, hasLength(1));
  });

  test('refusals and failed fetches map to the client contract', () async {
    for (final (status, code, expected) in [
      (403, 'ASSURANCE_EVIDENCE_DENIED', 'PERMISSION_DENIED'),
      (404, 'ASSURANCE_EVIDENCE_NOT_FOUND', 'NOT_FOUND'),
      (409, 'ASSURANCE_EVIDENCE_UNVERIFIED', 'VALIDATION_ERROR'),
      (503, 'ASSURANCE_EVIDENCE_UNCERTAIN', 'UNCERTAIN_RESULT'),
    ]) {
      function = (status, {'code': code});
      await expectLater(
        gateway.download(scope, eng, ev),
        throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
      );
    }
    function = (200, link(change: {'url': 'http://example.test/x'}));
    await expectLater(gateway.download(scope, eng, ev), throwsFormatException);
    function = (200, link());
    fileStatus = 403;
    await expectLater(
      gateway.download(scope, eng, ev),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
}
