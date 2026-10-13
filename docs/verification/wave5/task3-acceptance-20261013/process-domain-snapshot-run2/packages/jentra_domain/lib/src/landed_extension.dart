import 'exact_decimal.dart';

/// Exact protocol for bounded multi-receipt charges and immutable corrections.
final class LandedExtensionProtocol {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static void identity(Object? value) {
    if (value is! String || !_uuid.hasMatch(value)) {
      throw const FormatException('Choose a verified document identity.');
    }
  }

  static ExactDecimal decimal(Object? value, {bool positive = false}) {
    if (value is! String ||
        !RegExp(r'^-?\d{1,14}(\.\d{1,6})?$').hasMatch(value)) {
      throw const FormatException(
        'Amounts and weights require exact decimal text.',
      );
    }
    final result = ExactDecimal.parse(value, scale: 6);
    if (positive && !result.isPositive) {
      throw const FormatException('Enter a positive exact weight.');
    }
    return result;
  }

  static Map<String, Object?> payload(Map<String, Object?> form) {
    const fields = {
      'id',
      'correction_of',
      'document_date',
      'reference',
      'reason',
      'total_amount',
      'basis_mode',
      'offset_account_id',
      'variance_account_id',
      'receipts',
      'basis_hash',
    };
    return {
      for (final entry in form.entries)
        if (fields.contains(entry.key)) entry.key: entry.value,
    };
  }

  static void validateInput(Map<String, Object?> input, {bool sealed = false}) {
    identity(input['id']);
    if (decimal(input['total_amount']).isNegative) {
      throw const FormatException('The corrected total cannot be negative.');
    }
    final reason = input['reason'],
        reference = input['reference'],
        date = input['document_date'];
    if (reason is! String ||
        reason.trim().length < 3 ||
        reason.length > 1000 ||
        reference is! String ||
        reference.trim().isEmpty ||
        reference.length > 140 ||
        date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date)?.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Enter a valid date, reference and reason.');
    }
    if (input['correction_of'] != null) {
      identity(input['correction_of']);
      if (input.containsKey('receipts') ||
          input.containsKey('basis_mode') ||
          input.containsKey('offset_account_id') ||
          input.containsKey('variance_account_id')) {
        throw const FormatException(
          'A correction retains its original allocation basis.',
        );
      }
    } else {
      if (!const {
        'quantity',
        'original_value',
        'manual',
      }.contains(input['basis_mode'])) {
        throw const FormatException('Choose an explicit allocation basis.');
      }
      identity(input['offset_account_id']);
      identity(input['variance_account_id']);
      final receipts = input['receipts'];
      if (receipts is! List || receipts.isEmpty || receipts.length > 50) {
        throw const FormatException('Choose between one and fifty receipts.');
      }
      final ids = <Object?>{};
      for (final row in receipts) {
        if (row is! Map ||
            row.keys.any((k) => k != 'receipt_line_id' && k != 'weight')) {
          throw const FormatException('Receipt allocation is invalid.');
        }
        identity(row['receipt_line_id']);
        if (!ids.add(row['receipt_line_id']))
          {throw const FormatException('A receipt can appear once.');}
        if (input['basis_mode'] == 'manual') {
          decimal(row['weight'], positive: true);
        }
      }
    }
    if (sealed &&
        (input['basis_hash'] is! String ||
            !RegExp(
              r'^[a-f0-9]{32}$',
            ).hasMatch(input['basis_hash'] as String))) {
      throw const FormatException(
        'Refresh the exact allocation preview first.',
      );
    }
  }

  static void validateEvidence(
    Map<String, Object?> result,
    Map<String, Object?>? input,
  ) {
    identity(result['root_id']);
    if (result['correction_of'] != null) identity(result['correction_of']);
    if (!const {
          'quantity',
          'original_value',
          'manual',
        }.contains(result['basis_mode']) ||
        result['basis_hash'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(result['basis_hash'] as String)) {
      throw const FormatException('Allocation basis could not be verified.');
    }
    identity(result['offset_account_id']);
    identity(result['variance_account_id']);
    final receipts = result['receipts'], legs = result['legs'];
    if (receipts is! List ||
        receipts.isEmpty ||
        receipts.length > 50 ||
        legs is! List ||
        legs.length > 1000) {
      throw const FormatException('Allocation evidence exceeds its bounds.');
    }
    var target = ExactDecimal.zero(scale: 6),
        incremental = ExactDecimal.zero(scale: 6);
    final byId = <Object?, Map>{};
    for (final row in receipts) {
      if (row is! Map) {
        throw const FormatException('Receipt evidence is invalid.');
      }
      identity(row['receipt_line_id']);
      identity(row['product_id']);
      identity(row['inventory_account_id']);
      decimal(row['weight'], positive: true);
      if (byId.containsKey(row['receipt_line_id'])) {
        throw const FormatException('Receipt evidence repeats an identity.');
      }
      byId[row['receipt_line_id']] = row;
      final received = decimal(row['received_quantity'], positive: true);
      final held = decimal(row['held_quantity']),
          transit = decimal(row['transit_quantity']),
          consumed = decimal(row['consumed_quantity']);
      if (held.isNegative ||
          transit.isNegative ||
          consumed.isNegative ||
          received != held + transit + consumed) {
        throw const FormatException('Receipt quantities do not reconcile.');
      }
      final allocation = decimal(row['target_allocation']),
          delta = decimal(row['incremental_amount']);
      if (allocation.isNegative ||
          allocation - decimal(row['previous_allocation']) != delta) {
        throw const FormatException(
          'Receipt correction amount does not reconcile.',
        );
      }
      target = target + allocation;
      incremental = incremental + delta;
    }
    final categories = <String, ExactDecimal>{
      for (final kind in ['held', 'transit', 'consumed'])
        kind: ExactDecimal.zero(scale: 6),
    };
    final sums = <Object?, ExactDecimal>{};
    final quantities = <String, ExactDecimal>{};
    for (final leg in legs) {
      if (leg is! Map ||
          !categories.containsKey(leg['kind']) ||
          !byId.containsKey(leg['receipt_line_id'])) {
        throw const FormatException(
          'Allocation leg has an unknown receipt or disposition.',
        );
      }
      final row = byId[leg['receipt_line_id']]!;
      identity(leg['branch_id']);
      if (leg['product_id'] != row['product_id'] ||
          leg['inventory_account_id'] != row['inventory_account_id']) {
        throw const FormatException(
          'Allocation leg changed the receipt basis.',
        );
      }
      if (leg['kind'] == 'held') {
        identity(leg['warehouse_id']);
        identity(leg['valuation_id']);
      }
      if (leg['kind'] == 'transit') {
        identity(leg['transfer_id']);
        identity(leg['transfer_line_id']);
        identity(leg['destination_branch_id']);
      }
      final v = decimal(leg['value']), q = decimal(leg['quantity']);
      if (q.isNegative) {
        throw const FormatException('Allocation quantity is negative.');
      }
      categories[leg['kind'] as String] = categories[leg['kind']]! + v;
      sums[leg['receipt_line_id']] =
          (sums[leg['receipt_line_id']] ?? ExactDecimal.zero(scale: 6)) + v;
      final key = '${leg['receipt_line_id']}:${leg['kind']}';
      quantities[key] = (quantities[key] ?? ExactDecimal.zero(scale: 6)) + q;
    }
    for (final entry in byId.entries) {
      if ((sums[entry.key] ?? ExactDecimal.zero(scale: 6)) !=
          decimal(entry.value['incremental_amount'])) {
        throw const FormatException(
          'Receipt allocation legs do not reconcile.',
        );
      }
      for (final kind in categories.keys) {
        final field = kind == 'held'
            ? 'held_quantity'
            : kind == 'transit'
            ? 'transit_quantity'
            : 'consumed_quantity';
        if ((quantities['${entry.key}:$kind'] ?? ExactDecimal.zero(scale: 6)) !=
            decimal(entry.value[field])) {
          throw const FormatException(
            'Receipt allocation quantities do not reconcile.',
          );
        }
      }
    }
    if (target != decimal(result['total_amount']) ||
        incremental != decimal(result['amount']) ||
        incremental.isZero ||
        categories['held'] != decimal(result['inventory_amount']) ||
        categories['transit'] != decimal(result['transit_amount']) ||
        categories['consumed'] != decimal(result['variance_amount']) ||
        incremental !=
            categories['held']! +
                categories['transit']! +
                categories['consumed']!) {
      throw const FormatException('Allocation totals could not be verified.');
    }
    if (input != null) {
      if (result['correction_of'] != input['correction_of'] ||
          target != decimal(input['total_amount']) ||
          result['document_date'] != input['document_date']) {
        throw const FormatException('Allocation request identity changed.');
      }
      if (input['correction_of'] == null) {
        final requested = (input['receipts'] as List)
            .map((r) => (r as Map)['receipt_line_id'])
            .toSet();
        if (requested.length != byId.length ||
            !requested.containsAll(byId.keys) ||
            result['basis_mode'] != input['basis_mode'] ||
            result['root_id'] != input['id'] ||
            result['offset_account_id'] != input['offset_account_id'] ||
            result['variance_account_id'] != input['variance_account_id']) {
          throw const FormatException('Allocation receipt selection changed.');
        }
        if (input['basis_mode'] == 'manual') {
          for (final raw in input['receipts'] as List) {
            final row = raw as Map;
            if (decimal(row['weight']) != decimal(byId[row['receipt_line_id']]!['weight'])) {
              throw const FormatException('The requested manual allocation weight changed.');
            }
          }
        }
      }
    }
  }
}
