import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

Map<String, Object?> resolution({List<Map<String, Object?>>? candidates}) => {
  'calendar_version_id': '10000000-0000-0000-0000-000000000001',
  'date': '2026-11-01',
  'minute': 90,
  'timezone': 'America/New_York',
  'local_datetime': '2026-11-01T01:30:00',
  'algorithm': 'pg-iana-roundtrip-v1',
  'candidates':
      candidates ??
      [
        {'utc': '2026-11-01T05:30:00+00:00', 'offset_seconds': -14400},
        {'utc': '2026-11-01T06:30:00+00:00', 'offset_seconds': -18000},
      ],
};

void main() {
  test(
    'AC-405 fold requires an explicit offset and freezes exact evidence',
    () {
      final value = CalendarLocalResolution.fromJson(resolution());
      expect(value.choose, throwsFormatException);
      final chosen = value.choose(offsetSeconds: -18000);
      expect(chosen.utc, DateTime.utc(2026, 11, 1, 6, 30));
      expect(chosen.offsetSeconds, -18000);
      expect(() => value.choose(offsetSeconds: 0), throwsFormatException);
    },
  );
  test('AC-405 a gap is unavailable rather than normalized forward', () {
    final value = CalendarLocalResolution.fromJson(resolution(candidates: []));
    expect(value.isGap, isTrue);
    expect(value.choose, throwsFormatException);
  });
  test('AC-405 UTC/offset must round trip to the precise local boundary', () {
    expect(
      () => CalendarLocalResolution.fromJson(
        resolution(
          candidates: [
            {'utc': '2026-11-01T06:31:00Z', 'offset_seconds': -18000},
          ],
        ),
      ),
      throwsFormatException,
    );
  });
  test('AC-401 unexpected/private response fields are rejected', () {
    expect(
      () => CalendarLocalResolution.fromJson({...resolution(), 'salary': '1'}),
      throwsFormatException,
    );
  });
  test('AC-405 duplicate or reversed UTC candidates are rejected', () {
    final rows = (resolution()['candidates'] as List)
        .cast<Map<String, Object?>>();
    expect(
      () => CalendarLocalResolution.fromJson(
        resolution(candidates: rows.reversed.toList()),
      ),
      throwsFormatException,
    );
    expect(
      () => CalendarLocalResolution.fromJson(
        resolution(candidates: [rows.first, rows.first]),
      ),
      throwsFormatException,
    );
  });
  test('AC-405 historical second offsets are retained exactly', () {
    final raw =
        resolution(
          candidates: [
            {'utc': '1900-01-01T01:10:28Z', 'offset_seconds': 19172},
          ],
        )..addAll({
          'date': '1900-01-01',
          'minute': 390,
          'local_datetime': '1900-01-01T06:30:00',
          'timezone': 'Asia/Colombo',
        });
    final value = CalendarLocalResolution.fromJson(raw).choose();
    expect(value.offsetSeconds, 19172);
  });
}
