import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';

final class ExpensePickedDocument {
  const ExpensePickedDocument(this.mime, this.bytes, this.checksum);
  final String mime, checksum;
  final Uint8List bytes;
}

abstract interface class ExpenseEvidenceFiles {
  Future<ExpensePickedDocument?> chooseUpload();
  Future<String?> chooseExport(String fileName);
  Future<void> write(String path, Uint8List bytes, String mime);
}

/// Read no more than the selected size; reject growth before retaining the next
/// chunk. The picker also bounds its file stream to the original size plus one.
Future<Uint8List> readExpenseEvidenceBytes(
  Stream<List<int>> chunks,
  int expectedLength,
) async {
  if (expectedLength < 1 || expectedLength > 10485760) {
    throw const FormatException('Choose a supported document up to 10 MiB.');
  }
  final bytes = BytesBuilder();
  var size = 0;
  await for (final chunk in chunks) {
    if (chunk.length > expectedLength - size) {
      throw const FormatException(
        'The selected file changed. Choose it again.',
      );
    }
    size += chunk.length;
    bytes.add(chunk);
  }
  if (size != expectedLength) {
    throw const FormatException('The selected file changed. Choose it again.');
  }
  return bytes.takeBytes();
}

final class NativeExpenseEvidenceFiles implements ExpenseEvidenceFiles {
  const NativeExpenseEvidenceFiles();
  @override
  Future<ExpensePickedDocument?> chooseUpload() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Expense evidence document',
          extensions: ['txt', 'png', 'jpg', 'jpeg', 'pdf'],
        ),
      ],
    );
    if (file == null) return null;
    final length = await file.length();
    if (length < 1 || length > 10485760) {
      throw const FormatException('Choose a supported document up to 10 MiB.');
    }
    final mime = switch (file.name.split('.').last.toLowerCase()) {
      'txt' => 'text/plain',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'pdf' => 'application/pdf',
      _ => throw const FormatException('Choose text, PNG, JPEG or PDF.'),
    };
    final bytes = await readExpenseEvidenceBytes(
      file.openRead(0, length + 1),
      length,
    );
    if (await file.length() != length) {
      throw const FormatException(
        'The selected file changed. Choose it again.',
      );
    }
    final checksum = (await Sha256().hash(
      bytes,
    )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return ExpensePickedDocument(mime, bytes, checksum);
  }

  @override
  Future<String?> chooseExport(String fileName) async => (await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: 'Expense evidence export',
        extensions: [fileName.split('.').last],
      ),
    ],
  ))?.path;
  @override
  Future<void> write(String path, Uint8List bytes, String mime) =>
      XFile.fromData(bytes, mimeType: mime).saveTo(path);
}
