import 'package:jentra_domain/jentra_domain.dart';

final class SalesFailure implements Exception {
  const SalesFailure(this.code, this.message);
  final String code, message;
}

enum SalesPage { today, customers, orders, catalogue, visits, deliveries, more }

final class SalesCustomer {
  const SalesCustomer({
    required this.id,
    required this.name,
    required this.area,
    required this.contact,
    required this.email,
    required this.address,
    required this.terms,
    required this.initials,
    required this.outstanding,
  });
  final String id, name, area, contact, email, address, terms, initials;
  final String outstanding;
}

final class SalesProduct {
  const SalesProduct({
    required this.id,
    required this.name,
    required this.code,
    required this.category,
    required this.unit,
    required this.price,
    required this.availability,
    required this.symbol,
  });
  final String id, name, code, category, unit, price, availability, symbol;
}

final class SalesLine {
  const SalesLine(this.product, this.quantity);
  final SalesProduct product;
  final String quantity;
  ExactDecimal get total {
    final q = parseQuantity(quantity);
    final p = ExactDecimal.parse(product.price, scale: 2);
    final raw = q.scaledValue * p.scaledValue;
    final divisor = BigInt.from(1000);
    return ExactDecimal.fromScaledValue(
      (raw + divisor ~/ BigInt.two) ~/ divisor,
      scale: 2,
    );
  }

  Map<String, Object> toJson() => {
    'product_id': product.id,
    'quantity': quantity,
  };
}

ExactDecimal parseQuantity(String input) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,3})?$').hasMatch(input) || input.length > 11) {
    throw const FormatException(
      'Use a positive quantity with up to 3 decimals.',
    );
  }
  final value = ExactDecimal.parse(input, scale: 3);
  if (!value.isPositive) {
    throw const FormatException('Quantity must be greater than zero.');
  }
  return value;
}

ExactDecimal parseDiscount(String input) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,2})?$').hasMatch(input)) {
    throw const FormatException(
      'Use a percentage from 0 to 100, with up to 2 decimals.',
    );
  }
  final value = ExactDecimal.parse(input, scale: 2);
  if (value.isNegative ||
      value.compareTo(ExactDecimal.parse('100', scale: 2)) > 0) {
    throw const FormatException('Use a percentage from 0 to 100.');
  }
  return value;
}

final class SalesOrder {
  const SalesOrder({
    required this.id,
    required this.customerId,
    required this.date,
    required this.lines,
    required this.customerState,
    required this.companyState,
    required this.deliveryState,
    this.reference = '',
    this.notes = '',
    this.discount = '0',
    this.discountReason = '',
    this.local = false,
    this.commandId = '',
    this.requestedDate = '',
  });
  final String id, customerId, customerState, companyState, deliveryState;
  final String reference,
      notes,
      discount,
      discountReason,
      commandId,
      requestedDate;
  final DateTime date;
  final List<SalesLine> lines;
  final bool local;
  ExactDecimal get subtotal =>
      lines.fold(ExactDecimal.zero(scale: 2), (sum, line) => sum + line.total);
  String get status => local
      ? 'Local draft'
      : companyState == 'Review required'
      ? 'Company review'
      : customerState == 'Awaiting response'
      ? 'Awaiting customer'
      : deliveryState == 'Dispatched'
      ? 'Dispatched'
      : deliveryState == 'Partial delivery'
      ? 'Partial delivery'
      : 'In progress';
  Map<String, Object> toJson() => {
    'schema': 1,
    'id': id,
    'customer_id': customerId,
    'date': date.toUtc().toIso8601String(),
    'lines': lines.map((l) => l.toJson()).toList(),
    'reference': reference,
    'notes': notes,
    'discount': discount,
    'discount_reason': discountReason,
    'command_id': commandId,
    'requested_date': requestedDate,
  };
  static SalesOrder fromDraft(
    Map<String, dynamic> value,
    List<SalesProduct> products,
  ) {
    if (value['schema'] != 1 ||
        value['lines'] is! List ||
        (value['lines'] as List).length > 100) {
      throw const FormatException('Unsupported saved draft.');
    }
    final lines = (value['lines'] as List).map((raw) {
      final v = raw as Map;
      final p = products.where((p) => p.id == v['product_id']).firstOrNull;
      if (p == null || v['quantity'] is! String) {
        throw const FormatException('Catalogue changed.');
      }
      parseQuantity(v['quantity'] as String);
      return SalesLine(p, v['quantity'] as String);
    }).toList();
    parseDiscount(value['discount'] as String);
    return SalesOrder(
      id: value['id'] as String,
      customerId: value['customer_id'] as String,
      date: DateTime.parse(value['date'] as String),
      lines: List.unmodifiable(lines),
      customerState: 'Not requested',
      companyState: 'Not submitted',
      deliveryState: 'Not scheduled',
      reference: value['reference'] as String,
      notes: value['notes'] as String,
      discount: value['discount'] as String,
      discountReason: value['discount_reason'] as String,
      requestedDate: value['requested_date'] as String,
      commandId: value['command_id'] as String,
      local: true,
    );
  }
}

final class SalesVisit {
  const SalesVisit({
    required this.id,
    required this.customerId,
    required this.time,
    required this.purpose,
    required this.state,
    this.note = '',
  });
  final String id, customerId, time, purpose, state, note;
  SalesVisit complete(String note) => SalesVisit(
    id: id,
    customerId: customerId,
    time: time,
    purpose: purpose,
    state: 'Completed',
    note: note,
  );
}

String money(String value) {
  final parts = ExactDecimal.parse(
    value,
    scale: 2,
  ).toDecimalString().split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'LKR $whole.${parts[1]}';
}
