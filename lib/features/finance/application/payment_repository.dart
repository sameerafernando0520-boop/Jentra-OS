import '../application/payment_models.dart';

abstract class PaymentRepository {
  Future<List<MoneyAccount>> listMoneyAccounts({required String companyId});

  Future<List<Payment>> listPayments({required String companyId});

  Future<PaymentResult> recordInvoicePayment({
    required String companyId,
    required RecordPaymentInput input,
  });
}
