import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:jentra_domain/jentra_assurance.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'assurance_evidence_files.dart';

/// Evidence bytes that hashed, on this device, to the recorded digest.
final class DownloadedEvidence {
  const DownloadedEvidence(this.bytes, this.sha256);
  final Uint8List bytes;
  final String sha256;
}

/// Reviewer download of verified evidence (A12 `assurance-evidence-download`).
abstract interface class AssuranceEvidenceDownloadGateway {
  /// Returns the file only when its bytes hash to the recorded digest and
  /// size, and to [expectedSha256] when the caller has one.
  Future<DownloadedEvidence> download(
    TenantContext scope,
    String engagementId,
    String evidenceId, {
    String? expectedSha256,
  });
}

final class SupabaseAssuranceEvidenceDownloadGateway
    implements AssuranceEvidenceDownloadGateway {
  SupabaseAssuranceEvidenceDownloadGateway(this.client, {http.Client? files})
    : _files = files ?? http.Client();
  final SupabaseClient client;
  // The signed link carries its own token; no session header is sent with it.
  final http.Client _files;

  static const _mismatch = DomainError(
    code: 'EVIDENCE_MISMATCH',
    message:
        'The downloaded file does not match its recorded digest. Nothing was saved.',
  );

  @override
  Future<DownloadedEvidence> download(
    TenantContext s,
    String engagementId,
    String evidenceId, {
    String? expectedSha256,
  }) async {
    assuranceId(engagementId);
    assuranceId(evidenceId);
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    final Object? data;
    try {
      data = (await client.functions.invoke(
        assuranceEvidenceDownloadFunction,
        body: {
          'tenant_id': s.tenantId,
          'legal_entity_id': s.legalEntityId,
          'branch_id': s.branchId,
          'engagement_id': engagementId,
          'evidence_id': evidenceId,
        },
      )).data;
    } on FunctionException catch (e) {
      throw switch (e.status) {
        401 || 403 => const DomainError(
          code: 'PERMISSION_DENIED',
          message: 'Audit access is required to download this evidence.',
        ),
        404 => const DomainError(
          code: 'NOT_FOUND',
          message: 'The evidence is no longer available here.',
        ),
        409 => const DomainError(
          code: 'VALIDATION_ERROR',
          message:
              'Only evidence whose stored file has been verified can be '
              'downloaded. Verify it first.',
        ),
        _ => const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'The download link could not be prepared. Try again.',
        ),
      };
    }
    if (data is! Map) throw const FormatException('Invalid download response.');
    final t = EvidenceDownloadTicket.fromJson(
      data.cast<String, Object?>(),
      evidenceId: evidenceId,
    );
    if (expectedSha256 != null && assuranceDigest(expectedSha256) != t.sha256) {
      throw _mismatch;
    }
    final bytes = await _fetch(t);
    final sha = await assuranceSha256(bytes);
    if (bytes.length != t.byteSize || sha != t.sha256) throw _mismatch;
    return DownloadedEvidence(bytes, sha);
  }

  /// Reads at most one byte past the recorded size, so a longer object is a
  /// mismatch rather than an unbounded download.
  Future<Uint8List> _fetch(EvidenceDownloadTicket t) async {
    final b = BytesBuilder(copy: false);
    try {
      final r = await _files
          .send(http.Request('GET', t.url))
          .timeout(t.expiresIn);
      if (r.statusCode != 200) throw const _Failed();
      await for (final chunk in r.stream) {
        b.add(chunk);
        if (b.length > t.byteSize) break;
      }
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The file did not finish downloading. Try again.',
      );
    }
    return b.takeBytes();
  }
}

final class _Failed implements Exception {
  const _Failed();
}
