import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/finance/application/payment_validators.dart';

void main() {
  group('PaymentValidators', () {
    test('validateAmount requires non-empty amount', () {
      expect(PaymentValidators.validateAmount('', 100.0), equals('Payment amount is required'));
      expect(PaymentValidators.validateAmount('  ', 100.0), equals('Payment amount is required'));
    });

    test('validateAmount checks numeric positive format', () {
      expect(PaymentValidators.validateAmount('abc', 100.0), equals('Enter a valid amount'));
      expect(PaymentValidators.validateAmount('0', 100.0), equals('Amount must be greater than 0'));
      expect(PaymentValidators.validateAmount('-50', 100.0), equals('Amount must be greater than 0'));
    });

    test('validateAmount checks against outstanding balance', () {
      expect(
        PaymentValidators.validateAmount('150.00', 100.0),
        equals('Amount cannot exceed outstanding balance (\$100.00)'),
      );
      expect(PaymentValidators.validateAmount('100.00', 100.0), isNull);
      expect(PaymentValidators.validateAmount('50.00', 100.0), isNull);
    });

    test('validatePaymentMethod requires selection', () {
      expect(PaymentValidators.validatePaymentMethod(null), equals('Select a payment method'));
      expect(PaymentValidators.validatePaymentMethod(''), equals('Select a payment method'));
      expect(PaymentValidators.validatePaymentMethod('cash'), isNull);
    });
  });
}
