import 'exact_decimal.dart';
import 'goods_receipt.dart';

/// Advisory frozen-source credit. Posting recalculates under source locks.
final class PurchaseReturnAmount {
  PurchaseReturnAmount({
    required Object? originalQuantity,
    required Object? consumedQuantity,
    required Object? returnQuantity,
    required Object? netAmount,
    required Object? taxAmount,
    required int roundingScale,
  }) {
    if (roundingScale < 0 || roundingScale > 6) {
      throw const FormatException('Unsupported source currency precision.');
    }
    final original = GoodsReceiptQuantity.decimal(originalQuantity).scaledValue;
    final consumed = GoodsReceiptQuantity.decimal(consumedQuantity).scaledValue;
    final requested = GoodsReceiptQuantity.decimal(returnQuantity).scaledValue;
    if (original <= BigInt.zero || consumed + requested > original) {
      throw const FormatException(
        'Return exceeds the original eligible quantity.',
      );
    }
    final factor = BigInt.from(10).pow(6 - roundingScale);
    BigInt portion(Object? money) {
      final amount = GoodsReceiptQuantity.decimal(money).scaledValue;
      BigInt cumulative(BigInt quantity) {
        final numerator = amount * quantity;
        final denominator = original * factor;
        final whole = numerator ~/ denominator;
        return (whole +
                (numerator.remainder(denominator) * BigInt.two >= denominator
                    ? BigInt.one
                    : BigInt.zero)) *
            factor;
      }

      return cumulative(consumed + requested) - cumulative(consumed);
    }

    net = ExactDecimal.fromScaledValue(portion(netAmount), scale: 6);
    tax = ExactDecimal.fromScaledValue(portion(taxAmount), scale: 6);
    total = ExactDecimal.fromScaledValue(
      net.scaledValue + tax.scaledValue,
      scale: 6,
    );
  }
  late final ExactDecimal net, tax, total;
}
