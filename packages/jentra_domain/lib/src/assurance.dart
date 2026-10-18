// Corporate Audit & Assurance domain contract (blueprint 68).
//
// Mirrors the server-authoritative rules in
// supabase/candidates/20261018090000_assurance_engagement_core.sql so the client
// can reject invalid commands early. The server remains the authority; nothing
// here grants access.

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _civilDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _controlCode = RegExp(r'^[A-Z0-9][A-Z0-9._-]{1,39}$');
final _queryVersion = RegExp(r'^[a-z0-9._-]{1,64}$');

const assuranceMaxEvidenceBytes = 104857600;
const assuranceRecentMfaWindow = Duration(minutes: 15);
const assuranceMaxExternalAccess = Duration(days: 90);

enum AssuranceSeverity {
  low,
  medium,
  high,
  critical;

  static AssuranceSeverity parse(Object? v) =>
      _enumValue(values, v, 'severity');
}

enum EngagementStatus {
  planning,
  fieldwork,
  reporting,
  issued,
  archived,
  cancelled;

  static EngagementStatus parse(Object? v) => _enumValue(values, v, 'status');

  bool get closed => this == archived || this == cancelled;
}

enum EvidenceRequestStatus {
  open,
  submitted,
  accepted,
  cancelled;

  static EvidenceRequestStatus parse(Object? v) =>
      _enumValue(values, v, 'status');
}

enum ExceptionStatus {
  candidate,
  promoted,
  dismissed;

  static ExceptionStatus parse(Object? v) => _enumValue(values, v, 'status');
}

enum FindingStatus {
  issued('issued'),
  remediating('remediating'),
  riskPending('risk_pending'),
  riskAccepted('risk_accepted'),
  retestPending('retest_pending'),
  closed('closed');

  const FindingStatus(this.wire);
  final String wire;

  static FindingStatus parse(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    throw const FormatException('Unknown finding status.');
  }

  bool get open => this != closed && this != riskAccepted;
}

T _enumValue<T extends Enum>(List<T> values, Object? v, String field) {
  for (final e in values) {
    if (e.name == v) return e;
  }
  throw FormatException('Unknown $field.');
}

/// Explicit engagement lifecycle. `issued` is reachable only through
/// `issue_report` and `reporting` again only through `reopen_report`.
const engagementTransitions = <EngagementStatus, Set<EngagementStatus>>{
  EngagementStatus.planning: {
    EngagementStatus.fieldwork,
    EngagementStatus.cancelled,
  },
  EngagementStatus.fieldwork: {
    EngagementStatus.reporting,
    EngagementStatus.cancelled,
  },
  EngagementStatus.reporting: {
    EngagementStatus.issued,
    EngagementStatus.cancelled,
  },
  EngagementStatus.issued: {
    EngagementStatus.reporting,
    EngagementStatus.archived,
  },
  EngagementStatus.archived: {},
  EngagementStatus.cancelled: {},
};

const findingTransitions = <FindingStatus, Set<FindingStatus>>{
  FindingStatus.issued: {FindingStatus.remediating, FindingStatus.riskPending},
  FindingStatus.riskPending: {
    FindingStatus.riskAccepted,
    FindingStatus.remediating,
  },
  FindingStatus.remediating: {FindingStatus.retestPending},
  FindingStatus.retestPending: {
    FindingStatus.closed,
    FindingStatus.remediating,
  },
  FindingStatus.closed: {FindingStatus.remediating},
  FindingStatus.riskAccepted: {FindingStatus.remediating},
};

bool canTransitionEngagement(EngagementStatus from, EngagementStatus to) =>
    engagementTransitions[from]!.contains(to);

bool canTransitionFinding(FindingStatus from, FindingStatus to) =>
    findingTransitions[from]!.contains(to);

abstract final class AssuranceCommands {
  static const _capabilities = <String, String>{
    'create_engagement': 'assurance.engagement.manage',
    'add_team_member': 'assurance.engagement.manage',
    'revoke_team_member': 'assurance.engagement.manage',
    'map_control': 'assurance.engagement.manage',
    'transition': 'assurance.engagement.manage',
    'freeze_evidence': 'assurance.engagement.manage',
    'request_evidence': 'assurance.evidence.request',
    'cancel_request': 'assurance.evidence.request',
    'submit_evidence': 'assurance.evidence.submit',
    'review_evidence': 'assurance.test.review',
    'record_exception': 'assurance.test.perform',
    'dismiss_exception': 'assurance.test.review',
    'issue_finding': 'assurance.finding.issue',
    'respond': 'assurance.response.manage',
    'decide_risk': 'assurance.engagement.close',
    'submit_remediation': 'assurance.remediation.manage',
    'retest': 'assurance.retest.perform',
    'reopen_finding': 'assurance.engagement.close',
    'issue_report': 'assurance.engagement.close',
    'reopen_report': 'assurance.engagement.close',
    'place_hold': 'assurance.retention.manage',
    'release_hold': 'assurance.retention.manage',
  };

  static const _fields = <String, List<String>>{
    'create_engagement': [
      'name',
      'period_start',
      'period_end',
      'scope_summary',
      'lead_auditor_id',
    ],
    'add_team_member': ['user_id', 'role', 'expires_at'],
    'revoke_team_member': ['user_id', 'reason'],
    'map_control': ['control_id', 'control_code', 'title', 'owner_id', 'risk'],
    'transition': ['to_status', 'reason'],
    'freeze_evidence': ['reason'],
    'request_evidence': [
      'request_id',
      'control_id',
      'owner_id',
      'due_date',
      'description',
    ],
    'cancel_request': ['request_id', 'reason'],
    'submit_evidence': [
      'request_id',
      'evidence_id',
      'source_module',
      'source_reference',
      'source_as_of',
      'collection_method',
      'query_version',
      'sha256',
      'byte_size',
      'storage_ref',
      'classification',
    ],
    'review_evidence': ['request_id', 'decision', 'reason'],
    'record_exception': [
      'exception_id',
      'control_id',
      'description',
      'severity',
    ],
    'dismiss_exception': ['exception_id', 'reason'],
    'issue_finding': [
      'finding_id',
      'exception_id',
      'title',
      'severity',
      'owner_id',
    ],
    'respond': ['finding_id', 'response', 'due_date', 'accept_risk'],
    'decide_risk': ['finding_id', 'decision', 'reason'],
    'submit_remediation': ['finding_id', 'evidence_sha256', 'note'],
    'retest': ['finding_id', 'retest_id', 'result', 'evidence_sha256', 'note'],
    'reopen_finding': ['finding_id', 'reason'],
    'issue_report': ['report_id', 'summary'],
    'reopen_report': ['reason'],
    'place_hold': ['hold_id', 'reason'],
    'release_hold': ['hold_id', 'reason'],
  };

  static const _recentMfa = {
    'freeze_evidence',
    'issue_finding',
    'decide_risk',
    'retest',
    'reopen_finding',
    'issue_report',
    'reopen_report',
    'release_hold',
  };

  static Iterable<String> get actions => _capabilities.keys;

  static String capability(String action) =>
      _capabilities[action] ??
      (throw const FormatException('Unknown assurance action.'));

  static Set<String> fields(String action) {
    capability(action);
    return {'action', 'engagement_id', ..._fields[action]!};
  }

  static bool requiresRecentMfa(String action) {
    capability(action);
    return _recentMfa.contains(action);
  }

  /// Validates the payload shape exactly as the server does. [now] bounds
  /// future dates; [tenantId] is needed to verify generated storage paths.
  static void validate(
    String action,
    Map<String, Object?> p, {
    required DateTime now,
    required String tenantId,
  }) {
    final allowed = fields(action);
    for (final k in p.keys) {
      if (!allowed.contains(k)) {
        throw FormatException('Unexpected assurance field $k.');
      }
    }
    if (p['action'] != action) {
      throw const FormatException('Assurance action changed.');
    }
    final engagement = assuranceId(p['engagement_id']);
    final today = _civil(now);
    switch (action) {
      case 'create_engagement':
        assuranceText(p['name'], 3, 160);
        assuranceText(p['scope_summary'], 3, 2000);
        assuranceId(p['lead_auditor_id']);
        if (assuranceDate(
              p['period_end'],
            ).compareTo(assuranceDate(p['period_start'])) <
            0) {
          throw const FormatException('Audit period ends before it starts.');
        }
      case 'add_team_member':
        assuranceId(p['user_id']);
        final role = p['role'];
        if (!{'auditor', 'reviewer', 'external'}.contains(role)) {
          throw const FormatException('Unknown team role.');
        }
        if (role == 'external') {
          final raw = p['expires_at'];
          final at = raw is String ? DateTime.tryParse(raw) : null;
          if (at == null ||
              !at.isAfter(now) ||
              at.isAfter(now.add(assuranceMaxExternalAccess))) {
            throw const FormatException(
              'External access must expire within 90 days.',
            );
          }
        } else if (p.containsKey('expires_at')) {
          throw const FormatException('Only external access expires.');
        }
      case 'revoke_team_member':
        assuranceId(p['user_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'map_control':
        assuranceId(p['control_id']);
        assuranceId(p['owner_id']);
        assuranceText(p['title'], 3, 160);
        final code = p['control_code'];
        if (code is! String || !_controlCode.hasMatch(code)) {
          throw const FormatException('Invalid control code.');
        }
        AssuranceSeverity.parse(p['risk']);
      case 'transition':
        final to = EngagementStatus.parse(p['to_status']);
        if (to == EngagementStatus.issued) {
          throw const FormatException('Reports are issued, not transitioned.');
        }
        assuranceText(p['reason'], 3, 1000);
      case 'freeze_evidence' || 'reopen_report':
        assuranceText(p['reason'], 3, 1000);
      case 'request_evidence':
        for (final k in ['request_id', 'control_id', 'owner_id']) {
          assuranceId(p[k]);
        }
        if (assuranceDate(p['due_date']).compareTo(today) < 0) {
          throw const FormatException('Evidence due date is in the past.');
        }
        assuranceText(p['description'], 3, 2000);
      case 'cancel_request':
        assuranceId(p['request_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'submit_evidence':
        EvidenceMetadata.fromCommand(
          p,
          tenantId: tenantId,
          engagementId: engagement,
          now: now,
        );
      case 'review_evidence':
        assuranceId(p['request_id']);
        if (!{'accept', 'reject'}.contains(p['decision'])) {
          throw const FormatException('Unknown evidence decision.');
        }
        assuranceText(p['reason'], 3, 1000);
      case 'record_exception':
        assuranceId(p['exception_id']);
        assuranceId(p['control_id']);
        assuranceText(p['description'], 3, 4000);
        AssuranceSeverity.parse(p['severity']);
      case 'dismiss_exception':
        assuranceId(p['exception_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'issue_finding':
        for (final k in ['finding_id', 'exception_id', 'owner_id']) {
          assuranceId(p[k]);
        }
        assuranceText(p['title'], 3, 160);
        AssuranceSeverity.parse(p['severity']);
      case 'respond':
        assuranceId(p['finding_id']);
        assuranceText(p['response'], 3, 4000);
        if (assuranceDate(p['due_date']).compareTo(today) < 0) {
          throw const FormatException('Response due date is in the past.');
        }
        if (p['accept_risk'] is! bool) {
          throw const FormatException('Risk acceptance must be explicit.');
        }
      case 'decide_risk':
        assuranceId(p['finding_id']);
        if (!{'approve', 'reject'}.contains(p['decision'])) {
          throw const FormatException('Unknown risk decision.');
        }
        assuranceText(p['reason'], 3, 1000);
      case 'submit_remediation':
        assuranceId(p['finding_id']);
        assuranceDigest(p['evidence_sha256']);
        assuranceText(p['note'], 3, 2000);
      case 'retest':
        assuranceId(p['finding_id']);
        assuranceId(p['retest_id']);
        if (!{'pass', 'fail'}.contains(p['result'])) {
          throw const FormatException('Unknown retest result.');
        }
        assuranceDigest(p['evidence_sha256']);
        assuranceText(p['note'], 3, 2000);
      case 'reopen_finding':
        assuranceId(p['finding_id']);
        assuranceText(p['reason'], 3, 1000);
      case 'issue_report':
        assuranceId(p['report_id']);
        assuranceText(p['summary'], 3, 4000);
      case 'place_hold' || 'release_hold':
        assuranceId(p['hold_id']);
        assuranceText(p['reason'], 3, 1000);
    }
  }
}

String _civil(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}';
}

String assuranceId(Object? v) {
  if (v is! String || !_uuid.hasMatch(v)) {
    throw const FormatException('A lowercase UUID is required.');
  }
  return v;
}

String assuranceText(Object? v, int min, int max) {
  if (v is! String) throw const FormatException('Text is required.');
  final n = v.trim().length;
  if (n < min || n > max) {
    throw FormatException('Text must be $min–$max characters.');
  }
  return v;
}

String assuranceDigest(Object? v) {
  if (v is! String || !_sha256.hasMatch(v)) {
    throw const FormatException('A lowercase SHA-256 digest is required.');
  }
  return v;
}

/// Returns a validated `YYYY-MM-DD` civil date (rejects impossible dates).
String assuranceDate(Object? v) {
  if (v is! String || !_civilDate.hasMatch(v)) {
    throw const FormatException('A civil date is required.');
  }
  final y = int.parse(v.substring(0, 4));
  final m = int.parse(v.substring(5, 7));
  final d = int.parse(v.substring(8, 10));
  final parsed = DateTime.utc(y, m, d);
  if (parsed.year != y || parsed.month != m || parsed.day != d) {
    throw const FormatException('Impossible calendar date.');
  }
  return v;
}

/// Generated, scope-bound protected-object path. Clients never choose paths.
String assuranceStorageRef(String tenantId, String engagementId, String id) =>
    'assurance/${assuranceId(tenantId)}/${assuranceId(engagementId)}/${assuranceId(id)}';

const assuranceSourceModules = {
  'finance',
  'procurement',
  'inventory',
  'workforce',
  'it_control',
  'manual',
};
const assuranceClassifications = {'internal', 'confidential', 'restricted'};

/// Evidence provenance metadata. Never carries document bytes.
final class EvidenceMetadata {
  EvidenceMetadata._({
    required this.id,
    required this.sourceModule,
    required this.sourceReference,
    required this.sourceAsOf,
    required this.collectionMethod,
    required this.queryVersion,
    required this.sha256,
    required this.byteSize,
    required this.classification,
    required this.storageRef,
  });

  factory EvidenceMetadata.fromCommand(
    Map<String, Object?> p, {
    required String tenantId,
    required String engagementId,
    required DateTime now,
  }) {
    final id = assuranceId(p['evidence_id']);
    assuranceId(p['request_id']);
    final module = p['source_module'];
    final method = p['collection_method'];
    if (!assuranceSourceModules.contains(module)) {
      throw const FormatException('Unknown evidence source module.');
    }
    if (method != 'system' && method != 'manual') {
      throw const FormatException('Unknown collection method.');
    }
    if ((module == 'manual') != (method == 'manual')) {
      throw const FormatException(
        'Manual collection is only valid for manual sources.',
      );
    }
    final asOfRaw = assuranceText(p['source_as_of'], 10, 40);
    final asOf = DateTime.tryParse(asOfRaw);
    if (asOf == null || asOf.isAfter(now)) {
      throw const FormatException('Evidence cutoff must not be in the future.');
    }
    final qv = p['query_version'];
    if (qv != null && (qv is! String || !_queryVersion.hasMatch(qv))) {
      throw const FormatException('Invalid query version.');
    }
    final size = p['byte_size'];
    if (size is! int || size < 1 || size > assuranceMaxEvidenceBytes) {
      throw const FormatException('Evidence size must be 1 byte to 100 MiB.');
    }
    final classification = p['classification'];
    if (!assuranceClassifications.contains(classification)) {
      throw const FormatException('Unknown evidence classification.');
    }
    final ref = assuranceStorageRef(tenantId, engagementId, id);
    if (p['storage_ref'] != ref) {
      throw const FormatException('Storage reference must be generated.');
    }
    return EvidenceMetadata._(
      id: id,
      sourceModule: module! as String,
      sourceReference: assuranceText(p['source_reference'], 1, 200),
      sourceAsOf: asOf,
      collectionMethod: method! as String,
      queryVersion: qv as String?,
      sha256: assuranceDigest(p['sha256']),
      byteSize: size,
      classification: classification! as String,
      storageRef: ref,
    );
  }

  final String id;
  final String sourceModule;
  final String sourceReference;
  final DateTime sourceAsOf;
  final String collectionMethod;
  final String? queryVersion;
  final String sha256;
  final int byteSize;
  final String classification;
  final String storageRef;
}

/// Segregation-of-duty rules enforced again by the server.
abstract final class AssuranceIndependence {
  static bool canReviewEvidence({
    required String actor,
    required String submitter,
  }) => actor != submitter;

  static bool canIssueFinding({
    required String actor,
    required String exceptionRecorder,
  }) => actor != exceptionRecorder;

  static bool canRetest({
    required String actor,
    required String findingOwner,
    required String? remediationSubmitter,
    required String controlOwner,
  }) =>
      actor != findingOwner &&
      actor != remediationSubmitter &&
      actor != controlOwner;

  static bool canDecideRisk({
    required String actor,
    required String findingOwner,
    required String issuer,
  }) => actor != findingOwner && actor != issuer;

  static bool canIssueReport({
    required String actor,
    required String leadAuditor,
  }) => actor != leadAuditor;

  static bool canReleaseHold({
    required String actor,
    required String placedBy,
  }) => actor != placedBy;

  /// Audit team members cannot own in-scope controls or supply evidence.
  static bool canJoinTeam({
    required String user,
    required Set<String> controlOwners,
    required Set<String> evidenceOwners,
  }) => !controlOwners.contains(user) && !evidenceOwners.contains(user);
}

/// Attribute-sampling sizes by control risk. The full population is tested
/// when it is no larger than the risk-based size.
int assuranceSampleSize(int population, AssuranceSeverity risk) {
  if (population < 0) throw const FormatException('Negative population.');
  final base = switch (risk) {
    AssuranceSeverity.low => 10,
    AssuranceSeverity.medium => 25,
    AssuranceSeverity.high => 40,
    AssuranceSeverity.critical => 60,
  };
  return population < base ? population : base;
}

/// Deterministic systematic selection (1-based item positions) from a
/// recorded random start, so the sample is reproducible by a reviewer.
List<int> assuranceSystematicSample(int population, int size, int start) {
  if (size < 0 || size > population) {
    throw const FormatException('Sample size exceeds population.');
  }
  if (size == 0) return const [];
  if (start < 1 || start > population) {
    throw const FormatException('Sample start outside population.');
  }
  // Integer arithmetic, identical to assurance.systematic_sample in SQL.
  return [
    for (var i = 0; i < size; i++)
      ((start - 1 + (i * population) ~/ size) % population) + 1,
  ];
}

/// Commands served by `api.assurance_test_command` (slice A2).
abstract final class AssuranceTestCommands {
  static const _capabilities = <String, String>{
    'design_test': 'assurance.test.perform',
    'execute_test': 'assurance.test.perform',
    'review_test': 'assurance.test.review',
    'carry_forward': 'assurance.finding.issue',
  };

  static const _fields = <String, List<String>>{
    'design_test': [
      'procedure_id',
      'control_id',
      'code',
      'objective',
      'population_size',
      'sample_start',
    ],
    'execute_test': [
      'run_id',
      'procedure_id',
      'items_tested',
      'exceptions_found',
      'conclusion',
      'workpaper_sha256',
    ],
    'review_test': ['procedure_id', 'decision', 'reason'],
    'carry_forward': [
      'finding_id',
      'source_finding_id',
      'exception_id',
      'control_id',
    ],
  };

  static String capability(String action) =>
      _capabilities[action] ??
      (throw const FormatException('Unknown assurance test action.'));

  static Set<String> fields(String action) {
    capability(action);
    return {'action', 'engagement_id', ..._fields[action]!};
  }

  static bool requiresRecentMfa(String action) {
    capability(action);
    return action == 'carry_forward';
  }

  /// [sampleSize] is the server-recorded size for `execute_test`.
  static void validate(
    String action,
    Map<String, Object?> p, {
    int? sampleSize,
  }) {
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
    switch (action) {
      case 'design_test':
        assuranceId(p['procedure_id']);
        assuranceId(p['control_id']);
        final code = p['code'];
        if (code is! String || !_controlCode.hasMatch(code)) {
          throw const FormatException('Invalid test code.');
        }
        assuranceText(p['objective'], 3, 2000);
        final pop = _count(p['population_size'], 1, 100000000);
        _count(p['sample_start'], 1, pop);
      case 'execute_test':
        assuranceId(p['run_id']);
        assuranceId(p['procedure_id']);
        final items = _count(p['items_tested'], 1, 60);
        if (sampleSize != null && items != sampleSize) {
          throw const FormatException('Every sampled item must be tested.');
        }
        final found = _count(p['exceptions_found'], 0, items);
        assuranceTestConclusion(p['conclusion'], found);
        assuranceDigest(p['workpaper_sha256']);
      case 'review_test':
        assuranceId(p['procedure_id']);
        if (!{'accept', 'return'}.contains(p['decision'])) {
          throw const FormatException('Unknown test review decision.');
        }
        assuranceText(p['reason'], 3, 1000);
      case 'carry_forward':
        for (final k in [
          'finding_id',
          'source_finding_id',
          'exception_id',
          'control_id',
        ]) {
          assuranceId(p[k]);
        }
    }
  }
}

int _count(Object? v, int min, int max) {
  if (v is! int || v < min || v > max) {
    throw FormatException('Whole number $min–$max required.');
  }
  return v;
}

/// An effective conclusion cannot rest on a sample with exceptions.
String assuranceTestConclusion(Object? conclusion, int exceptionsFound) {
  if (conclusion != 'effective' && conclusion != 'ineffective') {
    throw const FormatException('Unknown test conclusion.');
  }
  if (conclusion == 'effective' && exceptionsFound > 0) {
    throw const FormatException(
      'Exceptions require an ineffective conclusion.',
    );
  }
  return conclusion as String;
}

/// One immutable engagement event as returned by `api.assurance_engagement`.
final class AssuranceEvent {
  AssuranceEvent.fromJson(Map<String, Object?> j)
    : version = _positive(j['version']),
      action = _knownAction(j['action']),
      aggregateType = assuranceText(j['aggregate_type'], 1, 40),
      aggregateId = assuranceId(j['aggregate_id']),
      fromStatus = j['from_status'] as String?,
      toStatus = j['to_status'] as String?,
      actorId = assuranceId(j['actor_id']),
      occurredAt = DateTime.parse(assuranceText(j['occurred_at'], 10, 40));

  final int version;
  final String action;
  final String aggregateType;
  final String aggregateId;
  final String? fromStatus;
  final String? toStatus;
  final String actorId;
  final DateTime occurredAt;
}

/// Engagement events also record test (A2) and evidence (A4/A4b) commands.
const _testAndEvidenceEventActions = {
  'design_test',
  'execute_test',
  'review_test',
  'carry_forward',
  'collect_system_evidence',
  'export_pack',
  'run_monitoring',
};

String _knownAction(Object? v) {
  if (v is! String) throw const FormatException('Unknown assurance action.');
  if (!_testAndEvidenceEventActions.contains(v)) {
    AssuranceCommands.capability(v);
  }
  return v;
}

int _positive(Object? v) {
  if (v is! int || v < 1) throw const FormatException('Positive version.');
  return v;
}

/// Typed, validated engagement detail. Unknown statuses or malformed digests
/// fail closed instead of rendering partially trusted data.
final class EngagementDetail {
  EngagementDetail.fromJson(Map<String, Object?> j)
    : id = assuranceId(_map(j['engagement'])['id']),
      name = assuranceText(_map(j['engagement'])['name'], 3, 160),
      status = EngagementStatus.parse(_map(j['engagement'])['status']),
      version = _positive(_map(j['engagement'])['version']),
      cutoffDigest = _optionalDigest(
        _map(j['engagement'])['evidence_cutoff_digest'],
      ),
      findings = [
        for (final f in _list(j['findings']))
          (
            id: assuranceId(_map(f)['id']),
            severity: AssuranceSeverity.parse(_map(f)['severity']),
            status: FindingStatus.parse(_map(f)['status']),
          ),
      ],
      requestStatuses = [
        for (final r in _list(j['requests']))
          (
            status: EvidenceRequestStatus.parse(_map(r)['status']),
            reworkCount: _nonNegative(_map(r)['rework_count']),
            digest: _evidenceDigest(_map(r)['evidence']),
          ),
      ],
      events = [
        for (final e in _list(j['events'])) AssuranceEvent.fromJson(_map(e)),
      ] {
    for (var i = 0; i < events.length; i++) {
      if (events[i].version != i + 1) {
        throw const FormatException('Event history is not contiguous.');
      }
    }
    if (events.isNotEmpty && events.last.version != version) {
      throw const FormatException('Event history does not match version.');
    }
  }

  final String id;
  final String name;
  final EngagementStatus status;
  final int version;
  final String? cutoffDigest;
  final List<({String id, AssuranceSeverity severity, FindingStatus status})>
  findings;
  final List<({EvidenceRequestStatus status, int reworkCount, String? digest})>
  requestStatuses;
  final List<AssuranceEvent> events;

  int get openHighRiskFindings => findings
      .where(
        (f) =>
            f.status.open &&
            (f.severity == AssuranceSeverity.high ||
                f.severity == AssuranceSeverity.critical),
      )
      .length;

  /// Share of accepted evidence requests accepted without rework.
  double? get evidenceFirstTimeRight {
    final accepted = requestStatuses.where(
      (r) => r.status == EvidenceRequestStatus.accepted,
    );
    if (accepted.isEmpty) return null;
    return accepted.where((r) => r.reworkCount == 0).length / accepted.length;
  }
}

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw const FormatException('Object expected.');
}

List<Object?> _list(Object? v) {
  if (v is List) return v;
  throw const FormatException('List expected.');
}

int _nonNegative(Object? v) {
  if (v is! int || v < 0) throw const FormatException('Count expected.');
  return v;
}

String? _optionalDigest(Object? v) => v == null ? null : assuranceDigest(v);

String? _evidenceDigest(Object? v) =>
    v == null ? null : assuranceDigest(_map(v)['sha256']);

/// Nearest-rank percentile of measured durations; null when unmeasured so
/// efficiency is never claimed without instrumentation.
Duration? assurancePercentile(List<Duration> samples, int percentile) {
  if (percentile < 1 || percentile > 100) {
    throw const FormatException('Percentile must be 1–100.');
  }
  if (samples.isEmpty) return null;
  final sorted = [...samples]..sort();
  final rank = (percentile / 100 * sorted.length).ceil();
  return sorted[rank - 1];
}

/// Measured time from an evidence request opening to its first submission and
/// to acceptance, derived from immutable events (not guessed).
({List<Duration> waiting, List<Duration> review}) assuranceEvidenceStages(
  List<AssuranceEvent> events,
) {
  final opened = <String, DateTime>{};
  final submitted = <String, DateTime>{};
  final waiting = <Duration>[];
  final review = <Duration>[];
  for (final e in events) {
    if (e.aggregateType != 'evidence_request') continue;
    if (e.action == 'request_evidence') {
      opened[e.aggregateId] = e.occurredAt;
    } else if (e.action == 'submit_evidence') {
      final o = opened[e.aggregateId];
      if (o != null && !submitted.containsKey(e.aggregateId)) {
        waiting.add(e.occurredAt.difference(o));
      }
      submitted[e.aggregateId] = e.occurredAt;
    } else if (e.action == 'review_evidence' && e.toStatus == 'accepted') {
      final s = submitted[e.aggregateId];
      if (s != null) review.add(e.occurredAt.difference(s));
    }
  }
  return (waiting: waiting, review: review);
}
