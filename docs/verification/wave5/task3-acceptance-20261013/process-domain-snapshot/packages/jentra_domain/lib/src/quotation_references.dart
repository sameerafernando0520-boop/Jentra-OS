import 'pagination.dart';
import 'tenant_context.dart';

enum QuotationReferenceKind {
  customer,
  contact,
  currency,
  exchangeRate,
  product,
  unit,
  tax,
  opportunity,
  warehouse,
}

final class QuotationReferenceQuery {
  QuotationReferenceQuery({
    String search = '',
    this.cursor,
    this.limit = 25,
    this.id,
    this.customerId,
    this.fromCurrency,
    this.toCurrency,
  }) : search = search.trim() {
    if (limit < 1 || limit > 199) {
      throw RangeError.range(limit, 1, 199, 'limit');
    }
    if (this.search.length > 200) {
      throw const FormatException('Search is too long.');
    }
    if (cursor != null &&
        !RegExp(
          r'^(?:[A-Z]{3}|[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})$',
        ).hasMatch(cursor!)) {
      throw const FormatException('Invalid reference cursor.');
    }
  }
  final String search;
  final String? cursor, id, customerId, fromCurrency, toCurrency;
  final int limit;
}

final class QuotationReference {
  QuotationReference({
    required this.id,
    required this.label,
    required Map<String, Object?> values,
  }) : values = Map.unmodifiable(values);
  final String id, label;
  final Map<String, Object?> values;
}

abstract interface class QuotationReferenceRepository {
  Future<CursorPage<QuotationReference>> pageReferences({
    required TenantContext context,
    required QuotationReferenceKind kind,
    required QuotationReferenceQuery query,
  });
}
