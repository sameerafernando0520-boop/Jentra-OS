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
  test(
    'AC-303 reads are scoped, literal, stably ordered and bounded',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final gateway = SupabaseLeadToCashGateway(client);
      await gateway.pageQuotations(
        context: context,
        query: QuotationListQuery(search: 'QUO%_', status: 'draft', limit: 25),
      );
      await gateway.quotationRevisions(context: context, id: 'quote');
      await gateway.quotationDecisions(context: context, id: 'quote');
      for (final request in requests) {
        expect(request.headers['accept-profile'], 'api');
        expect(request.url.queryParameters['tenant_id'], 'eq.tenant');
        expect(request.url.queryParameters['legal_entity_id'], 'eq.entity');
        expect(request.url.queryParameters['branch_id'], 'eq.branch');
        expect(
          int.parse(request.url.queryParameters['limit']!),
          lessThanOrEqualTo(200),
        );
      }
      expect(
        requests.first.url.queryParameters['document_number'],
        r'ilike.%QUO\%\_%',
      );
      expect(requests.first.url.queryParameters['order'], startsWith('id.asc'));
      expect(requests.first.url.queryParameters['status'], 'eq.draft');
    },
  );

  test(
    'AC-303 details use the coherent detail view and reject incomplete financial contracts',
    () async {
      late Uri uri;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({'id': 'quote', 'grand_total': 1.5}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final gateway = SupabaseLeadToCashGateway(client);
      await expectLater(
        gateway.loadQuotationDetail(context: context, id: 'quote'),
        throwsA(
          isA<DomainError>().having((e) => e.code, 'code', 'CONTRACT_ERROR'),
        ),
      );
      expect(uri.path, '/rest/v1/sales_quotation_details');
    },
  );
}
