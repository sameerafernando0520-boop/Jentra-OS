// Corporate Audit & Assurance A12: reviewer download of verified evidence
// (edge function `assurance-evidence-download`). The link is short-lived and
// carries the recorded digest and size; the device hashes the bytes again and
// saves nothing unless they match.
import 'assurance.dart';

const assuranceEvidenceDownloadFunction = 'assurance-evidence-download';

final class EvidenceDownloadTicket {
  EvidenceDownloadTicket.fromJson(
    Map<String, Object?> j, {
    required String evidenceId,
  }) : evidenceId = assuranceId(j['evidence_id']),
       url = _https(j['url']),
       expiresIn = switch (j['expires_in']) {
         final int s when s > 0 && s <= 300 => Duration(seconds: s),
         _ => throw const FormatException('Download links last 5 minutes.'),
       },
       sha256 = assuranceDigest(j['sha256']),
       byteSize = switch (j['byte_size']) {
         final int n when n > 0 && n <= assuranceMaxEvidenceBytes => n,
         _ => throw const FormatException('Evidence size is out of range.'),
       } {
    if (this.evidenceId != evidenceId) {
      throw const FormatException('Download belongs to other evidence.');
    }
  }

  final String evidenceId;
  final Uri url;
  final Duration expiresIn;
  final String sha256;
  final int byteSize;

  static Uri _https(Object? v) {
    final u = v is String ? Uri.tryParse(v) : null;
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      throw const FormatException('Download links must be https.');
    }
    return u;
  }
}

/// The name to save evidence under: the last segment of its recorded source
/// reference, with characters Windows refuses replaced.
String assuranceEvidenceFileName(String sourceReference, String evidenceId) {
  final last = sourceReference.split(RegExp(r'[\/]')).last;
  final safe = last
      .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'^[\s.]+|[\s.]+$'), '');
  return safe.isEmpty ? 'evidence-${evidenceId.substring(0, 8)}.bin' : safe;
}
