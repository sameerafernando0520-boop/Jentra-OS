import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_providers.dart';
import '../application/payment_failure.dart';
import '../application/payment_models.dart';

final paymentServiceProvider = Provider<PaymentService>((ref) {
  return PaymentService(ref.watch(supabaseServiceProvider).client);
});

final class PaymentService {
  const PaymentService(this._client);

  final SupabaseClient _client;

  void requireSession() {
    if (_client.auth.currentUser == null) {
      throw const PaymentFailure('Please sign in to process payments.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchMoneyAccounts({
    required String companyId,
  }) async {
    requireSession();
    final rows = await _client
        .from('money_accounts')
        .select('*')
        .eq('company_id', companyId)
        .eq('is_active', true)
        .order('name');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<List<Map<String, dynamic>>> fetchPayments({
    required String companyId,
  }) async {
    requireSession();
    final rows = await _client
        .from('payments')
        .select('''
          *,
          parties(name, display_name),
          money_accounts(name)
        ''')
        .eq('company_id', companyId)
        .order('payment_date', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> recordInvoicePayment({
    required String companyId,
    required RecordPaymentInput input,
  }) async {
    requireSession();
    final response = await _client.rpc(
      'record_invoice_payment',
      params: {
        'p_company_id': companyId,
        'p_invoice_id': input.invoiceId,
        'p_money_account_id': input.moneyAccountId,
        'p_payment_method': input.paymentMethod,
        'p_amount': input.amount,
        'p_payment_date': input.paymentDate.toIso8601String().split('T').first,
        'p_reference': input.reference,
        'p_notes': input.notes,
      },
    );

    if (response is! Map) {
      throw const PaymentFailure('Payment recording failed to return a valid response.');
    }

    return Map<String, dynamic>.from(response);
  }
}
