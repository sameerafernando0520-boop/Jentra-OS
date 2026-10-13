import 'dart:convert';
import '../jentra_domain.dart';

enum ReceivableKind {
  delivery('delivery', 'deliveries', 'Deliveries', 'sales.deliveries'),
  invoice('sales_invoice', 'sales_invoices', 'Invoices', 'sales.invoices'),
  receipt(
    'customer_receipt',
    'customer_receipts',
    'Receipts',
    'finance.receipts',
  ),
  credit('sales_return', 'sales_returns', 'Returns & credits', 'sales.returns');

  const ReceivableKind(this.wire, this.view, this.label, this.permission);
  final String wire, view, label, permission;
  String get managePermission => '$permission.manage';
  String get postPermission => '$permission.post';
  bool canRead(Set<String> capabilities) => {
    '$permission.view',
    managePermission,
    postPermission,
    'workflow.approvals.decide',
  }.any(capabilities.contains);
}

Map<String, Object?> receivableMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected a document object.');
  return value.cast<String, Object?>();
}

ExactDecimal receivableDecimal(Object? value, {int scale = 6}) {
  if (value is! String ||
      !RegExp('^-?[0-9]+(?:\\.[0-9]{1,$scale})?\$').hasMatch(value)) {
    throw const FormatException('An exact decimal string is required.');
  }
  return ExactDecimal.parse(value, scale: scale);
}

bool receivableDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null && date.toIso8601String().substring(0, 10) == value;
}

/// A deep immutable wire payload. Pricing and residual authority stays server-side.
final class ReceivableDraft {
  ReceivableDraft(this.kind, Map<String, Object?> json)
    : _json = jsonEncode(json);
  final ReceivableKind kind;
  final String _json;
  Map<String, Object?> toJson() => receivableMap(jsonDecode(_json));
  Map<String, String> validate() {
    final data = toJson(), errors = <String, String>{};
    for (final field in ['id', 'customer_id', 'currency_code']) {
      if (data[field] is! String || (data[field]! as String).trim().isEmpty) {
        errors[field] = 'Required';
      }
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch('${data['currency_code']}')) {
      errors['currency_code'] = 'Choose a currency';
    }
    if (!receivableDate('${data['document_date']}')) {
      errors['document_date'] = 'Use a valid YYYY-MM-DD date';
    }
    if (data['due_date'] != null &&
        (!receivableDate('${data['due_date']}') ||
            '${data['due_date']}'.compareTo('${data['document_date']}') < 0)) {
      errors['due_date'] = 'Due date cannot precede document date';
    }
    if (kind == ReceivableKind.receipt) {
      if (data['cash_bank_account_id'] == null) {
        errors['cash_bank_account_id'] = 'Choose a cash or bank account';
      }
      try {
        if (!receivableDecimal(data['amount']).isPositive) {
          errors['amount'] = 'Enter a positive amount';
        }
      } on FormatException {
        errors['amount'] = 'Enter an exact amount (up to six decimals)';
      }
      return errors;
    }
    if (kind == ReceivableKind.delivery) {
      for (final field in ['sales_order_id', 'warehouse_id']) {
        if (data[field] == null) {
          errors[field] = 'Choose an order and its warehouse';
        }
      }
    }
    if (kind == ReceivableKind.credit &&
        '${data['reason'] ?? ''}'.trim().isEmpty) {
      errors['reason'] = 'Explain the return or credit';
    }
    final lines = data['lines'];
    if (lines is! List || lines.isEmpty || lines.length > 500) {
      errors['lines'] = 'Add 1 to 500 lines';
      return errors;
    }
    final ids = <String>{};
    for (var i = 0; i < lines.length; i++) {
      final line = receivableMap(lines[i]);
      if (line['line_id'] is! String || !ids.add(line['line_id']! as String)) {
        errors['line.$i'] = 'Line identity missing or duplicated';
      }
      try {
        if (!receivableDecimal(line['base_quantity']).isPositive) {
          errors['quantity.$i'] = 'Quantity must be positive';
        }
      } on FormatException {
        errors['quantity.$i'] = 'Use an exact quantity';
      }
      if (kind == ReceivableKind.credit) {
        if (line['sales_invoice_line_id'] == null &&
            line['delivery_line_id'] == null) {
          errors['source.$i'] = 'Choose the original invoice or delivery line';
        }
        if (!['saleable', 'no_restock'].contains(line['disposition'])) {
          errors['disposition.$i'] = 'Choose a disposition';
        }
      } else if (kind == ReceivableKind.delivery &&
          line['sales_order_line_id'] == null) {
        errors['source.$i'] = 'Choose an order line';
      } else if (kind == ReceivableKind.invoice &&
          line['sales_order_line_id'] == null &&
          line['delivery_line_id'] == null) {
        for (final field in [
          'product_id',
          'unit_id',
          'quantity',
          'unit_price',
          'conversion_numerator',
          'conversion_denominator',
        ]) {
          if (line[field] == null) {
            errors['$field.$i'] = 'Required for a direct service invoice';
          }
        }
        try {
          receivableDecimal(line['unit_price']);
        } on FormatException {
          errors['price.$i'] = 'Use an exact price';
        }
      }
    }
    return errors;
  }
}

final class ReceivableDocument {
  ReceivableDocument(Map<String, Object?> json) : _json = jsonEncode(json) {
    final d = data;
    for (final field in [
      'id',
      'document_type',
      'status',
      'customer_id',
      'currency_code',
      'document_date',
    ]) {
      if (d[field] is! String) throw FormatException('Invalid $field');
    }
    if (d['version'] is! int || (d['version']! as int) < 1) {
      throw const FormatException('Invalid version');
    }
    for (final field in ['grand_total', 'base_total', 'tax_total']) {
      receivableDecimal(d[field]);
    }
  }
  final String _json;
  Map<String, Object?> get data => receivableMap(jsonDecode(_json));
  String get id => data['id']! as String;
  int get version => data['version']! as int;
  String get status => data['status']! as String;
  String get number => data['document_number'] as String? ?? 'Draft';
  String get currency => data['currency_code']! as String;
  String get total => data['grand_total']! as String;
  List<Map<String, Object?>> get lines =>
      (data['lines'] as List? ?? []).map(receivableMap).toList();
  ReceivableKind get kind =>
      ReceivableKind.values.firstWhere((k) => k.wire == data['document_type']);
  bool get editable => status == 'draft';
  Map<String, Object?> toDraft() => {
    ...data,
    if (kind == ReceivableKind.receipt) 'amount': total,
    'lines': lines.map((line) => receivableMap(line['snapshot'])).toList(),
  };
}

/// Explicit confirmed database rejection versus potentially committed transport failure.
final class ReceivableFailure implements Exception {
  const ReceivableFailure(
    this.code,
    this.message, {
    this.definite = false,
    this.requestId,
  });
  final String code, message;
  final bool definite;
  final String? requestId;
  @override
  String toString() => '$code: $message';
}

abstract interface class ReceivablesRepository {
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext scope,
    ReceivableKind kind, {
    String? cursor,
    String? status,
  });
  Future<ReceivableDocument> find(
    TenantContext scope,
    ReceivableKind kind,
    String id,
  );
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> envelope,
  );
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? customerId,
    String? sourceId,
  });
  Future<Map<String, Object?>> statement(
    TenantContext scope,
    String customer,
    String currency,
    String asOf,
    List<int> buckets,
  );
}
