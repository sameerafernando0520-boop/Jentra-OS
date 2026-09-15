import 'package:test/test.dart';
import 'package:jentra_domain/jentra_procurement.dart';

void main() {
  PurchaseReturnAmount amount(
    String consumed,
    String requested, {
    String original = '2',
    String net = '250.25',
    String tax = '45.05',
  }) => PurchaseReturnAmount(
    originalQuantity: original,
    consumedQuantity: consumed,
    returnQuantity: requested,
    netAmount: net,
    taxAmount: tax,
    roundingScale: 2,
  );
  test('successive returns retain separate half-cent net and tax rounding', () {
    final first = amount('0', '1'), last = amount('1', '1');
    expect(first.total.scaledValue, BigInt.from(147660000));
    expect(last.total.scaledValue, BigInt.from(147640000));
    expect(
      first.total.scaledValue + last.total.scaledValue,
      BigInt.from(295300000),
    );
  });
  test('many partial returns exhaust the frozen value exactly', () {
    var total = BigInt.zero;
    for (var i = 0; i < 200; i++) {
      total += amount(
        i.toString(),
        '1',
        original: '200',
        net: '99999999999999.99',
        tax: '0',
      ).total.scaledValue;
    }
    expect(total, BigInt.parse('99999999999999990000'));
  });
  test(
    'unbilled receipt preview starts after previously consumed quantity',
    () {
      expect(
        amount('1', '1', original: '3', net: '10', tax: '0').total.scaledValue,
        BigInt.from(3340000),
      );
    },
  );
  test('excess and numeric inputs fail rather than approximating', () {
    expect(() => amount('1.9', '0.2'), throwsFormatException);
    expect(
      () => PurchaseReturnAmount(
        originalQuantity: '2',
        consumedQuantity: '0',
        returnQuantity: 0.1,
        netAmount: '10',
        taxAmount: '0',
        roundingScale: 2,
      ),
      throwsFormatException,
    );
  });
}
