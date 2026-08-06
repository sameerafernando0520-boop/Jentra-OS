import 'package:jentra_os/features/crm/application/customer_models.dart';
import 'package:jentra_os/features/crm/application/customer_repository.dart';

final class CustomerListRequest {
  const CustomerListRequest({
    required this.companyId,
    required this.search,
    required this.includeInactive,
    required this.cursor,
    required this.pageSize,
  });

  final String companyId;
  final String search;
  final bool includeInactive;
  final CustomerCursor? cursor;
  final int pageSize;
}

final class FakeCustomerRepository implements CustomerRepository {
  FakeCustomerRepository({List<Customer> customers = const <Customer>[]})
    : customers = List<Customer>.of(customers);

  final List<Customer> customers;
  final List<CustomerListRequest> listRequests = <CustomerListRequest>[];
  final List<String> detailCompanyIds = <String>[];
  final List<String> createCompanyIds = <String>[];
  final List<String> updateCompanyIds = <String>[];
  final List<String> statusCompanyIds = <String>[];

  @override
  Future<CustomerPage> listCustomers({
    required String companyId,
    required String search,
    required bool includeInactive,
    CustomerCursor? cursor,
    int pageSize = 30,
  }) async {
    listRequests.add(
      CustomerListRequest(
        companyId: companyId,
        search: search,
        includeInactive: includeInactive,
        cursor: cursor,
        pageSize: pageSize,
      ),
    );
    final query = search.toLowerCase();
    final matches = customers
        .where((customer) {
          if (!includeInactive && !customer.isActive) return false;
          if (query.isEmpty) return true;
          return customer.title.toLowerCase().contains(query) ||
              (customer.email?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);
    return CustomerPage(customers: matches, nextCursor: null);
  }

  @override
  Future<Customer> getCustomer({
    required String companyId,
    required String customerId,
  }) async {
    detailCompanyIds.add(companyId);
    return customers.firstWhere((customer) => customer.id == customerId);
  }

  @override
  Future<Customer> createCustomer({
    required String companyId,
    required CustomerInput input,
  }) async {
    createCompanyIds.add(companyId);
    final customer = _fromInput(
      id: 'created-customer',
      companyId: companyId,
      input: input,
    );
    customers.add(customer);
    return customer;
  }

  @override
  Future<Customer> updateCustomer({
    required String companyId,
    required String customerId,
    required CustomerInput input,
  }) async {
    updateCompanyIds.add(companyId);
    final index = customers.indexWhere((customer) => customer.id == customerId);
    final updated = _fromInput(
      id: customerId,
      companyId: companyId,
      input: input,
      isActive: customers[index].isActive,
    );
    customers[index] = updated;
    return updated;
  }

  @override
  Future<Customer> setCustomerActive({
    required String companyId,
    required String customerId,
    required bool isActive,
  }) async {
    statusCompanyIds.add(companyId);
    final index = customers.indexWhere((customer) => customer.id == customerId);
    final current = customers[index];
    final updated = Customer(
      id: current.id,
      companyId: current.companyId,
      name: current.name,
      displayName: current.displayName,
      email: current.email,
      phone: current.phone,
      mobile: current.mobile,
      taxNumber: current.taxNumber,
      creditLimit: current.creditLimit,
      paymentTermsDays: current.paymentTermsDays,
      openingBalance: current.openingBalance,
      notes: current.notes,
      tags: current.tags,
      isActive: isActive,
      createdAt: current.createdAt,
      updatedAt: DateTime.utc(2026, 7, 14, 12),
    );
    customers[index] = updated;
    return updated;
  }

  Customer _fromInput({
    required String id,
    required String companyId,
    required CustomerInput input,
    bool isActive = true,
  }) {
    return Customer(
      id: id,
      companyId: companyId,
      name: input.name.trim(),
      displayName: input.displayName,
      email: input.email,
      phone: input.phone,
      mobile: input.mobile,
      taxNumber: input.taxNumber,
      creditLimit: input.creditLimit,
      paymentTermsDays: input.paymentTermsDays,
      openingBalance: input.openingBalance,
      notes: input.notes,
      tags: input.tags,
      isActive: isActive,
      createdAt: DateTime.utc(2026, 7, 14, 10),
      updatedAt: DateTime.utc(2026, 7, 14, 10),
    );
  }
}
