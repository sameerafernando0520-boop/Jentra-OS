import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:file_selector/file_selector.dart';
import 'package:jentra_domain/jentra_assurance.dart';

/// A chosen evidence file with the digest the client proposes for it.
final class AssurancePickedEvidence {
  const AssurancePickedEvidence(this.name, this.mime, this.bytes, this.sha256);
  final String name, mime, sha256;
  final Uint8List bytes;
}

abstract interface class AssuranceEvidenceFiles {
  Future<AssurancePickedEvidence?> choose();
}

/// Reads exactly [expectedLength] bytes and refuses a file that grows or
/// shrinks while it is read.
Future<Uint8List> readAssuranceEvidenceBytes(
  Stream<List<int>> chunks,
  int expectedLength,
) async {
  if (expectedLength < 1 || expectedLength > assuranceMaxEvidenceBytes) {
    throw const FormatException('Choose a file of 1 byte to 100 MiB.');
  }
  final bytes = BytesBuilder(copy: false);
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

Future<String> assuranceSha256(List<int> bytes) async => (await Sha256().hash(
  bytes,
)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final class NativeAssuranceEvidenceFiles implements AssuranceEvidenceFiles {
  const NativeAssuranceEvidenceFiles();

  @override
  Future<AssurancePickedEvidence?> choose() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Audit evidence',
          extensions: assuranceEvidenceMimeTypes.keys.toList(),
        ),
      ],
    );
    if (file == null) return null;
    final mime = assuranceEvidenceMime(file.name);
    final length = await file.length();
    final bytes = await readAssuranceEvidenceBytes(
      file.openRead(0, length + 1),
      length,
    );
    if (await file.length() != length) {
      throw const FormatException(
        'The selected file changed. Choose it again.',
      );
    }
    return AssurancePickedEvidence(
      file.name,
      mime,
      bytes,
      await assuranceSha256(bytes),
    );
  }
}
