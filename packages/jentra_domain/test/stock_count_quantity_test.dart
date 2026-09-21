import 'package:test/test.dart';
import 'package:jentra_domain/jentra_inventory.dart';

void main() {
  test(
    'count identity limit includes 500 and rejects 501 without truncation',
    () {
      final identities = [
        for (var i = 0; i < 501; i++) {'id': '$i', 'counted_quantity': '1'},
      ];
      expect(
        stockCountIdentityTotal(identities.take(500).toList(), serial: true),
        '500.000000',
      );
      expect(
        () => stockCountIdentityTotal(identities, serial: true),
        throwsFormatException,
      );
    },
  );
  test('identity quantities sum exactly beyond binary precision', () {
    expect(
      stockCountIdentityTotal([
        {'id': 'a', 'counted_quantity': '9007199254.740993'},
        {'id': 'b', 'counted_quantity': '0.000001'},
      ], serial: false),
      '9007199254.740994',
    );
  });
  test('serial quantities are exact presence values', () {
    expect(
      stockCountIdentityTotal([
        {'id': 'a', 'counted_quantity': '1'},
        {'id': 'b', 'counted_quantity': '0'},
      ], serial: true),
      '1.000000',
    );
    expect(
      () => stockCountIdentityTotal([
        {'id': 'a', 'counted_quantity': '0.5'},
      ], serial: true),
      throwsFormatException,
    );
  });
  test(
    'duplicate identities and numeric or overprecision values are rejected',
    () {
      expect(
        () => stockCountIdentityTotal([
          {'id': 'a', 'counted_quantity': '1'},
          {'id': 'a', 'counted_quantity': '1'},
        ], serial: false),
        throwsFormatException,
      );
      for (final value in [1, '-1', '0.0000001']) {
        expect(
          () => stockCountIdentityTotal([
            {'id': 'a', 'counted_quantity': value},
          ], serial: false),
          throwsFormatException,
        );
      }
    },
  );
}
