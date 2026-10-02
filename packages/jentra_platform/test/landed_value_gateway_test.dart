import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_inventory.dart';
import 'package:jentra_platform/jentra_inventory_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseLandedValueGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  const row = {
    'id': 'receipt',
    'covered': true,
    'received_quantity': '9007199254.740993',
  };
  setUp(() async {
    requests.clear();
    status = 200;
    response = {
      'items': [row],
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
                    'sub': 'actor',
                    'role': 'authenticated',
                    'exp': 4102444800,
                  }),
                ),
              )
              .replaceAll('=', '');
          return http.Response(
            jsonEncode({
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.$claims.synthetic-signature',
              'refresh_token': 'synthetic',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': 'actor',
                'aud': 'authenticated',
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-09-19T00:00:00Z',
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
    gateway = SupabaseLandedValueGateway(client);
  });
  tearDown(() => client.dispose());
  Map<String, Object?> allocation() => {
    'receipt_line_id': 'receipt',
    'basis_hash': 'basis',
    'amount': '9007199254.740993',
    'inventory_amount': '9007199254.740992',
    'variance_amount': '0.000001',
    'received_quantity': '3.000000',
    'held_quantity': '2.000000',
    'consumed_quantity': '1.000000',
    'legs': [
      {'warehouse_id': 'warehouse', 'value': '9007199254.740992'},
    ],
  };
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 20),
    expectedEntityVersion: 0,
    payload: {
      'id': 'document',
      'receipt_line_id': 'receipt',
      'amount': '9007199254.740993',
    },
  );
  Map<String, Object?> receipt() => {
    'command_id': 'command',
    'request_id': 'request',
    'entity': {
      ...allocation(),
      'id': 'document',
      'version': 1,
      'status': 'posted',
      'reverse_of': null,
      'journal_ids': ['journal'],
    },
  };
  final uncertain = throwsA(
    isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
  );
  test('options carry scope and independent cursor', () async {
    response = {'items': []};
    await gateway.options(scope, 'posted', after: 'cursor');
    expect(jsonDecode(requests.single.body), {
      'p_tenant_id': 'tenant',
      'p_legal_entity_id': 'entity',
      'p_branch_id': 'branch',
      'p_resource': 'posted',
      'p_after': 'cursor',
    });
  });
  test('oversized or inexact posted register fails closed', () async {
    response = {
      'items': List.filled(51, {'id': 'row'}),
    };
    await expectLater(gateway.options(scope, 'posted'), throwsFormatException);
    response = {
      'items': [
        {...allocation(), 'id': 'row', 'amount': 1},
      ],
    };
    await expectLater(gateway.options(scope, 'posted'), uncertain);
  });
  test('preview preserves values beyond binary integer precision', () async {
    response = allocation();
    final r = await gateway.preview(scope, {'receipt_line_id': 'receipt'});
    expect(r['amount'], '9007199254.740993');
  });
  test(
    'posting preserves expected creation version and exact amount',
    () async {
      response = receipt();
      await gateway.post(command());
      final body = jsonDecode(requests.single.body);
      expect(body['p_expected_entity_version'], 0);
      expect(body['p_payload']['amount'], '9007199254.740993');
      expect(body['p_idempotency_key'], 'key');
    },
  );
  for (final entry in <String, Object?>{
    'amount': 10.5,
    'inventory_amount': '9007199254.740991',
    'consumed_quantity': '2',
    'legs': [
      {'warehouse_id': 'warehouse', 'value': '0.000001'},
    ],
  }.entries) {
    test('malformed ${entry.key} cannot acknowledge a posting', () async {
      final r = receipt();
      r['entity'] = {...(r['entity'] as Map), entry.key: entry.value};
      response = r;
      await expectLater(gateway.post(command()), uncertain);
    });
  }
  test(
    'wrong receipt and missing journal identities retain uncertainty',
    () async {
      for (final change in [
        {'receipt_line_id': 'other'},
        {
          'journal_ids': [null],
        },
        {'journal_ids': []},
        {'id': 'other'},
        {'reverse_of': 'other'},
      ]) {
        final r = receipt();
        r['entity'] = {...(r['entity'] as Map), ...change};
        response = r;
        await expectLater(gateway.post(command()), uncertain);
      }
    },
  );
  test('preview identity cannot silently switch receipts', () async {
    response = allocation();
    await expectLater(
      gateway.preview(scope, {'receipt_line_id': 'other'}),
      throwsFormatException,
    );
  });
  test('linked reversal requires exact negative allocation evidence', () async {
    final reverse = CommandEnvelope<Map<String, Object?>>(
      commandId: 'command',
      idempotencyKey: 'key',
      context: scope,
      clientTimestamp: DateTime.utc(2026, 9, 20),
      expectedEntityVersion: 1,
      payload: {'id': 'document', 'reverse_of': 'original'},
    );
    final r = receipt();
    r['entity'] = {...(r['entity'] as Map), 'reverse_of': 'original'};
    response = r;
    await expectLater(gateway.post(reverse), uncertain);
    r['entity'] = {
      ...(r['entity'] as Map),
      'amount': '-9007199254.740993',
      'inventory_amount': '-9007199254.740992',
      'variance_amount': '-0.000001',
      'legs': [
        {'warehouse_id': 'warehouse', 'value': '-9007199254.740992'},
      ],
    };
    response = r;
    expect((await gateway.post(reverse))['reverse_of'], 'original');
  });
  test('stale server basis is a definite conflict', () async {
    status = 409;
    response = {'code': '40001', 'message': 'LANDED_PREVIEW_CHANGED'};
    await expectLater(
      gateway.post(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
      ),
    );
  });
  test('current actor mismatch fails before network access', () async {
    const other = TenantContext(
      tenantId: 'tenant',
      actorId: 'other',
      legalEntityId: 'entity',
      branchId: 'branch',
    );
    await expectLater(
      () => gateway.options(other, 'posted'),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  for (final entry in <String, String>{
    'PERMISSION_DENIED': 'P0001',
    'ACCESS_DENIED': 'P0001',
    'MFA_REQUIRED': 'P0001',
    'AUTHENTICATION_REQUIRED': 'P0001',
    'PGRST301': 'PGRST301',
    'PGRST302': 'PGRST302',
    'PGRST303': 'PGRST303',
    '42501': '42501',
  }.entries) {
    for (final read in ['options', 'preview']) {
      test('$read normalizes current read denial ${entry.key}', () async {
        status = 403;
        response = {'code': entry.value, 'message': entry.key};
        final expected = entry.key.startsWith('PGRST')
            ? 'AUTHENTICATION_REQUIRED'
            : entry.key == '42501'
            ? 'PERMISSION_DENIED'
            : entry.key;
        await expectLater(
          read == 'options'
              ? gateway.options(scope, 'receipts')
              : gateway.preview(scope, {'receipt_line_id': 'receipt'}),
          throwsA(isA<DomainError>().having((e) => e.code, 'code', expected)),
        );
      });
    }
    test('posting keeps existing error precedence for ${entry.key}', () async {
      status = 403;
      response = {'code': entry.value, 'message': entry.key};
      await expectLater(
        gateway.post(command()),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            entry.value == '42501'
                ? 'PERMISSION_DENIED'
                : entry.value == 'P0001'
                ? 'VALIDATION_ERROR'
                : 'UNCERTAIN_RESULT',
          ),
        ),
      );
    });
  }
}
