import 'exact_decimal.dart';

/// Exact advisory receipt quantities. The locked purchase order is authoritative.
final class GoodsReceiptQuantity {
  GoodsReceiptQuantity({
    required Object? accepted,
    required Object? rejected,
    required Object? numerator,
    required Object? denominator,
  }) {
    acceptedQuantity = decimal(accepted);
    rejectedQuantity = decimal(rejected);
    BigInt integer(Object? value) {
      if (value is! String || !RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(value)) {
        throw const FormatException(
          'A saved positive integer unit ratio is required.',
        );
      }
      return BigInt.parse(value);
    }

    final n = integer(numerator), d = integer(denominator);
    final scaled = acceptedQuantity.scaledValue * n;
    if (scaled % d != BigInt.zero || scaled ~/ d >= BigInt.from(10).pow(20)) {
      throw const FormatException(
        'Accepted quantity cannot be represented in base units.',
      );
    }
    baseQuantity = ExactDecimal.fromScaledValue(scaled ~/ d, scale: 6);
  }
  late final ExactDecimal acceptedQuantity, rejectedQuantity, baseQuantity;
  bool get empty => acceptedQuantity.isZero && rejectedQuantity.isZero;
  static ExactDecimal decimal(Object? value) {
    if (value is! String ||
        !RegExp(r'^[0-9]{1,14}(?:\.[0-9]{1,6})?$').hasMatch(value)) {
      throw const FormatException(
        'Enter a nonnegative exact quantity with up to six decimal places.',
      );
    }
    return ExactDecimal.parse(value, scale: 6);
  }
}
