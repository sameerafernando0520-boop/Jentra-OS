import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_finance_opening.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

const _headers = [
  'external_document_key',
  'party_code',
  'document_number',
  'document_date',
  'due_date',
  'currency',
  'outstanding_amount',
  'carrying_base_amount',
];

const _document = [
  'inv-1',
  'C001',
  'INV-0001',
  '2026-09-18',
  '2026-10-18',
  'USD',
  '9007199254.740993',
  '2500000000000.000001',
];

FinanceOpeningImportPreview _preview(
  List<List<String>> rows, {
  List<String> headers = _headers,
  String currency = 'USD',
}) => FinanceOpeningImportPreview.fromTable(
  TabularDocument(headers: headers, rows: rows),
  cutoffDate: CivilDate.parse('2026-10-31'),
  currencyCode: currency,
  baseCurrencyCode: 'LKR',
);

void main() {
  test(
    'retains exact outstanding and carrying values with the legacy due date',
    () {
      final result = _preview(
        [
          [..._document, '9007199300', '45.259007'],
          [
            'credit-1',
            'C001',
            'CN-0001',
            '2026-09-19',
            '2026-09-19',
            'USD',
            '-0.000001',
            '-0.000001',
            '',
            '',
          ],
        ],
        headers: [
          ..._headers,
          'legacy_original_amount',
          'legacy_settled_amount',
        ],
      );
      expect(result.issues, isEmpty);
      expect(result.isValid, isTrue);
      expect(result.outstandingTotal!.toDecimalString(), '9007199254.740992');
      expect(
        result.carryingBaseTotal!.toDecimalString(),
        '2500000000000.000000',
      );
      expect(result.lines.first.toPayload(), {
        'row_number': 2,
        'external_document_key': 'inv-1',
        'party_code': 'C001',
        'document_number': 'INV-0001',
        'document_date': '2026-09-18',
        'due_date': '2026-10-18',
        'currency': 'USD',
        'outstanding_amount': '9007199254.740993',
        'carrying_base_amount': '2500000000000.000001',
        'legacy_original_amount': '9007199300.000000',
        'legacy_settled_amount': '45.259007',
      });
      expect(
        result.lines.last.toPayload(),
        isNot(contains('legacy_original_amount')),
      );
    },
  );

  test(
    'reports the duplicate and invalid fields and withholds batch totals',
    () {
      final result = _preview([
        _document,
        [
          ' inv-1 ',
          ' C001 ',
          'INV-0002',
          '2026-11-01',
          '2026-02-30',
          'LKR',
          '1.0000001',
          '100000000000000',
        ],
        [
          'inv-2',
          'C002',
          'INV-0003',
          '2026-10-01',
          '2026-10-05',
          'USD',
          '1',
          '-1',
        ],
        [
          'inv-3',
          'C002',
          'INV-0004',
          '2026-10-01',
          '2026-11-05',
          'USD',
          '0',
          '0',
        ],
      ]);
      expect(result.isValid, isFalse);
      expect(result.outstandingTotal, isNull);
      expect(result.carryingBaseTotal, isNull);
      expect(
        result.issues.map((issue) => (issue.rowNumber, issue.field)),
        containsAll([
          (3, 'external_document_key'),
          (3, 'document_date'),
          (3, 'due_date'),
          (3, 'currency'),
          (3, 'outstanding_amount'),
          (3, 'carrying_base_amount'),
          (4, 'carrying_base_amount'),
          (5, 'outstanding_amount'),
        ]),
      );
    },
  );

  test(
    'rejects missing, duplicate and unrecognized columns without guessing',
    () {
      final result = _preview(
        [],
        headers: [..._headers.take(7), 'party_code', 'balance'],
      );
      expect(result.isValid, isFalse);
      expect(
        result.issues
            .where((issue) => issue.rowNumber == 1)
            .map((issue) => issue.field),
        containsAll(['party_code', 'balance', 'carrying_base_amount']),
      );
    },
  );

  test('rejects a row wider than the headers and a 501-row batch', () {
    expect(
      _preview([
        [..._document, 'extra cell'],
      ]).issues.single.rowNumber,
      2,
    );
    expect(_preview(List.filled(501, _document)).isValid, isFalse);
  });

  test('same currency cannot change carrying value', () {
    final result = _preview([
      [
        'bill-1',
        'S003',
        'BILL-03',
        '2026-10-18',
        '2026-11-30',
        'LKR',
        '10',
        '11',
      ],
    ], currency: 'LKR');
    expect(result.issues.single.field, 'carrying_base_amount');
  });
}
