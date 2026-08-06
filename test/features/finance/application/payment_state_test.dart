import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/company/application/company_state.dart';
import 'package:jentra_os/features/finance/application/payment_failure.dart';
import 'package:jentra_os/features/finance/application/payment_models.dart';
import 'package:jentra_os/features/finance/application/payment_state.dart';
import 'package:jentra_os/features/finance/data/supabase_payment_repository.dart';

import '../fake_payment_repository.dart';

void main() {
  group('PaymentState & PaymentMutationController', () {
    test('missing company ID returns empty accounts and payments', () async {
      final fakeRepo = FakePaymentRepository();
      final container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final accounts = await container.read(moneyAccountListProvider.future);
      expect(accounts, isEmpty);

      final payments = await container.read(paymentListControllerProvider.future);
      expect(payments, isEmpty);
    });

    test('missing company ID on recordPayment throws PaymentFailure', () async {
      final fakeRepo = FakePaymentRepository();
      final container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final input = RecordPaymentInput(
        invoiceId: 'inv-1',
        paymentMethod: 'cash',
        amount: 50.00,
        paymentDate: DateTime.now(),
      );

      expect(
        () => container
            .read(paymentMutationControllerProvider.notifier)
            .recordPayment(input),
        throwsA(isA<PaymentFailure>()),
      );
    });

    test('recordPayment injects company ID and records transaction', () async {
      final fakeRepo = FakePaymentRepository();
      final container = ProviderContainer(
        overrides: [
          paymentRepositoryProvider.overrideWithValue(fakeRepo),
          selectedCompanyIdProvider.overrideWith((ref) => 'comp-1'),
        ],
      );
      addTearDown(container.dispose);

      final input = RecordPaymentInput(
        invoiceId: 'inv-1',
        paymentMethod: 'cash',
        amount: 100.00,
        paymentDate: DateTime.now(),
      );

      final res = await container
          .read(paymentMutationControllerProvider.notifier)
          .recordPayment(input);

      expect(res.success, isTrue);
      expect(res.paymentNumber, equals('PMT-1001'));
      expect(res.journalNumber, equals('JRN-1001'));
      expect(fakeRepo.recordPaymentCompanyIds, contains('comp-1'));
    });
  });
}
