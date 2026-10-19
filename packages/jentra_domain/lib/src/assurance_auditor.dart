// Corporate Audit & Assurance: auditor actions offered on the desktop
// engagement view (evidence requests and review, system snapshots,
// exceptions, finding issue and audit-pack export).
//
// Availability mirrors the server rules in api.assurance_command and
// api.assurance_evidence_command so the workspace does not offer a command the
// server would refuse for state or capability; team role and recorder checks
// that the read model does not expose stay server-side.
import 'assurance.dart';
import 'assurance_evidence.dart';

/// Which API serves an auditor action.
enum AssuranceRpc {
  engagement('assurance_command'),
  evidence('assurance_evidence_command');

  const AssuranceRpc(this.function);
  final String function;
}

/// One governed auditor command. [aggregateKey] names the payload id the
/// server echoes as the receipt's `aggregate_id`.
final class AuditorAction {
  const AuditorAction._(this.action, this.rpc, this.aggregateKey, this.label);

  final String action;
  final AssuranceRpc rpc;
  final String aggregateKey;
  final String label;

  static const all = <String, AuditorAction>{
    'request_evidence': AuditorAction._(
      'request_evidence',
      AssuranceRpc.engagement,
      'request_id',
      'Request evidence',
    ),
    'collect_system_evidence': AuditorAction._(
      'collect_system_evidence',
      AssuranceRpc.evidence,
      'request_id',
      'Collect system snapshot',
    ),
    'review_evidence': AuditorAction._(
      'review_evidence',
      AssuranceRpc.engagement,
      'request_id',
      'Review evidence',
    ),
    'record_exception': AuditorAction._(
      'record_exception',
      AssuranceRpc.engagement,
      'exception_id',
      'Record exception',
    ),
    'dismiss_exception': AuditorAction._(
      'dismiss_exception',
      AssuranceRpc.engagement,
      'exception_id',
      'Dismiss exception',
    ),
    'issue_finding': AuditorAction._(
      'issue_finding',
      AssuranceRpc.engagement,
      'finding_id',
      'Issue finding',
    ),
    'export_pack': AuditorAction._(
      'export_pack',
      AssuranceRpc.evidence,
      'export_id',
      'Export audit pack',
    ),
  };

  static AuditorAction of(String action) =>
      all[action] ?? (throw const FormatException('Unknown auditor action.'));

  String get capability => rpc == AssuranceRpc.evidence
      ? AssuranceEvidenceCommands.capability(action)
      : AssuranceCommands.capability(action);

  bool get requiresRecentMfa => rpc == AssuranceRpc.evidence
      ? AssuranceEvidenceCommands.requiresRecentMfa(action)
      : AssuranceCommands.requiresRecentMfa(action);

  Set<String> get fields => rpc == AssuranceRpc.evidence
      ? AssuranceEvidenceCommands.fields(action)
      : AssuranceCommands.fields(action);

  void validate(
    Map<String, Object?> p, {
    required DateTime now,
    required String tenantId,
  }) => rpc == AssuranceRpc.evidence
      ? AssuranceEvidenceCommands.validate(action, p)
      : AssuranceCommands.validate(action, p, now: now, tenantId: tenantId);

  /// True when [receipt] confirms this exact command advanced the engagement
  /// by one version.
  bool confirms(
    Map<String, Object?> receipt,
    Map<String, Object?> payload,
    int expectedVersion,
  ) =>
      receipt['action'] == action &&
      receipt['engagement_id'] == payload['engagement_id'] &&
      receipt['aggregate_id'] == payload[aggregateKey] &&
      receipt['version'] == expectedVersion + 1;
}

typedef AuditorControl = ({
  String id,
  String code,
  String title,
  String ownerId,
  AssuranceSeverity risk,
});
typedef AuditorRequest = ({
  String id,
  String controlId,
  String ownerId,
  EvidenceRequestStatus status,
  String dueDate,
  String? evidenceSha256,
  String? collectedBy,
});
typedef AuditorException = ({
  String id,
  String controlId,
  AssuranceSeverity severity,
  ExceptionStatus status,
  String source,
});
typedef AuditorReport = ({String id, int version, String digest});

/// The parts of `api.assurance_engagement` an auditor acts on. Parsing fails
/// closed on unknown states, malformed ids or digests.
final class AuditorEngagementView {
  AuditorEngagementView.fromJson(Map<String, Object?> j)
    : id = assuranceId(_m(j['engagement'])['id']),
      version = _version(_m(j['engagement'])['version']),
      status = EngagementStatus.parse(_m(j['engagement'])['status']),
      evidenceFrozen = _m(j['engagement'])['evidence_frozen_at'] != null,
      controls = [
        for (final c in _l(j['controls']))
          (
            id: assuranceId(_m(c)['id']),
            code: assuranceText(_m(c)['control_code'], 1, 40),
            title: assuranceText(_m(c)['title'], 1, 160),
            ownerId: assuranceId(_m(c)['owner_id']),
            risk: AssuranceSeverity.parse(_m(c)['risk']),
          ),
      ],
      requests = [
        for (final r in _l(j['requests']))
          (
            id: assuranceId(_m(r)['id']),
            controlId: assuranceId(_m(r)['control_id']),
            ownerId: assuranceId(_m(r)['owner_id']),
            status: EvidenceRequestStatus.parse(_m(r)['status']),
            dueDate: assuranceDate(_m(r)['due_date']),
            evidenceSha256: _m(r)['evidence'] == null
                ? null
                : assuranceDigest(_m(_m(r)['evidence'])['sha256']),
            collectedBy: _m(r)['evidence'] == null
                ? null
                : assuranceId(_m(_m(r)['evidence'])['collected_by']),
          ),
      ],
      exceptions = [
        for (final x in _l(j['exceptions']))
          (
            id: assuranceId(_m(x)['id']),
            controlId: assuranceId(_m(x)['control_id']),
            severity: AssuranceSeverity.parse(_m(x)['severity']),
            status: ExceptionStatus.parse(_m(x)['status']),
            source: _source(_m(x)['source']),
          ),
      ],
      reports = [
        for (final v in _l(j['reports']))
          (
            id: assuranceId(_m(v)['id']),
            version: _version(_m(v)['report_version']),
            digest: assuranceDigest(_m(v)['digest']),
          ),
      ];

  final String id;
  final int version;
  final EngagementStatus status;
  final bool evidenceFrozen;
  final List<AuditorControl> controls;
  final List<AuditorRequest> requests;
  final List<AuditorException> exceptions;
  final List<AuditorReport> reports;

  AuditorControl? control(String id) =>
      controls.where((c) => c.id == id).firstOrNull;

  /// The latest report version; only it can be exported.
  AuditorReport? get currentReport => reports.isEmpty
      ? null
      : reports.reduce((a, b) => a.version >= b.version ? a : b);

  bool get _collecting =>
      status == EngagementStatus.fieldwork && !evidenceFrozen;
  bool get _concluding =>
      status == EngagementStatus.fieldwork ||
      status == EngagementStatus.reporting;

  bool canRequestEvidence(Set<String> caps) =>
      caps.contains('assurance.evidence.request') &&
      (status == EngagementStatus.planning ||
          status == EngagementStatus.fieldwork) &&
      !evidenceFrozen;

  bool canCollect(Set<String> caps, AuditorRequest r) =>
      caps.contains('assurance.evidence.request') &&
      _collecting &&
      r.status == EvidenceRequestStatus.open;

  /// Collectors never review evidence they collected.
  bool canReview(Set<String> caps, AuditorRequest r, String actorId) =>
      caps.contains('assurance.test.review') &&
      !evidenceFrozen &&
      r.status == EvidenceRequestStatus.submitted &&
      r.collectedBy != actorId;

  bool canRecordException(Set<String> caps) =>
      caps.contains('assurance.test.perform') && _concluding;

  bool canDismiss(Set<String> caps, AuditorException x) =>
      caps.contains('assurance.test.review') &&
      _concluding &&
      x.status == ExceptionStatus.candidate;

  bool canIssueFinding(Set<String> caps, AuditorException x) =>
      caps.contains('assurance.finding.issue') &&
      _concluding &&
      x.status == ExceptionStatus.candidate;

  /// Only issued engagements export: an export advances the engagement
  /// version, and archived engagements are read-only. Packs exported before
  /// archival stay readable.
  bool canExport(Set<String> caps) =>
      caps.contains('assurance.report.export') &&
      status == EngagementStatus.issued &&
      currentReport != null;
}

Map<String, Object?> _m(Object? v) => v is Map
    ? v.cast<String, Object?>()
    : throw const FormatException('Object expected.');

List<Object?> _l(Object? v) =>
    v is List ? v : throw const FormatException('List expected.');

int _version(Object? v) =>
    v is int && v > 0 ? v : throw const FormatException('Positive version.');

String _source(Object? v) =>
    const {'manual', 'continuous_monitoring', 'carry_forward'}.contains(v)
    ? v! as String
    : throw const FormatException('Unknown exception source.');
