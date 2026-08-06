import 'customer_models.dart';

abstract interface class CustomerRepository {
  Future<CustomerPage> listCustomers({
    required String companyId,
    required String search,
    required bool includeInactive,
    CustomerCursor? cursor,
    int pageSize = 30,
  });

  Future<Customer> getCustomer({
    required String companyId,
    required String customerId,
  });

  Future<Customer> createCustomer({
    required String companyId,
    required CustomerInput input,
  });

  Future<Customer> updateCustomer({
    required String companyId,
    required String customerId,
    required CustomerInput input,
  });

  Future<Customer> setCustomerActive({
    required String companyId,
    required String customerId,
    required bool isActive,
  });
}
