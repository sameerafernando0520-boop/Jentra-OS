import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'employee_document_export.dart';
import 'employee_gateway.dart';

EmployeeDocumentExporter createExporter() => _BrowserDocumentExporter();

final class _BrowserDocumentExporter implements EmployeeDocumentExporter {
  @override
  bool get supported => web.window.isSecureContext;
  @override
  Future<bool> save({
    required Uint8List bytes,
    required String mimeType,
    required Future<bool> Function() reauthorize,
    required bool Function() stillAuthorized,
  }) async {
    if (!supported || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const EmployeeFailure(
        'DOCUMENT_EXPORT_FAILED',
        'This document could not be saved.',
      );
    }
    final name = employeeExportName(mimeType);
    if (!await reauthorize() || !stillAuthorized()) {
      throw const EmployeeFailure(
        'SESSION_CHANGED',
        'Document access changed. Refresh your workspace.',
      );
    }
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..rel = 'noreferrer';
    try {
      web.document.body?.append(anchor);
      anchor.click();
      // Keep the URL just long enough for the browser's download dispatch.
      await Future<void>.delayed(const Duration(seconds: 1));
      return true;
    } finally {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    }
  }
}
