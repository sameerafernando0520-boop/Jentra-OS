import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';
import 'wave3_quotation_workspace_test.dart' as quote;

Map<String, Object?> orderInput() => {
  ...quote.input()
    ..remove('quotation_date')
    ..remove('valid_until')
    ..remove('salesperson_id')
    ..remove('create_revision'),
  'order_date': '2026-09-06',
  'promised_date': '2026-10-06',
  'warehouse_id': 'warehouse',
  'ship_to': {'city': 'Colombo'},
};
void main() {
  test(
    'AC-304 order input preserves exact prices, units and delivery fields',
    () {
      final order = SalesOrderDraftCodec.fromJson(orderInput());
      expect(order.validate().isValid, true);
      expect(order.toJson(), orderInput());
      expect(
        order.lines.single.unitPrice.toDecimalString(),
        '90071992547409.123456',
      );
    },
  );
  test('AC-304 order input rejects numeric JSON and invalid dates', () {
    expect(
      () =>
          SalesOrderDraftCodec.fromJson(orderInput()..['exchange_rate'] = 1.0),
      throwsFormatException,
    );
    expect(
      () => SalesOrderDraftCodec.fromJson(
        orderInput()..['promised_date'] = '2026-02-30',
      ),
      throwsFormatException,
    );
  });
  test('AC-304 order input requires a product on every line', () {
    final input = orderInput();
    ((input['lines'] as List).single as Map).remove('product_id');
    expect(SalesOrderDraftCodec.fromJson(input).validate().isValid, false);
  });
  test('AC-304 order queries bound pages and distinguish order states', () {
    expect(
      SalesOrderListQuery(status: 'credit_hold', search: '  SO%  ').search,
      'SO%',
    );
    expect(() => SalesOrderListQuery(limit: 201), throwsRangeError);
    expect(() => SalesOrderListQuery(cursor: 'bad'), throwsFormatException);
    expect(
      () => SalesOrderListQuery(status: 'accepted'),
      throwsFormatException,
    );
  });
  test(
    'AC-304 credit preview keeps limit currency separate and overdue inside due',
    () {
      final preview = SalesOrderCreditPreview.fromJson({
        'sales_order_id': 'order',
        'order_version': 2,
        'currency_code': 'LKR',
        'credit_currency_code': 'USD',
        'credit_limit': '500.000000',
        'due_exposure': '450.000000',
        'overdue_exposure': '20.000000',
        'existing_order_exposure': '0.000000',
        'current_order_exposure': '100.000000',
        'total_exposure': '550.000000',
        'projection_available': false,
        'checked_at': '2026-09-07T00:00:00Z',
        'credit_as_of_at': null,
        'reason': 'CREDIT_CURRENCY_MISMATCH',
      });
      expect(preview.creditLimit.currencyCode, 'USD');
      expect(preview.totalExposure.toDecimalString(), '550.000000');
      expect(preview.projectionAvailable, false);
      expect(preview.reason, 'CREDIT_CURRENCY_MISMATCH');
    },
  );
}
