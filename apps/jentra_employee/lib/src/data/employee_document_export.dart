import 'dart:typed_data';

import 'employee_document_export_stub.dart'
    if (dart.library.io) 'employee_document_export_io.dart'
    if (dart.library.js_interop) 'employee_document_export_web.dart'
    as platform;

abstract interface class EmployeeDocumentExporter {
  bool get supported;

  /// Explicit employee-chosen export. Authority is checked after any chooser;
  /// unencrypted temporary files and public document URLs are never created.
  Future<bool> save({
    required Uint8List bytes,
    required String mimeType,
    required Future<bool> Function() reauthorize,
    required bool Function() stillAuthorized,
  });
}

EmployeeDocumentExporter createEmployeeDocumentExporter() =>
    platform.createExporter();

String employeeExportName(String mimeType) => switch (mimeType) {
  'application/pdf' => 'Jentra-document.pdf',
  'image/jpeg' => 'Jentra-document.jpg',
  'image/png' => 'Jentra-document.png',
  'text/plain' => 'Jentra-document.txt',
  _ => throw ArgumentError('Unsupported document type'),
};
