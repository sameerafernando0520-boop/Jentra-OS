import 'dart:convert';
import 'commands.dart';
import 'lead_to_cash.dart';
import 'money.dart';
import 'pagination.dart';
import 'quotation_workspace.dart';
import 'tenant_context.dart';

final class SalesOrderListQuery {
  SalesOrderListQuery({
    String search = '',
    this.status,
    this.cursor,
    this.sourceQuotationId,
    this.limit = 50,
  }) : search = search.trim() {
    QuotationListQuery(search: search, cursor: cursor, limit: limit);
    if (sourceQuotationId != null) {
      QuotationListQuery(cursor: sourceQuotationId);
    }
    if (status != null && !statuses.contains(status)) {
      throw const FormatException('Invalid sales order status.');
    }
  }
  static const statuses = {
    'draft',
    'credit_hold',
    'confirmed',
    'partially_reserved',
    'reserved',
    'partially_delivered',
    'delivered',
    'cancelled',
  };
  final String search;
  final String? status, cursor, sourceQuotationId;
  final int limit;
}

abstract final class SalesOrderDraftCodec {
  static SalesOrderDraft fromJson(Map<String, Object?> json) {
    final quote = QuotationDraftCodec.fromJson({
      ...json,
      'quotation_date': json['order_date'],
      'valid_until': json['promised_date'],
      'salesperson_id': 'server-derived',
      'create_revision': false,
    });
    final shipTo = json['ship_to'];
    if (shipTo is! Map || json['warehouse_id'] is! String) {
      throw const FormatException(
        'Choose a warehouse and enter a ship-to address.',
      );
    }
    return SalesOrderDraft(
      id: quote.id,
      customerId: quote.customerId,
      contactId: quote.contactId,
      orderDate: quote.quotationDate,
      promisedDate: quote.validUntil,
      currencyCode: quote.currencyCode,
      exchangeRate: quote.exchangeRate,
      exchangeRateId: quote.exchangeRateId,
      rateDate: quote.rateDate,
      warehouseId: json['warehouse_id']! as String,
      shipTo: shipTo.cast<String, Object?>(),
      paymentTermsDays: quote.paymentTermsDays,
      deliveryTerms: quote.deliveryTerms,
      headerDiscountAmount: quote.headerDiscountAmount,
      headerDiscountPercent: quote.headerDiscountPercent,
      notes: quote.notes,
      lines: quote.lines,
    );
  }

  static SalesOrderDraft fromSnapshot(Map<String, Object?> json) {
    final quote = QuotationDraftCodec.fromSnapshot({
      ...json,
      'quotation_date': json['order_date'],
      'valid_until': json['promised_date'],
      'salesperson_id': 'server-derived',
      'lines': [
        for (final raw in json['lines']! as List)
          {
            ...(raw as Map).cast<String, Object?>(),
            'quantity': raw['ordered_quantity'],
            'base_quantity': raw['base_ordered_quantity'],
          },
      ],
    });
    return fromJson({
      ...quote.toJson(),
      'order_date': json['order_date'],
      'promised_date': json['promised_date'],
      'warehouse_id': json['warehouse_id'],
      'ship_to': json['ship_to'],
    });
  }
}

/// One caller-RLS snapshot, including all commercial and fulfillment quantities.
final class SalesOrderDetail {
  SalesOrderDetail.fromJson(Map<String, Object?> json)
    : order = SalesOrder.fromJson(json),
      draft = SalesOrderDraftCodec.fromSnapshot(json),
      _encoded = jsonEncode(json) {
    if (json['lines'] is! List) {
      throw const FormatException('Missing coherent order lines.');
    }
  }
  final SalesOrder order;
  final SalesOrderDraft draft;
  final String _encoded;
  Map<String, Object?> get snapshot =>
      (jsonDecode(_encoded) as Map).cast<String, Object?>();
  bool get canEdit => const {'draft', 'credit_hold'}.contains(order.status);
  bool get converted => order.sourceQuotationId != null;
}

final class SalesOrderCreditPreview {
  SalesOrderCreditPreview.fromJson(Map<String, Object?> json)
    : orderId = json['sales_order_id']! as String,
      orderVersion = json['order_version']! as int,
      creditLimit = _money(
        json,
        'credit_limit',
        json['credit_currency_code']! as String,
      ),
      dueExposure = _money(
        json,
        'due_exposure',
        json['currency_code']! as String,
      ),
      overdueExposure = _money(
        json,
        'overdue_exposure',
        json['currency_code']! as String,
      ),
      existingOrderExposure = _money(
        json,
        'existing_order_exposure',
        json['currency_code']! as String,
      ),
      currentOrderExposure = _money(
        json,
        'current_order_exposure',
        json['currency_code']! as String,
      ),
      totalExposure = _money(
        json,
        'total_exposure',
        json['currency_code']! as String,
      ),
      projectionAvailable = json['projection_available']! as bool,
      checkedAt = DateTime.parse(json['checked_at']! as String),
      asOf = json['credit_as_of_at'] == null
          ? null
          : DateTime.parse(json['credit_as_of_at']! as String),
      reason = json['reason'] as String? {
    if (totalExposure !=
        dueExposure + existingOrderExposure + currentOrderExposure) {
      throw const FormatException(
        'Credit exposure components do not reconcile.',
      );
    }
  }
  final String orderId;
  final int orderVersion;
  final Money creditLimit,
      dueExposure,
      overdueExposure,
      existingOrderExposure,
      currentOrderExposure,
      totalExposure;
  final bool projectionAvailable;
  final DateTime checkedAt;
  final DateTime? asOf;
  final String? reason;
  static Money _money(Map<String, Object?> json, String key, String currency) {
    final value = json[key];
    if (value is! String ||
        !RegExp(r'^-?[0-9]+(?:\.[0-9]{1,6})?$').hasMatch(value)) {
      throw FormatException('$key must be an exact six-place amount.');
    }
    return Money.parse(value, currency);
  }
}

abstract interface class SalesOrderWorkspaceRepository {
  Future<CursorPage<SalesOrder>> pageOrders({
    required TenantContext context,
    required SalesOrderListQuery query,
  });
  Future<SalesOrderDetail?> loadOrder({
    required TenantContext context,
    required String id,
  });
  Future<SalesOrderCreditPreview> creditPreview({
    required TenantContext context,
    required String id,
  });
  Future<List<Map<String, Object?>>> creditDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  });
  Future<List<Map<String, Object?>>> reservations({
    required TenantContext context,
    required String id,
    String? afterId,
  });
  Future<List<Map<String, Object?>>> availability({
    required TenantContext context,
    required String warehouseId,
    required List<String> productIds,
  });
  Future<CommandResult<SalesOrder>> executeOrder(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
