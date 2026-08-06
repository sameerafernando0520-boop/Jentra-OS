import '../application/invoice_models.dart';

/// Pure domain calculation service for Sales Invoice line items and document totals.
abstract final class InvoiceCalculationService {
  /// Calculates subtotal, line discount, line tax, and line total for a single item.
  static InvoiceCalculatedTotals calculateItemTotals(InvoiceItemInput item) {
    final rawSubtotal = item.quantity * item.unitPrice;
    final discount = item.discountAmount.clamp(0.0, rawSubtotal);
    final taxableAmount = (rawSubtotal - discount).clamp(0.0, double.infinity);
    final tax = (taxableAmount * (item.taxRate / 100.0));
    final lineTotal = taxableAmount + tax;

    return InvoiceCalculatedTotals(
      lineSubtotal: _round2(rawSubtotal),
      lineDiscountAmount: _round2(discount),
      lineTaxAmount: _round2(tax),
      lineTotal: _round2(lineTotal),
      subtotal: 0,
      totalDiscount: 0,
      totalTax: 0,
      grandTotal: 0,
    );
  }

  /// Calculates document totals (subtotal, total discount, total tax, grand total) across all items.
  static InvoiceCalculatedTotals calculateDocumentTotals(
    List<InvoiceItemInput> items,
  ) {
    double subtotal = 0.0;
    double totalDiscount = 0.0;
    double totalTax = 0.0;
    double grandTotal = 0.0;

    for (final item in items) {
      final itemCalc = calculateItemTotals(item);
      subtotal += itemCalc.lineSubtotal;
      totalDiscount += itemCalc.lineDiscountAmount;
      totalTax += itemCalc.lineTaxAmount;
      grandTotal += itemCalc.lineTotal;
    }

    return InvoiceCalculatedTotals(
      lineSubtotal: 0,
      lineDiscountAmount: 0,
      lineTaxAmount: 0,
      lineTotal: 0,
      subtotal: _round2(subtotal),
      totalDiscount: _round2(totalDiscount),
      totalTax: _round2(totalTax),
      grandTotal: _round2(grandTotal),
    );
  }

  static double _round2(double val) {
    return (val * 100.0).roundToDouble() / 100.0;
  }
}
