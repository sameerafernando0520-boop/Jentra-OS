import 'package:jentra_domain/jentra_procurement.dart';
import 'package:test/test.dart';

void main() {
  SupplierComparison response({
    String rate = '1',
    String quantity = '3',
    String total = '123.456789',
    bool duplicate = false,
  }) => SupplierComparison(
    requiredQuantities: {'source': '3'},
    quotedLines: [
      {'source_line_id': 'source', 'quantity': quantity, 'line_total': total},
      if (duplicate)
        {'source_line_id': 'source', 'quantity': quantity, 'line_total': total},
    ],
    exchangeRate: rate,
  );
  test('AC-309 compares complete responses using exact base amounts', () {
    expect(
      response(rate: '2.0000000000').baseTotal.toDecimalString(),
      '246.913578',
    );
    expect(response().complete, isTrue);
    expect(response(quantity: '2').complete, isFalse);
  });
  test(
    'AC-309 duplicate or unknown source lines cannot inflate comparison',
    () {
      expect(() => response(duplicate: true), throwsFormatException);
      expect(
        () => SupplierComparison(
          requiredQuantities: {'source': '3'},
          quotedLines: [
            {'source_line_id': 'other', 'quantity': '3', 'line_total': '1'},
          ],
          exchangeRate: '1',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'AC-309 missing lines are incomplete and binary numeric JSON is denied',
    () {
      expect(
        SupplierComparison(
          requiredQuantities: {'source': '3'},
          quotedLines: [],
          exchangeRate: '1',
        ).complete,
        isFalse,
      );
      expect(
        () => SupplierComparison(
          requiredQuantities: {'source': '3'},
          quotedLines: [
            {'source_line_id': 'source', 'quantity': 3, 'line_total': '1'},
          ],
          exchangeRate: '1',
        ),
        throwsFormatException,
      );
      expect(() => response(rate: '0'), throwsFormatException);
    },
  );
}
