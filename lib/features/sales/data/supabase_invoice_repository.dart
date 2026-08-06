import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/invoice_failure.dart';
import '../application/invoice_models.dart';
import '../application/invoice_repository.dart';
import '../domain/invoice_calculation_service.dart';
import 'invoice_service.dart';

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return SupabaseInvoiceRepository(ref.watch(invoiceServiceProvider));
});

final class SupabaseInvoiceRepository implements InvoiceRepository {
  const SupabaseInvoiceRepository(this._service);

  final InvoiceService _service;

  @override
  Future<InvoicePage> listInvoices({
    required String companyId,
    required String search,
    String? status,
    String? customerId,
    InvoiceCursor? cursor,
    int pageSize = 30,
  }) async {
    final rows = await _service.fetchInvoices(
      companyId: companyId,
      search: search,
      status: status,
      customerId: customerId,
      cursor: cursor,
      limit: pageSize,
    );

    final invoices = rows.map((r) => _mapInvoice(r, companyId)).toList();
    InvoiceCursor? nextCursor;
    if (invoices.length >= pageSize) {
      final last = invoices.last;
      nextCursor = InvoiceCursor(issueDate: last.issueDate, id: last.id);
    }

    return InvoicePage(invoices: invoices, nextCursor: nextCursor);
  }

  @override
  Future<Invoice> getInvoice({
    required String companyId,
    required String invoiceId,
  }) async {
    final row = await _service.fetchInvoiceDetail(
      companyId: companyId,
      invoiceId: invoiceId,
    );

    if (row == null) {
      throw const InvoiceFailure('Invoice not found.');
    }
    return _mapInvoice(row, companyId);
  }

  @override
  Future<Invoice> createInvoice({
    required String companyId,
    required InvoiceInput input,
  }) async {
    final docTotals = InvoiceCalculationService.calculateDocumentTotals(input.items);
    final mappedItems = input.items.map((item) {
      final itemCalc = InvoiceCalculationService.calculateItemTotals(item);
      return {
        'product_id': item.productId,
        'description': item.description,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'discount_amount': itemCalc.lineDiscountAmount,
        'tax_rate': item.taxRate,
        'tax_amount': itemCalc.lineTaxAmount,
        'line_total': itemCalc.lineTotal,
      };
    }).toList();

    final row = await _service.saveInvoice(
      companyId: companyId,
      customerId: input.customerId,
      documentNumber: input.documentNumber,
      status: input.status,
      issueDate: input.issueDate,
      dueDate: input.dueDate,
      subtotal: docTotals.subtotal,
      discountAmount: docTotals.totalDiscount,
      taxAmount: docTotals.totalTax,
      grandTotal: docTotals.grandTotal,
      notes: input.notes,
      items: mappedItems,
    );

    return getInvoice(companyId: companyId, invoiceId: row['id'] as String);
  }

  @override
  Future<Invoice> updateInvoice({
    required String companyId,
    required String invoiceId,
    required InvoiceInput input,
  }) async {
    final docTotals = InvoiceCalculationService.calculateDocumentTotals(input.items);
    final mappedItems = input.items.map((item) {
      final itemCalc = InvoiceCalculationService.calculateItemTotals(item);
      return {
        'product_id': item.productId,
        'description': item.description,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'discount_amount': itemCalc.lineDiscountAmount,
        'tax_rate': item.taxRate,
        'tax_amount': itemCalc.lineTaxAmount,
        'line_total': itemCalc.lineTotal,
      };
    }).toList();

    final row = await _service.saveInvoice(
      companyId: companyId,
      invoiceId: invoiceId,
      customerId: input.customerId,
      documentNumber: input.documentNumber,
      status: input.status,
      issueDate: input.issueDate,
      dueDate: input.dueDate,
      subtotal: docTotals.subtotal,
      discountAmount: docTotals.totalDiscount,
      taxAmount: docTotals.totalTax,
      grandTotal: docTotals.grandTotal,
      notes: input.notes,
      items: mappedItems,
    );

    return getInvoice(companyId: companyId, invoiceId: row['id'] as String);
  }

  @override
  Future<Invoice> updateInvoiceStatus({
    required String companyId,
    required String invoiceId,
    required String status,
  }) async {
    final row = await _service.updateInvoiceStatus(
      companyId: companyId,
      invoiceId: invoiceId,
      status: status,
    );

    if (row == null) {
      throw const InvoiceFailure('Invoice status update failed.');
    }
    return getInvoice(companyId: companyId, invoiceId: invoiceId);
  }

  Invoice _mapInvoice(Map<String, dynamic> row, String companyId) {
    final partyMap = row['parties'] as Map<String, dynamic>?;
    final customerName = partyMap?['display_name'] as String? ??
        partyMap?['name'] as String? ??
        'Customer';

    final itemsRaw = row['sales_document_items'] as List? ?? [];
    final items = itemsRaw
        .whereType<Map>()
        .map((r) => _mapInvoiceItem(Map<String, dynamic>.from(r), companyId))
        .toList();

    final grandTotal = (row['grand_total'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
    final balanceDue = (row['balance_due'] as num?)?.toDouble() ?? (grandTotal - paidAmount);

    return Invoice(
      id: row['id'] as String,
      companyId: row['company_id'] as String? ?? companyId,
      branchId: row['branch_id'] as String?,
      customerId: row['customer_id'] as String,
      customerName: customerName,
      documentNumber: row['document_number'] as String,
      status: row['status'] as String? ?? 'draft',
      issueDate: DateTime.parse(row['issue_date'] as String),
      dueDate: row['due_date'] != null ? DateTime.parse(row['due_date'] as String) : null,
      subtotal: (row['subtotal'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (row['tax_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: grandTotal,
      paidAmount: paidAmount,
      balanceDue: balanceDue,
      notes: row['notes'] as String?,
      items: items,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  InvoiceItem _mapInvoiceItem(Map<String, dynamic> row, String companyId) {
    return InvoiceItem(
      id: row['id'] as String? ?? '',
      companyId: row['company_id'] as String? ?? companyId,
      documentId: row['document_id'] as String? ?? '',
      productId: row['product_id'] as String?,
      description: row['description'] as String? ?? '',
      quantity: (row['quantity'] as num?)?.toDouble() ?? 1.0,
      unitPrice: (row['unit_price'] as num?)?.toDouble() ?? 0.0,
      discountAmount: (row['discount_amount'] as num?)?.toDouble() ?? 0.0,
      taxRate: (row['tax_rate'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (row['tax_amount'] as num?)?.toDouble() ?? 0.0,
      lineTotal: (row['line_total'] as num?)?.toDouble() ?? 0.0,
      createdAt: row['created_at'] != null ? DateTime.parse(row['created_at'] as String) : DateTime.now(),
      updatedAt: row['updated_at'] != null ? DateTime.parse(row['updated_at'] as String) : DateTime.now(),
    );
  }
}
