import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/customer_failure.dart';
import '../application/customer_models.dart';
import '../application/customer_repository.dart';
import '../application/customer_validators.dart';
import 'customer_service.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return SupabaseCustomerRepository(ref.watch(customerServiceProvider));
});

final class SupabaseCustomerRepository implements CustomerRepository {
  const SupabaseCustomerRepository(this._service);

  final CustomerService _service;

  @override
  Future<CustomerPage> listCustomers({
    required String companyId,
    required String search,
    required bool includeInactive,
    CustomerCursor? cursor,
    int pageSize = 30,
  }) {
    return _guard(() async {
      final scope = _requireCompanyId(companyId);
      final safePageSize = pageSize.clamp(1, 99);
      final rows = await _service.fetchCustomers(
        companyId: scope,
        search: search,
        includeInactive: includeInactive,
        cursor: cursor,
        limit: safePageSize + 1,
      );
      final mapped = rows.map(_mapCustomer).toList(growable: true);
      for (final customer in mapped) {
        _requireMatchingCompany(customer, scope);
      }

      final hasMore = mapped.length > safePageSize;
      if (hasMore) mapped.removeLast();
      final customers = List<Customer>.unmodifiable(mapped);
      final last = customers.isEmpty ? null : customers.last;
      return CustomerPage(
        customers: customers,
        nextCursor: hasMore && last != null
            ? CustomerCursor(sortName: last.sortName, id: last.id)
            : null,
      );
    });
  }

  @override
  Future<Customer> getCustomer({
    required String companyId,
    required String customerId,
  }) {
    return _guard(() async {
      final scope = _requireCompanyId(companyId);
      final id = _requireCustomerId(customerId);
      final row = await _service.fetchCustomer(
        companyId: scope,
        customerId: id,
      );
      if (row == null) {
        throw const CustomerFailure(
          'This customer is unavailable or you no longer have access.',
        );
      }
      final customer = _mapCustomer(row);
      _requireMatchingCompany(customer, scope);
      return customer;
    });
  }

  @override
  Future<Customer> createCustomer({
    required String companyId,
    required CustomerInput input,
  }) {
    return _guard(() async {
      final scope = _requireCompanyId(companyId);
      _validate(input);
      final customer = _mapCustomer(
        await _service.insertCustomer(companyId: scope, input: input),
      );
      _requireMatchingCompany(customer, scope);
      return customer;
    });
  }

  @override
  Future<Customer> updateCustomer({
    required String companyId,
    required String customerId,
    required CustomerInput input,
  }) {
    return _guard(() async {
      final scope = _requireCompanyId(companyId);
      final id = _requireCustomerId(customerId);
      _validate(input);
      final row = await _service.updateCustomer(
        companyId: scope,
        customerId: id,
        input: input,
      );
      if (row == null) {
        throw const CustomerFailure(
          'The customer could not be updated. Check your access and try again.',
        );
      }
      final customer = _mapCustomer(row);
      _requireMatchingCompany(customer, scope);
      return customer;
    });
  }

  @override
  Future<Customer> setCustomerActive({
    required String companyId,
    required String customerId,
    required bool isActive,
  }) {
    return _guard(() async {
      final scope = _requireCompanyId(companyId);
      final id = _requireCustomerId(customerId);
      final row = await _service.updateCustomerActive(
        companyId: scope,
        customerId: id,
        isActive: isActive,
      );
      if (row == null) {
        throw const CustomerFailure(
          'The customer status could not be changed. Check your access and try again.',
        );
      }
      final customer = _mapCustomer(row);
      _requireMatchingCompany(customer, scope);
      return customer;
    });
  }

  Customer _mapCustomer(Map<String, dynamic> row) {
    return Customer(
      id: _requiredString(row, 'id'),
      companyId: _requiredString(row, 'company_id'),
      name: _requiredString(row, 'name'),
      displayName: _optionalString(row['display_name']),
      email: _optionalString(row['email']),
      phone: _optionalString(row['phone']),
      mobile: _optionalString(row['mobile']),
      taxNumber: _optionalString(row['tax_no']),
      creditLimit: _readDouble(row['credit_limit']),
      paymentTermsDays: _readNullableInt(row['payment_terms_days']),
      openingBalance: _readDouble(row['opening_balance']),
      notes: _optionalString(row['notes']),
      tags: row['tags'] is List
          ? List<String>.unmodifiable(
              (row['tags'] as List).map((tag) => tag.toString()),
            )
          : const <String>[],
      isActive: row['is_active'] as bool? ?? true,
      createdAt: _readDate(row, 'created_at'),
      updatedAt: _readDate(row, 'updated_at'),
    );
  }

  void _validate(CustomerInput input) {
    final issue =
        CustomerValidators.name(input.name) ??
        CustomerValidators.email(input.email);
    if (issue != null) throw CustomerFailure(issue);
    if (!input.creditLimit.isFinite || input.creditLimit < 0) {
      throw const CustomerFailure('Credit limit cannot be negative.');
    }
    final terms = input.paymentTermsDays;
    if (terms != null && (terms < 0 || terms > 3650)) {
      throw const CustomerFailure(
        'Payment terms must be between 0 and 3650 days.',
      );
    }
    if (!input.openingBalance.isFinite) {
      throw const CustomerFailure('Enter a valid opening balance.');
    }
    if (input.tags.length > 30) {
      throw const CustomerFailure('Use no more than 30 customer tags.');
    }
  }

  String _requireCompanyId(String companyId) {
    final normalized = companyId.trim();
    if (normalized.isEmpty) {
      throw const CustomerFailure(
        'Select a company before managing customers.',
      );
    }
    return normalized;
  }

  String _requireCustomerId(String customerId) {
    final normalized = customerId.trim();
    if (normalized.isEmpty) {
      throw const CustomerFailure('Select a valid customer.');
    }
    return normalized;
  }

  void _requireMatchingCompany(Customer customer, String companyId) {
    if (customer.companyId != companyId) {
      throw const CustomerFailure(
        'The customer company context changed. Please refresh.',
      );
    }
  }

  String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw const CustomerFailure(
        'A customer record contains incomplete information.',
      );
    }
    return value;
  }

  String? _optionalString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  double _readDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _readNullableInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  DateTime _readDate(Map<String, dynamic> row, String key) {
    final value = DateTime.tryParse(row[key]?.toString() ?? '');
    if (value == null) {
      throw const CustomerFailure(
        'A customer record contains an invalid timestamp.',
      );
    }
    return value;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on CustomerFailure {
      rethrow;
    } on AuthException catch (error, stackTrace) {
      throw CustomerFailure(
        'Your session is no longer valid. Please sign in again.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on PostgrestException catch (error, stackTrace) {
      final denied = error.code == '42501';
      throw CustomerFailure(
        denied
            ? 'You do not have permission to complete this customer action.'
            : 'We could not complete the customer action. Please try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw CustomerFailure(
        'We could not complete the customer action. Please try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
