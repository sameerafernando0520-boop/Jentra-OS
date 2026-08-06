import '../application/invoice_models.dart';

abstract class InvoiceRepository {
  Future<InvoicePage> listInvoices({
    required String companyId,
    required String search,
    String? status,
    String? customerId,
    InvoiceCursor? cursor,
    int pageSize = 30,
  });

  Future<Invoice> getInvoice({
    required String companyId,
    required String invoiceId,
  });

  Future<Invoice> createInvoice({
    required String companyId,
    required InvoiceInput input,
  });

  Future<Invoice> updateInvoice({
    required String companyId,
    required String invoiceId,
    required InvoiceInput input,
  });

  Future<Invoice> updateInvoiceStatus({
    required String companyId,
    required String invoiceId,
    required String status,
  });
}
