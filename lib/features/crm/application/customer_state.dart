import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../data/supabase_customer_repository.dart';
import 'customer_failure.dart';
import 'customer_models.dart';

final customerControllerProvider =
    AsyncNotifierProvider<CustomerController, CustomerState>(
      CustomerController.new,
      retry: (_, _) => null,
    );

final customerMutationProvider =
    AsyncNotifierProvider<CustomerMutationController, Customer?>(
      CustomerMutationController.new,
      retry: (_, _) => null,
    );

final customerDetailProvider = FutureProvider.autoDispose
    .family<Customer, String>((ref, customerId) async {
      final companyId = ref.watch(selectedCompanyIdProvider);
      if (companyId == null || companyId.trim().isEmpty) {
        throw const CustomerFailure(
          'Select a company before loading a customer.',
        );
      }
      return ref
          .watch(customerRepositoryProvider)
          .getCustomer(companyId: companyId, customerId: customerId);
    }, retry: (_, _) => null);

final class CustomerState {
  const CustomerState({
    required this.companyId,
    required this.customers,
    required this.search,
    required this.includeInactive,
    required this.nextCursor,
    this.isRefreshing = false,
    this.isLoadingMore = false,
  });

  final String companyId;
  final List<Customer> customers;
  final String search;
  final bool includeInactive;
  final CustomerCursor? nextCursor;
  final bool isRefreshing;
  final bool isLoadingMore;

  bool get canLoadMore => nextCursor != null && !isLoadingMore;

  CustomerState copyWith({
    List<Customer>? customers,
    String? search,
    bool? includeInactive,
    CustomerCursor? nextCursor,
    bool clearCursor = false,
    bool? isRefreshing,
    bool? isLoadingMore,
  }) {
    return CustomerState(
      companyId: companyId,
      customers: customers ?? this.customers,
      search: search ?? this.search,
      includeInactive: includeInactive ?? this.includeInactive,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final class CustomerController extends AsyncNotifier<CustomerState> {
  static const _pageSize = 30;

  String _search = '';
  bool _includeInactive = false;
  int _requestVersion = 0;

  @override
  Future<CustomerState> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const CustomerFailure('Select a company before loading customers.');
    }

    _search = '';
    _includeInactive = false;
    _requestVersion += 1;
    final page = await ref
        .watch(customerRepositoryProvider)
        .listCustomers(
          companyId: companyId,
          search: _search,
          includeInactive: _includeInactive,
          pageSize: _pageSize,
        );
    _ensureCompany(companyId);
    _ensureCustomersCompany(page.customers, companyId);
    return CustomerState(
      companyId: companyId,
      customers: page.customers,
      search: _search,
      includeInactive: _includeInactive,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> updateSearch(String value) async {
    final normalized = value.trim();
    if (_search == normalized) return;
    _search = normalized;
    await _loadFirstPage();
  }

  Future<void> setIncludeInactive(bool value) async {
    if (_includeInactive == value) return;
    _includeInactive = value;
    await _loadFirstPage();
  }

  Future<void> refreshCustomers() => _loadFirstPage();

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.canLoadMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(customerRepositoryProvider)
          .listCustomers(
            companyId: current.companyId,
            search: _search,
            includeInactive: _includeInactive,
            cursor: cursor,
            pageSize: _pageSize,
          );
      _ensureCompany(current.companyId);
      _ensureCustomersCompany(page.customers, current.companyId);
      final existingIds = current.customers.map((item) => item.id).toSet();
      final combined = <Customer>[
        ...current.customers,
        ...page.customers.where((item) => existingIds.add(item.id)),
      ];
      state = AsyncData(
        current.copyWith(
          customers: List<Customer>.unmodifiable(combined),
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          isLoadingMore: false,
        ),
      );
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> _loadFirstPage() async {
    final current = state.asData?.value;
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      state = AsyncError(
        const CustomerFailure('Select a company before loading customers.'),
        StackTrace.current,
      );
      return;
    }

    final requestVersion = ++_requestVersion;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          search: _search,
          includeInactive: _includeInactive,
          isRefreshing: true,
        ),
      );
    } else {
      state = const AsyncLoading();
    }

    try {
      final page = await ref
          .read(customerRepositoryProvider)
          .listCustomers(
            companyId: companyId,
            search: _search,
            includeInactive: _includeInactive,
            pageSize: _pageSize,
          );
      if (requestVersion != _requestVersion) return;
      _ensureCompany(companyId);
      _ensureCustomersCompany(page.customers, companyId);
      state = AsyncData(
        CustomerState(
          companyId: companyId,
          customers: page.customers,
          search: _search,
          includeInactive: _includeInactive,
          nextCursor: page.nextCursor,
        ),
      );
    } on Object catch (error, stackTrace) {
      if (requestVersion == _requestVersion) {
        state = AsyncError(error, stackTrace);
      }
    }
  }

  void _ensureCompany(String companyId) {
    if (ref.read(selectedCompanyIdProvider) != companyId) {
      throw const CustomerFailure(
        'The selected company changed while loading customers.',
      );
    }
  }
}

final class CustomerMutationController extends AsyncNotifier<Customer?> {
  @override
  Future<Customer?> build() async => null;

  Future<Customer> createCustomer(CustomerInput input) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final created = await ref
          .read(customerRepositoryProvider)
          .createCustomer(companyId: companyId, input: input);
      _ensureCompany(companyId);
      _ensureCustomersCompany([created], companyId);
      state = AsyncData(created);
      ref.invalidate(customerControllerProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Customer> updateCustomer(
    String customerId,
    CustomerInput input,
  ) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(customerRepositoryProvider)
          .updateCustomer(
            companyId: companyId,
            customerId: customerId,
            input: input,
          );
      _ensureCompany(companyId);
      _ensureCustomersCompany([updated], companyId);
      state = AsyncData(updated);
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customerControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Customer> setCustomerActive(String customerId, bool isActive) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(customerRepositoryProvider)
          .setCustomerActive(
            companyId: companyId,
            customerId: customerId,
            isActive: isActive,
          );
      _ensureCompany(companyId);
      _ensureCustomersCompany([updated], companyId);
      state = AsyncData(updated);
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customerControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  String _requireCompanyId() {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const CustomerFailure(
        'Select a company before managing customers.',
      );
    }
    return companyId;
  }

  void _ensureCompany(String companyId) {
    if (ref.read(selectedCompanyIdProvider) != companyId) {
      throw const CustomerFailure(
        'The selected company changed during the customer action.',
      );
    }
  }
}

void _ensureCustomersCompany(List<Customer> customers, String companyId) {
  if (customers.any((customer) => customer.companyId != companyId)) {
    throw const CustomerFailure(
      'A customer response did not match the selected company.',
    );
  }
}
