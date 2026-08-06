import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/company/application/company_state.dart';
import 'package:i_book/features/finance/data/supabase_payment_repository.dart';
import 'package:i_book/features/sales/application/invoice_models.dart';
import 'package:i_book/features/sales/presentation/widgets/record_payment_dialog.dart';

import '../../finance/fake_payment_repository.dart';

void main() {
  final sampleInvoice = Invoice(
    id: 'inv-1',
    companyId: 'comp-1',
    customerId: 'cust-1',
    customerName: 'Acme Client',
    documentNumber: 'INV-1001',
    status: 'issued',
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

  Widget buildTestWidget(Widget child, {FakePaymentRepository? fakePaymentRepo}) {
    final paymentRepo = fakePaymentRepo ?? FakePaymentRepository();

    return ProviderScope(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(paymentRepo),
        selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('RecordPaymentDialog UI Tests', () {
    testWidgets('renders payment dialog with pre-populated balance due', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(RecordPaymentDialog(invoice: sampleInvoice)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Record Payment (INV-1001)'), findsOneWidget);
      expect(find.text('\$110.00'), findsWidgets);
      expect(find.text('Confirm Payment'), findsOneWidget);
    });
  });
}
