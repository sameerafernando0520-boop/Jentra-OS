import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

final class SelectedSetupFile {
  const SelectedSetupFile({
    required this.name,
    required this.extension,
    required this.bytes,
  });

  final String name;
  final String extension;
  final Uint8List bytes;
}

final class SelectedAttachmentFile {
  const SelectedAttachmentFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// Native open/save boundary for the Windows-first desktop client.
final class SetupFileService {
  const SetupFileService();

  static const _importTypes = <XTypeGroup>[
    XTypeGroup(
      label: 'Jentra setup data',
      extensions: <String>['csv', 'xlsx'],
      mimeTypes: <String>[
        'text/csv',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    ),
  ];

  static const _attachmentTypes = <XTypeGroup>[
    XTypeGroup(
      label: 'Jentra attachments',
      extensions: <String>['pdf', 'png', 'jpg', 'jpeg', 'csv', 'xlsx'],
      mimeTypes: <String>[
        'application/pdf',
        'image/png',
        'image/jpeg',
        'text/csv',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ],
    ),
  ];

  Future<SelectedSetupFile?> openImportFile() async {
    final file = await openFile(acceptedTypeGroups: _importTypes);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    return SelectedSetupFile(
      name: file.name,
      extension: extension,
      bytes: bytes,
    );
  }

  Future<SelectedAttachmentFile?> openAttachmentFile() async {
    final file = await openFile(acceptedTypeGroups: _attachmentTypes);
    if (file == null) return null;
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final mimeType = switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'csv' => 'text/csv',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      _ => '',
    };
    return SelectedAttachmentFile(
      name: file.name,
      mimeType: mimeType,
      bytes: await file.readAsBytes(),
    );
  }

  Future<String?> saveExport({
    required String suggestedName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final extension = suggestedName.split('.').last.toLowerCase();
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: <XTypeGroup>[
        XTypeGroup(
          label: extension.toUpperCase(),
          extensions: <String>[extension],
          mimeTypes: <String>[mimeType],
        ),
      ],
    );
    if (location == null) return null;
    final file = XFile.fromData(bytes, mimeType: mimeType, name: suggestedName);
    await file.saveTo(location.path);
    return location.path;
  }
}
