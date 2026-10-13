import 'exact_decimal.dart';

/// Exact RFQ comparison; eligibility and selection are always rechecked server-side.
final class SupplierComparison {
  SupplierComparison({
    required Map<String, String> requiredQuantities,
    required List<Map<String, Object?>> quotedLines,
    required String exchangeRate,
    int baseScale = 6,
  }) {
    ExactDecimal decimal(Object? value, int scale) {
      if (value is! String ||
          !RegExp('^[0-9]+(?:\\.[0-9]{1,$scale})?\$').hasMatch(value)) {
        throw const FormatException('Exact decimal string required.');
      }
      return ExactDecimal.parse(value, scale: scale);
    }

    if (requiredQuantities.isEmpty ||
        requiredQuantities.length > 500 ||
        quotedLines.length > 500) {
      throw const FormatException(
        'A comparison requires 1 to 500 source lines.',
      );
    }
    final rate = decimal(exchangeRate, 10);
    if (!rate.isPositive) {
      throw const FormatException('Exchange rate must be positive.');
    }
    final required = requiredQuantities.map(
      (id, value) => MapEntry(id, decimal(value, 6)),
    );
    if (required.values.any((q) => !q.isPositive)) {
      throw const FormatException('Source quantities must be positive.');
    }
    final seen = <String>{};
    var total = ExactDecimal.zero(scale: 6), sameQuantities = true;
    for (final line in quotedLines) {
      final source = line['source_line_id'];
      if (source is! String ||
          !required.containsKey(source) ||
          !seen.add(source)) {
        throw const FormatException(
          'Duplicate or unknown response source line.',
        );
      }
      final quantity = decimal(line['quantity'], 6);
      if (!quantity.isPositive) {
        throw const FormatException('Response quantity must be positive.');
      }
      sameQuantities = sameQuantities && quantity == required[source];
      total = total + decimal(line['line_total'], 6);
    }
    complete = seen.length == required.length && sameQuantities;
    baseTotal = ExactDecimal.fromScaledValue(
      total.scaledValue * rate.scaledValue,
      scale: 16,
    ).rescale(baseScale).rescale(6);
    transactionTotal = total;
  }
  late final bool complete;
  late final ExactDecimal baseTotal, transactionTotal;
}

/// Advisory requisition values. Server validation remains authoritative.
final class ProcurementLine {
  ProcurementLine._({
    required this.lineId,
    required this.description,
    required this.unitId,
    required this.quantity,
    required this.estimatedUnitPrice,
    required this.conversionNumerator,
    required this.conversionDenominator,
    required this.baseQuantity,
    this.productId,
    this.sourceLineId,
  });

  factory ProcurementLine.fromJson(Map<String, Object?> data) {
    String requiredText(String key) {
      final value = data[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key is required.');
      }
      return value.trim();
    }

    ExactDecimal decimal(String key, {bool positive = false}) {
      final value = data[key];
      if (value is! String ||
          !RegExp(r'^\d{1,14}(?:\.\d{1,6})?$').hasMatch(value)) {
        throw FormatException('$key requires an exact nonnegative decimal.');
      }
      final result = ExactDecimal.parse(value, scale: 6);
      if (positive && !result.isPositive) {
        throw FormatException('$key must be positive.');
      }
      return result;
    }

    BigInt integer(String key) {
      final value = data[key];
      if (value is! String || !RegExp(r'^[1-9]\d{0,17}$').hasMatch(value)) {
        throw FormatException('$key requires a positive integer string.');
      }
      return BigInt.parse(value);
    }

    String? optionalText(String key) {
      final value = data[key];
      if (value == null) return null;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key must be a nonempty identifier.');
      }
      return value;
    }

    final quantity = decimal('quantity', positive: true);
    final numerator = integer('conversion_numerator');
    final denominator = integer('conversion_denominator');
    final baseUnits = quantity.scaledValue * numerator;
    if (baseUnits.remainder(denominator) != BigInt.zero) {
      throw const FormatException('Base quantity exceeds six decimal places.');
    }
    if (baseUnits ~/ denominator >= BigInt.from(10).pow(20)) {
      throw const FormatException('Base quantity exceeds the storage limit.');
    }
    final line = ProcurementLine._(
      lineId: requiredText('line_id'),
      description: requiredText('description'),
      unitId: requiredText('unit_id'),
      quantity: quantity,
      estimatedUnitPrice: decimal('estimated_unit_price'),
      conversionNumerator: numerator,
      conversionDenominator: denominator,
      baseQuantity: ExactDecimal.fromScaledValue(
        baseUnits ~/ denominator,
        scale: 6,
      ),
      productId: optionalText('product_id'),
      sourceLineId: optionalText('source_line_id'),
    );
    if (line.description.length > 1000 ||
        line.estimatedTotal.scaledValue >= BigInt.from(10).pow(20)) {
      throw const FormatException(
        'Line description or estimate exceeds its limit.',
      );
    }
    return line;
  }

  final String lineId, description, unitId;
  final String? productId, sourceLineId;
  final ExactDecimal quantity, estimatedUnitPrice, baseQuantity;
  final BigInt conversionNumerator, conversionDenominator;

  ExactDecimal get estimatedTotal => ExactDecimal.fromScaledValue(
    quantity.scaledValue * estimatedUnitPrice.scaledValue,
    scale: 12,
  ).rescale(6);

  Map<String, Object?> toJson() => {
    'line_id': lineId,
    'description': description,
    'unit_id': unitId,
    'product_id': productId,
    'source_line_id': sourceLineId,
    'quantity': quantity.toDecimalString(),
    'estimated_unit_price': estimatedUnitPrice.toDecimalString(),
    'conversion_numerator': conversionNumerator.toString(),
    'conversion_denominator': conversionDenominator.toString(),
  };
}
