// Corporate Audit & Assurance: auditor actions offered on the desktop
// engagement view — evidence requests and review, system snapshots,
// exceptions, findings, engagement stages, evidence freeze, reports, risk
// decisions, retests, test procedures and audit-pack export.
//
// Availability mirrors the server rules in api.assurance_command,
// api.assurance_test_command and api.assurance_evidence_command so the
// workspace does not offer a command the server would refuse for state or
// capability; team-role, recorder and designer checks that the read models do
// not expose stay server-side.
import 'assurance.dart';
import 'assurance_evidence.dart';

/// Which API serves an auditor action.
enum AssuranceRpc {
  engagement('assurance_command'),
  test('assurance_test_command'),
  evidence('assurance_evidence_command');

  const AssuranceRpc(this.function);
  final String function;
}

/// One governed auditor command. [aggregateKey] names the payload id the
/// server echoes as the receipt's `aggregate_id`; engagement-level commands
/// echo the engagement itself.
final class AuditorAction {
  const AuditorAction._(this.action, this.rpc, this.aggregateKey, this.label);

  final String action;
  final AssuranceRpc rpc;
  final String aggregateKey;
  final String label;

  static const _e = AssuranceRpc.engagement;
  static const _t = AssuranceRpc.test;
  static const _v = AssuranceRpc.evidence;

  static const all = <String, AuditorAction>{
    'request_evidence': AuditorAction._(
      'request_evidence',
      _e,
      'request_id',
      'Request evidence',
    ),
    'collect_system_evidence': AuditorAction._(
      'collect_system_evidence',
      _v,
      'request_id',
      'Collect system snapshot',
    ),
    'review_evidence': AuditorAction._(
      'review_evidence',
      _e,
      'request_id',
      'Review evidence',
    ),
    'record_exception': AuditorAction._(
      'record_exception',
      _e,
      'exception_id',
      'Record exception',
    ),
    'dismiss_exception': AuditorAction._(
      'dismiss_exception',
      _e,
      'exception_id',
      'Dismiss exception',
    ),
    'issue_finding': AuditorAction._(
      'issue_finding',
      _e,
      'finding_id',
      'Issue finding',
    ),
    'export_pack': AuditorAction._(
      'export_pack',
      _v,
      'export_id',
      'Export audit pack',
    ),
    'transition': AuditorAction._(
      'transition',
      _e,
      'engagement_id',
      'Move engagement stage',
    ),
    'freeze_evidence': AuditorAction._(
      'freeze_evidence',
      _e,
      'engagement_id',
      'Freeze evidence',
    ),
    'issue_report': AuditorAction._(
      'issue_report',
      _e,
      'engagement_id',
      'Issue report',
    ),
    'reopen_report': AuditorAction._(
      'reopen_report',
      _e,
      'engagement_id',
      'Reopen report',
    ),
    'decide_risk': AuditorAction._(
      'decide_risk',
      _e,
      'finding_id',
      'Decide risk acceptance',
    ),
    'retest': AuditorAction._('retest', _e, 'finding_id', 'Retest finding'),
    'reopen_finding': AuditorAction._(
      'reopen_finding',
      _e,
      'finding_id',
      'Reopen finding',
    ),
    'design_test': AuditorAction._(
      'design_test',
      _t,
      'procedure_id',
      'Design test',
    ),
    'execute_test': AuditorAction._(
      'execute_test',
      _t,
      'procedure_id',
      'Record test run',
    ),
    'review_test': AuditorAction._(
      'review_test',
      _t,
      'procedure_id',
      'Review test',
    ),
  };

  static AuditorAction of(String action) =>
      all[action] ?? (throw const FormatException('Unknown auditor action.'));

  String get capability => switch (rpc) {
    AssuranceRpc.evidence => AssuranceEvidenceCommands.capability(action),
    AssuranceRpc.test => AssuranceTestCommands.capability(action),
    AssuranceRpc.engagement => AssuranceCommands.capability(action),
  };

  bool get requiresRecentMfa => switch (rpc) {
    AssuranceRpc.evidence => AssuranceEvidenceCommands.requiresRecentMfa(
      action,
    ),
    AssuranceRpc.test => AssuranceTestCommands.requiresRecentMfa(action),
    AssuranceRpc.engagement => AssuranceCommands.requiresRecentMfa(action),
  };

  Set<String> get fields => switch (rpc) {
    AssuranceRpc.evidence => AssuranceEvidenceCommands.fields(action),
    AssuranceRpc.test => AssuranceTestCommands.fields(action),
    AssuranceRpc.engagement => AssuranceCommands.fields(action),
  };

  /// [sampleSize] is the server-recorded size when recording a test run.
  void validate(
    Map<String, Object?> p, {
    required DateTime now,
    required String tenantId,
    int? sampleSize,
  }) => switch (rpc) {
    AssuranceRpc.evidence => AssuranceEvidenceCommands.validate(action, p),
    AssuranceRpc.test => AssuranceTestCommands.validate(
      action,
      p,
      sampleSize: sampleSize,
    ),
    AssuranceRpc.engagement => AssuranceCommands.validate(
      action,
      p,
      now: now,
      tenantId: tenantId,
    ),
  };

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
typedef AuditorFinding = ({
  String id,
  String title,
  AssuranceSeverity severity,
  FindingStatus status,
  String ownerId,
});
typedef AuditorReport = ({String id, int version, String digest});

/// Test procedure states (`assurance.test_procedures.status`).
enum TestProcedureStatus {
  designed,
  executed,
  reviewed;

  static TestProcedureStatus parse(Object? v) => values.firstWhere(
    (s) => s.name == v,
    orElse: () => throw const FormatException('Unknown test status.'),
  );
}

typedef AuditorTest = ({
  String id,
  String controlId,
  String code,
  TestProcedureStatus status,
  int populationSize,
  int sampleSize,
  String? lastRunBy,
});

/// The parts of `api.assurance_engagement` (and `api.assurance_tests`) an
/// auditor acts on. Parsing fails closed on unknown states, malformed ids or
/// digests.
final class AuditorEngagementView {
  AuditorEngagementView.fromJson(
    Map<String, Object?> j, {
    List<Object?> tests = const [],
  }) : id = assuranceId(_m(j['engagement'])['id']),
       version = _version(_m(j['engagement'])['version']),
       status = EngagementStatus.parse(_m(j['engagement'])['status']),
       leadAuditorId = assuranceId(_m(j['engagement'])['lead_auditor_id']),
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
       findings = [
         for (final f in _l(j['findings']))
           (
             id: assuranceId(_m(f)['id']),
             title: assuranceText(_m(f)['title'], 1, 160),
             severity: AssuranceSeverity.parse(_m(f)['severity']),
             status: FindingStatus.parse(_m(f)['status']),
             ownerId: assuranceId(_m(f)['owner_id']),
           ),
       ],
       reports = [
         for (final v in _l(j['reports']))
           (
             id: assuranceId(_m(v)['id']),
             version: _version(_m(v)['report_version']),
             digest: assuranceDigest(_m(v)['digest']),
           ),
       ],
       tests = [
         for (final t in tests)
           (
             id: assuranceId(_m(t)['id']),
             controlId: assuranceId(_m(t)['control_id']),
             code: assuranceText(_m(t)['code'], 1, 40),
             status: TestProcedureStatus.parse(_m(t)['status']),
             populationSize: _version(_m(t)['population_size']),
             sampleSize: _version(_m(t)['sample_size']),
             lastRunBy: _lastRunBy(_m(t)['runs']),
           ),
       ];

  final String id;
  final int version;
  final EngagementStatus status;
  final String leadAuditorId;
  final bool evidenceFrozen;
  final List<AuditorControl> controls;
  final List<AuditorRequest> requests;
  final List<AuditorException> exceptions;
  final List<AuditorFinding> findings;
  final List<AuditorReport> reports;
  final List<AuditorTest> tests;

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

  /// Stage moves the server allows from the current status. Issuing a report
  /// is its own command, never a transition.
  List<EngagementStatus> transitionTargets(Set<String> caps) {
    if (!caps.contains('assurance.engagement.manage')) return const [];
    return switch (status) {
      EngagementStatus.planning when controls.isNotEmpty => const [
        EngagementStatus.fieldwork,
      ],
      EngagementStatus.fieldwork when evidenceFrozen => const [
        EngagementStatus.reporting,
      ],
      EngagementStatus.issued
          when findings.every(
            (f) =>
                f.status == FindingStatus.closed ||
                f.status == FindingStatus.riskAccepted,
          ) =>
        const [EngagementStatus.archived],
      _ => const [],
    };
  }

  /// Only the lead auditor freezes, once every request is accepted or
  /// cancelled and at least one is accepted.
  bool canFreeze(Set<String> caps, String actorId) =>
      caps.contains('assurance.engagement.manage') &&
      _collecting &&
      actorId == leadAuditorId &&
      requests.any((r) => r.status == EvidenceRequestStatus.accepted) &&
      !requests.any(
        (r) =>
            r.status == EvidenceRequestStatus.open ||
            r.status == EvidenceRequestStatus.submitted,
      );

  /// The lead auditor never issues their own report, and candidate
  /// exceptions must be resolved first.
  bool canIssueReport(Set<String> caps, String actorId) =>
      caps.contains('assurance.engagement.close') &&
      status == EngagementStatus.reporting &&
      evidenceFrozen &&
      actorId != leadAuditorId &&
      !exceptions.any((x) => x.status == ExceptionStatus.candidate);

  bool canReopenReport(Set<String> caps) =>
      caps.contains('assurance.engagement.close') &&
      status == EngagementStatus.issued;

  /// Owners never decide their own risk acceptance (the issuer check stays
  /// server-side).
  bool canDecideRisk(Set<String> caps, AuditorFinding f, String actorId) =>
      caps.contains('assurance.engagement.close') &&
      f.status == FindingStatus.riskPending &&
      f.ownerId != actorId;

  bool canRetest(Set<String> caps, AuditorFinding f, String actorId) =>
      caps.contains('assurance.retest.perform') &&
      f.status == FindingStatus.retestPending &&
      f.ownerId != actorId;

  bool canReopenFinding(Set<String> caps, AuditorFinding f, String actorId) =>
      caps.contains('assurance.engagement.close') &&
      (f.status == FindingStatus.closed ||
          f.status == FindingStatus.riskAccepted) &&
      f.ownerId != actorId;

  bool canDesignTest(Set<String> caps) =>
      caps.contains('assurance.test.perform') &&
      (status == EngagementStatus.planning ||
          status == EngagementStatus.fieldwork);

  /// Tests run only on frozen evidence during fieldwork.
  bool canExecuteTest(Set<String> caps, AuditorTest t) =>
      caps.contains('assurance.test.perform') &&
      status == EngagementStatus.fieldwork &&
      evidenceFrozen &&
      t.status == TestProcedureStatus.designed;

  /// Whoever ran the test never reviews it (the designer check stays
  /// server-side).
  bool canReviewTest(Set<String> caps, AuditorTest t, String actorId) =>
      caps.contains('assurance.test.review') &&
      _concluding &&
      t.status == TestProcedureStatus.executed &&
      t.lastRunBy != actorId;
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

String? _lastRunBy(Object? runs) {
  final list = _l(runs ?? const []);
  return list.isEmpty ? null : assuranceId(_m(list.last)['performed_by']);
}
