import 'package:jentra_domain/jentra_procurement.dart';
import 'package:test/test.dart';

void main() {
  ProcurementLine line({String quantity = '3', String price = '0.333333'}) =>
      ProcurementLine.fromJson({
        'line_id': 'line-a',
        'description': 'Paper',
        'unit_id': 'each',
        'quantity': quantity,
        'estimated_unit_price': price,
        'conversion_numerator': '1',
        'conversion_denominator': '1',
      });

  test('AC-309 exact estimates retain large values and fractional cents', () {
    expect(line().estimatedTotal.toDecimalString(), '0.999999');
    expect(
      line(
        quantity: '99999999999999',
        price: '1',
      ).estimatedTotal.toDecimalString(),
      '99999999999999.000000',
    );
  });
  test('AC-309 financial JSON numbers and excess precision are rejected', () {
    expect(() => line(quantity: '0.0000001'), throwsFormatException);
    expect(() => line(quantity: '0'), throwsFormatException);
    expect(() => line(price: '-1'), throwsFormatException);
    expect(
      () => ProcurementLine.fromJson({...line().toJson(), 'quantity': 3}),
      throwsFormatException,
    );
  });
  test('AC-309 rational base quantity must be exactly representable', () {
    expect(
      () => ProcurementLine.fromJson({
        ...line().toJson(),
        'quantity': '1',
        'conversion_denominator': '3',
      }),
      throwsFormatException,
    );
    final pack = ProcurementLine.fromJson({
      ...line().toJson(),
      'conversion_numerator': '12',
    });
    expect(pack.baseQuantity.toDecimalString(), '36.000000');
  });
  test('AC-309 immutable line snapshots retain source identity', () {
    final input = {...line().toJson(), 'source_line_id': 'source'};
    final parsed = ProcurementLine.fromJson(input);
    input['quantity'] = '500';
    expect(parsed.quantity.toDecimalString(), '3.000000');
    expect(parsed.toJson()['source_line_id'], 'source');
  });
  test(
    'AC-309 exact estimate agrees with integer arithmetic across inputs',
    () {
      for (var i = 1; i <= 500; i++) {
        final value = line(quantity: '$i', price: '0.123456');
        expect(value.estimatedTotal.scaledValue, BigInt.from(i * 123456));
      }
    },
  );
}
