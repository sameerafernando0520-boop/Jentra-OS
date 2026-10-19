/// Manually submitted assurance evidence: the bytes go to the protected
/// upload path and the server records what they actually hash to before the
/// evidence can be accepted (PR #1 review, thread 4309904782).
///
/// The client computes the digest only to propose it. Acceptance depends on
/// the verification the server records after hashing the stored object.
library;

import 'assurance.dart';

/// Private bucket whose object names are the generated storage references.
const assuranceEvidenceBucket = 'jentra-assurance-evidence';

/// Edge function that hashes the stored bytes and records the outcome.
const assuranceEvidenceVerifyFunction = 'assurance-evidence-verify';

/// File types the evidence bucket accepts, by lower-case extension.
const assuranceEvidenceMimeTypes = {
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};

/// MIME type for [fileName], or a [FormatException] for unsupported types.
String assuranceEvidenceMime(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final mime = dot < 0
      ? null
      : assuranceEvidenceMimeTypes[fileName.substring(dot + 1).toLowerCase()];
  if (mime == null) {
    throw const FormatException(
      'Choose a PDF, image, text, CSV, Excel or Word file.',
    );
  }
  return mime;
}

/// Builds the exact `submit_evidence` payload for an uploaded file. The
/// storage reference is generated from scope; the source reference is the
/// file's name, bounded to the server's 200 characters.
Map<String, Object?> manualEvidencePayload({
  required String tenantId,
  required String engagementId,
  required String requestId,
  required String evidenceId,
  required String fileName,
  required String sha256,
  required int byteSize,
  required DateTime sourceAsOf,
  required DateTime now,
  String classification = 'confidential',
}) {
  final name = fileName.trim();
  final p = <String, Object?>{
    'action': 'submit_evidence',
    'engagement_id': assuranceId(engagementId),
    'request_id': assuranceId(requestId),
    'evidence_id': assuranceId(evidenceId),
    'source_module': 'manual',
    'source_reference': name.length > 200 ? name.substring(0, 200) : name,
    'source_as_of': sourceAsOf.toUtc().toIso8601String(),
    'collection_method': 'manual',
    'query_version': null,
    'sha256': sha256,
    'byte_size': byteSize,
    'storage_ref': assuranceStorageRef(tenantId, engagementId, evidenceId),
    'classification': classification,
  };
  AssuranceCommands.validate(
    'submit_evidence',
    p,
    now: now,
    tenantId: tenantId,
  );
  return p;
}

/// The server's record of what the stored object hashed to.
final class StoredEvidenceVerification {
  StoredEvidenceVerification.fromJson(
    Map<String, Object?> j, {
    String? evidenceId,
  }) : evidenceId = assuranceId(j['evidence_id']),
       outcome = switch (j['outcome']) {
         'verified' || 'mismatch' => j['outcome'] as String,
         _ => throw const FormatException('Unknown verification outcome.'),
       },
       observedSha256 = assuranceDigest(j['observed_sha256']),
       observedByteSize =
           j['observed_byte_size'] is int &&
               (j['observed_byte_size'] as int) >= 0
           ? j['observed_byte_size'] as int
           : throw const FormatException('Observed size is required.'),
       verifiedAt =
           DateTime.tryParse(j['verified_at'] as String? ?? '') ??
           (throw const FormatException('Verification time is required.')) {
    if (j['verifier'] != 'assurance-evidence-verify/v1') {
      throw const FormatException('Unknown evidence verifier.');
    }
    if (evidenceId != null && this.evidenceId != evidenceId) {
      throw const FormatException('Verification belongs to other evidence.');
    }
  }

  final String evidenceId;
  final String outcome;
  final String observedSha256;
  final int observedByteSize;
  final DateTime verifiedAt;

  /// The stored bytes match the submitted digest and size.
  bool get verified => outcome == 'verified';

  /// True only if the server's observation also matches what this client
  /// proposed — a second, local check of the server's answer.
  bool confirms({required String sha256, required int byteSize}) =>
      verified && observedSha256 == sha256 && observedByteSize == byteSize;
}

/// Read model: whether an evidence item needs bytes, has them and is verified.
final class EvidenceVerificationStatus {
  EvidenceVerificationStatus.fromJson(Map<String, Object?> j)
    : engagementId = assuranceId(j['engagement_id']),
      evidenceId = assuranceId(j['evidence_id']),
      sha256 = assuranceDigest(j['sha256']),
      byteSize = j['byte_size'] is int && (j['byte_size'] as int) > 0
          ? j['byte_size'] as int
          : throw const FormatException('Evidence size is required.'),
      uploadRequired = _bool(j['upload_required']),
      stored = _bool(j['stored']),
      bytesVerified = _bool(j['bytes_verified']),
      verification = j['verification'] == null
          ? null
          : StoredEvidenceVerification.fromJson(
              (j['verification'] as Map).cast<String, Object?>(),
              evidenceId: j['evidence_id'] as String?,
            ) {
    if (bytesVerified &&
        (verification == null ||
            !verification!.confirms(sha256: sha256, byteSize: byteSize))) {
      throw const FormatException('Verified status lacks a matching record.');
    }
  }

  final String engagementId;
  final String evidenceId;
  final String sha256;
  final int byteSize;
  final bool uploadRequired;
  final bool stored;
  final bool bytesVerified;
  final StoredEvidenceVerification? verification;

  /// Evidence a reviewer may accept: server-collected, or bytes verified.
  bool get acceptable => !uploadRequired || bytesVerified;
}

bool _bool(Object? v) =>
    v is bool ? v : throw const FormatException('A boolean is required.');
