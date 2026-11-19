import 'dart:typed_data';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_finance_opening.dart';
import 'package:jentra_domain/jentra_people.dart';

import 'tabular_codec.dart';

/// Bounded CSV and XLSX file boundary for the opening-document preview.
abstract final class FinanceOpeningFileCodec {
  static const _codec = SetupTabularCodec();

  static FinanceOpeningImportPreview decode(
    Uint8List bytes,
    String extension, {
    required CivilDate cutoffDate,
    required String currencyCode,
    required String baseCurrencyCode,
  }) {
    try {
      final table = switch (extension.toLowerCase()) {
        'csv' => _codec.decodeCsv(bytes),
        'xlsx' => _codec.decodeXlsx(bytes, padMissingTrailingCells: true),
        _ => throw const TabularFileException(
          'FILE_TYPE',
          'Choose a CSV or XLSX file.',
        ),
      };
      return FinanceOpeningImportPreview.fromTable(
        table,
        cutoffDate: cutoffDate,
        currencyCode: currencyCode,
        baseCurrencyCode: baseCurrencyCode,
      );
    } on TabularFileException catch (error) {
      return FinanceOpeningImportPreview.fileIssue(
        FinanceOpeningImportIssue(
          rowNumber: error.row ?? 1,
          field: error.field ?? (error.row == null ? 'file' : 'row'),
          code: error.code,
          message: error.message,
        ),
      );
    }
  }

  static Uint8List encodeTemplate(String extension) {
    const template = TabularDocument(
      headers: [
        ...FinanceOpeningImportPreview.requiredHeaders,
        ...FinanceOpeningImportPreview.optionalHeaders,
      ],
      rows: [],
    );
    return switch (extension.toLowerCase()) {
      'csv' => _codec.encodeCsv(template),
      'xlsx' => _codec.encodeXlsx(
        template,
        worksheetName: 'Opening documents',
        textColumns: true,
      ),
      _ => throw const FormatException('Choose CSV or XLSX for the template.'),
    };
  }
}
