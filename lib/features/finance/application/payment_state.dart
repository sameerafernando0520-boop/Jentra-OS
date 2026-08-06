import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../company/application/company_state.dart';
import '../../sales/application/invoice_state.dart';
import '../data/supabase_payment_repository.dart';
import 'payment_failure.dart';
import 'payment_models.dart';

final moneyAccountListProvider = FutureProvider.autoDispose<List<MoneyAccount>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref
      .watch(paymentRepositoryProvider)
      .listMoneyAccounts(companyId: companyId);
}, retry: (_, _) => null);

final paymentListControllerProvider = FutureProvider.autoDispose<List<Payment>>((
  ref,
) async {
  final companyId = ref.watch(selectedCompanyIdProvider);
  if (companyId == null || companyId.trim().isEmpty) return const [];

  return ref.watch(paymentRepositoryProvider).listPayments(companyId: companyId);
}, retry: (_, _) => null);

final paymentMutationControllerProvider =
    AsyncNotifierProvider<PaymentMutationController, PaymentResult?>(
      PaymentMutationController.new,
      retry: (_, _) => null,
    );

final class PaymentMutationController extends AsyncNotifier<PaymentResult?> {
  @override
  Future<PaymentResult?> build() async => null;

  Future<PaymentResult> recordPayment(RecordPaymentInput input) async {
    final companyId = ref.read(selectedCompanyIdProvider);
    if (companyId == null || companyId.trim().isEmpty) {
      throw const PaymentFailure('Select a company before recording payment.');
    }

    state = const AsyncLoading();
    try {
      final res = await ref
          .read(paymentRepositoryProvider)
          .recordInvoicePayment(companyId: companyId, input: input);

      state = AsyncData(res);

      // Invalidate relevant providers to update invoice detail, invoice list, money accounts, and payments
      ref.invalidate(invoiceDetailProvider(input.invoiceId));
      ref.invalidate(invoiceControllerProvider);
      ref.invalidate(moneyAccountListProvider);
      ref.invalidate(paymentListControllerProvider);

      return res;
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }
}
