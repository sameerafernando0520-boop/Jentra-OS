import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/company_failure.dart';
import '../application/company_models.dart';

final companyServiceProvider = Provider<CompanyService>((ref) {
  return CompanyService(ref.watch(supabaseServiceProvider).client);
});

/// Low-level, RLS-bound adapter for company onboarding data operations.
///
/// It always uses the currently authenticated user and never accepts another
/// user's ID from callers. Company defaults remain owned by the database's
/// synchronous `companies_initialize_defaults` trigger.
final class CompanyService {
  const CompanyService(this._client);

  final SupabaseClient _client;

  String get currentUserId {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const CompanyFailure('Please sign in to continue.');
    }
    return userId;
  }

  Future<List<Map<String, dynamic>>> fetchActiveMemberships() async {
    final rows = await _client
        .from('company_memberships')
        .select('''
          company_id,
          companies!inner(
            id,
            owner_user_id,
            name,
            legal_name,
            currency_code,
            country_code,
            timezone,
            status
          ),
          roles!company_memberships_role_company_fk(
            name,
            is_owner,
            is_admin
          )
        ''')
        .eq('user_id', currentUserId)
        .eq('status', 'active')
        .eq('companies.status', 'active');

    return rows;
  }

  Future<String?> fetchPreferredCompanyId() async {
    final row = await _client
        .from('profiles')
        .select('default_company_id')
        .eq('id', currentUserId)
        .maybeSingle();

    return row?['default_company_id'] as String?;
  }

  Future<Map<String, dynamic>> insertCompany(CreateCompanyInput input) async {
    final legalName = input.legalName?.trim();

    // Keep this payload explicit. Memberships, roles, settings, and branches
    // are created atomically by the database trigger after this insert.
    final values = <String, Object?>{
      'owner_user_id': currentUserId,
      'name': input.name.trim(),
      'legal_name': legalName == null || legalName.isEmpty ? null : legalName,
      'currency_code': input.currencyCode.trim().toUpperCase(),
      'country_code': input.countryCode.trim().toUpperCase(),
      'timezone': input.timezone.trim(),
    };

    return _client.from('companies').insert(values).select('''
          id,
          owner_user_id,
          name,
          legal_name,
          currency_code,
          country_code,
          timezone,
          status
        ''').single();
  }

  Future<void> updatePreferredCompanyId(String companyId) async {
    final updated = await _client
        .from('profiles')
        .update({'default_company_id': companyId})
        .eq('id', currentUserId)
        .select('default_company_id')
        .maybeSingle();

    if (updated == null || updated['default_company_id'] != companyId) {
      throw const CompanyFailure(
        'We could not save your company selection. Please try again.',
      );
    }
  }

  Future<Map<String, dynamic>?> fetchCompanySettings(String companyId) {
    return _client
        .from('company_settings')
        .select('''
          company_id,
          invoice_prefix,
          quotation_prefix,
          sales_order_prefix,
          purchase_order_prefix,
          bill_prefix,
          next_invoice_no,
          next_quotation_no,
          next_sales_order_no,
          next_purchase_order_no,
          next_bill_no,
          default_payment_terms_days
        ''')
        .eq('company_id', companyId)
        .maybeSingle();
  }
}
