import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/invoice_failure.dart';
import '../application/invoice_models.dart';

final invoiceServiceProvider = Provider<InvoiceService>((ref) {
  return InvoiceService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Data API adapter for sales invoices.
/// Every operation carries explicit company_id filtering and uses server-side RPC for atomic saves.
final class InvoiceService {
  const InvoiceService(this._client);

  final SupabaseClient _client;

  static const invoiceHeaderFields = '''
    id,
    company_id,
    branch_id,
    customer_id,
    document_type,
    document_number,
    status,
    issue_date,
    due_date,
    subtotal,
    discount_amount,
    tax_amount,
    grand_total,
    paid_amount,
    balance_due,
    notes,
    terms_and_conditions,
    created_by,
    created_at,
    updated_at,
    parties!inner(name, display_name)
  ''';

  static const invoiceItemFields = '''
    id,
    company_id,
    document_id,
    product_id,
    description,
    quantity,
    unit_price,
    discount_amount,
    tax_rate,
    tax_amount,
    line_total,
    created_at,
    updated_at
  ''';

  void requireSession() {
    if (_client.auth.currentUser == null) {
      throw const InvoiceFailure('Please sign in to manage invoices.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchInvoices({
    required String companyId,
    required String search,
    String? status,
    String? customerId,
    required InvoiceCursor? cursor,
    required int limit,
  }) async {
    requireSession();
    final response = await _client.rpc(
      'search_invoices',
      params: {
        'p_company_id': companyId,
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_status': status,
        'p_customer_id': customerId,
        'p_after_date': cursor?.issueDate.toIso8601String().split('T').first,
        'p_after_id': cursor?.id,
        'p_limit': limit,
      },
    );

    if (response is! List) {
      throw const InvoiceFailure('Unexpected response format from search_invoices.');
    }
    final rows = response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    // Join parties info for list display
    if (rows.isEmpty) return rows;

    final customerIds = rows.map((r) => r['customer_id'] as String).toSet().toList();
    final partiesResponse = await _client
        .from('parties')
        .select('id, name, display_name')
        .inFilter('id', customerIds);
    final partyMap = {
      for (final p in List<Map<String, dynamic>>.from(partiesResponse))
        p['id'] as String: p
    };

    return rows.map((row) {
      final cust = partyMap[row['customer_id'] as String];
      return {
        ...row,
        'parties': cust ?? {'name': 'Customer'},
      };
    }).toList();
  }

  Future<Map<String, dynamic>?> fetchInvoiceDetail({
    required String companyId,
    required String invoiceId,
  }) async {
    requireSession();
    final header = await _client
        .from('sales_documents')
        .select(invoiceHeaderFields)
        .eq('company_id', companyId)
        .eq('id', invoiceId)
        .eq('document_type', 'invoice')
        .maybeSingle();

    if (header == null) return null;

    final items = await _client
        .from('sales_document_items')
        .select(invoiceItemFields)
        .eq('company_id', companyId)
        .eq('document_id', invoiceId)
        .order('created_at');

    return {
      ...header,
      'sales_document_items': items,
    };
  }

  Future<Map<String, dynamic>> saveInvoice({
    required String companyId,
    String? invoiceId,
    required String customerId,
    String? documentNumber,
    required String status,
    required DateTime issueDate,
    DateTime? dueDate,
    required double subtotal,
    required double discountAmount,
    required double taxAmount,
    required double grandTotal,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    requireSession();
    final response = await _client.rpc(
      'save_sales_invoice',
      params: {
        'p_company_id': companyId,
        'p_invoice_id': invoiceId,
        'p_customer_id': customerId,
        'p_document_number': documentNumber,
        'p_status': status,
        'p_issue_date': issueDate.toIso8601String().split('T').first,
        'p_due_date': dueDate?.toIso8601String().split('T').first,
        'p_subtotal': subtotal,
        'p_discount_amount': discountAmount,
        'p_tax_amount': taxAmount,
        'p_grand_total': grandTotal,
        'p_notes': notes,
        'p_items': items,
      },
    );

    if (response is! Map) {
      throw const InvoiceFailure('Save invoice failed to return a valid document.');
    }
    final row = Map<String, dynamic>.from(response);

    // Fetch customer details for display
    final party = await _client
        .from('parties')
        .select('name, display_name')
        .eq('id', customerId)
        .maybeSingle();

    return {
      ...row,
      'parties': party ?? {'name': 'Customer'},
      'sales_document_items': items,
    };
  }

  Future<Map<String, dynamic>?> updateInvoiceStatus({
    required String companyId,
    required String invoiceId,
    required String status,
  }) async {
    requireSession();
    final row = await _client
        .from('sales_documents')
        .update({'status': status})
        .eq('company_id', companyId)
        .eq('id', invoiceId)
        .eq('document_type', 'invoice')
        .select(invoiceHeaderFields)
        .maybeSingle();

    if (row == null) return null;

    final items = await _client
        .from('sales_document_items')
        .select(invoiceItemFields)
        .eq('company_id', companyId)
        .eq('document_id', invoiceId);

    return {
      ...row,
      'sales_document_items': items,
    };
  }
}
