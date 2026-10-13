import 'calendar_repository.dart';
import 'clock_import.dart';
import 'commands.dart';
import 'employee.dart';
import 'tenant_context.dart';
import 'work_time.dart';

Map<String, Object?> workforceMap(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Workforce response is invalid.');
  }
  return value;
}

int workforceInteger(Object? value, {bool positive = false}) {
  if (value is! int ||
      value < (positive ? 1 : 0) ||
      value > maxExactWorkInteger) {
    throw const FormatException('Workforce exact integer is invalid.');
  }
  return value;
}

DateTime workforceInstant(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Workforce instant requires an offset.');
  }
  workforceLocalTime(value.substring(0, 19));
  final instant = DateTime.parse(value).toUtc();
  if (instant.millisecond != 0 || instant.microsecond != 0) {
    throw const FormatException('Workforce instant requires whole seconds.');
  }
  return instant;
}

DateTime workforceRecorded(Object? value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('Workforce audit time requires an offset.');
  }
  workforceLocalTime(value.substring(0, 19));
  return DateTime.parse(value).toUtc();
}

String workforceText(Object? value, int max) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw const FormatException('Workforce text is invalid.');
  }
  return value;
}

/// A civil wall time; resolving its IANA zone remains a trusted server operation.
DateTime workforceLocalTime(Object? value) {
  final text = workforceText(value, 19);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(text)) {
    throw const FormatException('Use a whole-second local date and time.');
  }
  return parseWorkUtc('${text}Z');
}

final class WorkforcePage<T> {
  const WorkforcePage(this.items, this.nextCursor);
  final List<T> items;
  final String? nextCursor;
}

final class WorkforceDetail<T, E> {
  const WorkforceDetail(this.record, this.history);
  final T record;
  final WorkforcePage<E> history;
}

final class AttendanceHistoryEntry {
  AttendanceHistoryEntry.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      version = workforceInteger(row['version'], positive: true),
      span = WorkSpan(
        workforceInstant(row['start_utc']),
        workforceInstant(row['end_utc']),
      ),
      payableSeconds = workforceInteger(row['payable_seconds'], positive: true),
      reason = workforceText(row['reason'], 1000),
      actorId = calendarUuid(row['recorded_by']),
      recordedAt = workforceRecorded(row['recorded_at']) {
    calendarFields(row, {
      'id',
      'version',
      'start_utc',
      'end_utc',
      'breaks',
      'payable_seconds',
      'reason',
      'supersedes_revision_id',
      'recorded_by',
      'recorded_at',
    });
    if (row['supersedes_revision_id'] != null) {
      calendarUuid(row['supersedes_revision_id']);
    }
    final pauses = <WorkSpan>[];
    for (final item in row['breaks'] as List) {
      final pause = workforceMap(item);
      calendarFields(pause, {'start_utc', 'end_utc'});
      pauses.add(
        WorkSpan(
          parseWorkUtc(pause['start_utc'] as String),
          parseWorkUtc(pause['end_utc'] as String),
        ),
      );
    }
    if (PayableWork(span, pauses).payableSeconds != payableSeconds) {
      throw const FormatException('Attendance history arithmetic changed.');
    }
  }
  final String id, reason, actorId;
  final int version, payableSeconds;
  final WorkSpan span;
  final DateTime recordedAt;
}

final class LeaveHistoryEntry {
  LeaveHistoryEntry.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      action = workforceText(row['action'], 20),
      beforeStatus = row['before_status'] as String?,
      afterStatus = workforceText(row['after_status'], 20),
      reason = workforceText(row['reason'], 1000),
      actorId = calendarUuid(row['actor_id']),
      recordedAt = workforceRecorded(row['recorded_at']) {
    calendarFields(row, {
      'id',
      'action',
      'before_status',
      'after_status',
      'reason',
      'actor_id',
      'recorded_at',
    });
    if (!{'create', 'submit', 'approve', 'reject', 'cancel'}.contains(action) ||
        !{
          'draft',
          'submitted',
          'approved',
          'rejected',
          'cancelled',
        }.contains(afterStatus)) {
      throw const FormatException('Leave history action changed.');
    }
  }
  final String id, action, afterStatus, reason, actorId;
  final String? beforeStatus;
  final DateTime recordedAt;
}

final class RawClockEvent {
  RawClockEvent.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      sourceSystem = workforceText(row['source_system'], 80),
      sourceKey = workforceText(row['source_key'], 160),
      observedUtc = workforceInstant(row['observed_utc']),
      checksum = workforceText(row['checksum'], 64),
      importedBy = calendarUuid(row['imported_by']),
      importedAt = workforceRecorded(row['imported_at']) {
    calendarFields(row, {
      'id',
      'source_system',
      'source_key',
      'observed_utc',
      'checksum',
      'imported_by',
      'imported_at',
    });
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Raw event checksum changed.');
    }
  }
  final String id, sourceSystem, sourceKey, checksum, importedBy;
  final DateTime observedUtc, importedAt;
}

final class WorkClaim {
  WorkClaim.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      sourceKind = workforceText(row['source_kind'], 20),
      sourceId = calendarUuid(row['source_id']),
      span = WorkSpan(
        workforceInstant(row['start_utc']),
        workforceInstant(row['end_utc']),
      ),
      grossSeconds = workforceInteger(row['gross_seconds'], positive: true),
      breakSeconds = workforceInteger(row['break_seconds']),
      payableSeconds = workforceInteger(row['payable_seconds'], positive: true),
      active = row['active'] as bool,
      calendarVersionId = calendarUuid(row['calendar_version_id']) {
    calendarFields(row, {
      'id',
      'source_kind',
      'source_id',
      'start_utc',
      'end_utc',
      'gross_seconds',
      'break_seconds',
      'payable_seconds',
      'active',
      'revoked_at',
      'calendar_version_id',
    });
    if (!{'attendance', 'leave', 'project', 'service'}.contains(sourceKind) ||
        span.seconds != grossSeconds ||
        payableSeconds != grossSeconds - breakSeconds ||
        active != (row['revoked_at'] == null)) {
      throw const FormatException(
        'Work ownership arithmetic or state changed.',
      );
    }
    if (row['revoked_at'] != null) workforceRecorded(row['revoked_at']);
  }
  final String id, sourceKind, sourceId, calendarVersionId;
  final WorkSpan span;
  final int grossSeconds, breakSeconds, payableSeconds;
  final bool active;
}

final class AttendanceRevision {
  AttendanceRevision.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      version = workforceInteger(row['version'], positive: true),
      calendarVersionId = calendarUuid(row['calendar_version_id']),
      startLocal = workforceText(row['start_local'], 32),
      endLocal = workforceText(row['end_local'], 32),
      startOffsetSeconds = row['start_offset_seconds'] as int,
      endOffsetSeconds = row['end_offset_seconds'] as int,
      span = WorkSpan(
        workforceInstant(row['start_utc']),
        workforceInstant(row['end_utc']),
      ),
      breaks = row['breaks'] as List,
      grossSeconds = workforceInteger(row['gross_seconds'], positive: true),
      breakSeconds = workforceInteger(row['break_seconds']),
      payableSeconds = workforceInteger(row['payable_seconds'], positive: true),
      reason = workforceText(row['reason'], 1000),
      recordedBy = calendarUuid(row['recorded_by']) {
    calendarFields(row, {
      'id',
      'version',
      'calendar_version_id',
      'start_local',
      'start_offset_seconds',
      'end_local',
      'end_offset_seconds',
      'start_utc',
      'end_utc',
      'breaks',
      'gross_seconds',
      'break_seconds',
      'payable_seconds',
      'raw_start_id',
      'raw_end_id',
      'reason',
      'supersedes_revision_id',
      'recorded_by',
      'recorded_at',
    });
    if (startOffsetSeconds.abs() > 86400 ||
        endOffsetSeconds.abs() > 86400 ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
        ).hasMatch(startLocal) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(endLocal) ||
        grossSeconds != span.seconds ||
        payableSeconds != grossSeconds - breakSeconds ||
        breaks.length > 16) {
      throw const FormatException('Attendance revision arithmetic changed.');
    }
    if (row['raw_start_id'] != null) calendarUuid(row['raw_start_id']);
    if (row['raw_end_id'] != null) calendarUuid(row['raw_end_id']);
    if ((row['raw_start_id'] == null) != (row['raw_end_id'] == null)) {
      throw const FormatException('Attendance raw event pair changed.');
    }
    if (row['supersedes_revision_id'] != null) {
      calendarUuid(row['supersedes_revision_id']);
    }
    workforceRecorded(row['recorded_at']);
    final pauses = <WorkSpan>[];
    for (final item in breaks) {
      final pause = workforceMap(item);
      calendarFields(pause, {'start_utc', 'end_utc'});
      pauses.add(
        WorkSpan(
          parseWorkUtc(pause['start_utc'] as String),
          parseWorkUtc(pause['end_utc'] as String),
        ),
      );
    }
    final payable = PayableWork(span, pauses);
    if (payable.breakSeconds != breakSeconds ||
        payable.payableSeconds != payableSeconds) {
      throw const FormatException('Attendance break arithmetic changed.');
    }
  }

  final String id, calendarVersionId, startLocal, endLocal, reason, recordedBy;
  final int version, startOffsetSeconds, endOffsetSeconds;
  final WorkSpan span;
  final List<dynamic> breaks;
  final int grossSeconds, breakSeconds, payableSeconds;
}

final class AttendanceEntry {
  AttendanceEntry.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      tenantId = calendarUuid(row['tenant_id']),
      legalEntityId = calendarUuid(row['legal_entity_id']),
      branchId = calendarUuid(row['branch_id']),
      employeeId = calendarUuid(row['employee_id']),
      version = workforceInteger(row['version'], positive: true),
      status = workforceText(row['status'], 20),
      revision = AttendanceRevision.fromJson(workforceMap(row['revision'])) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'version',
      'status',
      'submitted_by',
      'decided_by',
      'active_claim_id',
      'created_by',
      'created_at',
      'revision',
    });
    if (!{
          'draft',
          'submitted',
          'approved',
          'rejected',
          'cancelled',
        }.contains(status) ||
        revision.version > version) {
      throw const FormatException('Attendance state changed.');
    }
    calendarUuid(row['created_by']);
    workforceRecorded(row['created_at']);
    for (final key in ['submitted_by', 'decided_by', 'active_claim_id']) {
      if (row[key] != null) calendarUuid(row[key]);
    }
    if ((status == 'approved') != (row['active_claim_id'] != null)) {
      throw const FormatException('Attendance claim state changed.');
    }
  }
  final String id, tenantId, legalEntityId, branchId, employeeId, status;
  final int version;
  final AttendanceRevision revision;

  void assertScope(TenantContext scope, String employee) {
    if (tenantId != scope.tenantId ||
        legalEntityId != scope.legalEntityId ||
        branchId != scope.branchId ||
        employeeId != employee) {
      throw const FormatException('Attendance ancestry changed.');
    }
  }
}

final class LeaveRequest {
  LeaveRequest.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      tenantId = calendarUuid(row['tenant_id']),
      legalEntityId = calendarUuid(row['legal_entity_id']),
      branchId = calendarUuid(row['branch_id']),
      employeeId = calendarUuid(row['employee_id']),
      policyId = calendarUuid(row['policy_id']),
      policyVersionId = calendarUuid(row['policy_version_id']),
      calendarVersionId = calendarUuid(row['calendar_version_id']),
      version = workforceInteger(row['version'], positive: true),
      status = workforceText(row['status'], 20),
      span = WorkSpan(
        workforceInstant(row['start_utc']),
        workforceInstant(row['end_utc']),
      ),
      chargeSeconds = workforceInteger(row['charge_seconds'], positive: true),
      unpaidSeconds = workforceInteger(row['unpaid_seconds']),
      reason = workforceText(row['reason'], 1000) {
    calendarFields(row, {
      'id',
      'employee_id',
      'policy_id',
      'policy_version_id',
      'calendar_version_id',
      'version',
      'status',
      'start_utc',
      'end_utc',
      'charge_seconds',
      'unpaid_seconds',
      'active_claim_id',
      'created_by',
      'submitted_by',
      'decided_by',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'start_local',
      'start_offset_seconds',
      'end_local',
      'end_offset_seconds',
      'reason',
      'created_at',
    });
    if (!{
          'draft',
          'submitted',
          'approved',
          'rejected',
          'cancelled',
        }.contains(status) ||
        unpaidSeconds > chargeSeconds ||
        (status == 'approved') != (row['active_claim_id'] != null)) {
      throw const FormatException('Leave state changed.');
    }
    for (final key in [
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'created_by',
    ]) {
      calendarUuid(row[key]);
    }
    for (final key in ['active_claim_id', 'submitted_by', 'decided_by']) {
      if (row[key] != null) calendarUuid(row[key]);
    }
    workforceRecorded(row['created_at']);
    for (final key in ['start_local', 'end_local']) {
      if (!RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$',
      ).hasMatch(workforceText(row[key], 32))) {
        throw const FormatException('Leave local time changed.');
      }
    }
    for (final key in ['start_offset_seconds', 'end_offset_seconds']) {
      final offset = row[key];
      if (offset is! int || offset.abs() > 86400) {
        throw const FormatException('Leave selected offset changed.');
      }
    }
  }
  final String id,
      tenantId,
      legalEntityId,
      branchId,
      employeeId,
      policyId,
      policyVersionId,
      calendarVersionId,
      status,
      reason;
  final int version, chargeSeconds, unpaidSeconds;
  final WorkSpan span;

  void assertScope(TenantContext scope, String employee) {
    if (tenantId != scope.tenantId ||
        legalEntityId != scope.legalEntityId ||
        branchId != scope.branchId ||
        employeeId != employee) {
      throw const FormatException('Leave ancestry changed.');
    }
  }
}

final class LeaveBalance {
  LeaveBalance.fromJson(Map<String, Object?> row)
    : employeeId = calendarUuid(row['employee_id']),
      policyId = calendarUuid(row['policy_id']),
      asOf = CivilDate.parse(workforceText(row['as_of'], 10)),
      availableSeconds = workforceInteger(row['available_seconds']),
      accountVersion = workforceInteger(row['account_version']) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'policy_id',
      'as_of',
      'recorded_before',
      'available_seconds',
      'account_version',
      'grants',
      'next_cursor',
    });
    if (row['grants'] is! List || (row['grants'] as List).length > 50) {
      throw const FormatException('Leave grant page changed.');
    }
    grants = List.unmodifiable(
      (row['grants'] as List).map(
        (item) => LeaveGrantSource.fromJson(workforceMap(item)),
      ),
    );
    nextCursor = row['next_cursor'] == null
        ? null
        : calendarUuid(row['next_cursor']);
    if (grants.map((g) => g.id).toSet().length != grants.length ||
        (nextCursor != null &&
            (grants.length != 50 || nextCursor != grants.last.id))) {
      throw const FormatException('Leave balance pagination changed.');
    }
  }
  final String employeeId, policyId;
  final CivilDate asOf;
  final int availableSeconds, accountVersion;
  late final List<LeaveGrantSource> grants;
  late final String? nextCursor;
}

final class LeaveGrantSource {
  LeaveGrantSource.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      policyVersionId = calendarUuid(row['policy_version_id']),
      sourceKind = workforceText(row['source_kind'], 20),
      sourceKey = workforceText(row['source_key'], 160),
      effective = CivilDate.parse(row['effective_date'] as String),
      expiry = CivilDate.parse(row['expiry_date'] as String),
      seconds = workforceInteger(row['seconds'], positive: true),
      remainingSeconds = workforceInteger(row['remaining_seconds']),
      recordedAt = workforceRecorded(row['recorded_at']) {
    calendarFields(row, {
      'id',
      'source_kind',
      'source_key',
      'effective_date',
      'expiry_date',
      'seconds',
      'remaining_seconds',
      'policy_version_id',
      'recorded_at',
    });
    if (!{'accrual', 'carry', 'adjustment'}.contains(sourceKind) ||
        remainingSeconds > seconds ||
        expiry.compareTo(effective) <= 0) {
      throw const FormatException('Leave grant source or arithmetic changed.');
    }
  }
  final String id, policyVersionId, sourceKind, sourceKey;
  final CivilDate effective, expiry;
  final int seconds, remainingSeconds;
  final DateTime recordedAt;
}

final class LeavePolicyVersion {
  LeavePolicyVersion.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      version = workforceInteger(row['version'], positive: true),
      start = CivilDate.parse(row['start_date'] as String),
      endExclusive = CivilDate.parse(row['end_date_exclusive'] as String),
      unit = row['unit'] as String,
      daySeconds = workforceInteger(row['day_seconds'], positive: true),
      accrualFrequency = row['accrual_frequency'] as String,
      accrualSeconds = workforceInteger(row['accrual_seconds'], positive: true),
      carryCapSeconds = workforceInteger(row['carry_cap_seconds']),
      expiryDays = workforceInteger(row['expiry_days'], positive: true),
      eligibleTypes = List<String>.unmodifiable(
        (row['eligible_types'] as List).cast<String>(),
      ),
      allowUnpaid = row['allow_unpaid'] as bool,
      reason = workforceText(row['reason'], 1000),
      publishedBy = calendarUuid(row['published_by']),
      publishedAt = workforceRecorded(row['published_at']) {
    calendarFields(row, {
      'id',
      'version',
      'start_date',
      'end_date_exclusive',
      'unit',
      'day_seconds',
      'accrual_frequency',
      'accrual_seconds',
      'carry_cap_seconds',
      'expiry_days',
      'eligible_types',
      'allow_unpaid',
      'reason',
      'published_by',
      'published_at',
    });
    WorkforceCommands.validate(WorkforceCommandKind.leavePolicy, 'publish', {
      'action': 'publish',
      'id': id,
      'version_id': id,
      for (final key
          in WorkforceCommands
              .fields[WorkforceCommandKind.leavePolicy]!['publish']!
              .difference({'action', 'id', 'version_id'}))
        key: row[key],
    });
  }
  final String id, unit, accrualFrequency, reason, publishedBy;
  final int version, daySeconds, accrualSeconds, carryCapSeconds, expiryDays;
  final CivilDate start, endExclusive;
  final List<String> eligibleTypes;
  final bool allowUnpaid;
  final DateTime publishedAt;
  bool covers(CivilDate day) =>
      start.compareTo(day) <= 0 && endExclusive.compareTo(day) > 0;
}

final class LeavePolicy {
  LeavePolicy.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      code = workforceText(row['code'], 32),
      name = workforceText(row['name'], 160),
      version = workforceInteger(row['version'], positive: true),
      latest = _latest(row['versions']) {
    calendarFields(row, {'id', 'code', 'name', 'version', 'versions'});
    if (latest.version != version ||
        !RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code)) {
      throw const FormatException(
        'Leave policy identity or current revision changed.',
      );
    }
  }
  final String id, code, name;
  final int version;
  final LeavePolicyVersion latest;
  static LeavePolicyVersion _latest(Object? versions) {
    if (versions is! List || versions.length != 1) {
      throw const FormatException(
        'A policy directory row requires exactly one latest version.',
      );
    }
    return LeavePolicyVersion.fromJson(workforceMap(versions.single));
  }
}

enum WorkforceCommandKind { attendance, leavePolicy, leaveGrant, leaveRequest }

final class WorkforceCommands {
  static const fields = <WorkforceCommandKind, Map<String, Set<String>>>{
    WorkforceCommandKind.attendance: {
      'raw_import_batch': {
        'action',
        'id',
        'employee_id',
        'source_system',
        'records',
        'manifest_digest',
      },
      'raw_import': {
        'action',
        'id',
        'employee_id',
        'source_system',
        'source_key',
        'observed_utc',
        'checksum',
      },
      'create': {
        'action',
        'id',
        'employee_id',
        'calendar_version_id',
        'start_local',
        'start_offset_seconds',
        'end_local',
        'end_offset_seconds',
        'breaks',
        'raw_start_id',
        'raw_end_id',
        'reason',
      },
      'correct': {
        'action',
        'id',
        'employee_id',
        'calendar_version_id',
        'start_local',
        'start_offset_seconds',
        'end_local',
        'end_offset_seconds',
        'breaks',
        'raw_start_id',
        'raw_end_id',
        'reason',
      },
      'submit': {'action', 'id', 'employee_id', 'reason'},
      'approve': {'action', 'id', 'employee_id', 'reason'},
      'reject': {'action', 'id', 'employee_id', 'reason'},
      'cancel': {'action', 'id', 'employee_id', 'reason'},
    },
    WorkforceCommandKind.leavePolicy: {
      'create': {
        'action',
        'id',
        'version_id',
        'code',
        'name',
        'start_date',
        'end_date_exclusive',
        'unit',
        'day_seconds',
        'accrual_frequency',
        'accrual_seconds',
        'carry_cap_seconds',
        'expiry_days',
        'eligible_types',
        'allow_unpaid',
        'reason',
      },
      'publish': {
        'action',
        'id',
        'version_id',
        'start_date',
        'end_date_exclusive',
        'unit',
        'day_seconds',
        'accrual_frequency',
        'accrual_seconds',
        'carry_cap_seconds',
        'expiry_days',
        'eligible_types',
        'allow_unpaid',
        'reason',
      },
    },
    WorkforceCommandKind.leaveGrant: {
      'accrue': {
        'action',
        'id',
        'employee_id',
        'policy_version_id',
        'period_start',
        'reason',
      },
      'carry': {
        'action',
        'id',
        'employee_id',
        'policy_version_id',
        'prior_version_id',
        'boundary_date',
        'reason',
      },
      'adjust': {
        'action',
        'id',
        'employee_id',
        'policy_version_id',
        'effective_date',
        'source_key',
        'seconds',
        'reason',
      },
    },
    WorkforceCommandKind.leaveRequest: {
      'create': {
        'action',
        'id',
        'employee_id',
        'policy_version_id',
        'calendar_version_id',
        'start_local',
        'start_offset_seconds',
        'end_local',
        'end_offset_seconds',
        'reason',
      },
      'submit': {'action', 'id', 'employee_id', 'reason'},
      'approve': {'action', 'id', 'employee_id', 'balance_version', 'reason'},
      'reject': {'action', 'id', 'employee_id', 'reason'},
      'cancel': {'action', 'id', 'employee_id', 'balance_version', 'reason'},
    },
  };

  static void validate(
    WorkforceCommandKind kind,
    String action,
    Map<String, Object?> payload,
  ) {
    final allowed = fields[kind]?[action];
    if (allowed == null ||
        payload['action'] != action ||
        payload.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Workforce command fields are invalid.');
    }
    if (kind == WorkforceCommandKind.attendance &&
        action == 'raw_import_batch') {
      validateClockBatch(payload);
      return;
    }
    if (kind == WorkforceCommandKind.attendance && action == 'raw_import') {
      validateRawImport(payload);
      return;
    }
    final optional =
        kind == WorkforceCommandKind.attendance &&
            (action == 'create' || action == 'correct')
        ? {'breaks', 'raw_start_id', 'raw_end_id'}
        : <String>{};
    if (allowed.difference(optional).any((key) => payload[key] == null)) {
      throw const FormatException('Workforce command fields are required.');
    }
    calendarUuid(payload['id']);
    if (kind != WorkforceCommandKind.leavePolicy) {
      calendarUuid(payload['employee_id']);
    }
    workforceText(payload['reason'], 1000);
    for (final key in [
      'version_id',
      'policy_version_id',
      'prior_version_id',
      'calendar_version_id',
    ]) {
      if (allowed.contains(key)) calendarUuid(payload[key]);
    }
    if (allowed.contains('start_local')) {
      final start = workforceLocalTime(payload['start_local']);
      final end = workforceLocalTime(payload['end_local']);
      final startOffset = payload['start_offset_seconds'];
      final endOffset = payload['end_offset_seconds'];
      if (startOffset is! int ||
          endOffset is! int ||
          startOffset.abs() > 86400 ||
          endOffset.abs() > 86400) {
        throw const FormatException('Select whole-second UTC offsets.');
      }
      final span = WorkSpan(
        start.subtract(Duration(seconds: startOffset)),
        end.subtract(Duration(seconds: endOffset)),
      );
      if (kind == WorkforceCommandKind.attendance) {
        final breaks = payload['breaks'] ?? <Object?>[];
        if (breaks is! List) {
          throw const FormatException('Attendance breaks must be a list.');
        }
        final pauses = <WorkSpan>[];
        for (final item in breaks) {
          final pause = workforceMap(item);
          calendarFields(pause, {'start_utc', 'end_utc'});
          pauses.add(
            WorkSpan(
              parseWorkUtc(pause['start_utc'] as String),
              parseWorkUtc(pause['end_utc'] as String),
            ),
          );
        }
        PayableWork(span, pauses);
        if ((payload['raw_start_id'] == null) !=
            (payload['raw_end_id'] == null)) {
          throw const FormatException('Select both raw events or neither.');
        }
        for (final key in ['raw_start_id', 'raw_end_id']) {
          if (payload[key] != null) calendarUuid(payload[key]);
        }
      }
    }
    if (kind == WorkforceCommandKind.leavePolicy) {
      final start = CivilDate.parse(payload['start_date'] as String);
      final end = CivilDate.parse(payload['end_date_exclusive'] as String);
      final days = end.utc.difference(start.utc).inDays;
      if (days < 1 ||
          days > 1830 ||
          !{'hours', 'days'}.contains(payload['unit']) ||
          !{'once', 'monthly'}.contains(payload['accrual_frequency']) ||
          workforceInteger(payload['day_seconds'], positive: true) > 86400 ||
          workforceInteger(payload['expiry_days'], positive: true) > 3650 ||
          payload['allow_unpaid'] is! bool) {
        throw const FormatException('Leave policy dates or rules are invalid.');
      }
      workforceInteger(payload['accrual_seconds'], positive: true);
      workforceInteger(payload['carry_cap_seconds']);
      final types = payload['eligible_types'];
      if (types is! List ||
          types.isEmpty ||
          types.length > 4 ||
          types.toSet().length != types.length ||
          types.any(
            (type) => !{
              'permanent',
              'fixed_term',
              'casual',
              'contractor',
            }.contains(type),
          )) {
        throw const FormatException('Leave policy eligibility is invalid.');
      }
      if (action == 'create') {
        if (!RegExp(
          r'^[A-Z0-9][A-Z0-9_-]{0,31}$',
        ).hasMatch(workforceText(payload['code'], 32))) {
          throw const FormatException('Leave policy code is invalid.');
        }
        workforceText(payload['name'], 160);
      }
    }
    if (kind == WorkforceCommandKind.leaveGrant) {
      final dateKey = switch (action) {
        'accrue' => 'period_start',
        'carry' => 'boundary_date',
        _ => 'effective_date',
      };
      CivilDate.parse(payload[dateKey] as String);
      if (action == 'adjust') {
        final seconds = payload['seconds'];
        if (seconds is! int ||
            seconds == 0 ||
            seconds.abs() > maxExactWorkInteger) {
          throw const FormatException('Leave adjustment seconds are invalid.');
        }
        workforceText(payload['source_key'], 160);
      }
    }
    if (kind == WorkforceCommandKind.leaveRequest &&
        (action == 'approve' || action == 'cancel')) {
      workforceInteger(payload['balance_version']);
    }
  }

  static void validateRawImport(Map<String, Object?> payload) {
    final allowed = fields[WorkforceCommandKind.attendance]!['raw_import']!;
    if (payload['action'] != 'raw_import' ||
        payload.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Raw import fields are invalid.');
    }
    calendarUuid(payload['id']);
    calendarUuid(payload['employee_id']);
    workforceText(payload['source_system'], 80);
    workforceText(payload['source_key'], 160);
    parseWorkUtc(workforceText(payload['observed_utc'], 20));
    if (payload['checksum'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(payload['checksum'] as String)) {
      throw const FormatException('Raw import checksum is invalid.');
    }
  }
}

abstract interface class WorkforceRepository {
  Future<WorkforcePage<RawClockBatch>> clockBatches(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<ClockBatchDetail> clockBatchDetail(
    TenantContext scope,
    String employeeId,
    String batchId, {
    int after = 0,
  });
  Future<void> authorize(
    TenantContext scope,
    String? employeeId,
    String capability,
  );
  Future<WorkforcePage<LeavePolicy>> policies(
    TenantContext scope, {
    String? after,
  });
  Future<WorkforcePage<LeavePolicyVersion>> policyVersions(
    TenantContext scope,
    String policyId, {
    String? after,
  });
  Future<LeavePolicy> policyForVersion(TenantContext scope, String versionId);
  Future<WorkforcePage<AttendanceEntry>> attendance(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<WorkforceDetail<AttendanceEntry, AttendanceHistoryEntry>>
  attendanceDetail(TenantContext scope, String entryId, {String? after});
  Future<WorkforcePage<RawClockEvent>> rawEvents(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<WorkforcePage<WorkClaim>> workClaims(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<WorkforcePage<LeaveRequest>> leaveRequests(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<WorkforceDetail<LeaveRequest, LeaveHistoryEntry>> leaveDetail(
    TenantContext scope,
    String requestId, {
    String? after,
  });
  Future<LeaveBalance> leaveBalance(
    TenantContext scope,
    String employeeId,
    String policyId,
    CivilDate asOf, {
    DateTime? recordedBefore,
    String? after,
  });
  Future<Map<String, Object?>?> leaveOwnReceipt(
    TenantContext scope,
    String commandId,
  );
  Future<Map<String, Object?>> execute(
    WorkforceCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
