import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_finance_opening.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_platform/finance_opening_files.dart';
import 'package:jentra_platform/jentra_finance_platform.dart';

FinanceOpeningImportPreview _decode(Uint8List bytes, String extension) =>
    FinanceOpeningFileCodec.decode(
      bytes,
      extension,
      cutoffDate: CivilDate.parse('2026-10-31'),
      currencyCode: 'LKR',
      baseCurrencyCode: 'LKR',
    );

void main() {
  test('CSV and XLSX preserve the same quoted document and exact credit', () {
    const codec = SetupTabularCodec();
    const table = TabularDocument(
      headers: FinanceOpeningImportPreview.requiredHeaders,
      rows: [
        [
          'bill-4',
          'SUP-1',
          'Debit, note 4',
          '2026-09-01',
          '2026-10-01',
          'LKR',
          '-9007199254.740993',
          '-9007199254.740993',
        ],
      ],
    );
    final csv = _decode(codec.encodeCsv(table), 'CSV');
    final xlsx = _decode(codec.encodeXlsx(table), 'xlsx');
    expect(csv.isValid, isTrue);
    expect(xlsx.isValid, isTrue);
    expect(xlsx.lines.single.toPayload(), csv.lines.single.toPayload());
    expect(xlsx.lines.single.documentNumber, 'Debit, note 4');
    expect(xlsx.outstandingTotal!.toDecimalString(), '-9007199254.740993');
  });

  test('CSV and XLSX templates provide required and optional columns', () {
    const codec = SetupTabularCodec();
    final csv = codec.decodeCsv(FinanceOpeningFileCodec.encodeTemplate('csv'));
    final workbook = FinanceOpeningFileCodec.encodeTemplate('xlsx');
    final xlsx = codec.decodeXlsx(workbook);
    expect(csv.headers, [
      ...FinanceOpeningImportPreview.requiredHeaders,
      ...FinanceOpeningImportPreview.optionalHeaders,
    ]);
    expect(csv.rows, isEmpty);
    expect(xlsx, csv);

    final archive = ZipDecoder().decodeBytes(workbook);
    final worksheet = utf8.decode(
      archive.find('xl/worksheets/sheet1.xml')!.content,
    );
    final styles = utf8.decode(archive.find('xl/styles.xml')!.content);
    expect(
      worksheet,
      contains('min="1" max="${csv.headers.length}" style="1"'),
    );
    expect(styles, contains('numFmtId="49"'));
  });

  test('malformed file returns the row to correct', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '${FinanceOpeningImportPreview.requiredHeaders.join(',')}\na,b,c',
      ),
    );
    final result = _decode(bytes, 'csv');
    expect(result.isValid, isFalse);
    expect(result.issues.single.rowNumber, 2);
    expect(result.issues.single.code, 'COLUMN_COUNT_MISMATCH');
  });

  test('Excel may omit trailing cells in optional columns', () {
    const table = TabularDocument(
      headers: [
        ...FinanceOpeningImportPreview.requiredHeaders,
        ...FinanceOpeningImportPreview.optionalHeaders,
      ],
      rows: [
        [
          '01',
          'CUS-1',
          'INV-001',
          '2026-10-01',
          '2026-10-31',
          'LKR',
          '12.34',
          '12.34',
          '',
          '',
        ],
      ],
    );
    final archive = ZipDecoder().decodeBytes(
      const SetupTabularCodec().encodeXlsx(table),
    );
    final workbook = Archive();
    for (final part in archive) {
      if (part.name != 'xl/worksheets/sheet1.xml') {
        workbook.addFile(part);
        continue;
      }
      final xml = utf8
          .decode(part.content)
          .replaceAll(RegExp(r'<c r="[IJ]2"[^>]*>.*?</c>'), '');
      workbook.addFile(ArchiveFile.string(part.name, xml));
    }

    final preview = _decode(ZipEncoder().encodeBytes(workbook), 'xlsx');
    expect(preview.issues, isEmpty);
    expect(preview.lines.single.externalDocumentKey, '01');
    expect(preview.lines.single.legacyOriginalAmount, isNull);
    expect(preview.lines.single.legacySettledAmount, isNull);
  });
}
