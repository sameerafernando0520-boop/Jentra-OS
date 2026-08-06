import 'package:i_book/features/sales/application/invoice_models.dart';
import 'package:i_book/features/sales/application/invoice_repository.dart';
import 'package:i_book/features/sales/domain/invoice_calculation_service.dart';

final class FakeInvoiceRepository implements InvoiceRepository {
  FakeInvoiceRepository({List<Invoice> invoices = const <Invoice>[]})
      : invoices = List<Invoice>.of(invoices);

  final List<Invoice> invoices;
  final List<String> createCompanyIds = <String>[];
  final List<String> listCompanyIds = <String>[];

  @override
  Future<InvoicePage> listInvoices({
    required String companyId,
    required String search,
    String? status,
    String? customerId,
    InvoiceCursor? cursor,
    int pageSize = 30,
  }) async {
    listCompanyIds.add(companyId);
    final query = search.toLowerCase();
    final matches = invoices.where((inv) {
      if (inv.companyId != companyId) return false;
      if (status != null && inv.status != status) return false;
      if (customerId != null && inv.customerId != customerId) return false;
      if (query.isEmpty) return true;
      return inv.documentNumber.toLowerCase().contains(query);
    }).toList();

    return InvoicePage(invoices: matches, nextCursor: null);
  }

  @override
  Future<Invoice> getInvoice({
    required String companyId,
    required String invoiceId,
  }) async {
    return invoices.firstWhere(
      (inv) => inv.id == invoiceId && inv.companyId == companyId,
    );
  }

  @override
  Future<Invoice> createInvoice({
    required String companyId,
    required InvoiceInput input,
  }) async {
    createCompanyIds.add(companyId);
    final now = DateTime.now();
    final totals = InvoiceCalculationService.calculateDocumentTotals(input.items);

    final mappedItems = input.items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final itemCalc = InvoiceCalculationService.calculateItemTotals(item);
      return InvoiceItem(
        id: 'item-${idx + 1}',
        companyId: companyId,
        documentId: 'inv-${invoices.length + 1}',
        productId: item.productId,
        description: item.description,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discountAmount: itemCalc.lineDiscountAmount,
        taxRate: item.taxRate,
        taxAmount: itemCalc.lineTaxAmount,
        lineTotal: itemCalc.lineTotal,
        createdAt: now,
        updatedAt: now,
      );
    }).toList();

    final invoice = Invoice(
      id: 'inv-${invoices.length + 1}',
      companyId: companyId,
      customerId: input.customerId,
      customerName: 'Test Customer',
      documentNumber: input.documentNumber ?? 'INV-${invoices.length + 1001}',
      status: input.status,
      issueDate: input.issueDate,
      dueDate: input.dueDate,
      subtotal: totals.subtotal,
      discountAmount: totals.totalDiscount,
      taxAmount: totals.totalTax,
      grandTotal: totals.grandTotal,
      paidAmount: 0.0,
      balanceDue: totals.grandTotal,
      notes: input.notes,
      items: mappedItems,
      createdAt: now,
      updatedAt: now,
    );

    invoices.add(invoice);
    return invoice;
  }

  @override
  Future<Invoice> updateInvoice({
    required String companyId,
    required String invoiceId,
    required InvoiceInput input,
  }) async {
    final index = invoices.indexWhere((inv) => inv.id == invoiceId);
    final existing = invoices[index];
    final totals = InvoiceCalculationService.calculateDocumentTotals(input.items);

    final mappedItems = input.items.asMap().entries.map((entry) {
      final idx = entry.key;
      final item = entry.value;
      final itemCalc = InvoiceCalculationService.calculateItemTotals(item);
      return InvoiceItem(
        id: 'item-edit-${idx + 1}',
        companyId: companyId,
        documentId: invoiceId,
        productId: item.productId,
        description: item.description,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discountAmount: itemCalc.lineDiscountAmount,
        taxRate: item.taxRate,
        taxAmount: itemCalc.lineTaxAmount,
        lineTotal: itemCalc.lineTotal,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }).toList();

    final updated = Invoice(
      id: invoiceId,
      companyId: companyId,
      customerId: input.customerId,
      customerName: existing.customerName,
      documentNumber: input.documentNumber ?? existing.documentNumber,
      status: input.status,
      issueDate: input.issueDate,
      dueDate: input.dueDate,
      subtotal: totals.subtotal,
      discountAmount: totals.totalDiscount,
      taxAmount: totals.totalTax,
      grandTotal: totals.grandTotal,
      paidAmount: existing.paidAmount,
      balanceDue: totals.grandTotal - existing.paidAmount,
      notes: input.notes,
      items: mappedItems,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    invoices[index] = updated;
    return updated;
  }

  @override
  Future<Invoice> updateInvoiceStatus({
    required String companyId,
    required String invoiceId,
    required String status,
  }) async {
    final index = invoices.indexWhere((inv) => inv.id == invoiceId);
    final existing = invoices[index];

    final updated = Invoice(
      id: invoiceId,
      companyId: companyId,
      customerId: existing.customerId,
      customerName: existing.customerName,
      documentNumber: existing.documentNumber,
      status: status,
      issueDate: existing.issueDate,
      dueDate: existing.dueDate,
      subtotal: existing.subtotal,
      discountAmount: existing.discountAmount,
      taxAmount: existing.taxAmount,
      grandTotal: existing.grandTotal,
      paidAmount: existing.paidAmount,
      balanceDue: existing.balanceDue,
      notes: existing.notes,
      items: existing.items,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    invoices[index] = updated;
    return updated;
  }
}
