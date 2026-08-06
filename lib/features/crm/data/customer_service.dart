import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/customer_failure.dart';
import '../application/customer_models.dart';

final customerServiceProvider = Provider<CustomerService>((ref) {
  return CustomerService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level Data API adapter. Every operation carries an explicit company ID;
/// database RLS remains the authoritative tenant boundary.
final class CustomerService {
  const CustomerService(this._client);

  final SupabaseClient _client;

  static const fields = '''
    id,
    company_id,
    name,
    display_name,
    email,
    phone,
    mobile,
    tax_no,
    credit_limit,
    payment_terms_days,
    opening_balance,
    notes,
    tags,
    is_active,
    created_at,
    updated_at
  ''';

  void requireSession() {
    if (_client.auth.currentUser == null) {
      throw const CustomerFailure('Please sign in to manage customers.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomers({
    required String companyId,
    required String search,
    required bool includeInactive,
    required CustomerCursor? cursor,
    required int limit,
  }) async {
    requireSession();
    final response = await _client.rpc(
      'search_customers',
      params: {
        'p_company_id': companyId,
        'p_search': search.trim().isEmpty ? null : search.trim(),
        'p_include_inactive': includeInactive,
        'p_after_sort_name': cursor?.sortName,
        'p_after_id': cursor?.id,
        'p_limit': limit,
      },
    );

    if (response is! List) {
      throw const CustomerFailure(
        'The customer list returned an unexpected response.',
      );
    }
    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> fetchCustomer({
    required String companyId,
    required String customerId,
  }) {
    requireSession();
    return _client
        .from('parties')
        .select(fields)
        .eq('company_id', companyId)
        .eq('id', customerId)
        .inFilter('party_type', const ['customer', 'both'])
        .maybeSingle();
  }

  Future<Map<String, dynamic>> insertCustomer({
    required String companyId,
    required CustomerInput input,
  }) {
    requireSession();
    return _client
        .from('parties')
        .insert({
          'company_id': companyId,
          'party_type': 'customer',
          ..._inputValues(input),
        })
        .select(fields)
        .single();
  }

  Future<Map<String, dynamic>?> updateCustomer({
    required String companyId,
    required String customerId,
    required CustomerInput input,
  }) {
    requireSession();
    return _client
        .from('parties')
        .update(_inputValues(input))
        .eq('company_id', companyId)
        .eq('id', customerId)
        .inFilter('party_type', const ['customer', 'both'])
        .select(fields)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> updateCustomerActive({
    required String companyId,
    required String customerId,
    required bool isActive,
  }) {
    requireSession();
    return _client
        .from('parties')
        .update({'is_active': isActive})
        .eq('company_id', companyId)
        .eq('id', customerId)
        .inFilter('party_type', const ['customer', 'both'])
        .select(fields)
        .maybeSingle();
  }

  Map<String, Object?> _inputValues(CustomerInput input) {
    return {
      'name': input.name.trim(),
      'display_name': _optional(input.displayName),
      'email': _optional(input.email),
      'phone': _optional(input.phone),
      'mobile': _optional(input.mobile),
      'tax_no': _optional(input.taxNumber),
      'credit_limit': input.creditLimit,
      'payment_terms_days': input.paymentTermsDays,
      'opening_balance': input.openingBalance,
      'notes': _optional(input.notes),
      'tags': input.tags,
    };
  }

  String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
