import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'tenant_context.dart';

String organizationText(Object? value, int limit) {
  if (value is! String || value.trim().isEmpty || value.length > limit) {
    throw FormatException(
      'Organization text is required (maximum $limit characters).',
    );
  }
  return value;
}

int organizationVersion(Object? value) {
  if (value is! int || value < 1 || value > calendarMaxVersion) {
    throw const FormatException('Organization version is invalid.');
  }
  return value;
}

DateTime organizationTimestamp(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Organization timestamp requires an offset.');
  }
  return DateTime.parse(value).toUtc();
}

String? organizationOptionalId(Object? value) =>
    value == null ? null : calendarUuid(value);

final class OrganizationDates {
  OrganizationDates(Object? start, Object? end, {bool finite = false})
    : start = CivilDate.parse(organizationText(start, 10)),
      endExclusive = end == null
          ? null
          : CivilDate.parse(organizationText(end, 10)) {
    if (endExclusive != null && endExclusive!.compareTo(this.start) <= 0 ||
        finite &&
            (endExclusive == null ||
                endExclusive!.utc.difference(this.start.utc).inDays > 1830)) {
      throw const FormatException(
        'Organization dates must be a valid half-open interval. Assignments allow at most 1,830 days.',
      );
    }
  }
  final CivilDate start;
  final CivilDate? endExclusive;
  bool contains(CivilDate date) =>
      start.compareTo(date) <= 0 &&
      (endExclusive == null || endExclusive!.compareTo(date) > 0);
}

final class DepartmentEntry {
  DepartmentEntry.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      code = organizationText(row['code'], 32),
      version = organizationVersion(row['version']),
      revisionId = calendarUuid(row['revision_id']),
      name = organizationText(row['name'], 160),
      parentId = organizationOptionalId(row['parent_id']),
      dates = OrganizationDates(row['start_date'], row['end_date_exclusive']) {
    calendarFields(row, {
      'id',
      'code',
      'version',
      'revision_id',
      'name',
      'parent_id',
      'start_date',
      'end_date_exclusive',
    });
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code) ||
        parentId == id) {
      throw const FormatException('Department code or parent is invalid.');
    }
  }
  final String id, code, name, revisionId;
  final String? parentId;
  final int version;
  final OrganizationDates dates;
}

final class DepartmentRevision {
  DepartmentRevision.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      name = organizationText(row['name'], 160),
      parentId = organizationOptionalId(row['parent_id']),
      dates = OrganizationDates(row['start_date'], row['end_date_exclusive']),
      reason = organizationText(row['reason'], 1000),
      recordedBy = calendarUuid(row['recorded_by']),
      recordedAt = organizationTimestamp(row['recorded_at']),
      supersedesId = organizationOptionalId(row['supersedes_id']),
      supersededAt = row['superseded_at'] == null
          ? null
          : organizationTimestamp(row['superseded_at']) {
    calendarFields(row, {
      'id',
      'name',
      'parent_id',
      'start_date',
      'end_date_exclusive',
      'reason',
      'recorded_by',
      'recorded_at',
      'supersedes_id',
      'superseded_at',
    });
  }
  final String id, name, reason, recordedBy;
  final String? parentId, supersedesId;
  final OrganizationDates dates;
  final DateTime recordedAt;
  final DateTime? supersededAt;
}

final class OrganizationAssignment {
  OrganizationAssignment.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      tenantId = calendarUuid(row['tenant_id']),
      legalEntityId = calendarUuid(row['legal_entity_id']),
      branchId = calendarUuid(row['branch_id']),
      employeeId = calendarUuid(row['employee_id']),
      spellId = calendarUuid(row['spell_id']),
      departmentId = calendarUuid(row['department_id']),
      managerId = organizationOptionalId(row['manager_id']),
      calendarVersionId = calendarUuid(row['calendar_version_id']),
      roleTitle = organizationText(row['role_title'], 160),
      departmentName = organizationText(row['department_name_at_start'], 160),
      managerName = row['manager_display_name'] == null
          ? null
          : organizationText(row['manager_display_name'], 160),
      calendarName = organizationText(row['calendar_name'], 160),
      calendarTimezone = organizationText(row['calendar_timezone'], 100),
      withdrawal = row['withdrawal'] == null
          ? null
          : OrganizationWithdrawal.fromJson(
              Map<String, Object?>.from(row['withdrawal'] as Map),
            ),
      dates = OrganizationDates(
        row['start_date'],
        row['end_date_exclusive'],
        finite: true,
      ),
      reason = organizationText(row['reason'], 1000),
      recordedBy = calendarUuid(row['recorded_by']),
      recordedAt = organizationTimestamp(row['recorded_at']),
      supersedesId = organizationOptionalId(row['supersedes_id']),
      supersededAt = row['superseded_at'] == null
          ? null
          : organizationTimestamp(row['superseded_at']) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'spell_id',
      'department_id',
      'manager_id',
      'calendar_version_id',
      'role_title',
      'start_date',
      'end_date_exclusive',
      'reason',
      'recorded_by',
      'recorded_at',
      'supersedes_id',
      'superseded_at',
      'department_name_at_start',
      'manager_display_name',
      'calendar_name',
      'calendar_timezone',
      'withdrawal',
    });
    if (managerId == employeeId) {
      throw const FormatException('Employee cannot manage themselves.');
    }
    if ((managerId == null) != (managerName == null)) {
      throw const FormatException(
        'Manager reference and display name disagree.',
      );
    }
    if (withdrawal != null && supersededAt == null) {
      throw const FormatException('Withdrawn assignment cannot remain active.');
    }
  }
  final String id,
      tenantId,
      legalEntityId,
      branchId,
      employeeId,
      spellId,
      departmentId,
      calendarVersionId,
      roleTitle,
      reason,
      recordedBy;
  final String? managerId, supersedesId;
  final String departmentName, calendarName, calendarTimezone;
  final String? managerName;
  final OrganizationWithdrawal? withdrawal;
  final OrganizationDates dates;
  final DateTime recordedAt;
  final DateTime? supersededAt;
  bool get active => supersededAt == null;
}

final class OrganizationEmployeeState {
  const OrganizationEmployeeState(
    this.employeeId,
    this.version,
    this.asOf,
    this.assignments,
  );
  final String employeeId;
  final int version;
  final CivilDate asOf;
  final CalendarPage<OrganizationAssignment> assignments;
  OrganizationAssignment? get current => assignments.items
      .where((a) => a.active && a.dates.contains(asOf))
      .firstOrNull;
}

final class OrganizationConfirmation {
  const OrganizationConfirmation({
    required this.id,
    required this.version,
    this.departmentRevisionId,
    this.assignment,
    this.withdrawal,
  });
  final String id;
  final int version;
  final String? departmentRevisionId;
  final OrganizationAssignment? assignment;
  final OrganizationWithdrawal? withdrawal;
}

final class OrganizationWithdrawal {
  OrganizationWithdrawal.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      reason = organizationText(row['reason'], 1000),
      recordedBy = calendarUuid(row['recorded_by']),
      recordedAt = organizationTimestamp(row['recorded_at']) {
    calendarFields(row, {'id', 'reason', 'recorded_by', 'recorded_at'});
  }
  final String id, reason, recordedBy;
  final DateTime recordedAt;
}

Set<String> organizationPayloadFields(String action) {
  return switch (action) {
    'department_create' => {
      'id',
      'revision_id',
      'code',
      'name',
      'parent_id',
      'start_date',
      'end_date_exclusive',
      'reason',
    },
    'department_revise' => {
      'id',
      'revision_id',
      'name',
      'parent_id',
      'start_date',
      'end_date_exclusive',
      'reason',
      'replace_revision_id',
    },
    'assign' => {
      'id',
      'employee_id',
      'spell_id',
      'department_id',
      'manager_id',
      'calendar_version_id',
      'role_title',
      'start_date',
      'end_date_exclusive',
      'reason',
    },
    'replace' => {
      'id',
      'employee_id',
      'spell_id',
      'department_id',
      'manager_id',
      'calendar_version_id',
      'role_title',
      'start_date',
      'end_date_exclusive',
      'reason',
      'replace_revision_id',
    },
    'end_assignment' || 'withdraw_assignment' => {
      'id',
      'employee_id',
      'start_date',
      'end_date_exclusive',
      'reason',
      'replace_revision_id',
    },
    _ => throw const FormatException('Unknown organization action.'),
  };
}

void validateOrganizationPayload(String action, Map<String, Object?> payload) {
  final keys = organizationPayloadFields(action);
  calendarFields(payload, keys);
  for (final key in keys.where((k) => k == 'id' || k.endsWith('_id'))) {
    if (payload[key] == null && {'parent_id', 'manager_id'}.contains(key)) {
      continue;
    }
    calendarUuid(payload[key]);
  }
  organizationText(payload['reason'], 1000);
  OrganizationDates(
    payload['start_date'],
    payload['end_date_exclusive'],
    finite: !action.startsWith('department_'),
  );
  if (action.startsWith('department_')) {
    organizationText(payload['name'], 160);
    if (payload['parent_id'] == payload['id']) {
      throw const FormatException('Department cannot be its own parent.');
    }
    if (action == 'department_create' &&
        !RegExp(
          r'^[A-Z0-9][A-Z0-9_-]{0,31}$',
        ).hasMatch(organizationText(payload['code'], 32))) {
      throw const FormatException('Use an uppercase department code.');
    }
  } else if (!{'end_assignment', 'withdraw_assignment'}.contains(action)) {
    organizationText(payload['role_title'], 160);
    if (payload['manager_id'] == payload['employee_id']) {
      throw const FormatException('Employee cannot manage themselves.');
    }
  }
}

abstract interface class OrganizationRepository {
  Future<DepartmentEntry> department(
    TenantContext scope,
    String id,
    CivilDate asOf,
  );
  Future<CalendarPage<DepartmentEntry>> departments(
    TenantContext scope,
    CivilDate asOf, {
    String search = '',
    String? after,
  });
  Future<CalendarPage<DepartmentRevision>> departmentHistory(
    TenantContext scope,
    String departmentId, {
    String? after,
  });
  Future<OrganizationEmployeeState> employee(
    TenantContext scope,
    String employeeId,
    CivilDate asOf, {
    String? after,
  });
  Future<OrganizationConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
