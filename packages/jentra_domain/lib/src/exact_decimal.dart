/// Arbitrary fixed-scale decimal backed by [BigInt].
///
/// This is the public-contract representation for exchange rates, tax rates,
/// quantities, and other values that must never pass through binary floating
/// point. Parsing rounds excess precision half away from zero.
final class ExactDecimal implements Comparable<ExactDecimal> {
  const ExactDecimal._(this.scaledValue, this.scale);

  final BigInt scaledValue;
  final int scale;

  factory ExactDecimal.zero({required int scale}) {
    _validateScale(scale);
    return ExactDecimal._(BigInt.zero, scale);
  }

  factory ExactDecimal.fromScaledValue(BigInt value, {required int scale}) {
    _validateScale(scale);
    return ExactDecimal._(value, scale);
  }

  factory ExactDecimal.parse(String value, {required int scale}) {
    _validateScale(scale);
    final match = RegExp(
      r'^([+-]?)(\d+)(?:\.(\d+))?$',
    ).firstMatch(value.trim());
    if (match == null) {
      throw FormatException('Invalid exact decimal value.', value);
    }

    final negative = match.group(1) == '-';
    final whole = BigInt.parse(match.group(2)!);
    final fraction = match.group(3) ?? '';
    final factor = _pow10(scale);
    final padded = '$fraction${'0' * scale}';
    final retained = scale == 0 ? '' : padded.substring(0, scale);
    var units = whole * factor;
    if (retained.isNotEmpty) units += BigInt.parse(retained);
    if (fraction.length > scale && int.parse(fraction[scale]) >= 5) {
      units += BigInt.one;
    }
    return ExactDecimal._(negative ? -units : units, scale);
  }

  bool get isZero => scaledValue == BigInt.zero;
  bool get isPositive => scaledValue > BigInt.zero;
  bool get isNegative => scaledValue < BigInt.zero;

  ExactDecimal operator +(ExactDecimal other) {
    _requireSameScale(other);
    return ExactDecimal._(scaledValue + other.scaledValue, scale);
  }

  ExactDecimal operator -(ExactDecimal other) {
    _requireSameScale(other);
    return ExactDecimal._(scaledValue - other.scaledValue, scale);
  }

  ExactDecimal operator -() => ExactDecimal._(-scaledValue, scale);

  ExactDecimal rescale(int nextScale) {
    _validateScale(nextScale);
    if (nextScale == scale) return this;
    if (nextScale > scale) {
      return ExactDecimal._(scaledValue * _pow10(nextScale - scale), nextScale);
    }

    final divisor = _pow10(scale - nextScale);
    final quotient = scaledValue ~/ divisor;
    final remainder = scaledValue.remainder(divisor).abs();
    final roundsUp = remainder * BigInt.two >= divisor;
    return ExactDecimal._(
      roundsUp ? quotient + BigInt.from(scaledValue.sign) : quotient,
      nextScale,
    );
  }

  String toDecimalString() {
    final absolute = scaledValue.abs();
    if (scale == 0) {
      return '${scaledValue.isNegative ? '-' : ''}$absolute';
    }
    final factor = _pow10(scale);
    final whole = absolute ~/ factor;
    final fraction = (absolute % factor).toString().padLeft(scale, '0');
    return '${scaledValue.isNegative ? '-' : ''}$whole.$fraction';
  }

  void _requireSameScale(ExactDecimal other) {
    if (scale != other.scale) {
      throw StateError(
        'Cannot compare or combine scale $scale with scale ${other.scale}.',
      );
    }
  }

  @override
  int compareTo(ExactDecimal other) {
    _requireSameScale(other);
    return scaledValue.compareTo(other.scaledValue);
  }

  @override
  bool operator ==(Object other) =>
      other is ExactDecimal &&
      scaledValue == other.scaledValue &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(scaledValue, scale);

  @override
  String toString() => toDecimalString();

  static void _validateScale(int value) {
    if (value < 0 || value > 18) {
      throw RangeError.range(value, 0, 18, 'scale');
    }
  }

  static BigInt _pow10(int exponent) => BigInt.from(10).pow(exponent);
}
