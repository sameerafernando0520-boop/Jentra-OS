import 'commands.dart';
import 'tenant_context.dart';

/// Civil dates are interpreted in the legal entity's configured time zone.
final class CivilDate implements Comparable<CivilDate> {
  CivilDate._(this.value, this.utc);
  final String value;
  final DateTime utc;

  factory CivilDate.parse(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      throw const FormatException('Use a YYYY-MM-DD date.');
    }
    final year = int.parse(input.substring(0, 4));
    final month = int.parse(input.substring(5, 7));
    final day = int.parse(input.substring(8, 10));
    if (year < 1 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      throw const FormatException('Date is outside the supported range.');
    }
    final utc = DateTime.utc(year, month, day);
    if (utc.year != year || utc.month != month || utc.day != day) {
      throw const FormatException('Date does not exist.');
    }
    return CivilDate._(input, utc);
  }

  CivilDate get next {
    if (value == '9999-12-31') {
      throw const FormatException('Date has no supported successor.');
    }
    final tomorrow = utc.add(const Duration(days: 1));
    return CivilDate.parse(
      '${tomorrow.year.toString().padLeft(4, '0')}-'
      '${tomorrow.month.toString().padLeft(2, '0')}-'
      '${tomorrow.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  int compareTo(CivilDate other) => value.compareTo(other.value);
  @override
  String toString() => value;
}

final class EmploymentInterval {
  EmploymentInterval(String startDate, String? endDateExclusive)
    : start = CivilDate.parse(startDate),
      endExclusive = endDateExclusive == null
          ? null
          : CivilDate.parse(endDateExclusive) {
    if (endExclusive != null && start.compareTo(endExclusive!) >= 0) {
      throw const FormatException('Employment end must follow its start.');
    }
  }
  final CivilDate start;
  final CivilDate? endExclusive;

  bool contains(CivilDate date) =>
      date.compareTo(start) >= 0 &&
      (endExclusive == null || date.compareTo(endExclusive!) < 0);

  bool overlaps(EmploymentInterval other) =>
      (endExclusive == null || other.start.compareTo(endExclusive!) < 0) &&
      (other.endExclusive == null || start.compareTo(other.endExclusive!) < 0);
}

const employeeEmploymentTypes = {
  'permanent',
  'fixed_term',
  'casual',
  'contractor',
};
const _employeeMaxJsonInteger = 9007199254740991;

void validateEmployeePayload(String action, Map<String, Object?> payload) {
  const common = {'id', 'reason'};
  final allowed = switch (action) {
    'create' => {
      'id',
      'code',
      'display_name',
      'work_email',
      'start_date',
      'job_title',
      'employment_type',
    },
    'identity' => {...common, 'display_name', 'work_email'},
    'assignment' => {
      ...common,
      'effective_date',
      'destination_branch_id',
      'job_title',
      'employment_type',
    },
    'end' => {...common, 'spell_id', 'end_date_exclusive'},
    'rehire' => {...common, 'start_date', 'job_title', 'employment_type'},
    'correct' => {...common, 'event_id', 'correction_action'},
    _ => throw const FormatException('Unknown employee action.'),
  };
  if (payload.keys.any((key) => !allowed.contains(key)) ||
      (payload['id'] is! String) ||
      (payload['id'] as String).trim().isEmpty) {
    throw const FormatException(
      'Employee input contains an unknown or missing field.',
    );
  }
  if (action == 'create') {
    final code = payload['code'];
    if (code is! String ||
        !RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code)) {
      throw const FormatException('Employee code is invalid.');
    }
  }
  for (final name in [
    if (action == 'create' || action == 'identity') 'display_name',
    if (action == 'create' || action == 'assignment' || action == 'rehire')
      'job_title',
  ]) {
    final value = payload[name];
    if (value is! String || value.trim().isEmpty || value.trim().length > 160) {
      throw FormatException(
        '$name is required and must be at most 160 characters.',
      );
    }
  }
  if (action == 'create' || action == 'identity') {
    final email = payload['work_email'];
    if (email != null &&
        email != '' &&
        (email is! String ||
            email.length > 254 ||
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))) {
      throw const FormatException('Work email is invalid.');
    }
  }
  if (action != 'create') {
    final reason = payload['reason'];
    if (reason is! String ||
        reason.trim().isEmpty ||
        reason.trim().length > 1000) {
      throw const FormatException('Give a reason of at most 1000 characters.');
    }
  }
  for (final field in [
    if (action == 'create' || action == 'rehire') 'start_date',
    if (action == 'assignment') 'effective_date',
    if (action == 'end') 'end_date_exclusive',
  ]) {
    final value = payload[field];
    if (value is! String) throw FormatException('$field is required.');
    CivilDate.parse(value);
  }
  if (action == 'create' || action == 'assignment' || action == 'rehire') {
    if (!employeeEmploymentTypes.contains(payload['employment_type'])) {
      throw const FormatException('Employment type is invalid.');
    }
  }
  if (action == 'assignment' && payload['destination_branch_id'] is! String) {
    throw const FormatException('Select a destination branch.');
  }
  if (action == 'end' && payload['spell_id'] is! String) {
    throw const FormatException('Select an employment spell.');
  }
  if (action == 'correct') {
    if (payload['event_id'] is! String ||
        payload['correction_action'] != 'cancel') {
      throw const FormatException('Select an event and correction.');
    }
  }
}

final class EmployeeRecord {
  EmployeeRecord._({
    required this.id,
    required this.tenantId,
    required this.legalEntityId,
    required this.branchId,
    required this.code,
    required this.displayName,
    required this.workEmail,
    required this.version,
    required this.assignments,
  });
  final String id, tenantId, legalEntityId, branchId, code, displayName;
  final String? workEmail;
  final int version;
  final List<Map<String, Object?>> assignments;

  factory EmployeeRecord.fromJson(Map<String, Object?> json) {
    const allowed = {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'code',
      'display_name',
      'work_email',
      'version',
      'assignments',
    };
    final version = json['version'];
    if (json.keys.any((key) => !allowed.contains(key)) ||
        [
          json['id'],
          json['tenant_id'],
          json['legal_entity_id'],
          json['branch_id'],
          json['code'],
          json['display_name'],
        ].any((value) => value is! String || value.isEmpty) ||
        (json['work_email'] != null && json['work_email'] is! String) ||
        version is! int ||
        version < 1 ||
        version > _employeeMaxJsonInteger ||
        json['assignments'] is! List) {
      throw const FormatException(
        'Employee response is invalid or contains private fields.',
      );
    }
    final assignments = <Map<String, Object?>>[];
    for (final raw in json['assignments'] as List) {
      if (raw is! Map<String, Object?> ||
          raw.keys.any(
            (key) => !{
              'id',
              'spell_id',
              'branch_id',
              'start_date',
              'end_date_exclusive',
              'job_title',
              'employment_type',
            }.contains(key),
          ) ||
          raw['id'] is! String ||
          raw['spell_id'] is! String ||
          raw['branch_id'] is! String ||
          raw['start_date'] is! String ||
          raw['job_title'] is! String ||
          !employeeEmploymentTypes.contains(raw['employment_type'])) {
        throw const FormatException('Employee assignment response is invalid.');
      }
      EmploymentInterval(
        raw['start_date'] as String,
        raw['end_date_exclusive'] as String?,
      );
      assignments.add(Map.unmodifiable(raw));
    }
    return EmployeeRecord._(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      legalEntityId: json['legal_entity_id'] as String,
      branchId: json['branch_id'] as String,
      code: json['code'] as String,
      displayName: json['display_name'] as String,
      workEmail: json['work_email'] as String?,
      version: version,
      assignments: List.unmodifiable(assignments),
    );
  }
}

abstract interface class EmployeeRepository {
  Future<Map<String, Object?>> directory(
    TenantContext scope, {
    String? asOfDate,
    String status = 'employed',
    String search = '',
    String? after,
  });
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id,
    String asOfDate,
    String status,
  );
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    String? after,
  });
  Future<Map<String, Object?>> branches(
    TenantContext scope, {
    String search = '',
  });
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
