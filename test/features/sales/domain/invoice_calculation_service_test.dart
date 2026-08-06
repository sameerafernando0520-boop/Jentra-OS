import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/sales/application/invoice_models.dart';
import 'package:i_book/features/sales/domain/invoice_calculation_service.dart';

void main() {
  group('InvoiceCalculationService', () {
    test('calculateItemTotals computes line subtotal, discount, tax, line total', () {
      const item = InvoiceItemInput(
        description: 'Wireless Mouse',
        quantity: 2,
        unitPrice: 20.00,
        discountAmount: 5.00,
        taxRate: 10.0, // 10% tax
      );

      final calc = InvoiceCalculationService.calculateItemTotals(item);

      // Raw subtotal = 2 * 20.00 = 40.00
      expect(calc.lineSubtotal, equals(40.00));
      // Discount = 5.00
      expect(calc.lineDiscountAmount, equals(5.00));
      // Taxable = 40 - 5 = 35.00. Tax = 10% of 35 = 3.50
      expect(calc.lineTaxAmount, equals(3.50));
      // Line total = 35 + 3.50 = 38.50
      expect(calc.lineTotal, equals(38.50));
    });

    test('calculateDocumentTotals aggregates across multiple items correctly', () {
      const item1 = InvoiceItemInput(
        description: 'Item 1',
        quantity: 1,
        unitPrice: 100.00,
        discountAmount: 10.00,
        taxRate: 5.0,
      );
      // Item 1: subtotal 100, discount 10, taxable 90, tax 4.50, total 94.50

      const item2 = InvoiceItemInput(
        description: 'Item 2',
        quantity: 3,
        unitPrice: 50.00,
        discountAmount: 0.00,
        taxRate: 10.0,
      );
      // Item 2: subtotal 150, discount 0, taxable 150, tax 15.00, total 165.00

      final docTotals = InvoiceCalculationService.calculateDocumentTotals([
        item1,
        item2,
      ]);

      expect(docTotals.subtotal, equals(250.00));
      expect(docTotals.totalDiscount, equals(10.00));
      expect(docTotals.totalTax, equals(19.50));
      expect(docTotals.grandTotal, equals(259.50));
    });
  });
}
