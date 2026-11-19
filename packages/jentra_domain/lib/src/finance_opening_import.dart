import 'employee.dart';
import 'money.dart';
import 'tabular_document.dart';

final class FinanceOpeningImportIssue {
  const FinanceOpeningImportIssue({
    required this.rowNumber,
    required this.field,
    required this.code,
    required this.message,
  });

  /// One-based row number, including the header. File issues use row 1.
  final int rowNumber;
  final String field;
  final String code;
  final String message;
}

/// A normalized, locally validated unpaid document at the selected cutoff.
final class FinanceOpeningImportLine {
  const FinanceOpeningImportLine._({
    required this.rowNumber,
    required this.externalDocumentKey,
    required this.partyCode,
    required this.documentNumber,
    required this.documentDate,
    required this.dueDate,
    required this.outstandingAmount,
    required this.carryingBaseAmount,
    required this.legacyOriginalAmount,
    required this.legacySettledAmount,
  });

  final int rowNumber;
  final String externalDocumentKey;
  final String partyCode;
  final String documentNumber;
  final CivilDate documentDate;
  final CivilDate dueDate;
  final Money outstandingAmount;
  final Money carryingBaseAmount;
  final Money? legacyOriginalAmount;
  final Money? legacySettledAmount;
  String get currencyCode => outstandingAmount.currencyCode;

  Map<String, Object?> toPayload() => {
    'row_number': rowNumber,
    'external_document_key': externalDocumentKey,
    'party_code': partyCode,
    'document_number': documentNumber,
    'document_date': documentDate.value,
    'due_date': dueDate.value,
    'currency': currencyCode,
    'outstanding_amount': outstandingAmount.toDecimalString(),
    'carrying_base_amount': carryingBaseAmount.toDecimalString(),
    if (legacyOriginalAmount case final amount?)
      'legacy_original_amount': amount.toDecimalString(),
    if (legacySettledAmount case final amount?)
      'legacy_settled_amount': amount.toDecimalString(),
  };
}

/// File-level validation. The server validates company references, authority
/// and duplicates against existing batches before accepting a draft or posting.
final class FinanceOpeningImportPreview {
  FinanceOpeningImportPreview._({
    required List<FinanceOpeningImportLine> lines,
    required List<FinanceOpeningImportIssue> issues,
    this.outstandingTotal,
    this.carryingBaseTotal,
  }) : lines = List.unmodifiable(lines),
       issues = List.unmodifiable(issues);

  factory FinanceOpeningImportPreview.fileIssue(
    FinanceOpeningImportIssue issue,
  ) => FinanceOpeningImportPreview._(lines: const [], issues: [issue]);

  static const maximumRows = 500;
  static const requiredHeaders = [
    'external_document_key',
    'party_code',
    'document_number',
    'document_date',
    'due_date',
    'currency',
    'outstanding_amount',
    'carrying_base_amount',
  ];
  static const optionalHeaders = [
    'legacy_original_amount',
    'legacy_settled_amount',
  ];
  static final _currency = RegExp(r'^[A-Za-z]{3}$');
  static final _party = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{1,31}$');
  static final _amount = RegExp(r'^-?[0-9]{1,14}(\.[0-9]{1,6})?$');
  static final _control = RegExp(r'[\x00-\x1F\x7F]');

  final List<FinanceOpeningImportLine> lines;
  final List<FinanceOpeningImportIssue> issues;

  /// Totals are available only when all rows are valid.
  final Money? outstandingTotal;
  final Money? carryingBaseTotal;

  bool get isValid => issues.isEmpty && lines.isNotEmpty;

  factory FinanceOpeningImportPreview.fromTable(
    TabularDocument table, {
    required CivilDate cutoffDate,
    required String currencyCode,
    required String baseCurrencyCode,
  }) {
    final currency = currencyCode.trim().toUpperCase();
    final baseCurrency = baseCurrencyCode.trim().toUpperCase();
    final issues = <FinanceOpeningImportIssue>[];
    final lines = <FinanceOpeningImportLine>[];

    void issue(int rowNumber, String field, String code, String message) {
      issues.add(
        FinanceOpeningImportIssue(
          rowNumber: rowNumber,
          field: field,
          code: code,
          message: message,
        ),
      );
    }

    final columns = <String, int>{};
    for (var index = 0; index < table.headers.length; index++) {
      final header = table.headers[index];
      if (columns.containsKey(header)) {
        issue(1, header, 'DUPLICATE_HEADER', 'Use this column only once.');
      } else if (!requiredHeaders.contains(header) &&
          !optionalHeaders.contains(header)) {
        issue(1, header, 'UNKNOWN_HEADER', 'This column is not supported.');
      }
      columns[header] = index;
    }
    for (final header in requiredHeaders) {
      if (!columns.containsKey(header)) {
        issue(1, header, 'MISSING_HEADER', 'Add this required column.');
      }
    }
    if (table.rowCount < 1 || table.rowCount > maximumRows) {
      issue(1, 'file', 'ROW_COUNT', 'Include 1 to 500 unpaid documents.');
    }
    if (!_currency.hasMatch(currencyCode.trim())) {
      issue(
        1,
        'currency',
        'INVALID_CURRENCY',
        'Select a three-letter currency.',
      );
    }
    if (!_currency.hasMatch(baseCurrencyCode.trim())) {
      issue(
        1,
        'carrying_base_amount',
        'INVALID_BASE_CURRENCY',
        'The company must have a three-letter base currency.',
      );
    }
    if (issues.isNotEmpty) {
      return FinanceOpeningImportPreview._(lines: lines, issues: issues);
    }

    var outstandingTotal = Money.zero(currency);
    var carryingBaseTotal = Money.zero(baseCurrency);
    final seen = <(String, String), int>{};
    for (var index = 0; index < table.rows.length; index++) {
      final row = table.rows[index];
      final rowNumber = index + 2;
      if (row.length != columns.length) {
        issue(
          rowNumber,
          'row',
          'COLUMN_COUNT_MISMATCH',
          'The number of cells must match the headers.',
        );
        continue;
      }
      final issueCount = issues.length;
      String cell(String field) {
        final column = columns[field];
        return column == null ? '' : row[column].trim();
      }

      void rowIssue(String field, String code, String message) =>
          issue(rowNumber, field, code, message);

      String reference(String field) {
        final value = cell(field);
        if (value.isEmpty ||
            value.runes.length > 140 ||
            _control.hasMatch(value)) {
          rowIssue(
            field,
            'INVALID_REFERENCE',
            'Use 1 to 140 printable characters.',
          );
        }
        return value;
      }

      CivilDate? date(String field) {
        try {
          return CivilDate.parse(cell(field));
        } on FormatException {
          rowIssue(field, 'INVALID_DATE', 'Use a valid YYYY-MM-DD date.');
          return null;
        }
      }

      Money? money(String field, String code, {bool optional = false}) {
        final value = cell(field);
        if (optional && value.isEmpty) return null;
        if (!_amount.hasMatch(value)) {
          rowIssue(
            field,
            'INVALID_AMOUNT',
            'Use a decimal with up to 14 whole and 6 fractional digits.',
          );
          return null;
        }
        final money = Money.parse(value, code);
        if (!optional && money.minorUnits == BigInt.zero) {
          rowIssue(field, 'ZERO_AMOUNT', 'Enter a nonzero remaining amount.');
        }
        return money;
      }

      final key = reference('external_document_key');
      final documentNumber = reference('document_number');
      final rawParty = cell('party_code');
      final party = rawParty.toUpperCase();
      if (!_party.hasMatch(rawParty)) {
        rowIssue(
          'party_code',
          'INVALID_PARTY_CODE',
          'Enter a valid party code.',
        );
      } else if (key.isNotEmpty &&
          key.runes.length <= 140 &&
          !_control.hasMatch(key)) {
        final firstRow = seen.putIfAbsent((party, key), () => rowNumber);
        if (firstRow != rowNumber) {
          rowIssue(
            'external_document_key',
            'DUPLICATE_DOCUMENT',
            'This party and external document key already appear on row $firstRow.',
          );
        }
      }

      final documentDate = date('document_date');
      if (documentDate != null && documentDate.compareTo(cutoffDate) > 0) {
        rowIssue(
          'document_date',
          'DOCUMENT_AFTER_CUTOFF',
          'The document date must be on or before the cutoff.',
        );
      }
      final dueDate = date('due_date');
      if (documentDate != null &&
          dueDate != null &&
          dueDate.compareTo(documentDate) < 0) {
        rowIssue(
          'due_date',
          'DUE_BEFORE_DOCUMENT',
          'The due date must be on or after the document date.',
        );
      }
      if (!_currency.hasMatch(cell('currency')) ||
          cell('currency').toUpperCase() != currency) {
        rowIssue('currency', 'CURRENCY_MISMATCH', 'This batch uses $currency.');
      }

      final outstanding = money('outstanding_amount', currency);
      final carrying = money('carrying_base_amount', baseCurrency);
      if (outstanding != null &&
          carrying != null &&
          outstanding.minorUnits.sign != 0 &&
          carrying.minorUnits.sign != 0) {
        if (outstanding.minorUnits.sign != carrying.minorUnits.sign) {
          rowIssue(
            'carrying_base_amount',
            'AMOUNT_SIGN_MISMATCH',
            'The carrying and outstanding amounts must have the same sign.',
          );
        } else if (currency == baseCurrency && outstanding != carrying) {
          rowIssue(
            'carrying_base_amount',
            'BASE_AMOUNT_MISMATCH',
            'The amounts must match when both currencies are $baseCurrency.',
          );
        }
      }
      final legacyOriginal = money(
        'legacy_original_amount',
        currency,
        optional: true,
      );
      final legacySettled = money(
        'legacy_settled_amount',
        currency,
        optional: true,
      );
      if (issues.length != issueCount) continue;

      lines.add(
        FinanceOpeningImportLine._(
          rowNumber: rowNumber,
          externalDocumentKey: key,
          partyCode: party,
          documentNumber: documentNumber,
          documentDate: documentDate!,
          dueDate: dueDate!,
          outstandingAmount: outstanding!,
          carryingBaseAmount: carrying!,
          legacyOriginalAmount: legacyOriginal,
          legacySettledAmount: legacySettled,
        ),
      );
      outstandingTotal += outstanding;
      carryingBaseTotal += carrying;
    }

    return FinanceOpeningImportPreview._(
      lines: lines,
      issues: issues,
      outstandingTotal: issues.isEmpty ? outstandingTotal : null,
      carryingBaseTotal: issues.isEmpty ? carryingBaseTotal : null,
    );
  }
}
