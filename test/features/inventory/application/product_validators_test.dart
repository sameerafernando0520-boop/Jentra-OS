import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_os/features/inventory/application/product_validators.dart';

void main() {
  group('ProductValidators', () {
    test('validateName requires non-empty name', () {
      expect(ProductValidators.validateName(''), equals('Product name is required'));
      expect(ProductValidators.validateName('  '), equals('Product name is required'));
      expect(ProductValidators.validateName('Wireless Mouse'), isNull);
    });

    test('validateUnitPrice validates price format and range', () {
      expect(ProductValidators.validateUnitPrice(''), equals('Selling price is required'));
      expect(ProductValidators.validateUnitPrice('abc'), equals('Enter a valid selling price'));
      expect(ProductValidators.validateUnitPrice('-5'), equals('Selling price cannot be negative'));
      expect(ProductValidators.validateUnitPrice('19.99'), isNull);
    });

    test('validateCostPrice validates price format when present', () {
      expect(ProductValidators.validateCostPrice(''), isNull);
      expect(ProductValidators.validateCostPrice('abc'), equals('Enter a valid cost price'));
      expect(ProductValidators.validateCostPrice('-1'), equals('Cost price cannot be negative'));
      expect(ProductValidators.validateCostPrice('10.50'), isNull);
    });

    test('validateSku limits length', () {
      expect(ProductValidators.validateSku(null), isNull);
      expect(ProductValidators.validateSku('SKU-100'), isNull);
      expect(
        ProductValidators.validateSku('A' * 101),
        equals('SKU must be 100 characters or less'),
      );
    });

    test('validateBarcode limits length', () {
      expect(ProductValidators.validateBarcode(null), isNull);
      expect(ProductValidators.validateBarcode('1234567890123'), isNull);
      expect(
        ProductValidators.validateBarcode('B' * 101),
        equals('Barcode must be 100 characters or less'),
      );
    });
  });
}
