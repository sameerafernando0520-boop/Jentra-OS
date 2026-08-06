import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/finance/application/payment_failure.dart';
import 'package:jentra_os/features/finance/application/payment_models.dart';
import 'package:jentra_os/features/finance/application/payment_repository.dart';
import 'package:jentra_os/features/finance/application/payment_state.dart';
import 'package:jentra_os/features/finance/application/payment_validators.dart';
import 'package:jentra_os/features/finance/data/supabase_payment_repository.dart';

final class ThrowingPaymentRepository implements PaymentRepository {
  ThrowingPaymentRepository({this.errorMessage = 'Payment execution failed'});

  final String errorMessage;

  @override
  Future<List<MoneyAccount>> listMoneyAccounts({required String companyId}) async {
    throw PaymentFailure(errorMessage);
  }

  @override
  Future<List<Payment>> listPayments({required String companyId}) async {
    throw PaymentFailure(errorMessage);
  }

  @override
  Future<PaymentResult> recordInvoicePayment({
    required String companyId,
    required RecordPaymentInput input,
  }) async {
    throw PaymentFailure(errorMessage);
  }
}

void main() {
  group('Payment Failure Paths & Validation Error Handling', () {
    test('recordPayment handles repository error and throws PaymentFailure', () async {
      final throwingRepo = ThrowingPaymentRepository(errorMessage: 'Payment amount exceeds outstanding balance.');
      final container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(throwingRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final input = RecordPaymentInput(
        invoiceId: 'inv-1',
        paymentMethod: 'cash',
        amount: 500.00,
        paymentDate: DateTime.now(),
      );

      expect(
        () => container
            .read(paymentMutationControllerProvider.notifier)
            .recordPayment(input),
        throwsA(isA<PaymentFailure>().having((f) => f.message, 'message', contains('exceeds outstanding balance'))),
      );
    });

    test('PaymentValidators validateAmount rejects zero or negative amounts', () {
      expect(PaymentValidators.validateAmount(null, 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('', 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('0', 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('-10.00', 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('invalid', 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('50.00', 100.00), isNull);
    });

    test('PaymentValidators validateAmount checks against outstanding balance due', () {
      expect(PaymentValidators.validateAmount('150.00', 100.00), isNotNull);
      expect(PaymentValidators.validateAmount('100.00', 100.00), isNull);
      expect(PaymentValidators.validateAmount('50.00', 100.00), isNull);
    });
  });
}
