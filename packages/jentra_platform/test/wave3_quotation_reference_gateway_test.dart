import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const context = TenantContext(
    tenantId: 'tenant',
    actorId: 'actor',
    legalEntityId: 'entity',
    branchId: 'branch',
  );
  late List<http.Request> requests;
  late SupabaseClient client;
  late SupabaseLeadToCashGateway gateway;
  Object response = <Object>[];
  int status = 200;
  setUp(() {
    requests = [];
    response = <Object>[];
    status = 200;
    client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    gateway = SupabaseLeadToCashGateway(client);
  });
  tearDown(() => client.dispose());

  test(
    'governed reference pages use only public views and correct scopes',
    () async {
      for (final kind in QuotationReferenceKind.values) {
        await gateway.pageReferences(
          context: context,
          kind: kind,
          query: QuotationReferenceQuery(
            customerId: 'customer',
            fromCurrency: 'USD',
            toCurrency: 'LKR',
          ),
        );
      }
      final byView = {
        for (final request in requests)
          request.url.path.split('/').last: request,
      };
      expect(byView.keys.toSet(), {
        'parties',
        'contacts',
        'currencies',
        'exchange_rates',
        'products',
        'units',
        'tax_definitions',
        'crm_opportunities',
        'warehouses',
      });
      for (final entry in byView.entries) {
        final query = entry.value.url.queryParameters;
        expect(entry.value.headers['accept-profile'], 'api');
        expect(query['limit'], '26');
        expect(query['order'], startsWith('id.asc'));
        if (entry.key == 'currencies') {
          expect(query.containsKey('tenant_id'), isFalse);
        } else {
          expect(query['tenant_id'], 'eq.tenant');
        }
        if ({
          'products',
          'tax_definitions',
          'exchange_rates',
          'crm_opportunities',
          'warehouses',
        }.contains(entry.key)) {
          expect(query['legal_entity_id'], 'eq.entity');
        } else {
          expect(query.containsKey('legal_entity_id'), isFalse);
        }
      }
      expect(
        byView['parties']!.url.queryParameters['kind'],
        'in.("customer","both")',
      );
      expect(
        byView['contacts']!.url.queryParameters['party_id'],
        'eq.customer',
      );
      expect(byView['products']!.url.queryParameters['can_sell'], 'eq.true');
      expect(
        byView['exchange_rates']!.url.queryParameters['source_currency_code'],
        'eq.USD',
      );
      expect(
        byView['exchange_rates']!.url.queryParameters['target_currency_code'],
        'eq.LKR',
      );
      expect(
        byView['crm_opportunities']!.url.queryParameters['or'],
        '(branch_id.is.null,branch_id.eq.branch)',
      );
      await gateway.pageReferences(
        context: context,
        kind: QuotationReferenceKind.opportunity,
        query: QuotationReferenceQuery(search: 'office'),
      );
      expect(requests.last.url.queryParametersAll['or'], [
        '(branch_id.is.null,branch_id.eq.branch)',
        '(code.ilike."%office%",prospect_name.ilike."%office%")',
      ]);
    },
  );

  test(
    'literal search, exact financial values and keyset continuation are preserved',
    () async {
      response = [
        {
          'id': '00000000-0000-0000-0000-000000000001',
          'code': 'USD/LKR',
          'name': 'USD to LKR',
          'rate': '300.1234567890',
          'effective_date': '2026-09-06',
        },
        {
          'id': '00000000-0000-0000-0000-000000000002',
          'code': 'USD/LKR',
          'name': 'USD to LKR',
          'rate': '301.1234567890',
          'effective_date': '2026-09-06',
        },
      ];
      final page = await gateway.pageReferences(
        context: context,
        kind: QuotationReferenceKind.exchangeRate,
        query: QuotationReferenceQuery(search: 'AC%_",x', limit: 1),
      );
      expect(page.items.single.values['rate'], '300.1234567890');
      expect(page.items.single.label, contains('300.1234567890'));
      expect(page.nextCursor, '00000000-0000-0000-0000-000000000001');
      expect(
        requests.single.url.queryParameters['or'],
        r'(code.ilike."%AC\%\_\",x%",name.ilike."%AC\%\_\",x%")',
      );
      response = [];
      await gateway.pageReferences(
        context: context,
        kind: QuotationReferenceKind.exchangeRate,
        query: QuotationReferenceQuery(cursor: page.nextCursor),
      );
      expect(requests.last.url.queryParameters['id'], 'gt.${page.nextCursor}');
    },
  );

  test(
    'contact picker requires customer and hydration retains scope',
    () async {
      final empty = await gateway.pageReferences(
        context: context,
        kind: QuotationReferenceKind.contact,
        query: QuotationReferenceQuery(),
      );
      expect(empty.items, isEmpty);
      expect(requests, isEmpty);
      await gateway.pageReferences(
        context: context,
        kind: QuotationReferenceKind.customer,
        query: QuotationReferenceQuery(id: 'customer'),
      );
      expect(requests.single.url.queryParameters['id'], 'eq.customer');
      expect(requests.single.url.queryParameters['tenant_id'], 'eq.tenant');
    },
  );

  test(
    'references fail closed for missing scope and reject unbounded input',
    () async {
      await expectLater(
        gateway.pageReferences(
          context: const TenantContext(tenantId: 'tenant', actorId: 'actor'),
          kind: QuotationReferenceKind.product,
          query: QuotationReferenceQuery(),
        ),
        throwsA(
          isA<DomainError>().having(
            (e) => e.code,
            'code',
            'LEGAL_ENTITY_REQUIRED',
          ),
        ),
      );
      expect(requests, isEmpty);
      expect(() => QuotationReferenceQuery(limit: 201), throwsRangeError);
      expect(
        () => QuotationReferenceQuery(cursor: 'x,or.id.gt.anything'),
        throwsFormatException,
      );
      expect(
        () => QuotationReferenceQuery(search: 'x' * 201),
        throwsFormatException,
      );
    },
  );

  test(
    'permission denial and malformed financial references are explicit',
    () async {
      status = 403;
      response = {'code': '42501', 'message': 'Permission denied'};
      await expectLater(
        gateway.pageReferences(
          context: context,
          kind: QuotationReferenceKind.tax,
          query: QuotationReferenceQuery(),
        ),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'PERMISSION_DENIED'),
        ),
      );
      status = 200;
      response = [
        {'id': 'tax', 'code': 'VAT', 'name': 'VAT', 'rate': 18.0},
      ];
      await expectLater(
        gateway.pageReferences(
          context: context,
          kind: QuotationReferenceKind.tax,
          query: QuotationReferenceQuery(),
        ),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'CONTRACT_ERROR'),
        ),
      );
    },
  );
}
