// Corporate Audit & Assurance: who holds which assurance role
// (api.assurance_access, candidate API) and the grant/revoke command
// (api.assurance_set_role). The server remains the authority.
import 'assurance.dart';

/// The five assignable assurance roles seeded in every tenant.
enum AssuranceRole {
  lead(
    'assurance_lead',
    'Audit lead',
    'Plans audits, runs engagements, issues findings and reports, and exports audit packs.',
    true,
  ),
  auditor(
    'assurance_auditor',
    'Auditor',
    'Requests and collects evidence, performs tests and raises findings.',
    true,
  ),
  reviewer(
    'assurance_reviewer',
    'Reviewer',
    'Reviews workpapers, retests remediation and decides reports and risk acceptance.',
    true,
  ),
  processOwner(
    'assurance_process_owner',
    'Process owner',
    'Answers evidence requests, responds to findings and submits remediation.',
    false,
  ),
  external(
    'assurance_external',
    'External reviewer',
    'Time-bound read-only access for external auditors added to an engagement.',
    false,
  );

  const AssuranceRole(this.code, this.label, this.summary, this.requiresMfa);
  final String code;
  final String label;
  final String summary;
  final bool requiresMfa;

  static AssuranceRole parse(Object? v) => values.firstWhere(
    (r) => r.code == v,
    orElse: () => throw const FormatException('Unknown assurance role.'),
  );
}

/// Where an assignment applies: the whole organisation, the current legal
/// entity, or the current branch.
enum AccessScope {
  tenant,
  entity,
  branch;

  static AccessScope parse(Object? v) => values.firstWhere(
    (s) => s.name == v,
    orElse: () => throw const FormatException('Unknown access scope.'),
  );
}

typedef AccessAssignment = ({
  AssuranceRole role,
  AccessScope scope,
  String? legalEntityId,
  String? branchId,
});

typedef AccessMember = ({
  String membershipId,
  String label,
  bool linked,
  int version,
  List<AccessAssignment> assignments,
});

/// One page of tenant members with the assurance roles they hold. Labels are
/// employee names or a short membership id; a login e-mail fails closed.
final class AssuranceAccess {
  AssuranceAccess.fromJson(Map<String, Object?> j)
    : canManage = _bool(j['can_manage']),
      members = [for (final m in _list(j['members'])) _member(_map(m))],
      nextCursor = j['next_cursor'] == null
          ? null
          : assuranceId(j['next_cursor']);

  final bool canManage;
  final List<AccessMember> members;
  final String? nextCursor;

  bool holds(AccessMember m, AssuranceRole role, AccessScope scope) =>
      m.assignments.any((a) => a.role == role && a.scope == scope);

  static AccessMember _member(Map<String, Object?> m) {
    final label = assuranceText(m['label'], 1, 160);
    if (label.contains('@')) {
      throw const FormatException('Member labels must not be e-mails.');
    }
    final version = m['version'];
    if (version is! int || version < 0) {
      throw const FormatException('Access version expected.');
    }
    return (
      membershipId: assuranceId(m['membership_id']),
      label: label,
      linked: _bool(m['linked']),
      version: version,
      assignments: [
        for (final a in _list(m['assignments']))
          (
            role: AssuranceRole.parse(_map(a)['role_code']),
            scope: AccessScope.parse(_map(a)['scope']),
            legalEntityId: _optionalId(_map(a)['legal_entity_id']),
            branchId: _optionalId(_map(a)['branch_id']),
          ),
      ],
    );
  }
}

/// The grant/revoke command: exactly these fields, validated before sending.
abstract final class AssuranceAccessCommands {
  static const fields = ['membership_id', 'role_code', 'granted', 'scope'];

  static void validate(Map<String, Object?> p) {
    if (p.length != fields.length || !fields.every(p.containsKey)) {
      throw const FormatException('Access changes carry exactly four fields.');
    }
    assuranceId(p['membership_id']);
    AssuranceRole.parse(p['role_code']);
    AccessScope.parse(p['scope']);
    if (p['granted'] is! bool) {
      throw const FormatException('Grant or revoke must be chosen.');
    }
  }
}

/// True only when the receipt reports the same change one version later.
bool assuranceAccessReceiptConfirms(
  Map<String, Object?> r,
  Map<String, Object?> p,
  int expectedVersion,
) =>
    r['membership_id'] == p['membership_id'] &&
    r['role_code'] == p['role_code'] &&
    r['granted'] == p['granted'] &&
    r['scope'] == p['scope'] &&
    r['version'] == expectedVersion + 1;

Map<String, Object?> _map(Object? v) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw const FormatException('Object expected.');
}

List<Object?> _list(Object? v) {
  if (v is List) return v;
  throw const FormatException('List expected.');
}

bool _bool(Object? v) {
  if (v is bool) return v;
  throw const FormatException('Boolean expected.');
}

String? _optionalId(Object? v) => v == null ? null : assuranceId(v);
