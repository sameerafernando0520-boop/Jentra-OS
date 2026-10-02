import 'package:jentra_domain/disposition.dart';
import 'package:test/test.dart';

Map<String, Object?> form() => {
  'id': 'doc',
  'warehouse_id': 'warehouse',
  'document_date': '2026-09-30',
  'reason': 'Expired held stock',
  'offset_account_id': 'variance',
  'lines': [
    <String, Object?>{
      'line_id': 'line',
      'product_id': 'product',
      'unit_id': 'unit',
      'quantity': '99999999999999.999999',
      'tracking_mode': 'none',
      'conversion_numerator': '1',
      'conversion_denominator': '1',
      'serial_ids': <String>[],
      'carrying_value': '999',
      'baseline_version': '999',
    },
  ],
};
void main() {
  test(
    'maximum decimal quantity remains exact and cannot override pooled preview',
    () {
      expect(
        dispositionQuantity('99999999999999.999999'),
        BigInt.parse('99999999999999999999'),
      );
      final payload = dispositionSavePayload(form());
      final line = (payload['lines'] as List).single as Map;
      expect(line['quantity'], '99999999999999.999999');
      expect(line.containsKey('carrying_value'), false);
      expect(line.containsKey('baseline_version'), false);
    },
  );
  test('numeric JSON, zero and excess precision are rejected', () {
    for (final value in [3, '0', '1.0000001', '1e3', '-1']) {
      expect(() => dispositionQuantity(value), throwsFormatException);
    }
  });
  test(
    'serial selection equals exact converted base units and rejects duplicates',
    () {
      final f = form(), line = (form()['lines'] as List).single as Map;
      line.addAll(<String, Object?>{
        'quantity': '0.25',
        'tracking_mode': 'serial',
        'conversion_numerator': '12',
        'serial_ids': ['s1', 's2', 's3'],
      });
      f['lines'] = [line];
      expect(dispositionSavePayload(f)['lines'], isNotEmpty);
      line['serial_ids'] = ['s1', 's1', 's3'];
      expect(() => dispositionSavePayload(f), throwsFormatException);
      line['serial_ids'] = ['s1', 's2'];
      expect(() => dispositionSavePayload(f), throwsFormatException);
    },
  );
  test('lot identity and bounded line range are mandatory', () {
    final f = form(), line = (f['lines'] as List).single as Map;
    line['tracking_mode'] = 'lot';
    expect(() => dispositionSavePayload(f), throwsFormatException);
    line['lot_id'] = 'lot';
    expect(dispositionSavePayload(f)['lines'], isNotEmpty);
    f['lines'] = List.filled(101, line);
    expect(() => dispositionSavePayload(f), throwsFormatException);
  });
  test('reversal payload never supplies quantity value or provenance', () {
    final f = form()..['reverses_disposition_id'] = 'original';
    final p = dispositionSavePayload(f);
    expect(p['reverses_disposition_id'], 'original');
    expect(p.containsKey('lines'), false);
    f['corrects_disposition_id'] = 'other';
    expect(() => dispositionSavePayload(f), throwsFormatException);
  });
}
