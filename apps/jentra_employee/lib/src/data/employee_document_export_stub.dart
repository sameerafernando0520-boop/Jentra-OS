import 'dart:typed_data';

import 'employee_document_export.dart';
import 'employee_gateway.dart';

EmployeeDocumentExporter createExporter() => const _UnsupportedExporter();

final class _UnsupportedExporter implements EmployeeDocumentExporter {
  const _UnsupportedExporter();
  @override
  bool get supported => false;
  @override
  Future<bool> save({
    required Uint8List bytes,
    required String mimeType,
    required Future<bool> Function() reauthorize,
    required bool Function() stillAuthorized,
  }) async => throw const EmployeeFailure(
    'DOCUMENT_EXPORT_UNAVAILABLE',
    'Document saving is available in the browser and Android app.',
  );
}
