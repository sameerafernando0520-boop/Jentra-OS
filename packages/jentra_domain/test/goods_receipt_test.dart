import 'package:jentra_domain/jentra_procurement.dart';
import 'package:test/test.dart';

void main() {
  test(
    'accepted base quantities use frozen rational strings; rejection is separate',
    () {
      final q = GoodsReceiptQuantity(
        accepted: '0.25',
        rejected: '0.1',
        numerator: '12',
        denominator: '1',
      );
      expect(q.baseQuantity.toString(), '3.000000');
      expect(q.rejectedQuantity.toString(), '0.100000');
    },
  );
  test(
    'invalid financial transport and nonterminating unit conversion fail closed',
    () {
      for (final input in [0.25, '-1', 'NaN', '1e3', '0.0000001']) {
        expect(
          () => GoodsReceiptQuantity(
            accepted: input,
            rejected: '0',
            numerator: '1',
            denominator: '1',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => GoodsReceiptQuantity(
          accepted: '1',
          rejected: '0',
          numerator: '1',
          denominator: '3',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'large exact receipt quantities retain all digits across 500 rational inputs',
    () {
      for (var i = 1; i <= 500; i++) {
        final q = GoodsReceiptQuantity(
          accepted: '9007199254.740993',
          rejected: '0',
          numerator: '$i',
          denominator: '1',
        );
        expect(
          q.baseQuantity.scaledValue,
          BigInt.parse('9007199254740993') * BigInt.from(i),
        );
      }
    },
  );
}
