import 'package:timezone/data/latest.dart' as time_data;
import 'package:timezone/timezone.dart' as tz;

import 'employee_gateway.dart';

bool _timeZonesReady = false;

void _initializeZones() {
  if (!_timeZonesReady) {
    time_data.initializeTimeZones();
    _timeZonesReady = true;
  }
}

DateTime employeeWorkplaceTime(DateTime instant, String zone) {
  _initializeZones();
  try {
    return tz.TZDateTime.from(instant.toUtc(), tz.getLocation(zone));
  } on Object {
    throw const EmployeeFailure(
      'LOCAL_TIME_INVALID',
      'The workplace time zone could not be resolved.',
    );
  }
}

final class EmployeeLocalInstant {
  const EmployeeLocalInstant(this.utc, this.local, this.offsetSeconds);
  final DateTime utc;
  final String local;
  final int offsetSeconds;
}

/// A company-local wall time must map to exactly one instant. DST gaps and
/// repeated hours require a different user selection, never a guessed offset.
EmployeeLocalInstant employeeWorkplaceInstant(DateTime wall, String zone) {
  _initializeZones();
  try {
    final location = tz.getLocation(zone);
    final naive = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    );
    final offsets = <int>{};
    for (var hours = -36; hours <= 36; hours += 3) {
      offsets.add(
        tz.TZDateTime.from(
          naive.add(Duration(hours: hours)),
          location,
        ).timeZoneOffset.inSeconds,
      );
    }
    final matches = <DateTime>[];
    for (final offset in offsets) {
      final candidate = naive.subtract(Duration(seconds: offset));
      final local = tz.TZDateTime.from(candidate, location);
      if (local.year == wall.year &&
          local.month == wall.month &&
          local.day == wall.day &&
          local.hour == wall.hour &&
          local.minute == wall.minute &&
          local.second == wall.second) {
        matches.add(candidate);
      }
    }
    if (matches.length != 1) {
      throw const EmployeeFailure(
        'LOCAL_TIME_INVALID',
        'Choose an unambiguous workplace time.',
      );
    }
    return EmployeeLocalInstant(
      matches.single,
      naive.toIso8601String().substring(0, 19),
      naive.difference(matches.single).inSeconds,
    );
  } on EmployeeFailure {
    rethrow;
  } on Object {
    throw const EmployeeFailure(
      'LOCAL_TIME_INVALID',
      'The workplace time zone could not be resolved.',
    );
  }
}
