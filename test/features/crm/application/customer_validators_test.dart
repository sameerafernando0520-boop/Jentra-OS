import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/crm/application/customer_validators.dart';

void main() {
  test('customer name is required', () {
    expect(CustomerValidators.name('  '), 'Enter the customer name.');
    expect(CustomerValidators.name('Acme Trading'), isNull);
  });

  test('optional email validates only when present', () {
    expect(CustomerValidators.email(''), isNull);
    expect(CustomerValidators.email('not-an-email'), isNotNull);
    expect(CustomerValidators.email('accounts@example.com'), isNull);
  });

  test('credit limit cannot be negative', () {
    expect(
      CustomerValidators.nonnegativeMoney('-1', 'credit limit'),
      'credit limit cannot be negative.',
    );
    expect(CustomerValidators.nonnegativeMoney('0', 'credit limit'), isNull);
  });
}
