import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../../crm/application/customer_models.dart';
import '../../crm/data/supabase_customer_repository.dart';
import '../data/supabase_invoice_repository.dart';
import 'invoice_failure.dart';
import 'invoice_models.dart';

final invoiceControllerProvider =
    AsyncNotifierProvider<InvoiceController, InvoiceState>(
      InvoiceController.new,
      retry: (_, _) => null,
    );

final invoiceMutationControllerProvider =
    AsyncNotifierProvider<InvoiceMutationController, Invoice?>(
      InvoiceMutationController.new,
      retry: (_, _) => null,
    );

final invoiceDetailProvider = FutureProvider.autoDispose
    .family<Invoice, String>((ref, invoiceId) async {
      final companyId = ref.watch(selectedCompanyIdProvider);
      if (companyId == null || companyId.trim().isEmpty) {
        throw const InvoiceFailure('Select a company before loading an invoice.');
      }
      return ref
          .watch(invoiceRepositoryProvider)
          .getInvoice(companyId: companyId, invoiceId: invoiceId);
    }, retry: (_, _) => null);

final invoiceCustomerListProvider = FutureProvider.autoDispose<List<Customer>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  final page = await ref
      .watch(customerRepositoryProvider)
      .listCustomers(
        companyId: companyId,
        search: '',
        includeInactive: false,
        pageSize: 100,
      );
  return page.customers;
}, retry: (_, _) => null);

final class InvoiceState {
  const InvoiceState({
    required this.companyId,
    required this.invoices,
    required this.search,
    this.selectedStatus,
    required this.nextCursor,
    this.isRefreshing = false,
    this.isLoadingMore = false,
  });

  final String companyId;
  final List<Invoice> invoices;
  final String search;
  final String? selectedStatus;
  final InvoiceCursor? nextCursor;
  final bool isRefreshing;
  final bool isLoadingMore;

  bool get canLoadMore => nextCursor != null && !isLoadingMore;

  InvoiceState copyWith({
    List<Invoice>? invoices,
    String? search,
    String? selectedStatus,
    bool clearStatus = false,
    InvoiceCursor? nextCursor,
    bool clearCursor = false,
    bool? isRefreshing,
    bool? isLoadingMore,
  }) {
    return InvoiceState(
      companyId: companyId,
      invoices: invoices ?? this.invoices,
      search: search ?? this.search,
      selectedStatus:
          clearStatus ? null : selectedStatus ?? this.selectedStatus,
      nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}

final class InvoiceController extends AsyncNotifier<InvoiceState> {
  static const _pageSize = 30;

  String _search = '';
  String? _selectedStatus;
  int _requestVersion = 0;

  @override
  Future<InvoiceState> build() async {
    final companyId = ref.watch(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InvoiceFailure('Select a company before loading invoices.');
    }

    _search = '';
    _selectedStatus = null;
    _requestVersion += 1;

    final page = await ref
        .watch(invoiceRepositoryProvider)
        .listInvoices(
          companyId: companyId,
          search: _search,
          status: _selectedStatus,
          pageSize: _pageSize,
        );

    _ensureCompany(companyId);
    _ensureInvoicesCompany(page.invoices, companyId);

    return InvoiceState(
      companyId: companyId,
      invoices: page.invoices,
      search: _search,
      selectedStatus: _selectedStatus,
      nextCursor: page.nextCursor,
    );
  }

  Future<void> updateSearch(String value) async {
    final normalized = value.trim();
    if (_search == normalized) return;
    _search = normalized;
    await _loadFirstPage();
  }

  Future<void> filterByStatus(String? status) async {
    if (_selectedStatus == status) return;
    _selectedStatus = status;
    await _loadFirstPage();
  }

  Future<void> refreshInvoices() => _loadFirstPage();

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.canLoadMore) return;
    final cursor = current.nextCursor;
    if (cursor == null) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(invoiceRepositoryProvider)
          .listInvoices(
            companyId: current.companyId,
            search: _search,
            status: _selectedStatus,
            cursor: cursor,
            pageSize: _pageSize,
          );

      _ensureCompany(current.companyId);
      _ensureInvoicesCompany(page.invoices, current.companyId);

      final existingIds = current.invoices.map((item) => item.id).toSet();
      final combined = <Invoice>[
        ...current.invoices,
        ...page.invoices.where((item) => existingIds.add(item.id)),
      ];

      state = AsyncData(
        current.copyWith(
          invoices: List<Invoice>.unmodifiable(combined),
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
        const InvoiceFailure('Select a company before loading invoices.'),
        StackTrace.current,
      );
      return;
    }

    final requestVersion = ++_requestVersion;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          search: _search,
          selectedStatus: _selectedStatus,
          isRefreshing: true,
        ),
      );
    } else {
      state = const AsyncLoading();
    }

    try {
      final page = await ref
          .read(invoiceRepositoryProvider)
          .listInvoices(
            companyId: companyId,
            search: _search,
            status: _selectedStatus,
            pageSize: _pageSize,
          );

      if (requestVersion != _requestVersion) return;
      _ensureCompany(companyId);
      _ensureInvoicesCompany(page.invoices, companyId);

      state = AsyncData(
        InvoiceState(
          companyId: companyId,
          invoices: page.invoices,
          search: _search,
          selectedStatus: _selectedStatus,
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
      throw const InvoiceFailure(
        'The selected company changed while loading invoices.',
      );
    }
  }
}

final class InvoiceMutationController extends AsyncNotifier<Invoice?> {
  @override
  Future<Invoice?> build() async => null;

  Future<Invoice> createInvoice(InvoiceInput input) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final created = await ref
          .read(invoiceRepositoryProvider)
          .createInvoice(companyId: companyId, input: input);

      _ensureCompany(companyId);
      _ensureInvoicesCompany([created], companyId);

      state = AsyncData(created);
      ref.invalidate(invoiceControllerProvider);
      return created;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Invoice> updateInvoice(String invoiceId, InvoiceInput input) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(invoiceRepositoryProvider)
          .updateInvoice(
            companyId: companyId,
            invoiceId: invoiceId,
            input: input,
          );

      _ensureCompany(companyId);
      _ensureInvoicesCompany([updated], companyId);

      state = AsyncData(updated);
      ref.invalidate(invoiceDetailProvider(invoiceId));
      ref.invalidate(invoiceControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<Invoice> markAsIssued(String invoiceId) async {
    final companyId = _requireCompanyId();
    state = const AsyncLoading();
    try {
      final updated = await ref
          .read(invoiceRepositoryProvider)
          .updateInvoiceStatus(
            companyId: companyId,
            invoiceId: invoiceId,
            status: 'issued',
          );

      _ensureCompany(companyId);
      _ensureInvoicesCompany([updated], companyId);

      state = AsyncData(updated);
      ref.invalidate(invoiceDetailProvider(invoiceId));
      ref.invalidate(invoiceControllerProvider);
      return updated;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  String _requireCompanyId() {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const InvoiceFailure(
        'Select a company before managing invoices.',
      );
    }
    return companyId;
  }

  void _ensureCompany(String companyId) {
    if (ref.read(selectedCompanyIdProvider) != companyId) {
      throw const InvoiceFailure(
        'The selected company changed during the invoice action.',
      );
    }
  }
}

void _ensureInvoicesCompany(List<Invoice> invoices, String companyId) {
  if (invoices.any((inv) => inv.companyId != companyId)) {
    throw const InvoiceFailure(
      'An invoice response did not match the selected company.',
    );
  }
}
