import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_procurement.dart';
import 'package:jentra_platform/jentra_procurement_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseProcurementGateway gateway;
  final requests = <http.Request>[];
  Object? response;
  var status = 200;
  setUp(() async {
    requests.clear();
    response = [];
    status = 200;
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
                'created_at': '2026-09-13T00:00:00Z',
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
    gateway = SupabaseProcurementGateway(client);
  });
  tearDown(() => client.dispose());
  CommandEnvelope<Map<String, Object?>> command() => CommandEnvelope(
    commandId: 'command',
    idempotencyKey: 'key',
    context: scope,
    clientTimestamp: DateTime.utc(2026, 9, 13),
    expectedEntityVersion: 4,
    payload: {
      'id': 'document',
      'lines': [
        {'quantity': '99999999999999.999999', 'unit_price': '0.000001'},
      ],
    },
  );
  test('bounded order list includes tenant entity branch and keyset', () async {
    response = List.generate(
      51,
      (i) => {
        'detail': {'id': 'id-$i'},
      },
    );
    final page = await gateway.orders(scope, after: 'cursor');
    final q = requests.single.url.queryParameters;
    expect(q['tenant_id'], 'eq.tenant');
    expect(q['legal_entity_id'], 'eq.entity');
    expect(q['branch_id'], 'eq.branch');
    expect(q['id'], 'gt.cursor');
    expect(q['limit'], '51');
    expect(requests.single.headers['accept-profile'], 'api');
    expect(page.items.length, 50);
    expect(page.nextCursor, 'id-49');
  });
  test('wrong actor or missing scope fails before HTTP', () async {
    await expectLater(
      gateway.orders(scope.copyWith(actorId: 'other')),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
      ),
    );
    await expectLater(
      gateway.rfqs(scope.copyWith(clearBranch: true)),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  test(
    'order command preserves envelope and exact financial strings',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {'id': 'document'},
      };
      await gateway.saveOrder(command());
      final r = requests.single;
      final body = jsonDecode(r.body) as Map;
      expect(r.url.path, endsWith('/upsert_purchase_order'));
      expect(r.headers['content-profile'], 'api');
      expect(body['p_payload'], command().payload);
      expect(body['p_command_id'], 'command');
      expect(body['p_idempotency_key'], 'key');
      expect(body['p_expected_entity_version'], 4);
      expect(body['p_branch_id'], 'branch');
    },
  );
  test('malformed successful receipt remains uncertain', () async {
    response = {
      'command_id': 'other',
      'request_id': 'request',
      'entity': {'id': 'document'},
    };
    await expectLater(
      gateway.source(command()),
      throwsA(
        isA<DomainError>().having((e) => e.code, 'code', 'UNCERTAIN_RESULT'),
      ),
    );
  });
  test(
    'supplier bill lifecycle and control commands remain distinct RPCs',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {'id': 'document'},
      };
      await gateway.saveBill(command());
      await gateway.billAction('post', command());
      await gateway.billAction('approve', command());
      await gateway.billAction('cancel', command());
      await gateway.saveBillControls(command());
      expect(requests.map((r) => r.url.path.split('/').last), [
        'upsert_supplier_bill',
        'post_supplier_bill',
        'approve_supplier_bill_match',
        'cancel_supplier_bill',
        'upsert_supplier_bill_controls',
      ]);
      for (final r in requests) {
        expect((jsonDecode(r.body) as Map)['p_payload'], command().payload);
      }
      await expectLater(
      () => gateway.billAction('delete', command()),
        throwsA(isA<DomainError>()),
      );
      expect(requests.length, 5);
    },
  );
  test(
    'goods receipt commands use separate named RPCs with preserved envelopes',
    () async {
      response = {
        'command_id': 'command',
        'request_id': 'request',
        'entity': {'id': 'document'},
      };
      await gateway.postReceipt(command());
      await gateway.reverseReceipt(command());
      await gateway.saveReceiptControls(command());
      expect(requests.map((r) => r.url.path.split('/').last), [
        'post_goods_receipt',
        'reverse_goods_receipt',
        'upsert_receipt_controls',
      ]);
      for (final request in requests) {
        final body = jsonDecode(request.body) as Map;
        expect(body['p_payload'], command().payload);
        expect(body['p_expected_entity_version'], 4);
      }
    },
  );
  test(
    'receipt source picker uses its permission-gated bounded reference RPC',
    () async {
      response = {'items': [], 'next_cursor': null};
      await gateway.references(
        scope,
        'receipt_orders',
        search: 'PO-0007',
        after: 'cursor',
      );
      expect(
        requests.single.url.path,
        endsWith('/goods_receipt_reference_options'),
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_resource'], 'receipt_orders');
      expect(body['p_branch_id'], 'branch');
      expect(body['p_after'], 'cursor');
    },
  );
  for (final entry in {
    '40001': 'VERSION_CONFLICT',
    '42501': 'PERMISSION_DENIED',
    '22023': 'VALIDATION_ERROR',
    'XX000': 'UNCERTAIN_RESULT',
  }.entries) {
    test(
      'server ${entry.key} is classified without exposing server detail',
      () async {
        response = {
          'code': entry.key,
          'message': 'private database details',
          'details': 'private rows',
          'hint': '',
        };
        status = 400;
        await expectLater(
          gateway.save(command()),
          throwsA(
            isA<DomainError>()
                .having((e) => e.code, 'code', entry.value)
                .having(
                  (e) => e.message,
                  'redacted',
                  isNot(contains('private')),
                ),
          ),
        );
      },
    );
  }
  test(
    'reference search sends literal text and all scope dimensions',
    () async {
      response = {'items': [], 'base_currency': 'LKR', 'next_cursor': null};
      await gateway.references(
        scope,
        'selected_rfqs',
        search: '100% _ paper',
        after: 'after',
      );
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['p_search'], '100% _ paper');
      expect(body['p_after'], 'after');
      expect(body['p_resource'], 'selected_rfqs');
      expect(body['p_tenant_id'], 'tenant');
      expect(body['p_legal_entity_id'], 'entity');
      expect(body['p_branch_id'], 'branch');
    },
  );
}
