import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';

final class HrPickedDocument {
  const HrPickedDocument(this.mime, this.bytes, this.checksum);
  final String mime, checksum;
  final Uint8List bytes;
}

abstract interface class HrFiles {
  Future<HrPickedDocument?> chooseUpload();
  Future<String?> chooseExport(String fileName);
  Future<void> write(String path, Uint8List bytes, String mime);
}

final class NativeHrFiles implements HrFiles {
  const NativeHrFiles();
  @override
  Future<HrPickedDocument?> chooseUpload() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Private HR document',
          extensions: ['txt', 'png', 'jpg', 'jpeg', 'pdf'],
        ),
      ],
    );
    if (file == null) return null;
    final length = await file.length();
    if (length < 1 || length > 10485760)
      throw const FormatException('Choose a supported document up to 10 MiB.');
    final mime = switch (file.name.split('.').last.toLowerCase()) {
      'txt' => 'text/plain',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'pdf' => 'application/pdf',
      _ => throw const FormatException('Choose text, PNG, JPEG or PDF.'),
    };
    final bytes = await file.readAsBytes();
    if (bytes.length != length)
      throw const FormatException(
        'The selected file changed. Choose it again.',
      );
    final checksum = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return HrPickedDocument(mime, bytes, checksum);
  }

  @override
  Future<String?> chooseExport(String fileName) async => (await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Private HR export',
        extensions: [fileName.split('.').last],
      ),
    ],
  ))?.path;
  @override
  Future<void> write(String path, Uint8List bytes, String mime) =>
      XFile.fromData(bytes, mimeType: mime).saveTo(path);
}
