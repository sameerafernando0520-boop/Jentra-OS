import 'exact_decimal.dart';

BigInt dispositionQuantity(Object? value) {
  if (value is! String || !RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(value)) {
    throw const FormatException(
      'Enter a positive exact quantity with up to six decimal places.',
    );
  }
  final amount = ExactDecimal.parse(value, scale: 6).scaledValue;
  if (amount <= BigInt.zero) {
    throw const FormatException('Disposition quantity must be positive.');
  }
  return amount;
}

/// Sends source selections only. Carrying cost, baseline versions, provenance and
/// reversal lines are server-owned and never copied from a local preview.
Map<String, Object?> dispositionSavePayload(Map<String, Object?> form) {
  final date = form['document_date'] as String? ?? '';
  final parsed = DateTime.tryParse(date);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
    throw const FormatException('Enter a valid YYYY-MM-DD date.');
  }
  if (form['id'] is! String ||
      form['warehouse_id'] is! String ||
      form['offset_account_id'] is! String ||
      (form['reason'] as String? ?? '').trim().length < 3 ||
      (form['reason'] as String).trim().length > 1000) {
    throw const FormatException(
      'Choose warehouse and variance account, and enter a reason.',
    );
  }
  if (form['corrects_disposition_id'] != null &&
      form['reverses_disposition_id'] != null) {
    throw const FormatException('Select one source correction or reversal.');
  }
  final payload = <String, Object?>{
    for (final key in [
      'id',
      'warehouse_id',
      'document_date',
      'reason',
      'offset_account_id',
      'corrects_disposition_id',
      'reverses_disposition_id',
    ])
      key: form[key],
  };
  if (form['reverses_disposition_id'] != null) return payload;
  final rows = form['lines'];
  if (rows is! List || rows.isEmpty || rows.length > 100) {
    throw const FormatException(
      'Select between one and 100 disposition lines.',
    );
  }
  final ids = <String>{}, serialIds = <String>{}, lots = <String>{};
  payload['lines'] = [
    for (final raw in rows)
      (() {
        final row = (raw as Map).cast<String, Object?>();
        if (row['line_id'] is! String ||
            !ids.add(row['line_id'] as String) ||
            row['product_id'] is! String ||
            row['unit_id'] is! String) {
          throw const FormatException(
            'Choose a product and unit for each distinct line.',
          );
        }
        final quantity = dispositionQuantity(row['quantity']);
        for (final key in ['conversion_numerator', 'conversion_denominator']) {
          final value = row[key];
          if (value is! String || !RegExp(r'^[1-9]\d{0,17}$').hasMatch(value)) {
            throw const FormatException(
              'Use the governed exact unit conversion.',
            );
          }
        }
        final selected = row['serial_ids'] as List? ?? [];
        if (row['tracking_mode'] == 'lot' && row['lot_id'] is! String) {
          throw const FormatException('Select the held lot to disposition.');
        }
        if (row['lot_id'] is String && !lots.add(row['lot_id'] as String)) {
          throw const FormatException('Select each lot once per disposition.');
        }
        if (row['tracking_mode'] == 'serial') {
          final numerator = BigInt.parse(row['conversion_numerator'] as String);
          final denominator = BigInt.parse(
            row['conversion_denominator'] as String,
          );
          if (quantity * numerator !=
              BigInt.from(selected.length) *
                  BigInt.from(1000000) *
                  denominator) {
            throw const FormatException(
              'Select one serial for every base unit.',
            );
          }
          for (final id in selected) {
            if (id is! String || !serialIds.add(id) || serialIds.length > 500) {
              throw const FormatException(
                'Select each serial once, up to 500 identities.',
              );
            }
          }
        } else if (selected.isNotEmpty) {
          throw const FormatException(
            'Serial selections require a serial-tracked product.',
          );
        }
        return <String, Object?>{
          for (final key in [
            'line_id',
            'product_id',
            'unit_id',
            'quantity',
            'conversion_numerator',
            'conversion_denominator',
            'lot_id',
          ])
            key: row[key],
          'serial_ids': List<Object?>.from(selected),
        };
      })(),
  ];
  return payload;
}
