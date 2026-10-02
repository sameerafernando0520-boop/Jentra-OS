import 'dart:convert';
import 'calendar_repository.dart';
import 'tenant_context.dart';
import 'work_time.dart';
import 'workforce.dart';

const maxClockFileBytes = 65536;
const maxClockBatchRecords = 200;

final class RawClockBatch {
  RawClockBatch.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      sourceSystem = clockSourceText(row['source_system'], 80),
      rowCount = workforceInteger(row['row_count'], positive: true),
      importedCount = workforceInteger(row['imported_count']),
      importedBy = calendarUuid(row['imported_by']),
      importedAt = workforceRecorded(row['imported_at']),
      digest = workforceText(row['manifest_digest'], 64) {
    calendarFields(row, {
      'id',
      'source_system',
      'row_count',
      'imported_count',
      'imported_by',
      'imported_at',
      'manifest_digest',
    });
    if (rowCount > maxClockBatchRecords ||
        importedCount > rowCount ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Clock batch history totals changed.');
    }
  }
  final String id, sourceSystem, importedBy, digest;
  final int rowCount, importedCount;
  final DateTime importedAt;
}

final class ClockBatchLineage {
  ClockBatchLineage.fromJson(Map<String, Object?> row)
    : position = workforceInteger(row['position'], positive: true),
      eventId = calendarUuid(row['event_id']),
      sourceKey = clockSourceText(row['source_key'], 160),
      observedUtc = parseWorkUtc(row['observed_utc'] as String),
      checksum = workforceText(row['checksum'], 64),
      reused = row['reused'] as bool {
    calendarFields(row, {
      'position',
      'event_id',
      'source_key',
      'observed_utc',
      'checksum',
      'reused',
    });
    if (position > maxClockBatchRecords ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Clock batch row history changed.');
    }
  }
  final int position;
  final String eventId, sourceKey, checksum;
  final DateTime observedUtc;
  final bool reused;
}

final class ClockBatchDetail {
  const ClockBatchDetail(this.batch, this.rows, this.nextPosition);
  final RawClockBatch batch;
  final List<ClockBatchLineage> rows;
  final int? nextPosition;
}

String clockSourceText(Object? value, int limit) {
  final text = workforceText(value, limit);
  if (text != text.trim() || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
    throw const FormatException(
      'Clock references must be exact printable text.',
    );
  }
  return text;
}

final class ClockSourceRecord {
  ClockSourceRecord(this.sourceKey, this.observedUtc) {
    clockSourceText(sourceKey, 160);
    parseWorkUtc(observedUtc);
  }
  final String sourceKey, observedUtc;
}

/// A bounded preview; it never resolves employee identities or payable input.
final class ClockFilePreview {
  ClockFilePreview._(List<ClockSourceRecord> rows)
    : records = List.unmodifiable(rows);
  final List<ClockSourceRecord> records;

  factory ClockFilePreview.parse(String text) {
    if (utf8.encode(text).length > maxClockFileBytes) {
      throw const FormatException('Clock CSV must be at most 64 KiB.');
    }
    if (text.startsWith('\ufeff')) text = text.substring(1);
    final rows = <List<String>>[];
    var row = <String>[], field = StringBuffer();
    var quoted = false, closed = false, started = false;
    void finishField() {
      row.add(field.toString());
      field = StringBuffer();
      closed = false;
      started = false;
    }

    void finishRow() {
      finishField();
      if (row.length != 2) {
        throw const FormatException('Clock CSV requires exactly two columns.');
      }
      rows.add(row);
      row = [];
      if (rows.length > maxClockBatchRecords + 1) {
        throw const FormatException('Clock CSV supports at most 200 events.');
      }
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(char);
        }
      } else if (char == ',') {
        finishField();
      } else if (char == '\n' || char == '\r') {
        if (char == '\r') {
          if (i + 1 >= text.length || text[i + 1] != '\n') {
            throw const FormatException(
              'Clock CSV uses LF or CRLF line endings.',
            );
          }
          i++;
        }
        finishRow();
      } else if (char == '"' && !started && !closed) {
        quoted = true;
        started = true;
      } else {
        if (closed || char == '"') {
          throw const FormatException('Clock CSV quoting is invalid.');
        }
        field.write(char);
        started = true;
      }
    }
    if (quoted) throw const FormatException('Clock CSV quote is unfinished.');
    if (started || closed || row.isNotEmpty) finishRow();
    if (rows.length < 2 || rows.first.join(',') != 'source_key,observed_utc') {
      throw const FormatException(
        'Use source_key,observed_utc and at least one event.',
      );
    }
    final records = rows
        .skip(1)
        .map((r) => ClockSourceRecord(r[0], r[1]))
        .toList();
    if (records.map((r) => r.sourceKey).toSet().length != records.length) {
      throw const FormatException(
        'Clock source references must be unique in a file.',
      );
    }
    return ClockFilePreview._(records);
  }
}

String clockChecksumBasis(
  TenantContext scope,
  String employeeId,
  String sourceSystem,
  ClockSourceRecord row,
) => [
  calendarUuid(scope.tenantId).toLowerCase(),
  calendarUuid(scope.legalEntityId).toLowerCase(),
  calendarUuid(scope.branchId).toLowerCase(),
  calendarUuid(employeeId).toLowerCase(),
  clockSourceText(sourceSystem, 80),
  row.sourceKey,
  row.observedUtc,
].join('\n');

String clockManifestBasis(
  TenantContext scope,
  String employeeId,
  String sourceSystem,
  List<String> checksums,
) => [
  'w4-clock-batch-v1',
  calendarUuid(scope.tenantId).toLowerCase(),
  calendarUuid(scope.legalEntityId).toLowerCase(),
  calendarUuid(scope.branchId).toLowerCase(),
  calendarUuid(employeeId).toLowerCase(),
  clockSourceText(sourceSystem, 80),
  ...checksums,
].join('\n');

void validateClockBatch(Map<String, Object?> payload) {
  calendarFields(payload, {
    'action',
    'id',
    'employee_id',
    'source_system',
    'records',
    'manifest_digest',
  });
  if (payload['action'] != 'raw_import_batch') {
    throw const FormatException('Clock batch action is invalid.');
  }
  calendarUuid(payload['id']);
  calendarUuid(payload['employee_id']);
  clockSourceText(payload['source_system'], 80);
  final rows = payload['records'];
  if (rows is! List || rows.isEmpty || rows.length > maxClockBatchRecords) {
    throw const FormatException('Clock batch requires 1 to 200 records.');
  }
  final ids = <String>{}, keys = <String>{};
  for (final item in rows) {
    final row = workforceMap(item);
    calendarFields(row, {'id', 'source_key', 'observed_utc', 'checksum'});
    if (!ids.add(calendarUuid(row['id'])) ||
        !keys.add(clockSourceText(row['source_key'], 160))) {
      throw const FormatException(
        'Clock event identities and keys must be unique.',
      );
    }
    parseWorkUtc(row['observed_utc'] as String);
    if (row['checksum'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['checksum'] as String)) {
      throw const FormatException('Clock row checksum is invalid.');
    }
  }
  if (payload['manifest_digest'] is! String ||
      !RegExp(
        r'^[a-f0-9]{64}$',
      ).hasMatch(payload['manifest_digest'] as String)) {
    throw const FormatException('Clock manifest digest is invalid.');
  }
}
