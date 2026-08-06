import 'package:flutter_test/flutter_test.dart';
import 'package:i_book/features/sales/application/invoice_validators.dart';

void main() {
  group('InvoiceValidators', () {
    test('validateCustomer requires customer ID selection', () {
      expect(InvoiceValidators.validateCustomer(null), equals('Please select a customer'));
      expect(InvoiceValidators.validateCustomer('  '), equals('Please select a customer'));
      expect(InvoiceValidators.validateCustomer('cust-123'), isNull);
    });

    test('validateQuantity checks positive quantity', () {
      expect(InvoiceValidators.validateQuantity(''), equals('Quantity is required'));
      expect(InvoiceValidators.validateQuantity('abc'), equals('Enter a valid quantity'));
      expect(InvoiceValidators.validateQuantity('0'), equals('Quantity must be greater than 0'));
      expect(InvoiceValidators.validateQuantity('-1'), equals('Quantity must be greater than 0'));
      expect(InvoiceValidators.validateQuantity('5'), isNull);
    });

    test('validateUnitPrice checks non-negative price', () {
      expect(InvoiceValidators.validateUnitPrice(''), equals('Unit price is required'));
      expect(InvoiceValidators.validateUnitPrice('xyz'), equals('Enter a valid price'));
      expect(InvoiceValidators.validateUnitPrice('-10'), equals('Unit price cannot be negative'));
      expect(InvoiceValidators.validateUnitPrice('0'), isNull);
      expect(InvoiceValidators.validateUnitPrice('25.50'), isNull);
    });

    test('validateTaxRate checks percentage range', () {
      expect(InvoiceValidators.validateTaxRate(''), isNull);
      expect(InvoiceValidators.validateTaxRate('-1'), equals('Tax rate must be between 0% and 100%'));
      expect(InvoiceValidators.validateTaxRate('105'), equals('Tax rate must be between 0% and 100%'));
      expect(InvoiceValidators.validateTaxRate('15'), isNull);
    });

    test('validateItems checks non-empty items list', () {
      expect(InvoiceValidators.validateItems([]), equals('Please add at least one line item to the invoice'));
      expect(InvoiceValidators.validateItems(['item1']), isNull);
    });
  });
}
