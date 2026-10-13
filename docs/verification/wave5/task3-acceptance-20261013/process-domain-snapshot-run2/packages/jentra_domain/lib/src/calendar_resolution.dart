import 'calendar_repository.dart';
import 'employee.dart';
import 'tenant_context.dart';

abstract interface class CalendarInstantResolver {
  Future<CalendarLocalResolution> localCandidates(
    TenantContext scope,
    CalendarVersionDetail version,
    CivilDate date,
    int minute,
  );
}

/// A precise server-resolved instant; downstream consumers must freeze it.
final class CalendarInstant {
  const CalendarInstant(this.utc, this.offsetSeconds);
  final DateTime utc;
  final int offsetSeconds;
  Map<String, Object?> toJson() => {
    'utc': utc.toIso8601String(),
    'offset_seconds': offsetSeconds,
  };
}

final class CalendarLocalResolution {
  CalendarLocalResolution.fromJson(Map<String, Object?> json)
    : versionId = calendarUuid(json['calendar_version_id']),
      date = CivilDate.parse(json['date'] as String),
      minute = json['minute'] as int,
      timezone = json['timezone'] as String,
      candidates = _parse(json) {
    calendarFields(json, {
      'calendar_version_id',
      'date',
      'minute',
      'timezone',
      'local_datetime',
      'algorithm',
      'candidates',
    });
    if (minute < 0 ||
        minute > 1439 ||
        timezone.isEmpty ||
        timezone.length > 100 ||
        json['algorithm'] != algorithm) {
      throw const FormatException('Calendar resolution metadata is invalid.');
    }
    final local = date.utc.add(Duration(minutes: minute));
    final expected =
        '${date.value}T${(minute ~/ 60).toString().padLeft(2, '0')}:'
        '${(minute % 60).toString().padLeft(2, '0')}:00';
    if (json['local_datetime'] != expected) {
      throw const FormatException('Calendar local boundary changed.');
    }
    DateTime? previous;
    for (final candidate in candidates) {
      if (candidate.utc.add(Duration(seconds: candidate.offsetSeconds)) !=
              local ||
          (previous != null && !candidate.utc.isAfter(previous))) {
        throw const FormatException(
          'Calendar instant does not round trip or is duplicated.',
        );
      }
      previous = candidate.utc;
    }
  }
  static const algorithm = 'pg-iana-roundtrip-v1';
  final String versionId, timezone;
  final CivilDate date;
  final int minute;
  final List<CalendarInstant> candidates;
  bool get isGap => candidates.isEmpty;
  bool get isAmbiguous => candidates.length > 1;

  static List<CalendarInstant> _parse(Map<String, Object?> json) {
    final rows = json['candidates'];
    if (rows is! List || rows.length > 4) {
      throw const FormatException('Invalid calendar instant candidates.');
    }
    return List.unmodifiable(
      rows.map((raw) {
        if (raw is! Map<String, Object?>) {
          throw const FormatException('Invalid calendar instant.');
        }
        calendarFields(raw, {'utc', 'offset_seconds'});
        final timestamp = raw['utc'];
        final offset = raw['offset_seconds'];
        if (timestamp is! String ||
            offset is! int ||
            offset.abs() > 86400 ||
            !RegExp(
              r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|\+00:00)$',
            ).hasMatch(timestamp)) {
          throw const FormatException(
            'Calendar instant requires exact UTC and integer offset seconds.',
          );
        }
        final utc = DateTime.parse(timestamp);
        if (!utc.isUtc) {
          throw const FormatException('Calendar instant must be UTC.');
        }
        return CalendarInstant(utc, offset);
      }),
    );
  }

  CalendarInstant choose({int? offsetSeconds}) {
    if (isGap) {
      throw const FormatException('This local time does not exist.');
    }
    if (isAmbiguous && offsetSeconds == null) {
      throw const FormatException(
        'Choose the UTC offset for this ambiguous local time.',
      );
    }
    for (final candidate in candidates) {
      if (offsetSeconds == null || candidate.offsetSeconds == offsetSeconds) {
        return candidate;
      }
    }
    throw const FormatException('The selected UTC offset is invalid.');
  }
}
