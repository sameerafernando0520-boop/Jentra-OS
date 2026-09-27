import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'tabular_codec.dart';

final class ReportExportArtifact {
  const ReportExportArtifact({
    required this.bytes,
    required this.columns,
    required this.sha256,
    required this.rowCount,
  });
  final Uint8List bytes;
  final List<String> columns;
  final String sha256;
  final int rowCount;
}

final class ReportExportCodec {
  const ReportExportCodec();
  static const maxBytes = 10 * 1024 * 1024;
  static Future<String> hash(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  String cell(Object? v) {
    final s = v == null
        ? ''
        : v is Map || v is List
        ? jsonEncode(v)
        : v.toString();
    if (s.length > 32767 ||
        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]').hasMatch(s) ||
        utf8.decode(utf8.encode(s)) != s) {
      throw const FormatException(
        'Export evidence contains an unsupported spreadsheet cell.',
      );
    }
    return s;
  }

  Future<ReportExportArtifact> encode(
    Map<String, Object?> document, {
    required String format,
    required String exportId,
    required String preparedAt,
    required String sourceHash,
  }) async {
    if (!['csv', 'xlsx'].contains(format) ||
        document['version'] != 1 ||
        document['metadata'] is! Map ||
        document['rows'] is! List ||
        (document['rows'] as List).length > 10000) {
      throw const FormatException('Unsupported or oversized report export.');
    }
    final meta = {
      ...(document['metadata'] as Map).cast<String, Object?>(),
      'export_id': exportId,
      'export_prepared_at': preparedAt,
      'source_hash': sourceHash,
      'file_format': format,
    };
    final rows = [
      for (final r in document['rows'] as List)
        if (r is Map)
          r.cast<String, Object?>()
        else
          throw const FormatException('Invalid evidence row.'),
    ];
    if (meta['row_count'] != rows.length) {
      throw const FormatException(
        'Export row count does not match its source.',
      );
    }
    final metaKeys = meta.keys.toList()..sort(),
        dataKeys = rows.expand((r) => r.keys).toSet().toList()..sort();
    final headers = [
      'record_type',
      ...metaKeys.map((k) => 'report.$k'),
      ...dataKeys.map((k) => 'data.$k'),
    ];
    if (headers.length > 256 || (rows.length + 1) * headers.length > 500000) {
      throw const FormatException('Export exceeds its supported cell count.');
    }
    final exactKey = RegExp(
      r'(^|_)(amount|value|debit|credit|balance|total|price|cost|tax|rate|quantity|percent)$',
    );
    for (final row in rows) {
      for (final entry in row.entries) {
        if (entry.value is num && exactKey.hasMatch(entry.key)) {
          throw const FormatException(
            'Financial evidence must contain exact decimal strings.',
          );
        }
      }
    }
    String value(Object? v) {
      final s = cell(v);
      if (format == 'csv' &&
          RegExp(r'^[\s]*[=+\-@]').hasMatch(s) &&
          !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
        return "'$s";
      }
      return s;
    }

    final grid = <List<String>>[
      [
        'metadata',
        for (final k in metaKeys) value(meta[k]),
        for (final _ in dataKeys) '',
      ],
      for (final row in rows)
        [
          'data',
          for (final _ in metaKeys) '',
          for (final k in dataKeys) value(row[k]),
        ],
    ];
    const codec = SetupTabularCodec.reportExport();
    final tabular = TabularDocument(headers: headers, rows: grid);
    final bytes = format == 'csv'
        ? codec.encodeCsv(tabular)
        : codec.encodeXlsx(tabular, worksheetName: 'Report evidence');
    if (bytes.length > maxBytes) {
      throw const FormatException(
        'The export exceeds 10 MiB. No file was written.',
      );
    }
    return ReportExportArtifact(
      bytes: bytes,
      columns: headers,
      sha256: await hash(bytes),
      rowCount: rows.length,
    );
  }
}

abstract interface class ReportExportFiles {
  Future<String?> choose(String fileName);
  Future<void> write(String path, Uint8List bytes, String mimeType);
}

final class NativeReportExportFiles implements ReportExportFiles {
  const NativeReportExportFiles();
  @override
  Future<String?> choose(String fileName) async => (await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Report export',
        extensions: [fileName.split('.').last],
      ),
    ],
  ))?.path;
  @override
  Future<void> write(String path, Uint8List bytes, String mimeType) async {
    await XFile.fromData(bytes, mimeType: mimeType).saveTo(path);
  }
}
