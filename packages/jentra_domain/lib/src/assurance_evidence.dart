// Corporate Audit & Assurance A4/A4b: system evidence adapters, continuous
// monitoring and audit packs.
//
// Mirrors api.assurance_evidence_command, api.assurance_verify_evidence and
// api.assurance_export_manifest in
// supabase/candidates/20261018150000_assurance_evidence_adapters_export.sql and
// supabase/candidates/20261018170000_assurance_adapters_monitoring.sql.
// Hashing is done by the platform layer over the exact `manifest_text` bytes.
import 'dart:convert';

import 'assurance.dart';

/// Authoritative sources an adapter may bind, with the owning module, query
/// version and classification the server records.
const assuranceSourceKinds =
    <String, ({String module, String queryVersion, String classification})>{
      'finance.financial_statement': (
        module: 'finance',
        queryVersion: 'fin.financial_reports.v1',
        classification: 'confidential',
      ),
      'finance.close_review': (
        module: 'finance',
        queryVersion: 'fin.close_control_reviews.v1',
        classification: 'confidential',
      ),
      'finance.control_reconciliation': (
        module: 'finance',
        queryVersion: 'fin.control_reports.v1',
        classification: 'confidential',
      ),
      'finance.tax_summary': (
        module: 'finance',
        queryVersion: 'fin.tax_reports.v1',
        classification: 'confidential',
      ),
      'inventory.valuation': (
        module: 'inventory',
        queryVersion: 'inv.valuation_reports.v1',
        classification: 'confidential',
      ),
      'it_control.access_review': (
        module: 'it_control',
        queryVersion: 'core.access_review.v1',
        classification: 'restricted',
      ),
      'procurement.three_way_match': (
        module: 'procurement',
        queryVersion: 'proc.supplier_bill_match.v1',
        classification: 'confidential',
      ),
      'workforce.attendance_approvals': (
        module: 'workforce',
        queryVersion: 'people.attendance_approvals.v1',
        classification: 'restricted',
      ),
    };

/// Kinds the server builds as an immutable period snapshot over the
/// engagement period (A4b). They take no `source_id`, and only they can be
/// input to `run_monitoring`.
const assuranceSnapshotKinds = {
  'it_control.access_review',
  'procurement.three_way_match',
  'workforce.attendance_approvals',
};

/// Continuous-monitoring rules (`assurance.monitoring_rules`). A hit becomes a
/// candidate exception only; promotion to a finding stays a separate,
/// independent decision.
const assuranceMonitoringRules = <String, ({String kind, String severity})>{
  'ACCESS_PRIVILEGED_NO_MFA': (
    kind: 'it_control.access_review',
    severity: 'high',
  ),
  'P2P_MATCH_OVERRIDE': (
    kind: 'procurement.three_way_match',
    severity: 'medium',
  ),
  'P2P_OVERRIDE_BY_CREATOR': (
    kind: 'procurement.three_way_match',
    severity: 'high',
  ),
  'HR_ATTENDANCE_SELF_APPROVAL': (
    kind: 'workforce.attendance_approvals',
    severity: 'high',
  ),
};

/// Commands served by `api.assurance_evidence_command`.
abstract final class AssuranceEvidenceCommands {
  static const _capabilities = <String, String>{
    'collect_system_evidence': 'assurance.evidence.request',
    'export_pack': 'assurance.report.export',
    'run_monitoring': 'assurance.test.perform',
  };
  static const _fields = <String, List<String>>{
    'collect_system_evidence': [
      'request_id',
      'evidence_id',
      'source_kind',
      'source_id',
    ],
    'export_pack': ['export_id', 'report_id'],
    'run_monitoring': ['evidence_id', 'control_id'],
  };

  static String capability(String action) =>
      _capabilities[action] ??
      (throw const FormatException('Unknown assurance evidence action.'));

  static Set<String> fields(String action) {
    capability(action);
    return {'action', 'engagement_id', ..._fields[action]!};
  }

  static bool requiresRecentMfa(String action) {
    capability(action);
    return action == 'export_pack';
  }

  static void validate(String action, Map<String, Object?> p) {
    final allowed = fields(action);
    for (final k in p.keys) {
      if (!allowed.contains(k)) {
        throw FormatException('Unexpected assurance field $k.');
      }
    }
    if (p['action'] != action) {
      throw const FormatException('Assurance action changed.');
    }
    assuranceId(p['engagement_id']);
    if (action == 'collect_system_evidence') {
      assuranceId(p['request_id']);
      assuranceId(p['evidence_id']);
      final kind = p['source_kind'];
      if (!assuranceSourceKinds.containsKey(kind)) {
        throw const FormatException('Unknown evidence source kind.');
      }
      if (assuranceSnapshotKinds.contains(kind)) {
        if (p['source_id'] != null) {
          throw const FormatException('Period snapshots take no source id.');
        }
      } else {
        assuranceId(p['source_id']);
      }
    } else if (action == 'run_monitoring') {
      assuranceId(p['evidence_id']);
      assuranceId(p['control_id']);
    } else {
      assuranceId(p['export_id']);
      assuranceId(p['report_id']);
    }
  }
}

/// Result of `api.assurance_verify_evidence`.
final class EvidenceVerification {
  EvidenceVerification.fromJson(Map<String, Object?> j)
    : evidenceId = assuranceId(j['evidence_id']),
      recordedSha256 = assuranceDigest(j['recorded_sha256']),
      currentSha256 = assuranceDigest(j['current_sha256']),
      matches = j['matches'] is bool
          ? j['matches']! as bool
          : throw const FormatException('Verification result required.') {
    if (matches != (recordedSha256 == currentSha256)) {
      throw const FormatException('Inconsistent verification result.');
    }
  }

  final String evidenceId;
  final String recordedSha256;
  final String currentSha256;
  final bool matches;
}

/// A downloaded audit pack. Parsing fails closed: the structure must be the
/// expected format, `manifest_text` must decode to the same manifest, and the
/// recorded size must equal the UTF-8 byte length. The SHA-256 itself is
/// checked by the platform over [bytes].
final class AuditPackManifest {
  factory AuditPackManifest.fromResponse(Map<String, Object?> j) {
    final text = j['manifest_text'];
    if (text is! String || text.isEmpty) {
      throw const FormatException('Audit pack text is required.');
    }
    final bytes = utf8.encode(text);
    final recordedBytes = j['manifest_bytes'];
    if (recordedBytes is! int || recordedBytes != bytes.length) {
      throw const FormatException('Audit pack size does not match.');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map || jsonEncode(decoded) != jsonEncode(j['manifest'])) {
      throw const FormatException('Audit pack text and manifest differ.');
    }
    final m = decoded.cast<String, Object?>();
    if (m['format'] != 'jentra.assurance.audit_pack.v1') {
      throw const FormatException('Unknown audit pack format.');
    }
    final engagement = (m['engagement'] as Map?)?.cast<String, Object?>();
    final report = (m['report'] as Map?)?.cast<String, Object?>();
    final evidence = m['evidence'];
    if (engagement == null || report == null || evidence is! List) {
      throw const FormatException('Incomplete audit pack.');
    }
    final items = [
      for (final e in evidence)
        (
          id: assuranceId((e as Map)['id']),
          sha256: assuranceDigest(e['sha256']),
          byteSize: e['byte_size'] is int && (e['byte_size'] as int) > 0
              ? e['byte_size'] as int
              : throw const FormatException('Evidence size required.'),
          sourceModule: assuranceSourceModules.contains(e['source_module'])
              ? e['source_module'] as String
              : throw const FormatException('Unknown evidence module.'),
        ),
    ];
    if (text.contains('storage_ref')) {
      throw const FormatException('Audit pack must not carry storage paths.');
    }
    return AuditPackManifest._(
      exportId: assuranceId(j['export_id']),
      recordedSha256: assuranceDigest(j['manifest_sha256']),
      bytes: bytes,
      engagementId: assuranceId(engagement['id']),
      cutoffDigest: assuranceDigest(engagement['evidence_cutoff_digest']),
      reportDigest: assuranceDigest(report['digest']),
      reportVersion: report['report_version'] is int
          ? report['report_version']! as int
          : throw const FormatException('Report version required.'),
      evidence: items,
    );
  }

  AuditPackManifest._({
    required this.exportId,
    required this.recordedSha256,
    required this.bytes,
    required this.engagementId,
    required this.cutoffDigest,
    required this.reportDigest,
    required this.reportVersion,
    required this.evidence,
  });

  final String exportId;
  final String recordedSha256;

  /// Exact UTF-8 bytes to hash and save.
  final List<int> bytes;
  final String engagementId;
  final String cutoffDigest;
  final String reportDigest;
  final int reportVersion;
  final List<({String id, String sha256, int byteSize, String sourceModule})>
  evidence;

  /// True only when [computedSha256] (over [bytes]) equals the recorded digest.
  bool verifies(String computedSha256) =>
      assuranceDigest(computedSha256) == recordedSha256;
}
