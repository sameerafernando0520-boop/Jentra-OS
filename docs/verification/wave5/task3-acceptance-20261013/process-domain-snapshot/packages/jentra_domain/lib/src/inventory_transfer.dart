import 'exact_decimal.dart';

/// Exact advisory quantity; the server independently resolves the governed unit.
final class InventoryTransferQuantity {
  InventoryTransferQuantity(
    Object? quantity,
    Object? numerator,
    Object? denominator,
  ) {
    if (quantity is! String ||
        !RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(quantity)) {
      throw const FormatException(
        'Enter a positive quantity with at most six decimals.',
      );
    }
    BigInt ratio(Object? value) {
      if (value is! String || !RegExp(r'^[1-9]\d{0,18}$').hasMatch(value)) {
        throw const FormatException(
          'Select a governed positive unit conversion.',
        );
      }
      final result = BigInt.parse(value);
      if (result > BigInt.parse('9223372036854775807')) {
        throw const FormatException(
          'The unit conversion exceeds the supported range.',
        );
      }
      return result;
    }

    final q = ExactDecimal.parse(quantity, scale: 6).scaledValue;
    final n = ratio(numerator), d = ratio(denominator);
    if (q <= BigInt.zero || (q * n) % d != BigInt.zero) {
      throw const FormatException(
        'Quantity must resolve to positive exact base units.',
      );
    }
    _base = (q * n) ~/ d;
    if (_base >= BigInt.from(10).pow(20)) {
      throw const FormatException('Base quantity exceeds the supported range.');
    }
  }
  late final BigInt _base;
  String get baseQuantity =>
      ExactDecimal.fromScaledValue(_base, scale: 6).toDecimalString();
  void validateSerialCount(int count) {
    if (_base != BigInt.from(count) * BigInt.from(1000000)) {
      throw const FormatException(
        'Select one distinct serial for each base unit.',
      );
    }
  }
}
