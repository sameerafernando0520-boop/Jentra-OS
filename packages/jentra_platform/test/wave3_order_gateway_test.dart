import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const scope = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late SupabaseClient client;
  late SupabaseLeadToCashGateway gateway;
  late List<http.Request> requests;
  Object? response;
  int status = 200;
  setUp(() {
    requests = [];
    response = [];
    status = 200;
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(response),
          status,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseLeadToCashGateway(client);
  });
  tearDown(() => client.dispose());
  test(
    'AC-304 order register uses literal search, keyset and complete scope',
    () async {
      await gateway.pageOrders(
        context: scope,
        query: SalesOrderListQuery(
          search: r'SO%_\',
          status: 'credit_hold',
          cursor: '00000000-0000-4000-8000-000000000001',
          limit: 25,
        ),
      );
      final q = requests.single.url.queryParameters;
      expect(requests.single.url.path, endsWith('/sales_orders'));
      expect(requests.single.headers['accept-profile'], 'api');
      expect(q['tenant_id'], 'eq.tenant');
      expect(q['legal_entity_id'], 'eq.entity');
      expect(q['branch_id'], 'eq.branch');
      expect(q['status'], 'eq.credit_hold');
      expect(q['limit'], '26');
      expect(q['document_number'], r'ilike.%SO\%\_\\%');
      expect(q['id'], startsWith('gt.'));
    },
  );
  test('AC-304 missing branch prevents all order reads', () async {
    await expectLater(
      gateway.pageOrders(
        context: const TenantContext(
          tenantId: 'tenant',
          actorId: 'actor',
          legalEntityId: 'entity',
        ),
        query: SalesOrderListQuery(),
      ),
      throwsA(isA<DomainError>()),
    );
    expect(requests, isEmpty);
  });
  test('AC-304 detail uses one coherent snapshot query', () async {
    response = null;
    await gateway.loadOrder(context: scope, id: 'order');
    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/sales_order_details'));
    expect(requests.single.url.queryParameters['branch_id'], 'eq.branch');
  });
  test(
    'AC-304 decision and reservation history have bounded independent cursors',
    () async {
      await gateway.creditDecisions(
        context: scope,
        id: 'order',
        beforeId: 'decision',
      );
      await gateway.reservations(
        context: scope,
        id: 'order',
        afterId: 'reservation',
      );
      expect(requests[0].url.queryParameters['id'], 'lt.decision');
      expect(requests[1].url.queryParameters['id'], 'gt.reservation');
      for (final r in requests) {
        expect(r.url.queryParameters['limit'], '100');
        expect(r.url.queryParameters['sales_order_id'], 'eq.order');
        expect(r.url.queryParameters['branch_id'], 'eq.branch');
      }
    },
  );
  test(
    'AC-304 stock availability rejects inexact numbers and unbounded identity sets',
    () async {
      response = [
        {
          'product_id': 'product',
          'on_hand_quantity': 10.0,
          'allocated_quantity': '0.000000',
          'available_quantity': '10.000000',
        },
      ];
      await expectLater(
        gateway.availability(
          context: scope,
          warehouseId: 'warehouse',
          productIds: ['product'],
        ),
        throwsA(isA<DomainError>()),
      );
      await expectLater(
        gateway.availability(
          context: scope,
          warehouseId: 'warehouse',
          productIds: List.filled(101, 'product'),
        ),
        throwsA(isA<DomainError>()),
      );
      expect(requests, hasLength(1));
    },
  );
  test(
    'AC-304 pending wire is passed unchanged and SQL conflict is explicit',
    () async {
      response = {'code': '40001', 'message': 'VERSION_CONFLICT'};
      status = 409;
      final command = CommandEnvelope<Map<String, Object?>>(
        commandId: 'command',
        idempotencyKey: 'retry-key',
        context: scope,
        clientTimestamp: DateTime.utc(2026, 9, 7),
        expectedEntityVersion: 7,
        payload: {
          'id': 'order',
          'ship_to': {'city': 'Galle'},
          'promised_date': '2099-10-01',
          'warehouse_id': 'warehouse',
        },
      );
      final result = await gateway.executeOrder('fulfillment', command);
      final sent = jsonDecode(requests.single.body) as Map;
      expect(
        requests.single.url.path,
        endsWith('/rpc/update_sales_order_fulfillment'),
      );
      expect(sent['p_payload'], command.payload);
      expect(sent['p_idempotency_key'], 'retry-key');
      expect(sent['p_expected_entity_version'], 7);
      expect(
        sent['p_client_timestamp'],
        command.clientTimestamp.toIso8601String(),
      );
      expect(result.error?.code, 'VERSION_CONFLICT');
    },
  );
  test(
    'AC-304 malformed successful command stays an uncertain contract error',
    () async {
      response = {
        'request_id': 'server',
        'entity': {'id': 'order'},
      };
      final result = await gateway.executeOrder(
        'convert',
        CommandEnvelope(
          commandId: 'command',
          idempotencyKey: 'key',
          context: scope,
          payload: <String, Object?>{},
        ),
      );
      expect(result.error?.code, 'CONTRACT_ERROR');
    },
  );
}
