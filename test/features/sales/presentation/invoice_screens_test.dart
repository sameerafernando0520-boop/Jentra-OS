import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/company/application/company_models.dart';
import 'package:i_book/features/company/application/company_state.dart';
import 'package:i_book/features/sales/application/invoice_models.dart';
import 'package:i_book/features/sales/data/supabase_invoice_repository.dart';
import 'package:i_book/features/sales/presentation/screens/create_invoice_screen.dart';
import 'package:i_book/features/sales/presentation/screens/invoice_detail_screen.dart';
import 'package:i_book/features/sales/presentation/screens/invoice_list_screen.dart';

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
    customerName: 'Acme Client',
    documentNumber: 'INV-1001',
    status: 'draft',
    issueDate: DateTime.now(),
    subtotal: 100.00,
    discountAmount: 0.00,
    taxAmount: 10.00,
    grandTotal: 110.00,
    paidAmount: 0.00,
    balanceDue: 110.00,
    items: [
      InvoiceItem(
        id: 'item-1',
        companyId: 'comp-1',
        documentId: 'inv-1',
        description: 'Software Design Service',
        quantity: 1,
        unitPrice: 100.00,
        taxRate: 10.0,
        taxAmount: 10.00,
        lineTotal: 110.00,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Widget buildTestWidget(Widget child, {FakeInvoiceRepository? fakeInvoiceRepo}) {
    final invoiceRepo = fakeInvoiceRepo ?? FakeInvoiceRepository(invoices: [sampleInvoice]);

    return ProviderScope(
      overrides: [
        invoiceRepositoryProvider.overrideWithValue(invoiceRepo),
        selectedCompanyProvider.overrideWith((ref) => company1),
        selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
      ],
      child: MaterialApp(home: child),
    );
  }

  group('Invoice Screens UI Tests', () {
    testWidgets('InvoiceListScreen renders invoice items for company', (tester) async {
      await tester.pumpWidget(buildTestWidget(const InvoiceListScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sales Invoices - Acme Corp'), findsOneWidget);
      expect(find.text('INV-1001'), findsOneWidget);
      expect(find.textContaining('Acme Client'), findsOneWidget);
      expect(find.text('\$110.00'), findsOneWidget);
    });

    testWidgets('InvoiceDetailScreen displays header and item table', (tester) async {
      await tester.pumpWidget(buildTestWidget(const InvoiceDetailScreen(invoiceId: 'inv-1')));
      await tester.pumpAndSettle();

      expect(find.text('Invoice Details'), findsOneWidget);
      expect(find.text('INV-1001'), findsOneWidget);
      expect(find.text('Software Design Service'), findsOneWidget);
      expect(find.text('Mark as Issued'), findsOneWidget);
    });

    testWidgets('CreateInvoiceScreen exposes form and calculations', (tester) async {
      await tester.pumpWidget(buildTestWidget(const CreateInvoiceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('New Sales Invoice'), findsOneWidget);
      expect(find.text('Save as Draft'), findsOneWidget);
      expect(find.text('Save & Issue'), findsOneWidget);
    });
  });
}
