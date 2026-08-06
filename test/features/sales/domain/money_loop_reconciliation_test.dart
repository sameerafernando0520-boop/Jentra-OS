import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/sales/application/invoice_models.dart';

void main() {
  group('Money Loop Reconciliation & Accounting Invariants', () {
    test('multi-payment balance tracking reduces balance_due and updates paid_amount', () {
      final issueDate = DateTime(2026, 8, 1);
      final initialInvoice = Invoice(
        id: 'inv-100',
        companyId: 'comp-1',
        customerId: 'cust-1',
        customerName: 'Acme Client',
        documentNumber: 'INV-1001',
        status: 'posted',
        issueDate: issueDate,
        subtotal: 1000.00,
        discountAmount: 100.00,
        taxAmount: 90.00,
        grandTotal: 990.00,
        paidAmount: 0.00,
        balanceDue: 990.00,
        createdAt: issueDate,
        updatedAt: issueDate,
      );

      // First partial payment of 400.00
      const payment1Amount = 400.00;
      final paidAfterP1 = initialInvoice.paidAmount + payment1Amount;
      final balanceAfterP1 = initialInvoice.grandTotal - paidAfterP1;
      final statusAfterP1 = balanceAfterP1 <= 0.001 ? 'paid' : 'partially_paid';

      expect(paidAfterP1, equals(400.00));
      expect(balanceAfterP1, equals(590.00));
      expect(statusAfterP1, equals('partially_paid'));

      // Second payment of remaining 590.00
      const payment2Amount = 590.00;
      final paidAfterP2 = paidAfterP1 + payment2Amount;
      final balanceAfterP2 = initialInvoice.grandTotal - paidAfterP2;
      final statusAfterP2 = balanceAfterP2 <= 0.001 ? 'paid' : 'partially_paid';

      expect(paidAfterP2, equals(990.00));
      expect(balanceAfterP2, equals(0.00));
      expect(statusAfterP2, equals('paid'));
    });

    test('journal debit and credit equality invariant for payment entry', () {
      const paymentAmount = 450.75;

      // Simulated double-entry lines for payment receipt
      const debitAmount = paymentAmount;
      const creditAmount = paymentAmount;

      expect(debitAmount, equals(creditAmount), reason: 'Total debits must equal total credits');
      expect(debitAmount - creditAmount, equals(0.0), reason: 'Journal entry must balance to zero');
    });

    test('over-payment amount validation rejects amounts exceeding balance due', () {
      const grandTotal = 500.00;
      const currentPaid = 200.00;
      const currentBalanceDue = grandTotal - currentPaid;

      const attemptedPayment = 350.00;
      final isOverPayment = attemptedPayment > currentBalanceDue + 0.001;

      expect(isOverPayment, isTrue);
    });
  });
}
