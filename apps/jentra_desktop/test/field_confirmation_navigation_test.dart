import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_desktop/src/shell/navigation.dart';

void main() {
  test('dedicated confirmation navigation requires its own capability and both flags', () {
    final routes = visibleJentraDestinations({
      'sales.field.confirmations.manage',
    }).map((d) => d.path).toList();
    const enabled =
        bool.fromEnvironment('FIELD_SALES_CANDIDATE_ENABLED') &&
        bool.fromEnvironment('FIELD_SALES_EMAIL_CONFIRMATION_ENABLED');
    expect(routes.contains('/sales/customer-email-requests'), enabled);
    expect(
      routes.contains('/sales/delivery-responses'),
      enabled &&
          const bool.fromEnvironment(
            'FIELD_SALES_DELIVERY_CONFIRMATION_ENABLED',
          ),
    );
    expect(routes.contains('/sales'), isFalse);
    expect(
      visibleJentraDestinations({})
          .any((d) => d.path == '/sales/customer-email-requests'),
      isFalse,
    );
  });
}
