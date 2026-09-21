import 'exact_decimal.dart';

/// Advisory identity total. The server independently resolves frozen identities.
String stockCountIdentityTotal(
  Iterable<Map> identities, {
  required bool serial,
}) {
  var total = BigInt.zero;
  final ids = <String>{};
  for (final identity in identities) {
    final id = identity['id'], quantity = identity['counted_quantity'];
    if (id is! String || id.isEmpty || !ids.add(id) || ids.length > 500) {
      throw const FormatException('Count each captured identity once.');
    }
    if (quantity is! String ||
        !RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(quantity)) {
      throw const FormatException(
        'Enter a nonnegative exact identity quantity.',
      );
    }
    final value = ExactDecimal.parse(quantity, scale: 6).scaledValue;
    if (serial && value != BigInt.zero && value != BigInt.from(1000000)) {
      throw const FormatException('A serial must be present or absent.');
    }
    total += value;
    if (total >= BigInt.from(10).pow(20)) {
      throw const FormatException('Count total exceeds the supported range.');
    }
  }
  return ExactDecimal.fromScaledValue(total, scale: 6).toDecimalString();
}
