import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:uuid/uuid.dart';

abstract interface class ClockImportFiles {
  Future<String?> chooseCsv();
}

final class NativeClockImportFiles implements ClockImportFiles {
  const NativeClockImportFiles();
  @override
  Future<String?> chooseCsv() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Clock CSV', extensions: ['csv']),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxClockFileBytes) {
      throw const FormatException('Clock CSV must be at most 64 KiB.');
    }
    final bytes = await file.readAsBytes();
    try {
      if (bytes.length > maxClockFileBytes) {
        throw const FormatException('Clock CSV must be at most 64 KiB.');
      }
      return utf8.decode(bytes, allowMalformed: false);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }
}

Future<String> _clockHash(String text) async {
  final digest = await Sha256().hash(utf8.encode(text));
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Builds one stable command from a validated preview before any network call.
Future<Map<String, Object?>> prepareClockBatch(
  TenantContext scope,
  String employeeId,
  String sourceSystem,
  String csv, {
  String Function()? newId,
}) async {
  final preview = ClockFilePreview.parse(csv);
  clockSourceText(sourceSystem, 80);
  final uuid = newId ?? const Uuid().v4;
  final batchId = uuid();
  final eventIds = List.generate(preview.records.length, (_) => uuid());
  final records = <Map<String, Object?>>[];
  for (final (index, row) in preview.records.indexed) {
    records.add({
      'id': eventIds[index],
      'source_key': row.sourceKey,
      'observed_utc': row.observedUtc,
      'checksum': await _clockHash(
        clockChecksumBasis(scope, employeeId, sourceSystem, row),
      ),
    });
  }
  final payload = <String, Object?>{
    'action': 'raw_import_batch',
    'id': batchId,
    'employee_id': employeeId,
    'source_system': sourceSystem,
    'records': records,
    'manifest_digest': await _clockHash(
      clockManifestBasis(
        scope,
        employeeId,
        sourceSystem,
        records.map((r) => r['checksum'] as String).toList(),
      ),
    ),
  };
  validateClockBatch(payload);
  return payload;
}
