import 'dart:io';

import 'package:flutter/services.dart';

import 'employee_document_export.dart';
import 'employee_gateway.dart';

EmployeeDocumentExporter createExporter() => AndroidEmployeeDocumentExporter();

final class AndroidEmployeeDocumentExporter
    implements EmployeeDocumentExporter {
  AndroidEmployeeDocumentExporter({
    this.channel = const MethodChannel('com.jentra.employee/document-export'),
    bool Function()? isAndroid,
  }) : _isAndroid = isAndroid ?? (() => Platform.isAndroid);
  final MethodChannel channel;
  final bool Function() _isAndroid;
  @override
  bool get supported => _isAndroid();
  @override
  Future<bool> save({
    required Uint8List bytes,
    required String mimeType,
    required Future<bool> Function() reauthorize,
    required bool Function() stillAuthorized,
  }) async {
    if (!supported) {
      throw const EmployeeFailure(
        'DOCUMENT_EXPORT_UNAVAILABLE',
        'Document saving is available in the browser and Android app.',
      );
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const EmployeeFailure(
        'DOCUMENT_EXPORT_FAILED',
        'This document could not be saved.',
      );
    }
    String? handle;
    try {
      handle = await channel.invokeMethod<String>('chooseDestination', {
        'mimeType': mimeType,
        'name': employeeExportName(mimeType),
      });
      if (handle == null) return false;
      if (!await reauthorize() || !stillAuthorized()) {
        throw const EmployeeFailure(
          'SESSION_CHANGED',
          'Document access changed. Refresh your workspace.',
        );
      }
      await channel.invokeMethod<void>('writeDocument', {
        'handle': handle,
        'bytes': bytes,
      });
      return true;
    } on EmployeeFailure {
      rethrow;
    } on Object {
      throw const EmployeeFailure(
        'DOCUMENT_EXPORT_FAILED',
        'This document could not be saved.',
      );
    } finally {
      if (handle != null) {
        try {
          await channel.invokeMethod<void>('discardDestination', {
            'handle': handle,
          });
        } on Object {
          /* The native handle is also cleared on activity destruction. */
        }
      }
    }
  }
}
