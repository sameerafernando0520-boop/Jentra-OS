import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

Future<FileSaveLocation?> jentraSaveLocation({
  required String suggestedName,
  required List<XTypeGroup> acceptedTypeGroups,
}) async {
  if (!web.window.isSecureContext ||
      suggestedName.isEmpty ||
      suggestedName.length > 180 ||
      suggestedName.startsWith('.') ||
      RegExp(r'[\\/:\x00-\x1f\x7f]').hasMatch(suggestedName)) {
    throw const FormatException('Use HTTPS and a supported download filename.');
  }
  // The existing caller still reauthorizes before XFile.saveTo delivers bytes.
  // Browsers choose the final destination in their download UI.
  return FileSaveLocation(suggestedName);
}
