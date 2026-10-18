import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:jentra_domain/jentra_assurance.dart';

/// Outcome of checking a downloaded audit pack against its recorded digest.
final class AuditPackVerification {
  const AuditPackVerification(this.pack, this.computedSha256, this.verified);
  final AuditPackManifest pack;
  final String computedSha256;
  final bool verified;

  /// Bytes to save. Only call when [verified] is true.
  Uint8List get bytes => verified
      ? Uint8List.fromList(pack.bytes)
      : throw StateError('Unverified audit pack must not be saved.');
}

/// Parses an `api.assurance_export_manifest` response and hashes the exact
/// `manifest_text` bytes. Reopening a saved pack runs the same check on the
/// file's bytes via [verifySaved].
abstract final class AssurancePackVerifier {
  static Future<String> _sha256(List<int> bytes) async => (await Sha256().hash(
    bytes,
  )).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Future<AuditPackVerification> verify(
    Map<String, Object?> response,
  ) async {
    final pack = AuditPackManifest.fromResponse(response);
    final computed = await _sha256(pack.bytes);
    return AuditPackVerification(pack, computed, pack.verifies(computed));
  }

  /// True when previously saved bytes still hash to the recorded digest.
  static Future<bool> verifySaved(
    List<int> saved,
    String recordedSha256,
  ) async => assuranceDigest(recordedSha256) == await _sha256(saved);
}
