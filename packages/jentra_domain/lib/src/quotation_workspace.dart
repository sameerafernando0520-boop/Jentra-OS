import 'exact_decimal.dart';
import 'lead_to_cash.dart';
import 'money.dart';
import 'pagination.dart';
import 'tenant_context.dart';

/// Literal filters and an ID keyset cursor; never an unbounded quotation read.
final class QuotationListQuery {
  QuotationListQuery({
    String search = '',
    this.status,
    this.cursor,
    this.limit = 50,
  }) : search = search.trim() {
    if (limit < 1 || limit > 200) {
      throw RangeError.range(limit, 1, 200, 'limit');
    }
    if (cursor != null &&
        !RegExp(
          r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
        ).hasMatch(cursor!)) {
      throw const FormatException('Invalid quotation cursor.');
    }
    if (this.search.length > 200) {
      throw const FormatException('Search is too long.');
    }
    if (status != null &&
        !const {
          'draft',
          'submitted',
          'pending_approval',
          'approved',
          'rejected',
          'accepted',
          'expired',
          'cancelled',
          'converted',
        }.contains(status)) {
      throw const FormatException('Invalid quotation status.');
    }
  }
  final String search;
  final String? status;
  final String? cursor;
  final int limit;
}

/// Decodes both persisted command inputs and immutable server snapshots. No
/// numeric coercion or silent rounding is allowed at this financial boundary.
abstract final class QuotationDraftCodec {
  static QuotationDraft fromJson(Map<String, Object?> json) =>
      _decode(json, false);
  static QuotationDraft fromSnapshot(Map<String, Object?> json) =>
      _decode(json, true);

  static QuotationDraft _decode(Map<String, Object?> json, bool snapshot) {
    final currency = _text(json, 'currency_code');
    final rawLines = json['lines'];
    if (rawLines is! List || rawLines.length > 500) {
      throw const FormatException('Expected at most 500 quotation lines.');
    }
    final headerPercent = json['header_discount_percent'];
    return QuotationDraft(
      id: _optionalText(json, 'id'),
      customerId: _text(json, 'customer_id'),
      contactId: _optionalText(json, 'contact_id'),
      opportunityId: _optionalText(json, 'opportunity_id'),
      quotationDate: _date(json, 'quotation_date'),
      validUntil: _date(json, 'valid_until'),
      currencyCode: currency,
      exchangeRateId: _optionalText(json, 'exchange_rate_id'),
      exchangeRate: _decimal(json, 'exchange_rate', 10),
      rateDate: _date(json, 'rate_date'),
      paymentTermsDays: _integer(json, 'payment_terms_days', fallback: 0),
      deliveryTerms: _optionalText(json, 'delivery_terms'),
      salespersonId: _text(json, 'salesperson_id'),
      headerDiscountAmount:
          (snapshot && headerPercent != null) ||
              json['header_discount_amount'] == null
          ? null
          : _money(json, 'header_discount_amount', currency),
      headerDiscountPercent: headerPercent == null
          ? null
          : _decimal(json, 'header_discount_percent', 6),
      notes: _optionalText(json, 'notes'),
      createRevision:
          !snapshot && _boolean(json, 'create_revision', fallback: false),
      revisionReason: _optionalText(json, 'revision_reason'),
      lines: List.unmodifiable(
        rawLines.map((raw) {
          if (raw is! Map) {
            throw const FormatException('Expected a quotation line.');
          }
          final line = raw.cast<String, Object?>();
          final percent = line['discount_percent'];
          final amountKey = snapshot
              ? 'line_discount_amount'
              : 'discount_amount';
          final taxId = _optionalText(line, 'tax_definition_id');
          return QuotationLineDraft(
            lineId: _text(line, snapshot ? 'id' : 'line_id'),
            productId: _optionalText(line, 'product_id'),
            description: _text(line, 'description'),
            quantity: CommercialQuantity(
              quantity: _decimal(line, 'quantity', 6),
              unitId: _text(line, 'unit_id'),
              baseQuantity: _decimal(line, 'base_quantity', 6),
              conversionNumerator: _positiveInteger(
                line,
                'conversion_numerator',
              ),
              conversionDenominator: _positiveInteger(
                line,
                'conversion_denominator',
              ),
            ),
            unitPrice: _money(line, 'unit_price', currency),
            discountAmount:
                (snapshot && percent != null) || line[amountKey] == null
                ? null
                : _money(line, amountKey, currency),
            discountPercent: percent == null
                ? null
                : _decimal(line, 'discount_percent', 6),
            taxDefinitionId: taxId,
            previewTax: !snapshot || taxId == null
                ? null
                : QuotationTaxSnapshot(
                    definitionId: taxId,
                    code: _text(line, 'tax_code'),
                    name: _text(line, 'tax_name'),
                    kind: _text(line, 'tax_kind'),
                    rate: _decimal(line, 'tax_rate', 6),
                    inclusive: _boolean(line, 'tax_inclusive'),
                    definitionVersion: _integer(line, 'tax_definition_version'),
                  ),
          );
        }),
      ),
    );
  }

  static String _text(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String) throw FormatException('$key must be a string.');
    return value;
  }

  static String? _optionalText(Map<String, Object?> json, String key) =>
      json[key] == null ? null : _text(json, key);
  static bool _boolean(
    Map<String, Object?> json,
    String key, {
    bool? fallback,
  }) {
    final value = json[key] ?? fallback;
    if (value is! bool) throw FormatException('$key must be a boolean.');
    return value;
  }

  static int _integer(Map<String, Object?> json, String key, {int? fallback}) {
    final value = json[key] ?? fallback;
    if (value is! int) throw FormatException('$key must be an integer.');
    return value;
  }

  static DateTime _date(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw FormatException('$key must be a date.');
    }
    final result = DateTime.parse('${value}T00:00:00Z');
    if (result.toIso8601String().substring(0, 10) != value) {
      throw FormatException('$key is not a valid date.');
    }
    return result;
  }

  static ExactDecimal _decimal(
    Map<String, Object?> json,
    String key,
    int scale,
  ) {
    final value = _text(json, key);
    if (!RegExp('^-?[0-9]+(?:\\.[0-9]{1,$scale})?\$').hasMatch(value)) {
      throw FormatException(
        '$key must be an exact decimal with at most $scale places.',
      );
    }
    return ExactDecimal.parse(value, scale: scale);
  }

  static Money _money(Map<String, Object?> json, String key, String currency) =>
      Money.fromMinorUnits(_decimal(json, key, 6).scaledValue, currency);
  static BigInt _positiveInteger(Map<String, Object?> json, String key) {
    final value = _text(json, key);
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(value)) {
      throw FormatException('$key must be a positive integer string.');
    }
    return BigInt.parse(value);
  }
}

final class QuotationDetail {
  QuotationDetail.fromJson(Map<String, Object?> json)
    : quotation = SalesQuotation.fromJson(json),
      draft = QuotationDraftCodec.fromSnapshot(json),
      snapshot = Map.unmodifiable(json);
  final SalesQuotation quotation;
  final QuotationDraft draft;
  final Map<String, Object?> snapshot;
}

/// Additive workspace read contract. Existing lead-to-cash consumers remain valid.
abstract interface class QuotationWorkspaceRepository {
  Future<CursorPage<SalesQuotation>> pageQuotations({
    required TenantContext context,
    required QuotationListQuery query,
  });
  Future<QuotationDetail?> loadQuotationDetail({
    required TenantContext context,
    required String id,
  });
  Future<List<SalesQuotationRevision>> quotationRevisions({
    required TenantContext context,
    required String id,
    int beforeRevision = 2147483647,
  });
  Future<List<Map<String, Object?>>> quotationDecisions({
    required TenantContext context,
    required String id,
    String? beforeId,
  });
}
