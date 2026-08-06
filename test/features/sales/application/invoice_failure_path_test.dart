import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_models.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/sales/application/invoice_failure.dart';
import 'package:jentra_os/features/sales/application/invoice_models.dart';
import 'package:jentra_os/features/sales/application/invoice_repository.dart';
import 'package:jentra_os/features/sales/application/invoice_state.dart';
import 'package:jentra_os/features/sales/application/invoice_validators.dart';
import 'package:jentra_os/features/sales/data/supabase_invoice_repository.dart';

final class ThrowingInvoiceRepository implements InvoiceRepository {
  ThrowingInvoiceRepository({this.errorMessage = 'Database connection error'});

  final String errorMessage;

  @override
  Future<Invoice> createInvoice({
    required String companyId,
    required InvoiceInput input,
  }) async {
    throw InvoiceFailure(errorMessage);
  }

  @override
  Future<InvoicePage> listInvoices({
    required String companyId,
    required String search,
    String? status,
    String? customerId,
    InvoiceCursor? cursor,
    int pageSize = 30,
  }) async {
    throw InvoiceFailure(errorMessage);
  }

  @override
  Future<Invoice> getInvoice({
    required String companyId,
    required String invoiceId,
  }) async {
    throw InvoiceFailure(errorMessage);
  }

  @override
  Future<Invoice> updateInvoice({
    required String companyId,
    required String invoiceId,
    required InvoiceInput input,
  }) async {
    throw InvoiceFailure(errorMessage);
  }

  @override
  Future<Invoice> updateInvoiceStatus({
    required String companyId,
    required String invoiceId,
    required String status,
  }) async {
    throw InvoiceFailure(errorMessage);
  }
}

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

  group('Invoice Failure Paths & Error State Handling', () {
    test('invoice list controller handles repository failure cleanly', () async {
      final throwingRepo = ThrowingInvoiceRepository(errorMessage: 'Network timeout');
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(throwingRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(invoiceControllerProvider.future),
        throwsA(isA<InvoiceFailure>().having((f) => f.message, 'message', contains('Network timeout'))),
      );
    });

    test('createInvoice handles repository failure and throws InvoiceFailure', () async {
      final throwingRepo = ThrowingInvoiceRepository(errorMessage: 'Permission denied to create sales invoices.');
      final container = ProviderContainer(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(throwingRepo),
          selectedCompanyProvider.overrideWith((ref) => company1),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final input = InvoiceInput(
        customerId: 'cust-1',
        issueDate: DateTime.now(),
        items: const [
          InvoiceItemInput(description: 'Test Item', quantity: 1, unitPrice: 100.0),
        ],
      );

      expect(
        () => container.read(invoiceMutationControllerProvider.notifier).createInvoice(input),
        throwsA(isA<InvoiceFailure>().having((f) => f.message, 'message', contains('Permission denied'))),
      );
    });

    test('InvoiceValidators rejects invalid customer selection', () {
      expect(InvoiceValidators.validateCustomer(null), isNotNull);
      expect(InvoiceValidators.validateCustomer(''), isNotNull);
      expect(InvoiceValidators.validateCustomer('cust-1'), isNull);
    });

    test('InvoiceValidators rejects empty items list', () {
      expect(InvoiceValidators.validateItems(const []), isNotNull);
      expect(
        InvoiceValidators.validateItems(const [
          InvoiceItemInput(description: 'Valid Item', quantity: 1, unitPrice: 10.0),
        ]),
        isNull,
      );
    });
  });
}
