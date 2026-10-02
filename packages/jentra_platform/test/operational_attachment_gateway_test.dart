import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  const attachment = <String, Object?>{
    'id': 'file',
    'file_name': 'proof.pdf',
    'upload_status': 'ready',
    'object_path': 'tenant/supplier_bill/source/file/file.pdf',
  };
  late SupabaseClient client;
  late SupabaseOperationalGateway gateway;
  final requests = <http.Request>[];
  int status = 200;
  Object response = {};
  bool transportFailure = false;
  setUp(() async {
    status = 200;
    response = {
      'signedURL':
          '/object/sign/jentra-attachments/tenant/supplier_bill/source/file/file.pdf?token=PRIVATE_TOKEN',
    };
    transportFailure = false;
    requests.clear();
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          final claims = base64Url
              .encode(
                utf8.encode(
                  jsonEncode({
                    'sub': 'actor',
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
                'id': 'actor',
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
        requests.add(request);
        if (transportFailure) {
          throw http.ClientException('PRIVATE_TRANSPORT_DIAGNOSTIC');
        }
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await client.auth.signInWithPassword(
      email: 'actor@synthetic.invalid',
      password: 'synthetic-only',
    );
    gateway = SupabaseOperationalGateway(client);
  });
  tearDown(() => client.dispose());
  Future<String> read([Map<String, Object?> value = attachment]) =>
      gateway.signedAttachmentUrl(scope, 'supplier_bill', 'source', value);
  test('private link binds its validated object and short expiry', () async {
    expect(await read(), contains('PRIVATE_TOKEN'));
    expect(
      requests.single.url.path,
      '/storage/v1/object/sign/jentra-attachments/tenant/supplier_bill/source/file/file.pdf',
    );
    expect(jsonDecode(requests.single.body), {'expiresIn': 900});
  });
  for (final (httpStatus, code) in [
    (401, 'AUTHENTICATION_REQUIRED'),
    (403, 'PERMISSION_DENIED'),
    (400, 'READ_REJECTED'),
    (404, 'READ_REJECTED'),
    (500, 'READ_UNAVAILABLE'),
  ]) {
    test(
      'Storage $httpStatus preserves typed $code and redacts diagnostics',
      () async {
        status = httpStatus;
        response = {
          'message': 'PRIVATE_SERVER_DIAGNOSTIC',
          'error': 'PRIVATE_SERVER_ERROR',
          'statusCode': '$httpStatus',
        };
        await expectLater(
          read(),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.message.contains('PRIVATE'),
                  'private diagnostic',
                  false,
                ),
          ),
        );
      },
    );
  }
  test('unknown transport uses a fixed unavailable read state', () async {
    transportFailure = true;
    await expectLater(
      read(),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'READ_UNAVAILABLE')
            .having(
              (e) => e.message.contains('PRIVATE'),
              'private diagnostic',
              false,
            ),
      ),
    );
  });
  test('malformed signed link uses a fixed invalid read state', () async {
    response = {'signedURL': 12, 'message': 'PRIVATE_SERVER_DIAGNOSTIC'};
    await expectLater(
      read(),
      throwsA(
        isA<DomainError>()
            .having((e) => e.code, 'code', 'READ_INVALID')
            .having(
              (e) => e.message.contains('PRIVATE'),
              'private diagnostic',
              false,
            ),
      ),
    );
  });
  test(
    'substituted object identity is rejected without a Storage call',
    () async {
      await expectLater(
        read({
          ...attachment,
          'object_path': 'foreign/supplier_bill/source/file/file.pdf',
        }),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    },
  );
}
