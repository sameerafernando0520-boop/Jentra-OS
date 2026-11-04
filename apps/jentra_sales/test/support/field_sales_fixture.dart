import 'dart:async';
import 'dart:convert';

import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

final fieldScope = FieldSalesScope('tenant', 'entity', 'branch');
final fieldInput = <String, dynamic>{
  'customer_id': 'customer',
  'warehouse_id': 'warehouse',
  'requested_date': '2099-01-01',
  'reference': 'REF',
  'notes': '',
  'discount_percent': '10',
  'discount_reason': 'Company request',
  'lines': [
    {'policy_id': 'policy', 'policy_version': '1', 'quantity': '1.125'},
  ],
};
final fieldReview = <String, dynamic>{
  'source_digest': 'a' * 64,
  'currency_code': 'LKR',
  'discount_percent': '10',
  'discount_state': 'requested',
  'stock_state': 'unavailable',
  'credit_state': 'company_review_required',
  'terms': {
    'ship_to': {'address': 'Company approved address'},
    'payment_terms_days': '30',
    'delivery_terms': 'Company delivery',
    'warehouse_id': 'warehouse',
    'requested_date': '2099-01-01',
  },
  'pricing': {
    'subtotal': '1.410000',
    'tax_total': '0.000000',
    'grand_total': '1.270000',
  },
};

final class FakeFieldSalesGateway implements FieldSalesGateway {
  @override
  String? actorId = 'rep';
  Object? failure;
  Object? submitFailure;
  bool badReceipt = false, multipleScopes = false;
  Completer<List<FieldSalesJson>>? catalogueWait;
  Completer<FieldSalesJson>? previewWait;
  final commands = <FieldSalesCommand>[];
  FieldSalesJson? committed;
  List<FieldSalesJson>? currentSubjects;
  @override
  Future<FieldSalesJson> workspace() async {
    if (failure != null) throw failure!;
    return {
      'contract_version': '1',
      'scopes': [
        {
          'tenant_id': 'tenant',
          'legal_entity_id': 'entity',
          'branch_id': 'branch',
          'company_name': 'Synthetic Company',
          'branch_name': 'Head Office',
          'warehouses': [
            {'id': 'warehouse', 'name': 'Approved Warehouse'},
          ],
        },
        if (multipleScopes)
          {
            'tenant_id': 'other',
            'legal_entity_id': 'otherEntity',
            'branch_id': 'otherBranch',
            'company_name': 'Other Company',
            'branch_name': 'Other Branch',
            'warehouses': [],
          },
      ],
    };
  }

  @override
  Future<List<FieldSalesJson>> customers(FieldSalesScope s) async {
    if (failure != null) throw failure!;
    return [
      {
        'id': 'customer',
        'name': 'Assigned customer with no transactions',
        'payment_terms_days': '30',
        'delivery_terms': 'Company delivery',
        'ship_to': {'address': 'Company approved address'},
      },
    ];
  }

  @override
  Future<List<FieldSalesJson>> catalogue(
    FieldSalesScope s,
    String customer,
  ) async {
    if (failure != null) throw failure!;
    if (catalogueWait != null) return catalogueWait!.future;
    return [
      {
        'id': 'product',
        'policy_id': 'policy',
        'policy_version': '1',
        'name': 'Governed Product',
        'code': 'P1',
        'unit_id': 'unit',
        'unit': 'Each',
        'currency_code': 'LKR',
        'unit_price': '1.250000',
        'max_discount_percent': '10',
        'stock_state': 'unavailable',
      },
    ];
  }

  @override
  Future<List<FieldSalesJson>> subjects(FieldSalesScope s) async =>
      currentSubjects ??
      (committed == null ? [] : [fieldSalesObject(committed!['entity'])]);
  @override
  Future<FieldSalesJson> preview(
    FieldSalesScope s,
    FieldSalesJson input,
  ) async =>
      previewWait?.future ??
      jsonDecode(jsonEncode(fieldReview)) as FieldSalesJson;
  FieldSalesJson confirmation(FieldSalesCommand c) => {
    'command_id': c.commandId,
    'request_id': 'server-request',
    'entity': {
      'id': c.payload['id'],
      'version': '1',
      'tenant_id': c.scope.tenantId,
      'legal_entity_id': c.scope.entityId,
      'branch_id': c.scope.branchId,
      'rep_id': c.actorId,
      'customer_id': c.payload['input']['customer_id'],
      'source_digest': c.payload['source_digest'],
      'company_state': 'submitted',
      'canonical_order_id': null,
      'customer_state': 'email_link_pending',
      'delivery_state': 'not_requested',
      'preview': fieldReview,
      'input': c.payload['input'],
    },
  };
  @override
  Future<FieldSalesJson> submit(FieldSalesCommand c) async {
    commands.add(c);
    if (submitFailure != null) throw submitFailure!;
    committed = confirmation(c);
    if (badReceipt) committed!['entity']['rep_id'] = 'someone-else';
    return committed!;
  }

  @override
  Future<FieldSalesJson> receipt(FieldSalesScope s, String key) async =>
      committed == null
      ? {'state': 'not_found'}
      : {'state': 'committed', 'receipt': committed};
}
