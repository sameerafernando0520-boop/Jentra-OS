import 'dart:convert';
import '../jentra_domain.dart';

bool canReadStockOpenings(Set<String> capabilities) =>
    capabilities.contains('inventory.cost.view') &&
    {
      'inventory.adjustments.post',
      'workflow.approvals.decide',
    }.any(capabilities.contains);

Map<String, Object?> openingMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected an opening object.');
  return value.cast<String, Object?>();
}

ExactDecimal openingDecimal(Object? value) {
  if (value is! String ||
      !RegExp(r'^[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(value)) {
    throw const FormatException('Use an exact positive decimal string.');
  }
  final number = ExactDecimal.parse(value, scale: 6);
  if (number.compareTo(ExactDecimal.parse('99999999999999.999999', scale: 6)) >
      0) {
    throw const FormatException('Value exceeds opening limit.');
  }
  return number;
}

bool openingDate(String value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse(value)?.toIso8601String().substring(0, 10) == value;

/// User-entered values remain strings. The server owns mappings and posted totals.
final class StockOpeningDraft {
  StockOpeningDraft(Map<String, Object?> json) : _json = jsonEncode(json);
  final String _json;
  Map<String, Object?> toJson() => openingMap(jsonDecode(_json));
  ExactDecimal get total => (toJson()['lines'] as List? ?? []).fold(
    ExactDecimal.zero(scale: 6),
    (sum, line) => sum + openingDecimal(openingMap(line)['base_value']),
  );
  Map<String, String> validate() {
    final data = toJson(), errors = <String, String>{};
    for (final field in ['id', 'warehouse_id', 'offset_account_id']) {
      if (data[field] is! String || '${data[field]}'.trim().isEmpty) {
        errors[field] = 'Choose a value';
      }
    }
    if (!openingDate('${data['document_date']}')) {
      errors['document_date'] = 'Use a valid YYYY-MM-DD date';
    }
    final reason = '${data['reason'] ?? ''}'.trim();
    if (reason.length < 3 || reason.length > 1000) {
      errors['reason'] = 'Use 3 to 1000 characters';
    }
    final lines = data['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 100) {
      errors['lines'] = 'Add 1 to 100 counted product lines';
      return errors;
    }
    final ids = <String>{}, productLots = <String>{};
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] is! Map) {
        errors['line.$i'] = 'Invalid line';
        continue;
      }
      final line = openingMap(lines[i]);
      if (line['line_id'] is! String || !ids.add('${line['line_id']}')) {
        errors['line.$i'] = 'Duplicate or missing line identity';
      }
      if (line['product_id'] is! String) {
        errors['product.$i'] = 'Choose a stocked product';
      }
      for (final field in ['base_quantity', 'base_value']) {
        try {
          if (!openingDecimal(line[field]).isPositive) {
            errors['$field.$i'] = 'Enter a positive value';
          }
        } on FormatException {
          errors['$field.$i'] = 'Use a positive decimal with up to six places';
        }
      }
      final tracking = line['tracking_mode'] ?? 'none';
      final lot = '${line['lot_code'] ?? ''}'.trim();
      final rawSerials = line['serial_codes'] ?? <Object?>[];
      final serials = rawSerials is List ? rawSerials : <Object?>[];
      if (rawSerials is! List || serials.length > 500) {
        errors['tracking.$i'] = 'Use at most 500 serial codes';
      }
      if (!productLots.add(
        '${line['product_id']}:${tracking == 'lot' ? lot : ''}',
      )) {
        errors['product.$i'] = 'Combine duplicate product and lot lines';
      }
      if (tracking == 'lot') {
        if (lot.isEmpty || lot.length > 100 || serials.isNotEmpty) {
          errors['tracking.$i'] = 'Enter a lot code (up to 100 characters)';
        }
        for (final field in ['manufacture_date', 'expiry_date']) {
          if (line[field] != null && !openingDate('${line[field]}')) {
            errors['$field.$i'] = 'Use a valid YYYY-MM-DD date';
          }
        }
      } else if (tracking == 'serial') {
        if (lot.isNotEmpty ||
            serials.any(
              (s) => s is! String || s.trim().isEmpty || s.trim().length > 100,
            ) ||
            serials.map((s) => '$s'.trim()).toSet().length != serials.length) {
          errors['tracking.$i'] = 'Enter distinct serial codes, one per unit';
        }
        try {
          if (openingDecimal(line['base_quantity']) !=
              ExactDecimal.parse('${serials.length}', scale: 6)) {
            errors['tracking.$i'] =
                'Serial count must equal the whole-unit quantity';
          }
        } on FormatException {
          errors['tracking.$i'] =
              'Serial count must equal the whole-unit quantity';
        }
      } else if (tracking != 'none' || lot.isNotEmpty || serials.isNotEmpty) {
        errors['tracking.$i'] =
            'This product does not use lot or serial tracking';
      }
    }
    try {
      openingDecimal(total.toDecimalString());
    } on FormatException {
      errors['total'] = 'Check line values and the total';
    }
    return errors;
  }
}

final class StockOpeningDocument {
  StockOpeningDocument(Map<String, Object?> json) : _json = jsonEncode(json) {
    for (final field in [
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'warehouse_id',
      'offset_account_id',
      'status',
      'currency_code',
      'document_date',
    ]) {
      if (data[field] is! String) throw FormatException('Invalid $field');
    }
    if (data['document_type'] != 'stock_opening' ||
        data['version'] is! int ||
        (data['version']! as int) < 1 ||
        !{
          'draft',
          'pending_approval',
          'approved',
          'rejected',
          'cancelled',
          'posted',
        }.contains(data['status'])) {
      throw const FormatException('Invalid opening state');
    }
    openingDecimal(data['grand_total']);
    if (data['lines'] is! List || lines.isEmpty) {
      throw const FormatException('Opening lines are required');
    }
    for (final line in lines) {
      openingDecimal(line['base_quantity']);
      openingDecimal(line['base_value']);
    }
  }
  final String _json;
  Map<String, Object?> get data => openingMap(jsonDecode(_json));
  String get id => data['id']! as String;
  int get version => data['version']! as int;
  String get status => data['status']! as String;
  String get number => data['document_number'] as String? ?? 'Draft opening';
  String get currency => data['currency_code']! as String;
  String get total => data['grand_total']! as String;
  List<Map<String, Object?>> get lines =>
      (data['lines']! as List).map(openingMap).toList();
  bool get editable => status == 'draft';
  bool preparedBy(String actor) => [
    'created_by',
    'prepared_by',
    'submitted_by',
  ].any((f) => data[f] == actor);
  Map<String, Object?> toDraft() => data;
}

final class StockOpeningFailure implements Exception {
  const StockOpeningFailure(this.code, this.message, {this.definite = false});
  final String code, message;
  final bool definite;
  @override
  String toString() => '$code: $message';
}

abstract interface class StockOpeningRepository {
  Future<CursorPage<StockOpeningDocument>> page(
    TenantContext scope, {
    String? cursor,
    String? status,
  });
  Future<StockOpeningDocument> find(TenantContext scope, String id);
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> envelope,
  );
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? id,
  });
}
