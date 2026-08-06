import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/company/application/company_models.dart';
import 'package:i_book/features/company/application/company_state.dart';
import 'package:i_book/features/crm/application/customer_failure.dart';
import 'package:i_book/features/crm/application/customer_models.dart';
import 'package:i_book/features/crm/application/customer_state.dart';
import 'package:i_book/features/crm/data/supabase_customer_repository.dart';

import '../fake_customer_repository.dart';

void main() {
  test('missing company fails closed without a customer query', () async {
    final repository = FakeCustomerRepository();
    final container = ProviderContainer(
      overrides: [
        selectedCompanyProvider.overrideWithValue(null),
        customerRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(customerControllerProvider.future),
      throwsA(isA<CustomerFailure>()),
    );
    expect(repository.listRequests, isEmpty);
  });

  test('list and search use only the selected company ID', () async {
    final repository = FakeCustomerRepository(customers: [_customer]);
    final container = _container(repository);
    addTearDown(container.dispose);

    final initial = await container.read(customerControllerProvider.future);
    expect(initial.customers, [_customer]);
    expect(repository.listRequests.single.companyId, _company.id);

    await container
        .read(customerControllerProvider.notifier)
        .updateSearch('Acme');

    expect(repository.listRequests.last.companyId, _company.id);
    expect(repository.listRequests.last.search, 'Acme');
  });

  test('cross-company customer rows are rejected by state', () async {
    final repository = FakeCustomerRepository(
      customers: [
        Customer(
          id: 'customer-2',
          companyId: 'company-2',
          name: 'Wrong tenant',
          displayName: null,
          email: null,
          phone: null,
          mobile: null,
          taxNumber: null,
          creditLimit: 0,
          paymentTermsDays: null,
          openingBalance: 0,
          notes: null,
          tags: const [],
          isActive: true,
          createdAt: DateTime.utc(2026, 7, 14),
          updatedAt: DateTime.utc(2026, 7, 14),
        ),
      ],
    );
    final container = _container(repository);
    addTearDown(container.dispose);

    await expectLater(
      container.read(customerControllerProvider.future),
      throwsA(isA<CustomerFailure>()),
    );
  });

  test('create mutation injects the selected company scope', () async {
    final repository = FakeCustomerRepository();
    final container = _container(repository);
    addTearDown(container.dispose);

    const input = CustomerInput(name: 'New Customer');
    final created = await container
        .read(customerMutationProvider.notifier)
        .createCustomer(input);

    expect(created.companyId, _company.id);
    expect(repository.createCompanyIds, [_company.id]);
  });

  test('detail query injects the selected company scope', () async {
    final repository = FakeCustomerRepository(customers: [_customer]);
    final container = _container(repository);
    addTearDown(container.dispose);

    final customer = await container.read(
      customerDetailProvider(_customer.id).future,
    );

    expect(customer, _customer);
    expect(repository.detailCompanyIds, [_company.id]);
  });
}

ProviderContainer _container(FakeCustomerRepository repository) {
  return ProviderContainer(
    overrides: [
      selectedCompanyProvider.overrideWithValue(_company),
      customerRepositoryProvider.overrideWithValue(repository),
    ],
  );
}

const _company = Company(
  id: 'company-1',
  ownerUserId: 'user-1',
  name: 'Acme Trading',
  legalName: null,
  currencyCode: 'LKR',
  countryCode: 'LK',
  timezone: 'Asia/Colombo',
  membershipRole: 'Owner',
  isOwner: true,
  isAdmin: true,
);

final _customer = Customer(
  id: 'customer-1',
  companyId: _company.id,
  name: 'Acme Customer',
  displayName: null,
  email: 'customer@example.com',
  phone: null,
  mobile: '0771234567',
  taxNumber: null,
  creditLimit: 10000,
  paymentTermsDays: 30,
  openingBalance: 0,
  notes: null,
  tags: const ['Priority'],
  isActive: true,
  createdAt: DateTime.utc(2026, 7, 14),
  updatedAt: DateTime.utc(2026, 7, 14),
);
