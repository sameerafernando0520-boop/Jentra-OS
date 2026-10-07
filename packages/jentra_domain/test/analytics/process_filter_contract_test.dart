import 'package:test/test.dart';
import 'package:jentra_domain/analytics.dart';

void main() {
  final values = <String, Object?>{
    'windowStart': '2026-09-01T00:00:00Z',
    'windowEnd': '2026-10-01T00:00:00Z',
    'asOf': '2026-10-01T00:00:00Z',
    'recordedThrough': '2026-10-02T00:00:00Z',
  };
  test(
    'exact filter survives serialization and rejects partial or injected payloads',
    () {
      final filter = ProcessMetricFilter.fromJson(values);
      expect(
        ProcessMetricFilter.fromJson(filter.toJson()).toJson(),
        filter.toJson(),
      );
      for (final altered in [
        {...values, 'privateRows': []},
        {...values}..remove('asOf'),
        {...values, 'windowStart': 1},
      ]) {
        expect(
          () => ProcessMetricFilter.fromJson(altered),
          throwsFormatException,
        );
      }
    },
  );
  test('filter requires ordered complete cutoffs and the 366 day bound', () {
    for (final altered in [
      {...values, 'windowEnd': values['windowStart']},
      {...values, 'asOf': '2026-09-30T00:00:00Z'},
      {...values, 'recordedThrough': '2026-09-30T00:00:00Z'},
      {...values, 'windowStart': '2024-01-01T00:00:00Z'},
    ]) {
      expect(
        () => ProcessMetricFilter.fromJson(altered),
        throwsFormatException,
      );
    }
  });
}
