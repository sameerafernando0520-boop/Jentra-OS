import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

void main() {
  test('Sales navigation fails closed while capabilities are unavailable', () {
    for (final capabilities in [
      null,
      <String>{},
      {'inventory.products.view'},
    ]) {
      expect(
        visibleJentraDestinations(capabilities).any((d) => d.path == '/sales'),
        isFalse,
      );
    }
  });

  test(
    'Sales permits readers and managers and preserves Operations grouping',
    () {
      for (final capability in [
        'sales.quotations.view',
        'sales.quotations.manage',
        'sales.orders.view',
        'sales.orders.manage',
      ]) {
        final destinations = visibleJentraDestinations({capability});
        expect(
          destinations.firstWhere((d) => d.path == '/sales').section,
          'OPERATIONS',
        );
      }
      expect(
        visibleJentraDestinations(
          {},
        ).firstWhere((d) => d.path == '/procurement').section,
        'OPERATIONS',
      );
    },
  );
}
