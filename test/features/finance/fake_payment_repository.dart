import 'package:jentra_os/features/finance/application/payment_models.dart';
import 'package:jentra_os/features/finance/application/payment_repository.dart';

final class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository({
    List<MoneyAccount>? moneyAccounts,
    List<Payment>? payments,
  })  : moneyAccounts = moneyAccounts ??
            [
              MoneyAccount(
                id: 'acc-1',
                companyId: 'comp-1',
                name: 'Main Cash Account',
                accountType: 'cash',
                balance: 500.00,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ],
        payments = payments ?? <Payment>[];

  final List<MoneyAccount> moneyAccounts;
  final List<Payment> payments;
  final List<String> recordPaymentCompanyIds = <String>[];

  @override
  Future<List<MoneyAccount>> listMoneyAccounts({required String companyId}) async {
    return moneyAccounts.where((acc) => acc.companyId == companyId).toList();
  }

  @override
  Future<List<Payment>> listPayments({required String companyId}) async {
    return payments.where((pmt) => pmt.companyId == companyId).toList();
  }

  @override
  Future<PaymentResult> recordInvoicePayment({
    required String companyId,
    required RecordPaymentInput input,
  }) async {
    recordPaymentCompanyIds.add(companyId);
    final now = DateTime.now();

    final pmt = Payment(
      id: 'pmt-${payments.length + 1}',
      companyId: companyId,
      paymentNumber: 'PMT-${payments.length + 1001}',
      paymentType: 'incoming',
      moneyAccountId: input.moneyAccountId ?? 'acc-1',
      moneyAccountName: 'Main Cash Account',
      paymentMethod: input.paymentMethod,
      amount: input.amount,
      paymentDate: input.paymentDate,
      reference: input.reference,
      notes: input.notes,
      createdAt: now,
      updatedAt: now,
    );

    payments.add(pmt);

    return PaymentResult(
      success: true,
      paymentId: pmt.id,
      paymentNumber: pmt.paymentNumber,
      journalId: 'jrn-1',
      journalNumber: 'JRN-1001',
      invoiceStatus: 'paid',
      paidAmount: input.amount,
      balanceDue: 0.0,
    );
  }
}
