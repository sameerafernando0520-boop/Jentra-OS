import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_platform/jentra_platform.dart';

void main() {
  const document = TabularDocument(
    headers: ['code', 'name', 'rate', 'notes'],
    rows: [
      ['VAT18', 'VAT, Output', '18.000000', 'Quoted "value"'],
      ['TEA', 'Ceylon tea', '312.1234567891', 'Line 1\nLine 2'],
      ['SI', 'ව්‍යාපාර / வணிகம்', '0.000000', 'UTF-8'],
    ],
  );

  group('CSV codec — AC-212 / AC-214', () {
    test(
      'round-trips commas, quotes, newlines, Unicode and exact decimals',
      () {
        const codec = SetupTabularCodec();
        final bytes = codec.encodeCsv(document);
        final decoded = codec.decodeCsv(bytes);

        expect(decoded, document);
        expect(decoded.rows[0][2], '18.000000');
        expect(decoded.rows[1][2], '312.1234567891');
      },
    );

    test('accepts a UTF-8 BOM and rejects duplicate headers', () {
      const codec = SetupTabularCodec();
      final withBom = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('code,name\nA,Alpha\n'),
      ]);

      expect(codec.decodeCsv(withBom).headers, ['code', 'name']);
      expect(
        () => codec.decodeCsv(
          Uint8List.fromList(utf8.encode('code,code\nA,B\n')),
        ),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'DUPLICATE_HEADER',
          ),
        ),
      );
    });

    test('rejects invalid UTF-8 with a stable diagnostic', () {
      const codec = SetupTabularCodec();

      expect(
        () => codec.decodeCsv(Uint8List.fromList([0xC3, 0x28])),
        throwsA(
          isA<TabularFileException>()
              .having((error) => error.code, 'code', 'CSV_INVALID_UTF8')
              .having(
                (error) => error.toString(),
                'diagnostic',
                contains('CSV must use valid UTF-8 encoding'),
              ),
        ),
      );
    });

    test('parses CRLF rows and reports mismatched column counts', () {
      const codec = SetupTabularCodec();
      final valid = codec.decodeCsv(
        Uint8List.fromList(utf8.encode('code,name\r\nA,Alpha\r\n')),
      );

      expect(valid.rows, const [
        ['A', 'Alpha'],
      ]);
      expect(
        () => codec.decodeCsv(
          Uint8List.fromList(utf8.encode('code,name\r\nA\r\n')),
        ),
        throwsA(
          isA<TabularFileException>()
              .having((error) => error.code, 'code', 'COLUMN_COUNT_MISMATCH')
              .having((error) => error.row, 'row', 2),
        ),
      );
    });

    test('rejects files above the 500-row import bound', () {
      const codec = SetupTabularCodec();
      final source = StringBuffer('code,name\n');
      for (var index = 0; index < 501; index += 1) {
        source.writeln('C$index,Name $index');
      }

      expect(
        () =>
            codec.decodeCsv(Uint8List.fromList(utf8.encode(source.toString()))),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'ROW_LIMIT_EXCEEDED',
          ),
        ),
      );
    });
  });

  group('XLSX codec — AC-213 / AC-214', () {
    test('round-trips one safe worksheet without decimal coercion', () {
      const codec = SetupTabularCodec();
      final bytes = codec.encodeXlsx(document, worksheetName: 'Setup data');
      final decoded = codec.decodeXlsx(bytes);

      expect(decoded, document);
      expect(decoded.rows[1][2], '312.1234567891');
    });

    test('rejects malformed archives with a stable error code', () {
      const codec = SetupTabularCodec();

      expect(
        () => codec.decodeXlsx(
          Uint8List.fromList(utf8.encode('this is not an xlsx archive')),
        ),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_MALFORMED',
          ),
        ),
      );
    });

    test('rejects formula-bearing workbooks', () {
      const codec = SetupTabularCodec();
      final source = codec.encodeXlsx(document);
      final unsafe = _rewriteXlsx(
        source,
        replacements: {
          'xl/worksheets/sheet1.xml': (xml) =>
              xml.replaceFirst('</c>', '<f>1+1</f></c>'),
        },
      );

      expect(
        () => codec.decodeXlsx(unsafe),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_FORMULA_NOT_ALLOWED',
          ),
        ),
      );
    });

    test('rejects macro-bearing workbooks', () {
      const codec = SetupTabularCodec();
      final unsafe = _rewriteXlsx(
        codec.encodeXlsx(document),
        additions: {
          'xl/vbaProject.bin': [0x4D, 0x5A],
        },
      );

      expect(
        () => codec.decodeXlsx(unsafe),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_ACTIVE_CONTENT',
          ),
        ),
      );
    });

    test('rejects workbooks with multiple data sheets', () {
      const codec = SetupTabularCodec();
      final unsafe = _rewriteXlsx(
        codec.encodeXlsx(document),
        replacements: {
          'xl/workbook.xml': (xml) => xml.replaceFirst(
            '</sheets>',
            '<sheet name="Extra" sheetId="2" r:id="rId2"/></sheets>',
          ),
        },
      );

      expect(
        () => codec.decodeXlsx(unsafe),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_SHEET_COUNT',
          ),
        ),
      );
    });

    test('reads shared strings, booleans, and exact raw numerics', () {
      const codec = SetupTabularCodec();
      final workbook = _rewriteXlsx(
        codec.encodeXlsx(
          const TabularDocument(
            headers: ['placeholder'],
            rows: [
              ['placeholder'],
            ],
          ),
        ),
        replacements: {
          'xl/worksheets/sheet1.xml': (_) =>
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>'
              '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="b"><v>1</v></c><c r="C2"><v>312.1234567891</v></c></row>'
              '</sheetData></worksheet>',
        },
        additions: {
          'xl/sharedStrings.xml': utf8.encode(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" count="4" uniqueCount="4">'
            '<si><t>code</t></si><si><t>active</t></si><si><t>rate</t></si><si><t>USD/LKR</t></si>'
            '</sst>',
          ),
        },
      );

      final decoded = codec.decodeXlsx(workbook);
      expect(decoded.headers, ['code', 'active', 'rate']);
      expect(decoded.rows.single, ['USD/LKR', 'true', '312.1234567891']);
    });

    test('rejects invalid shared-string references and encrypted OLE files', () {
      const codec = SetupTabularCodec();
      final invalidSharedString = _rewriteXlsx(
        codec.encodeXlsx(
          const TabularDocument(
            headers: ['code'],
            rows: [
              ['A'],
            ],
          ),
        ),
        replacements: {
          'xl/worksheets/sheet1.xml': (_) =>
              '<?xml version="1.0" encoding="UTF-8"?>'
              '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1"><c r="A1" t="inlineStr"><is><t>code</t></is></c></row>'
              '<row r="2"><c r="A2" t="s"><v>99</v></c></row>'
              '</sheetData></worksheet>',
        },
        additions: {
          'xl/sharedStrings.xml': utf8.encode(
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            '<si><t>code</t></si></sst>',
          ),
        },
      );

      expect(
        () => codec.decodeXlsx(invalidSharedString),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_MALFORMED',
          ),
        ),
      );
      expect(
        () => codec.decodeXlsx(
          Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0]),
        ),
        throwsA(
          isA<TabularFileException>().having(
            (error) => error.code,
            'code',
            'XLSX_ENCRYPTED',
          ),
        ),
      );
    });
  });
}

Uint8List _rewriteXlsx(
  Uint8List bytes, {
  Map<String, String Function(String source)> replacements = const {},
  Map<String, List<int>> additions = const {},
}) {
  final source = ZipDecoder().decodeBytes(bytes, verify: true);
  final output = Archive();
  for (final entry in source) {
    final replacement = replacements[entry.name];
    output.addFile(
      replacement == null
          ? ArchiveFile.bytes(entry.name, entry.content)
          : ArchiveFile.string(
              entry.name,
              replacement(utf8.decode(entry.content)),
            ),
    );
  }
  for (final addition in additions.entries) {
    output.addFile(ArchiveFile.bytes(addition.key, addition.value));
  }
  return ZipEncoder().encodeBytes(output, modified: DateTime.utc(2026));
}
