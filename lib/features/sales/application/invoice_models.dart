final class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.companyId,
    required this.documentId,
    this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0.0,
    this.taxRate = 0.0,
    this.taxAmount = 0.0,
    required this.lineTotal,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String documentId;
  final String? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final double taxRate;
  final double taxAmount;
  final double lineTotal;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class InvoiceItemInput {
  const InvoiceItemInput({
    this.productId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0.0,
    this.taxRate = 0.0,
  });

  final String? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double discountAmount;
  final double taxRate;
}

final class InvoiceCalculatedTotals {
  const InvoiceCalculatedTotals({
    required this.lineSubtotal,
    required this.lineDiscountAmount,
    required this.lineTaxAmount,
    required this.lineTotal,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTax,
    required this.grandTotal,
  });

  final double lineSubtotal;
  final double lineDiscountAmount;
  final double lineTaxAmount;
  final double lineTotal;

  final double subtotal;
  final double totalDiscount;
  final double totalTax;
  final double grandTotal;
}

final class Invoice {
  const Invoice({
    required this.id,
    required this.companyId,
    this.branchId,
    required this.customerId,
    this.customerName,
    required this.documentNumber,
    required this.status, // 'draft', 'issued', 'paid', 'partially_paid', 'void', 'cancelled'
    required this.issueDate,
    this.dueDate,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.paidAmount,
    required this.balanceDue,
    this.notes,
    this.items = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String companyId;
  final String? branchId;
  final String customerId;
  final String? customerName;
  final String documentNumber;
  final String status;
  final DateTime issueDate;
  final DateTime? dueDate;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double grandTotal;
  final double paidAmount;
  final double balanceDue;
  final String? notes;
  final List<InvoiceItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isDraft => status == 'draft';
  bool get isIssued => status == 'issued';
}

final class InvoiceInput {
  const InvoiceInput({
    required this.customerId,
    this.documentNumber,
    this.status = 'draft',
    required this.issueDate,
    this.dueDate,
    this.notes,
    required this.items,
  });

  final String customerId;
  final String? documentNumber;
  final String status;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String? notes;
  final List<InvoiceItemInput> items;
}

final class InvoiceCursor {
  const InvoiceCursor({required this.issueDate, required this.id});

  final DateTime issueDate;
  final String id;
}

final class InvoicePage {
  const InvoicePage({required this.invoices, required this.nextCursor});

  final List<Invoice> invoices;
  final InvoiceCursor? nextCursor;
}
