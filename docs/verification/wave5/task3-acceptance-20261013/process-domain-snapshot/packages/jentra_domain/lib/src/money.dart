/// Fixed-scale ISO-currency amount. Six decimal places match numeric(20,6).
final class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.currencyCode);

  static const int scale = 6;
  static final BigInt _factor = BigInt.from(1000000);

  final BigInt minorUnits;
  final String currencyCode;

  factory Money.zero(String currencyCode) =>
      Money._(BigInt.zero, _validateCurrency(currencyCode));

  factory Money.fromMinorUnits(BigInt minorUnits, String currencyCode) =>
      Money._(minorUnits, _validateCurrency(currencyCode));

  factory Money.parse(String value, String currencyCode) {
    final match = RegExp(
      r'^([+-]?)(\d+)(?:\.(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Invalid decimal money value.', value);
    }
    final negative = match.group(1) == '-';
    final whole = BigInt.parse(match.group(2)!);
    final fraction = match.group(3) ?? '';
    final kept = '${fraction}000000'.substring(0, scale);
    var units = whole * _factor + BigInt.parse(kept);
    if (fraction.length > scale && int.parse(fraction[scale]) >= 5) {
      units += BigInt.one;
    }
    return Money._(negative ? -units : units, _validateCurrency(currencyCode));
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money._(minorUnits + other.minorUnits, currencyCode);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money._(minorUnits - other.minorUnits, currencyCode);
  }

  Money operator -() => Money._(-minorUnits, currencyCode);

  /// Multiplies by an exact rational value and rounds half away from zero.
  Money multiplyRatio(int numerator, int denominator) {
    if (denominator == 0) throw ArgumentError.value(denominator, 'denominator');
    final product = minorUnits * BigInt.from(numerator);
    final divisor = BigInt.from(denominator);
    final quotient = product ~/ divisor;
    final remainder = product.remainder(divisor).abs();
    final roundsUp = remainder * BigInt.two >= divisor.abs();
    final direction = product.sign * divisor.sign;
    return Money._(
      roundsUp ? quotient + BigInt.from(direction) : quotient,
      currencyCode,
    );
  }

  String toDecimalString() {
    final absolute = minorUnits.abs();
    final whole = absolute ~/ _factor;
    final fraction = (absolute % _factor).toString().padLeft(scale, '0');
    return '${minorUnits.isNegative ? '-' : ''}$whole.$fraction';
  }

  static String _validateCurrency(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'currencyCode',
        'Expected ISO 4217 code',
      );
    }
    return normalized;
  }

  void _requireSameCurrency(Money other) {
    if (currencyCode != other.currencyCode) {
      throw StateError(
        'Cannot combine $currencyCode and ${other.currencyCode}.',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      minorUnits == other.minorUnits &&
      currencyCode == other.currencyCode;

  @override
  int get hashCode => Object.hash(minorUnits, currencyCode);

  @override
  String toString() => '$currencyCode ${toDecimalString()}';
}
