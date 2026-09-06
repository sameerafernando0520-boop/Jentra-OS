import 'package:test/test.dart';
import 'package:jentra_domain/jentra_domain.dart';

void main() {
  test(
    'AC-303 draft codec preserves exact inputs and stable line identities',
    () {
      final draft = QuotationDraftCodec.fromJson(input());
      expect(draft.validate().isValid, isTrue);
      expect(draft.toJson(), input());
      expect(
        draft.lines.single.unitPrice.toDecimalString(),
        '90071992547409.123456',
      );
    },
  );

  test('AC-303 draft codec rejects numeric JSON and excess precision', () {
    final numeric = input()..['exchange_rate'] = 1.0;
    expect(() => QuotationDraftCodec.fromJson(numeric), throwsFormatException);
    final precise = input()..['exchange_rate'] = '1.00000000001';
    expect(() => QuotationDraftCodec.fromJson(precise), throwsFormatException);
  });

  test(
    'AC-303 server snapshots reconstruct discounts without double application',
    () {
      final snapshot = input()
        ..['header_discount_amount'] = '0.000000'
        ..['header_discount_percent'] = '10.000000'
        ..['lines'] = [
          {
            ...(input()['lines'] as List).single as Map<String, Object?>,
            'id': 'line-1',
            'line_discount_amount': '9.000000',
            'discount_percent': '5.000000',
            'tax_rate': '15.000000',
            'tax_inclusive': true,
            'tax_code': 'VAT',
            'tax_name': 'Output VAT',
            'tax_kind': 'output',
            'tax_definition_id': 'tax-1',
            'tax_definition_version': 2,
          },
        ];
      final draft = QuotationDraftCodec.fromSnapshot(snapshot);
      expect(draft.headerDiscountAmount, isNull);
      expect(draft.lines.single.discountAmount, isNull);
      expect(draft.lines.single.previewTax?.inclusive, isTrue);
      expect(draft.lines.single.previewTax?.definitionVersion, 2);
    },
  );

  test('AC-303 quotation paging is bounded and rejects malformed cursors', () {
    expect(QuotationListQuery(search: '  ACME  ').search, 'ACME');
    expect(() => QuotationListQuery(limit: 201), throwsRangeError);
    expect(() => QuotationListQuery(limit: 0), throwsRangeError);
    expect(() => QuotationListQuery(cursor: 'bad'), throwsFormatException);
  });

  test('AC-303 recall is explicit and requires a reason', () {
    final command = OperationalDocumentTransition(
      documentType: OperationalDocumentType.salesQuotation,
      documentId: 'quote-1',
      action: OperationalDocumentAction.recall,
    );
    expect(command.toJson()['action'], 'recall');
    expect(command.validate().isValid, isFalse);
  });

  test(
    'AC-303 malformed revision flags cannot silently change command intent',
    () {
      expect(
        () =>
            QuotationDraftCodec.fromJson(input()..['create_revision'] = 'true'),
        throwsFormatException,
      );
    },
  );

  test('AC-303 malformed tax flags cannot silently change tax treatment', () {
    final snapshot = input()
      ..['lines'] = [
        {
          ...(input()['lines'] as List).single as Map<String, Object?>,
          'id': 'line-1',
          'tax_definition_id': 'tax-1',
          'tax_code': 'VAT',
          'tax_name': 'VAT',
          'tax_kind': 'output',
          'tax_rate': '15.000000',
          'tax_definition_version': 1,
          'tax_inclusive': 'true',
        },
      ];
    expect(
      () => QuotationDraftCodec.fromSnapshot(snapshot),
      throwsFormatException,
    );
  });
}

Map<String, Object?> input() => {
  'id': 'quote-1',
  'customer_id': 'customer-1',
  'quotation_date': '2026-09-06',
  'valid_until': '2026-10-06',
  'currency_code': 'LKR',
  'exchange_rate': '1.0000000000',
  'rate_date': '2026-09-06',
  'payment_terms_days': 30,
  'salesperson_id': 'seller-1',
  'create_revision': false,
  'lines': [
    {
      'line_id': 'line-1',
      'product_id': 'product-1',
      'description': 'Exact quotation',
      'unit_id': 'unit-1',
      'quantity': '1.000000',
      'base_quantity': '1.000000',
      'conversion_numerator': '1',
      'conversion_denominator': '1',
      'unit_price': '90071992547409.123456',
    },
  ],
};
