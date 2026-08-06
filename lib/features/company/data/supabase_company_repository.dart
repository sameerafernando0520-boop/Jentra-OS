import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/company_failure.dart';
import '../application/company_models.dart';
import '../application/company_repository.dart';
import 'company_service.dart';

final companyRepositoryProvider = Provider<CompanyRepository>((ref) {
  return SupabaseCompanyRepository(ref.watch(companyServiceProvider));
});

/// Reads only memberships visible through the database RLS policies.
final class SupabaseCompanyRepository implements CompanyRepository {
  const SupabaseCompanyRepository(this._service);

  final CompanyService _service;

  @override
  Future<List<Company>> listAvailableCompanies() {
    return _guard(
      () async {
        final rows = await _service.fetchActiveMemberships();
        final companies = rows.map(_mapCompany).toList(growable: false)
          ..sort((left, right) => left.name.compareTo(right.name));
        return List<Company>.unmodifiable(companies);
      },
      'We could not load your companies. Check your connection and try again.',
    );
  }

  @override
  Future<String?> getPreferredCompanyId() {
    return _guard(
      _service.fetchPreferredCompanyId,
      'We could not restore your company selection. Please try again.',
    );
  }

  @override
  Future<Company> createCompany(CreateCompanyInput input) async {
    _validate(input);
    final inserted = await _guard(
      () => _service.insertCompany(input),
      'We could not create the company. Check the details and try again.',
    );
    final companyId = inserted['id'] as String?;
    if (companyId == null) {
      throw const CompanyFailure(
        'The company may have been created, but its setup could not be '
        'confirmed. Refresh companies before trying again.',
      );
    }

    return _guard(
      () async {
        // The AFTER INSERT trigger is synchronous. Confirm both outputs needed
        // by onboarding before reporting success to the UI.
        final memberships = await _service.fetchActiveMemberships();
        Map<String, dynamic>? membership;
        for (final row in memberships) {
          if (row['company_id'] == companyId) {
            membership = row;
            break;
          }
        }

        final settings = await _service.fetchCompanySettings(companyId);
        if (membership == null || settings == null) {
          throw const CompanyFailure(
            'The company was created, but its setup could not be confirmed. '
            'Refresh companies before trying again.',
          );
        }

        return _mapCompany(membership);
      },
      'The company was created, but its setup could not be confirmed. '
      'Refresh companies before trying again.',
    );
  }

  @override
  Future<void> savePreferredCompanyId(String companyId) {
    return _guard(() async {
      if (companyId.trim().isEmpty) {
        throw const CompanyFailure('Select a valid company to continue.');
      }
      await _service.updatePreferredCompanyId(companyId);
    }, 'We could not save your company selection. Please try again.');
  }

  @override
  Future<CompanySettingsOverview> getCompanySettings(String companyId) {
    return _guard(() async {
      final row = await _service.fetchCompanySettings(companyId);
      if (row == null) {
        throw const CompanyFailure(
          'Company settings are not available yet. Please refresh.',
        );
      }
      return _mapSettings(row);
    }, 'We could not load company settings. Please try again.');
  }

  Company _mapCompany(Map<String, dynamic> row) {
    final company = row['companies'] as Map<String, dynamic>?;
    final role = row['roles'] as Map<String, dynamic>?;
    if (company == null || role == null) {
      throw const CompanyFailure(
        'A company membership contains incomplete information.',
      );
    }

    return Company(
      id: company['id'] as String,
      ownerUserId: company['owner_user_id'] as String,
      name: company['name'] as String,
      legalName: company['legal_name'] as String?,
      currencyCode: (company['currency_code'] as String).trim(),
      countryCode: (company['country_code'] as String).trim(),
      timezone: company['timezone'] as String,
      membershipRole: role['name'] as String,
      isOwner: role['is_owner'] as bool? ?? false,
      isAdmin: role['is_admin'] as bool? ?? false,
    );
  }

  CompanySettingsOverview _mapSettings(Map<String, dynamic> row) {
    return CompanySettingsOverview(
      companyId: row['company_id'] as String,
      invoicePrefix: row['invoice_prefix'] as String,
      quotationPrefix: row['quotation_prefix'] as String,
      salesOrderPrefix: row['sales_order_prefix'] as String,
      purchaseOrderPrefix: row['purchase_order_prefix'] as String,
      billPrefix: row['bill_prefix'] as String,
      nextInvoiceNumber: _readInt(row, 'next_invoice_no'),
      nextQuotationNumber: _readInt(row, 'next_quotation_no'),
      nextSalesOrderNumber: _readInt(row, 'next_sales_order_no'),
      nextPurchaseOrderNumber: _readInt(row, 'next_purchase_order_no'),
      nextBillNumber: _readInt(row, 'next_bill_no'),
      defaultPaymentTermsDays: _readInt(row, 'default_payment_terms_days'),
    );
  }

  int _readInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.parse(value.toString());
  }

  void _validate(CreateCompanyInput input) {
    if (input.name.trim().isEmpty) {
      throw const CompanyFailure('Enter a company name.');
    }
    if (input.currencyCode.trim().length != 3) {
      throw const CompanyFailure('Enter a valid three-letter currency code.');
    }
    if (input.countryCode.trim().length != 2) {
      throw const CompanyFailure('Enter a valid two-letter country code.');
    }
    if (input.timezone.trim().isEmpty) {
      throw const CompanyFailure('Enter a valid timezone.');
    }
  }

  Future<T> _guard<T>(
    Future<T> Function() operation,
    String fallbackMessage,
  ) async {
    try {
      return await operation();
    } on CompanyFailure {
      rethrow;
    } on AuthException catch (error, stackTrace) {
      throw CompanyFailure(
        'Your session is no longer valid. Please sign in again.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on PostgrestException catch (error, stackTrace) {
      throw CompanyFailure(
        fallbackMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw CompanyFailure(
        fallbackMessage,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
