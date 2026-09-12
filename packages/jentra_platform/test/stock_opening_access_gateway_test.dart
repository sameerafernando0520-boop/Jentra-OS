import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;
  late SupabaseStockOpeningAccessGateway gateway;
  final requests = <http.Request>[];
  Object response = [];
  setUp(() {
    requests.clear();
    client = SupabaseClient(
      'https://example.test',
      'test',
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseStockOpeningAccessGateway(client);
  });
  tearDown(() => client.dispose());
  test('invitation command carries exact scope and retry identity', () async {
    response = {
      'request_id': 'receipt',
      'entity': {'id': 'invitation', 'role_id': 'role'},
    };
    await gateway.invite(
      tenantId: 'tenant',
      legalEntityId: 'entity',
      branchId: 'branch',
      email: 'test@lh.com',
      idempotencyKey: 'same-key',
    );
    await gateway.invite(
      tenantId: 'tenant',
      legalEntityId: 'entity',
      branchId: 'branch',
      email: 'test@lh.com',
      idempotencyKey: 'same-key',
    );
    expect(
      requests.first.url.path,
      '/rest/v1/rpc/invite_stock_opening_approver',
    );
    expect(requests.first.headers['content-profile'], 'api');
    expect(requests[0].body, requests[1].body);
    expect(jsonDecode(requests.first.body), {
      'p_tenant_id': 'tenant',
      'p_legal_entity_id': 'entity',
      'p_branch_id': 'branch',
      'p_email': 'test@lh.com',
      'p_idempotency_key': 'same-key',
    });
  });
  test(
    'inbox and acceptance let the server resolve recipient identity',
    () async {
      response = [
        {
          'id': 'invitation',
          'tenant_name': 'Lab',
          'legal_entity_name': 'Trading',
          'branch_name': 'HQ',
          'expires_at': '2026-09-14T00:00:00Z',
        },
      ];
      expect((await gateway.pending()).single['tenant_name'], 'Lab');
      expect(jsonDecode(requests.single.body), isNull);
      response = {
        'request_id': 'receipt',
        'entity': {'id': 'membership'},
      };
      await gateway.accept(
        invitationId: 'invitation',
        idempotencyKey: 'accept-key',
      );
      expect(jsonDecode(requests.last.body), {
        'p_invitation_id': 'invitation',
        'p_idempotency_key': 'accept-key',
      });
    },
  );
  test('malformed response does not confirm an invitation', () async {
    response = {
      'entity': {'id': 'invitation'},
    };
    await expectLater(
      gateway.invite(
        tenantId: 'tenant',
        legalEntityId: 'entity',
        branchId: 'branch',
        email: 'test@lh.com',
        idempotencyKey: 'key',
      ),
      throwsFormatException,
    );
  });
}
