import 'package:test/test.dart';
import 'package:jentra_domain/jentra_stock_opening.dart';

Map<String, Object?> openingForm() => {
  'id': '00000000-0000-4000-8000-000000000001',
  'warehouse_id': 'warehouse',
  'offset_account_id': 'equity',
  'document_date': '2026-09-11',
  'reason': 'Initial physical count',
  'lines': [
    {
      'line_id': 'line',
      'product_id': 'product',
      'tracking_mode': 'none',
      'base_quantity': '10.125',
      'base_value': '90071992547409.91',
    },
  ],
};

void main() {
  test('opening keeps an immutable exact decimal snapshot', () {
    final form = openingForm();
    final draft = StockOpeningDraft(form);
    form['reason'] = 'changed';
    expect(draft.toJson()['reason'], 'Initial physical count');
    expect(draft.validate(), isEmpty);
    expect(draft.total.toDecimalString(), '90071992547409.910000');
  });
  test('malformed quantities and duplicate serials fail validation', () {
    final f = openingForm();
    f['lines'] = [
      {
        'line_id': 'line',
        'product_id': 'p',
        'tracking_mode': 'serial',
        'base_quantity': 2,
        'base_value': '20',
        'serial_codes': ['S1', ' S1 '],
      },
    ];
    expect(StockOpeningDraft(f).validate(), isNotEmpty);
  });
  test('stock opening access requires cost plus an operational capability', () {
    expect(canReadStockOpenings({'inventory.adjustments.post'}), false);
    expect(canReadStockOpenings({'inventory.cost.view'}), false);
    expect(
      canReadStockOpenings({
        'inventory.cost.view',
        'workflow.approvals.decide',
      }),
      true,
    );
  });
}
