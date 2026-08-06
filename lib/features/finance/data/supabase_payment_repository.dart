import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/payment_models.dart';
import '../application/payment_repository.dart';
import 'payment_service.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return SupabasePaymentRepository(ref.watch(paymentServiceProvider));
});

final class SupabasePaymentRepository implements PaymentRepository {
  const SupabasePaymentRepository(this._service);

  final PaymentService _service;

  @override
  Future<List<MoneyAccount>> listMoneyAccounts({
    required String companyId,
  }) async {
    final rows = await _service.fetchMoneyAccounts(companyId: companyId);
    return rows.map((r) => _mapMoneyAccount(r)).toList();
  }

  @override
  Future<List<Payment>> listPayments({required String companyId}) async {
    final rows = await _service.fetchPayments(companyId: companyId);
    return rows.map((r) => _mapPayment(r)).toList();
  }

  @override
  Future<PaymentResult> recordInvoicePayment({
    required String companyId,
    required RecordPaymentInput input,
  }) async {
    final res = await _service.recordInvoicePayment(
      companyId: companyId,
      input: input,
    );

    return PaymentResult(
      success: res['success'] as bool? ?? false,
      paymentId: res['payment_id'] as String? ?? '',
      paymentNumber: res['payment_number'] as String? ?? '',
      journalId: res['journal_id'] as String? ?? '',
      journalNumber: res['journal_number'] as String? ?? '',
      invoiceStatus: res['invoice_status'] as String? ?? 'paid',
      paidAmount: (res['paid_amount'] as num?)?.toDouble() ?? input.amount,
      balanceDue: (res['balance_due'] as num?)?.toDouble() ?? 0.0,
    );
  }

  MoneyAccount _mapMoneyAccount(Map<String, dynamic> row) {
    return MoneyAccount(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      name: row['name'] as String,
      accountType: row['account_type'] as String? ?? 'bank',
      accountNumber: row['account_number'] as String?,
      currency: row['currency'] as String? ?? 'USD',
      balance: (row['balance'] as num?)?.toDouble() ?? 0.0,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Payment _mapPayment(Map<String, dynamic> row) {
    final partyMap = row['parties'] as Map<String, dynamic>?;
    final partyName = partyMap?['display_name'] as String? ?? partyMap?['name'] as String?;

    final accMap = row['money_accounts'] as Map<String, dynamic>?;
    final accName = accMap?['name'] as String?;

    return Payment(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      paymentNumber: row['payment_number'] as String,
      paymentType: row['payment_type'] as String? ?? 'incoming',
      partyId: row['party_id'] as String?,
      partyName: partyName,
      moneyAccountId: row['money_account_id'] as String?,
      moneyAccountName: accName,
      paymentMethod: row['payment_method'] as String? ?? 'cash',
      amount: (row['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: DateTime.parse(row['payment_date'] as String),
      reference: row['reference'] as String?,
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
