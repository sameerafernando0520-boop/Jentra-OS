import 'commands.dart';
import 'employee.dart';
import 'tenant_context.dart';
import 'work_calendar.dart';

const calendarMaxVersion = 9007199254740991;
final _calendarUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String calendarUuid(Object? value) {
  if (value is! String || !_calendarUuid.hasMatch(value)) {
    throw const FormatException('Calendar identity is invalid.');
  }
  return value;
}

void calendarFields(Map<String, Object?> json, Set<String> keys) {
  if (json.length != keys.length ||
      json.keys.any((key) => !keys.contains(key))) {
    throw const FormatException(
      'Calendar response contains missing or unexpected fields.',
    );
  }
}

String _text(Object? value, int max, [String label = 'Calendar text']) {
  if (value is! String || value.trim().isEmpty || value.length > max) {
    throw FormatException(
      '$label is required and must be at most $max characters.',
    );
  }
  return value;
}

DateTime _timestamp(Object? value) {
  final text = _text(value, 64);
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(text)) {
    throw const FormatException('Calendar timestamp must include an offset.');
  }
  return DateTime.parse(text).toUtc();
}

/// Validated half-open civil dates. This does not resolve local times to instants.
final class CalendarCoverage {
  CalendarCoverage({
    required this.id,
    required String startDate,
    required String endDateExclusive,
    required this.timezone,
  }) : start = CivilDate.parse(startDate),
       endExclusive = CivilDate.parse(endDateExclusive) {
    calendarUuid(id);
    _text(timezone, 100);
    final days = endExclusive.utc.difference(start.utc).inDays;
    if (days < 1 || days > 1830) {
      throw const FormatException('Calendar coverage must be 1 to 1,830 days.');
    }
  }
  final String id, timezone;
  final CivilDate start, endExclusive;
  bool contains(CivilDate date) =>
      start.compareTo(date) <= 0 && endExclusive.compareTo(date) > 0;
  factory CalendarCoverage.fromJson(Map<String, Object?> json) {
    calendarFields(json, {
      'id',
      'start_date',
      'end_date_exclusive',
      'timezone',
    });
    return CalendarCoverage(
      id: calendarUuid(json['id']),
      startDate: _text(json['start_date'], 10),
      endDateExclusive: _text(json['end_date_exclusive'], 10),
      timezone: _text(json['timezone'], 100),
    );
  }
}

final class WorkCalendarIdentity {
  WorkCalendarIdentity.fromJson(Map<String, Object?> json)
    : id = calendarUuid(json['id']),
      tenantId = calendarUuid(json['tenant_id']),
      legalEntityId = calendarUuid(json['legal_entity_id']),
      code = _text(json['code'], 32),
      name = _text(json['name'], 160),
      version = _version(json['version']) {
    calendarFields(json, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'code',
      'name',
      'version',
    });
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code)) {
      throw const FormatException('Calendar code is invalid.');
    }
  }
  final String id, tenantId, legalEntityId, code, name;
  final int version;
  static int _version(Object? value) {
    if (value is! int || value < 1 || value > calendarMaxVersion) {
      throw const FormatException('Calendar version is invalid.');
    }
    return value;
  }
}

final class CalendarDirectoryEntry {
  const CalendarDirectoryEntry(this.calendar, this.coverage);
  final WorkCalendarIdentity calendar;
  final CalendarCoverage? coverage;
}

final class CalendarPage<T> {
  CalendarPage(List<T> items, this.nextCursor)
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;
}

final class CalendarDirectoryPage {
  const CalendarDirectoryPage(this.asOf, this.page);
  final CivilDate asOf;
  final CalendarPage<CalendarDirectoryEntry> page;
}

final class CalendarVersionSummary {
  CalendarVersionSummary.fromJson(Map<String, Object?> json)
    : coverage = CalendarCoverage.fromJson({
        for (final key in [
          'id',
          'start_date',
          'end_date_exclusive',
          'timezone',
        ])
          key: json[key],
      }),
      publishedBy = calendarUuid(json['published_by']),
      publishedAt = _timestamp(json['published_at']) {
    calendarFields(json, {
      'id',
      'start_date',
      'end_date_exclusive',
      'timezone',
      'published_by',
      'published_at',
    });
  }
  final CalendarCoverage coverage;
  final String publishedBy;
  final DateTime publishedAt;
}

final class CalendarVersionDetail {
  CalendarVersionDetail.fromJson(Map<String, Object?> json)
    : summary = CalendarVersionSummary.fromJson({
        for (final key in [
          'id',
          'start_date',
          'end_date_exclusive',
          'timezone',
          'published_by',
          'published_at',
        ])
          key: json[key],
      }),
      calendarId = calendarUuid(json['calendar_id']),
      tenantId = calendarUuid(json['tenant_id']),
      legalEntityId = calendarUuid(json['legal_entity_id']),
      pattern = WorkCalendarPattern.fromJson(
        json['weekly_intervals'],
        json['date_overrides'],
      ) {
    calendarFields(json, {
      'id',
      'calendar_id',
      'tenant_id',
      'legal_entity_id',
      'start_date',
      'end_date_exclusive',
      'timezone',
      'published_by',
      'published_at',
      'weekly_intervals',
      'date_overrides',
    });
    for (final override in pattern.overrides) {
      if (!summary.coverage.contains(override.date)) {
        throw const FormatException(
          'Calendar exception is outside version coverage.',
        );
      }
    }
  }
  final CalendarVersionSummary summary;
  final String calendarId, tenantId, legalEntityId;
  final WorkCalendarPattern pattern;
}

final class CalendarDetail {
  const CalendarDetail(this.calendar, this.version);
  final WorkCalendarIdentity calendar;
  final CalendarVersionDetail version;
}

final class CalendarConfirmation {
  const CalendarConfirmation(this.calendar, this.publishedVersionId);
  final WorkCalendarIdentity calendar;
  final String? publishedVersionId;
}

final class CalendarHistoryEvent {
  const CalendarHistoryEvent({
    required this.id,
    required this.action,
    required this.publishedVersionId,
    required this.effectiveDate,
    required this.reason,
    required this.actorId,
    required this.recordedAt,
    required this.before,
    required this.after,
  });
  final String id, action, reason, actorId;
  final String? publishedVersionId;
  final CivilDate? effectiveDate;
  final DateTime recordedAt;
  final WorkCalendarIdentity? before;
  final CalendarConfirmation after;
}

void validateCalendarPayload(String action, Map<String, Object?> payload) {
  final keys = switch (action) {
    'create' => {
      'id',
      'code',
      'name',
      'version_id',
      'start_date',
      'end_date_exclusive',
      'timezone',
      'weekly_intervals',
      'date_overrides',
      'reason',
    },
    'publish' => {
      'id',
      'version_id',
      'start_date',
      'end_date_exclusive',
      'timezone',
      'weekly_intervals',
      'date_overrides',
      'reason',
    },
    'rename' => {'id', 'name', 'reason'},
    _ => throw const FormatException('Unknown calendar action.'),
  };
  calendarFields(payload, keys);
  calendarUuid(payload['id']);
  _text(payload['reason'], 1000, 'Reason');
  if (action == 'create' || action == 'rename') {
    _text(payload['name'], 160, 'Calendar name');
  }
  if (action == 'create' &&
      !RegExp(
        r'^[A-Z0-9][A-Z0-9_-]{0,31}$',
      ).hasMatch(_text(payload['code'], 32))) {
    throw const FormatException(
      'Use an uppercase calendar code of up to 32 characters.',
    );
  }
  if (action != 'rename') {
    final coverage = CalendarCoverage(
      id: calendarUuid(payload['version_id']),
      startDate: _text(payload['start_date'], 10),
      endDateExclusive: _text(payload['end_date_exclusive'], 10),
      timezone: _text(payload['timezone'], 100),
    );
    final pattern = WorkCalendarPattern.fromJson(
      payload['weekly_intervals'],
      payload['date_overrides'],
    );
    for (final override in pattern.overrides) {
      if (!coverage.contains(override.date)) {
        throw const FormatException(
          'Calendar exception must fall within version dates.',
        );
      }
    }
  }
}

abstract interface class WorkCalendarRepository {
  Future<CalendarDirectoryPage> directory(
    TenantContext scope, {
    String? asOfDate,
    String search = '',
    String? after,
  });
  Future<CalendarDetail> detail(
    TenantContext scope,
    String calendarId,
    String versionId,
  );
  Future<CalendarPage<CalendarVersionSummary>> versions(
    TenantContext scope,
    String calendarId, {
    String? after,
  });
  Future<CalendarPage<CalendarHistoryEvent>> history(
    TenantContext scope,
    String calendarId, {
    String? after,
  });
  Future<CalendarConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
