import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/company/application/company_models.dart';
import 'package:i_book/features/company/application/company_state.dart';
import 'package:i_book/features/crm/application/customer_models.dart';
import 'package:i_book/features/crm/data/supabase_customer_repository.dart';
import 'package:i_book/features/crm/presentation/screens/create_customer_screen.dart';
import 'package:i_book/features/crm/presentation/screens/customer_detail_screen.dart';
import 'package:i_book/features/crm/presentation/screens/customer_list_screen.dart';
import 'package:i_book/features/crm/presentation/screens/edit_customer_screen.dart';

import '../fake_customer_repository.dart';

void main() {
  testWidgets('customer list renders selected-company customers', (
    tester,
  ) async {
    final repository = FakeCustomerRepository(customers: [_customer]);
    await _pump(
      tester,
      repository: repository,
      child: const CustomerListScreen(),
    );

    expect(
      find.byKey(const ValueKey('customer-list-company-company-1')),
      findsOneWidget,
    );
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Acme Customer'), findsAtLeastNWidgets(1));
    expect(find.text('customer@example.com'), findsOneWidget);
    expect(find.text('Add customer'), findsOneWidget);
    expect(repository.listRequests.single.companyId, _company.id);
  });

  testWidgets('customer list has a useful empty state', (tester) async {
    await _pump(
      tester,
      repository: FakeCustomerRepository(),
      child: const CustomerListScreen(),
    );

    expect(find.text('No customers yet'), findsOneWidget);
    expect(
      find.text('Create the first customer for this company.'),
      findsOneWidget,
    );
  });

  testWidgets('create screen exposes validated business fields', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: FakeCustomerRepository(),
      child: const CreateCustomerScreen(),
    );

    expect(find.text('Add customer'), findsOneWidget);
    expect(find.text('Legal or customer name *'), findsOneWidget);
    expect(find.text('Credit limit'), findsOneWidget);
    expect(find.text('Create customer'), findsOneWidget);
  });

  testWidgets('detail screen shows finance balance placeholder', (
    tester,
  ) async {
    await _pump(
      tester,
      repository: FakeCustomerRepository(customers: [_customer]),
      child: const CustomerDetailScreen(customerId: 'customer-1'),
    );

    expect(find.text('Acme Customer'), findsAtLeastNWidgets(1));
    expect(find.text('Customer balance'), findsOneWidget);
    expect(find.text('LKR 0.00'), findsNWidgets(2));
    expect(
      find.textContaining('connect when Finance is implemented'),
      findsOneWidget,
    );
  });

  testWidgets('edit screen loads the existing customer', (tester) async {
    await _pump(
      tester,
      repository: FakeCustomerRepository(customers: [_customer]),
      child: const EditCustomerScreen(customerId: 'customer-1'),
    );

    expect(find.text('Edit customer'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Acme Customer'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeCustomerRepository repository,
  required Widget child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        selectedCompanyProvider.overrideWithValue(_company),
        customerRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
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
  phone: '0112345678',
  mobile: '0771234567',
  taxNumber: 'TIN-100',
  creditLimit: 10000,
  paymentTermsDays: 30,
  openingBalance: 0,
  notes: 'Priority account',
  tags: const ['Priority'],
  isActive: true,
  createdAt: DateTime.utc(2026, 7, 14),
  updatedAt: DateTime.utc(2026, 7, 14),
);
