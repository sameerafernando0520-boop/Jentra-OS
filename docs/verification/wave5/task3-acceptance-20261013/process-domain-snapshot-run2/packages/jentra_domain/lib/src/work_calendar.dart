import 'employee.dart';

/// A local weekly working interval. Monday is 1 and Sunday is 7.
///
/// Minutes are wall-clock minutes after local midnight. This validates the
/// recurring pattern only; a versioned IANA time zone and an explicit offset
/// still determine real instants on clock-transition dates at the server.
final class WeeklyWorkInterval {
  WeeklyWorkInterval({
    required this.dayOfWeek,
    required this.startMinute,
    required this.endMinute,
    required this.endDayOffset,
  }) {
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      throw const FormatException('Choose a weekday from Monday to Sunday.');
    }
    if (startMinute < 0 ||
        startMinute >= minutesPerDay ||
        endMinute < 0 ||
        endMinute >= minutesPerDay ||
        (endDayOffset != 0 && endDayOffset != 1)) {
      throw const FormatException('Working interval time is invalid.');
    }
    final duration = endDayOffset * minutesPerDay + endMinute - startMinute;
    if (duration <= 0 || duration > minutesPerDay) {
      throw const FormatException(
        'Working interval must last more than zero and at most one local day.',
      );
    }
  }

  static const minutesPerDay = 1440;
  static const minutesPerWeek = 7 * minutesPerDay;

  final int dayOfWeek;
  final int startMinute;
  final int endMinute;
  final int endDayOffset;

  factory WeeklyWorkInterval.fromJson(Map<String, Object?> json) {
    const keys = {
      'day_of_week',
      'start_minute',
      'end_minute',
      'end_day_offset',
    };
    if (json.length != keys.length ||
        json.keys.any((key) => !keys.contains(key)) ||
        json.values.any((value) => value is! int)) {
      throw const FormatException('Working interval fields are invalid.');
    }
    return WeeklyWorkInterval(
      dayOfWeek: json['day_of_week'] as int,
      startMinute: json['start_minute'] as int,
      endMinute: json['end_minute'] as int,
      endDayOffset: json['end_day_offset'] as int,
    );
  }

  Map<String, Object?> toJson() => {
    'day_of_week': dayOfWeek,
    'start_minute': startMinute,
    'end_minute': endMinute,
    'end_day_offset': endDayOffset,
  };

  int get startOfWeekMinute => (dayOfWeek - 1) * minutesPerDay + startMinute;
  int get endOfWeekMinute =>
      (dayOfWeek - 1 + endDayOffset) * minutesPerDay + endMinute;
}

/// A dated exception for one local date in a specific calendar version.
final class WorkdayOverride {
  WorkdayOverride({
    required String date,
    required this.isWorkingDay,
    required this.reason,
  }) : date = CivilDate.parse(date) {
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw const FormatException('Give a calendar exception reason.');
    }
  }

  final CivilDate date;
  final bool isWorkingDay;
  final String reason;

  factory WorkdayOverride.fromJson(Map<String, Object?> json) {
    if (json.length != 3 ||
        json.keys.any(
          (key) => !{'date', 'is_working_day', 'reason'}.contains(key),
        ) ||
        json['date'] is! String ||
        json['is_working_day'] is! bool ||
        json['reason'] is! String) {
      throw const FormatException('Calendar exception fields are invalid.');
    }
    return WorkdayOverride(
      date: json['date'] as String,
      isWorkingDay: json['is_working_day'] as bool,
      reason: json['reason'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'date': date.value,
    'is_working_day': isWorkingDay,
    'reason': reason,
  };
}

/// Structural validation shared by calendar editors and gateway responses.
/// The server remains authoritative for scope, version, zone and DST resolution.
final class WorkCalendarPattern {
  WorkCalendarPattern({
    required List<WeeklyWorkInterval> weeklyIntervals,
    required List<WorkdayOverride> overrides,
  }) : weeklyIntervals = List.unmodifiable(weeklyIntervals),
       overrides = List.unmodifiable(overrides) {
    if (this.weeklyIntervals.length > 56 || this.overrides.length > 366) {
      throw const FormatException(
        'Calendar pattern exceeds the allowed limit.',
      );
    }
    final segments = <(int, int)>[];
    for (final interval in this.weeklyIntervals) {
      final start = interval.startOfWeekMinute;
      final end = interval.endOfWeekMinute;
      if (end <= WeeklyWorkInterval.minutesPerWeek) {
        segments.add((start, end));
      } else {
        segments.add((start, WeeklyWorkInterval.minutesPerWeek));
        segments.add((0, end - WeeklyWorkInterval.minutesPerWeek));
      }
    }
    segments.sort((a, b) => a.$1.compareTo(b.$1));
    for (var i = 1; i < segments.length; i++) {
      if (segments[i - 1].$2 > segments[i].$1) {
        throw const FormatException('Working intervals overlap.');
      }
    }

    final dates = <String>{};
    for (final override in this.overrides) {
      if (!dates.add(override.date.value)) {
        throw const FormatException('Calendar exception date is duplicated.');
      }
      final day = override.date.utc.weekday;
      final previousDay = (day + 5) % 7 + 1;
      if (override.isWorkingDay &&
          !this.weeklyIntervals.any(
            (interval) =>
                interval.dayOfWeek == day ||
                (interval.dayOfWeek == previousDay &&
                    interval.endDayOffset == 1 &&
                    interval.endMinute > 0),
          )) {
        throw const FormatException(
          'Working-day exception has no configured regular hours.',
        );
      }
    }
  }

  final List<WeeklyWorkInterval> weeklyIntervals;
  final List<WorkdayOverride> overrides;

  factory WorkCalendarPattern.fromJson(Object? weekly, Object? overrides) {
    if (weekly is! List ||
        overrides is! List ||
        weekly.length > 56 ||
        overrides.length > 366) {
      throw const FormatException(
        'Calendar pattern exceeds the allowed limit or is invalid.',
      );
    }
    Map<String, Object?> row(Object? value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('Invalid calendar pattern row.');
      }
      return value;
    }

    return WorkCalendarPattern(
      weeklyIntervals: weekly
          .map((value) => WeeklyWorkInterval.fromJson(row(value)))
          .toList(),
      overrides: overrides
          .map((value) => WorkdayOverride.fromJson(row(value)))
          .toList(),
    );
  }
}
