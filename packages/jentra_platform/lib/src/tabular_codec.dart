import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:xml/xml.dart';

final class TabularFileException implements Exception {
  const TabularFileException(this.code, this.message, {this.row, this.field});

  final String code;
  final String message;
  final int? row;
  final String? field;

  @override
  String toString() => 'TabularFileException($code, $message)';
}

/// Bounded RFC-4180 CSV and safe, string-only OOXML codec.
///
/// XLSX values are written as inline strings so exact decimals never pass
/// through a spreadsheet numeric coercion. Import accepts inline strings,
/// shared strings, booleans, and raw numeric XML values, while rejecting
/// formulas, macros, multiple data sheets, unsafe paths, and oversized ZIPs.
final class SetupTabularCodec {
  const SetupTabularCodec() : rowLimit = maximumRows;
  const SetupTabularCodec.bankStatement() : rowLimit = 2000;
  final int rowLimit;

  static const int maximumImportBytes = 5 * 1024 * 1024;
  static const int maximumRows = 500;
  static const int maximumColumns = 256;
  static const int maximumArchiveEntries = 128;
  static const int maximumUncompressedBytes = 20 * 1024 * 1024;

  Uint8List encodeCsv(TabularDocument document) {
    _validateDocument(document);
    final output = StringBuffer();
    void writeRow(List<String> row) {
      output.writeln(row.map(_escapeCsv).join(','));
    }

    writeRow(document.headers);
    for (final row in document.rows) {
      writeRow(row);
    }
    return Uint8List.fromList(utf8.encode(output.toString()));
  }

  TabularDocument decodeCsv(Uint8List bytes) {
    _validateByteLimit(bytes);
    late String source;
    try {
      source = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const TabularFileException(
        'CSV_INVALID_UTF8',
        'CSV must use valid UTF-8 encoding.',
      );
    }
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    final rows = _parseCsv(source);
    if (rows.isEmpty) {
      throw const TabularFileException('EMPTY_FILE', 'The file has no rows.');
    }
    return _documentFromGrid(rows);
  }

  Uint8List encodeXlsx(
    TabularDocument document, {
    String worksheetName = 'Setup data',
  }) {
    _validateDocument(document);
    final safeName = _safeWorksheetName(worksheetName);
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypesXml))
      ..addFile(ArchiveFile.string('_rels/.rels', _packageRelationshipsXml))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbookXml(safeName)))
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _workbookRelationshipsXml,
        ),
      )
      ..addFile(
        ArchiveFile.string('xl/worksheets/sheet1.xml', _worksheetXml(document)),
      );
    return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2026));
  }

  TabularDocument decodeXlsx(Uint8List bytes) {
    _validateByteLimit(bytes);
    if (_looksLikeEncryptedOle(bytes)) {
      throw const TabularFileException(
        'XLSX_ENCRYPTED',
        'Encrypted workbooks are not supported.',
      );
    }

    late Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } on Object {
      throw const TabularFileException(
        'XLSX_MALFORMED',
        'The XLSX archive is malformed.',
      );
    }

    if (archive.length > maximumArchiveEntries) {
      throw const TabularFileException(
        'XLSX_ARCHIVE_LIMIT',
        'The workbook contains too many archive entries.',
      );
    }
    var totalSize = 0;
    for (final entry in archive) {
      final normalized = entry.name.replaceAll('\\', '/');
      if (normalized.startsWith('/') ||
          normalized.split('/').contains('..') ||
          entry.isSymbolicLink) {
        throw const TabularFileException(
          'XLSX_UNSAFE_PATH',
          'The workbook contains an unsafe archive path.',
        );
      }
      totalSize += entry.size;
      if (entry.size > maximumUncompressedBytes ||
          totalSize > maximumUncompressedBytes) {
        throw const TabularFileException(
          'XLSX_ARCHIVE_LIMIT',
          'The expanded workbook exceeds the safety limit.',
        );
      }
      final lower = normalized.toLowerCase();
      if (lower.contains('vbaproject') ||
          lower.startsWith('xl/externallinks/')) {
        throw const TabularFileException(
          'XLSX_ACTIVE_CONTENT',
          'Macros and external links are not supported.',
        );
      }
    }

    try {
      final workbook = _parseArchiveXml(archive, 'xl/workbook.xml');
      final sheets = workbook.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'sheet')
          .toList(growable: false);
      if (sheets.length != 1) {
        throw const TabularFileException(
          'XLSX_SHEET_COUNT',
          'Use exactly one data worksheet.',
        );
      }

      final relationshipId = sheets.single.attributes
          .where((attribute) => attribute.name.local == 'id')
          .map((attribute) => attribute.value)
          .firstOrNull;
      final relationships = _parseArchiveXml(
        archive,
        'xl/_rels/workbook.xml.rels',
      );
      String? sheetTarget;
      for (final relationship
          in relationships.descendants.whereType<XmlElement>().where(
            (element) => element.name.local == 'Relationship',
          )) {
        if (relationship.getAttribute('Id') == relationshipId) {
          sheetTarget = relationship.getAttribute('Target');
          break;
        }
      }
      if (sheetTarget == null || sheetTarget.isEmpty) {
        throw const TabularFileException(
          'XLSX_MALFORMED',
          'The worksheet relationship is missing.',
        );
      }
      final sheetPath = _resolveWorkbookTarget(sheetTarget);
      final worksheet = _parseArchiveXml(archive, sheetPath);
      if (worksheet.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'f',
      )) {
        throw const TabularFileException(
          'XLSX_FORMULA_NOT_ALLOWED',
          'Formula-bearing workbooks are not supported.',
        );
      }

      final sharedStrings = _readSharedStrings(archive);
      final grid = _readWorksheetGrid(worksheet, sharedStrings);
      return _documentFromGrid(grid);
    } on TabularFileException {
      rethrow;
    } on Object {
      throw const TabularFileException(
        'XLSX_MALFORMED',
        'The XLSX document structure is malformed.',
      );
    }
  }

  static String _escapeCsv(String value) {
    final mustQuote =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\r') ||
        value.contains('\n') ||
        value != value.trim();
    if (!mustQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  static List<List<String>> _parseCsv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var justClosedQuote = false;

    void finishField() {
      row.add(field.toString());
      field.clear();
      justClosedQuote = false;
    }

    void finishRow() {
      finishField();
      if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
      row = <String>[];
    }

    for (var index = 0; index < source.length; index += 1) {
      final character = source[index];
      if (inQuotes) {
        if (character == '"') {
          if (index + 1 < source.length && source[index + 1] == '"') {
            field.write('"');
            index += 1;
          } else {
            inQuotes = false;
            justClosedQuote = true;
          }
        } else {
          field.write(character);
        }
        continue;
      }

      if (justClosedQuote &&
          character != ',' &&
          character != '\r' &&
          character != '\n') {
        throw const TabularFileException(
          'CSV_MALFORMED',
          'Unexpected text follows a quoted CSV field.',
        );
      }
      if (character == '"') {
        if (field.isNotEmpty) {
          throw const TabularFileException(
            'CSV_MALFORMED',
            'A quote appears inside an unquoted CSV field.',
          );
        }
        inQuotes = true;
      } else if (character == ',') {
        finishField();
      } else if (character == '\r' || character == '\n') {
        if (character == '\r' &&
            index + 1 < source.length &&
            source[index + 1] == '\n') {
          index += 1;
        }
        finishRow();
      } else {
        field.write(character);
      }
    }
    if (inQuotes) {
      throw const TabularFileException(
        'CSV_MALFORMED',
        'A quoted CSV field is not closed.',
      );
    }
    if (field.isNotEmpty || row.isNotEmpty || justClosedQuote) finishRow();
    return rows;
  }

  TabularDocument _documentFromGrid(List<List<String>> rows) {
    if (rows.isEmpty) {
      throw const TabularFileException('EMPTY_FILE', 'The file has no rows.');
    }
    final headers = rows.first.map(_normalizeHeader).toList(growable: false);
    if (headers.isEmpty || headers.any((header) => header.isEmpty)) {
      throw const TabularFileException(
        'BLANK_HEADER',
        'Every column must have a header.',
      );
    }
    if (headers.length > maximumColumns) {
      throw const TabularFileException(
        'COLUMN_LIMIT_EXCEEDED',
        'The import supports at most 256 columns.',
      );
    }
    if (headers.toSet().length != headers.length) {
      throw const TabularFileException(
        'DUPLICATE_HEADER',
        'Column headers must be unique after normalization.',
      );
    }
    final dataRows = rows.skip(1).toList(growable: false);
    if (dataRows.length > rowLimit) {
      throw TabularFileException(
        'ROW_LIMIT_EXCEEDED',
        'The import exceeds its configured row limit.',
      );
    }
    for (var index = 0; index < dataRows.length; index += 1) {
      if (dataRows[index].length != headers.length) {
        throw TabularFileException(
          'COLUMN_COUNT_MISMATCH',
          'Row ${index + 2} has ${dataRows[index].length} columns; '
              'expected ${headers.length}.',
          row: index + 2,
        );
      }
    }
    return TabularDocument(headers: headers, rows: dataRows).immutableCopy();
  }

  static String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static void _validateByteLimit(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const TabularFileException('EMPTY_FILE', 'The file is empty.');
    }
    if (bytes.length > maximumImportBytes) {
      throw const TabularFileException(
        'FILE_SIZE_EXCEEDED',
        'Import files must not exceed 5 MiB.',
      );
    }
  }

  void _validateDocument(TabularDocument document) {
    _documentFromGrid([document.headers, ...document.rows]);
  }

  static XmlDocument _parseArchiveXml(Archive archive, String path) {
    final entry = archive.find(path);
    if (entry == null || !entry.isFile) {
      throw const TabularFileException(
        'XLSX_MALFORMED',
        'A required workbook part is missing.',
      );
    }
    return XmlDocument.parse(utf8.decode(entry.content, allowMalformed: false));
  }

  static List<String> _readSharedStrings(Archive archive) {
    final entry = archive.find('xl/sharedStrings.xml');
    if (entry == null) return const [];
    final document = XmlDocument.parse(
      utf8.decode(entry.content, allowMalformed: false),
    );
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'si')
        .map(
          (item) => item.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 't')
              .map((element) => element.innerText)
              .join(),
        )
        .toList(growable: false);
  }

  List<List<String>> _readWorksheetGrid(
    XmlDocument worksheet,
    List<String> sharedStrings,
  ) {
    final output = <List<String>>[];
    final rowElements = worksheet.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == 'row',
    );
    for (final rowElement in rowElements) {
      final values = <int, String>{};
      var sequentialColumn = 0;
      for (final cell in rowElement.children.whereType<XmlElement>().where(
        (element) => element.name.local == 'c',
      )) {
        final reference = cell.getAttribute('r');
        final column = reference == null
            ? sequentialColumn
            : _columnIndex(reference);
        sequentialColumn = column + 1;
        if (column >= maximumColumns) {
          throw const TabularFileException(
            'COLUMN_LIMIT_EXCEEDED',
            'The import supports at most 256 columns.',
          );
        }
        final type = cell.getAttribute('t');
        String value;
        if (type == 'inlineStr') {
          value = cell.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 't')
              .map((element) => element.innerText)
              .join();
        } else {
          final raw =
              cell.descendants
                  .whereType<XmlElement>()
                  .where((element) => element.name.local == 'v')
                  .map((element) => element.innerText)
                  .firstOrNull ??
              '';
          if (type == 's') {
            final index = int.tryParse(raw);
            if (index == null || index < 0 || index >= sharedStrings.length) {
              throw const TabularFileException(
                'XLSX_MALFORMED',
                'A shared-string reference is invalid.',
              );
            }
            value = sharedStrings[index];
          } else if (type == 'b') {
            value = raw == '1' ? 'true' : 'false';
          } else {
            value = raw;
          }
        }
        values[column] = value;
      }
      if (values.isEmpty) continue;
      final width =
          values.keys.reduce((left, right) => left > right ? left : right) + 1;
      output.add([
        for (var column = 0; column < width; column += 1) values[column] ?? '',
      ]);
      if (output.length > rowLimit + 1) {
        throw const TabularFileException(
          'ROW_LIMIT_EXCEEDED',
          'The import exceeds its configured row limit.',
        );
      }
    }
    return output;
  }

  static int _columnIndex(String cellReference) {
    final letters = RegExp(r'^[A-Za-z]+').stringMatch(cellReference);
    if (letters == null) {
      throw const TabularFileException(
        'XLSX_MALFORMED',
        'A worksheet cell reference is invalid.',
      );
    }
    var value = 0;
    for (final rune in letters.toUpperCase().runes) {
      value = value * 26 + rune - 64;
    }
    return value - 1;
  }

  static String _resolveWorkbookTarget(String target) {
    final normalized = target.replaceAll('\\', '/');
    if (normalized.startsWith('/') || normalized.split('/').contains('..')) {
      throw const TabularFileException(
        'XLSX_UNSAFE_PATH',
        'The worksheet relationship contains an unsafe path.',
      );
    }
    return normalized.startsWith('xl/') ? normalized : 'xl/$normalized';
  }

  static bool _looksLikeEncryptedOle(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0xD0 &&
      bytes[1] == 0xCF &&
      bytes[2] == 0x11 &&
      bytes[3] == 0xE0;

  static String _safeWorksheetName(String source) {
    final value = source.replaceAll(RegExp(r'[:\\/?*\[\]]'), ' ').trim();
    final safe = value.isEmpty ? 'Setup data' : value;
    return safe.length <= 31 ? safe : safe.substring(0, 31);
  }

  static String _worksheetXml(TabularDocument document) {
    final rows = <List<String>>[document.headers, ...document.rows];
    final output = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>',
    );
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      output.write('<row r="${rowIndex + 1}">');
      for (
        var columnIndex = 0;
        columnIndex < rows[rowIndex].length;
        columnIndex += 1
      ) {
        final reference = '${_columnName(columnIndex)}${rowIndex + 1}';
        output
          ..write(
            '<c r="$reference" t="inlineStr"><is><t xml:space="preserve">',
          )
          ..write(_escapeXml(rows[rowIndex][columnIndex]))
          ..write('</t></is></c>');
      }
      output.write('</row>');
    }
    output.write('</sheetData></worksheet>');
    return output.toString();
  }

  static String _columnName(int zeroBased) {
    var value = zeroBased + 1;
    final output = StringBuffer();
    while (value > 0) {
      final remainder = (value - 1) % 26;
      output.writeCharCode(65 + remainder);
      value = (value - 1) ~/ 26;
    }
    return output.toString().split('').reversed.join();
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _workbookXml(String worksheetName) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheets><sheet name="${_escapeXml(worksheetName)}" sheetId="1" r:id="rId1"/>'
      '</sheets></workbook>';

  static const String _contentTypesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
      '</Types>';

  static const String _packageRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  static const String _workbookRelationshipsXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
      '</Relationships>';
}
