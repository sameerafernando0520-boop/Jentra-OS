import 'process_metrics.dart';

final class ProcessMetricFilter {
  ProcessMetricFilter({
    required String windowStart,
    required String windowEnd,
    required String asOf,
    required String recordedThrough,
  }) : windowStart = parseProcessMetricUtc(windowStart),
       windowEnd = parseProcessMetricUtc(windowEnd),
       asOf = parseProcessMetricUtc(asOf),
       recordedThrough = parseProcessMetricUtc(recordedThrough) {
    if (!this.windowEnd.isAfter(this.windowStart) ||
        this.asOf.isBefore(this.windowEnd) ||
        this.recordedThrough.isBefore(this.asOf) ||
        this.windowEnd.difference(this.windowStart) >
            const Duration(days: 366)) {
      throw const FormatException(
        'Use an ordered UTC cohort of at most 366 days.',
      );
    }
  }
  final DateTime windowStart, windowEnd, asOf, recordedThrough;
  Map<String, Object?> toJson() => {
    'windowStart': windowStart.toIso8601String(),
    'windowEnd': windowEnd.toIso8601String(),
    'asOf': asOf.toIso8601String(),
    'recordedThrough': recordedThrough.toIso8601String(),
  };
  factory ProcessMetricFilter.fromJson(Map<String, Object?> json) {
    if (json.length != 4 ||
        !json.keys.toSet().containsAll({
          'windowStart',
          'windowEnd',
          'asOf',
          'recordedThrough',
        }) ||
        json.values.any((v) => v is! String)) {
      throw const FormatException('Invalid saved process filter.');
    }
    return ProcessMetricFilter(
      windowStart: json['windowStart'] as String,
      windowEnd: json['windowEnd'] as String,
      asOf: json['asOf'] as String,
      recordedThrough: json['recordedThrough'] as String,
    );
  }
}

abstract interface class ProcessMetricRepository {
  Future<void> authorize(ProcessMetricScope scope);
  Future<void> authorizeRecovery(ProcessMetricScope scope, String actorId);
  Future<ProcessMetricSnapshot> snapshot(
    ProcessMetricScope scope,
    ProcessMetricFilter filter,
  );
  Future<Map<String, Object?>> event(ProcessMetricScope scope, String eventId);
}
