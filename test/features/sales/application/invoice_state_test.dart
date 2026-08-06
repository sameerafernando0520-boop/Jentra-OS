import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/sales/application/invoice_failure.dart';
import 'package:jentra_os/features/sales/application/invoice_models.dart';
import 'package:jentra_os/features/sales/application/invoice_state.dart';
import 'package:jentra_os/features/sales/data/supabase_invoice_repository.dart';

import '../fake_invoice_repository.dart';

void main() {
  const company1 = Company(
    id: 'comp-1',
    ownerUserId: 'user-1',
    name: 'Acme Corp',
    legalName: 'Acme Corp LLC',
    currencyCode: 'USD',
    countryCode: 'US',
    timezone: 'UTC',
    membershipRole: 'Owner',
    isOwner: true,
    isAdmin: true,
  );

  final sampleInvoice = Invoice(
    id: 'inv-1',
    companyId: 'comp-1',
    customerId: 'cust-1',
    customerName: 'Customer One',
    documentNumber: 'INV-1001',
    status: 'draft',
    issueDate: DateTime.now(),
    subtotal: 100.00,
    discountAmount: 0.00,
    taxAmount: 10.00,
    grandTotal: 110.00,
    paidAmount: 0.00,
    balanceDue: 110.00,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  group('InvoiceState & InvoiceController', () {
    test('missing selected company throws InvoiceFailure', () async {
      final fakeRepo = FakeInvoiceRepository();
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(invoiceControllerProvider.future),
        throwsA(isA<InvoiceFailure>()),
      );
    });

    test('lists invoices using selected company ID scope', () async {
      final fakeRepo = FakeInvoiceRepository(invoices: [sampleInvoice]);
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final state = await container.read(invoiceControllerProvider.future);
      expect(state.companyId, equals('comp-1'));
      expect(state.invoices, hasLength(1));
      expect(state.invoices.first.documentNumber, equals('INV-1001'));
    });

    test('create invoice injects selected company ID scope', () async {
      final fakeRepo = FakeInvoiceRepository();
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyProvider.overrideWith((ref) => company1),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final input = InvoiceInput(
        customerId: 'cust-1',
        issueDate: DateTime.now(),
        items: const [
          InvoiceItemInput(
            description: 'Consulting Service',
            quantity: 2,
            unitPrice: 50.00,
          ),
        ],
      );

      final created = await container
          .read(invoiceMutationControllerProvider.notifier)
          .createInvoice(input);

      expect(created.companyId, equals('comp-1'));
      expect(created.grandTotal, equals(100.00));
      expect(fakeRepo.createCompanyIds, contains('comp-1'));
    });
  });
}
