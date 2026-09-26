import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> payload() => {
    'id': '20000000-0000-0000-0000-000000000001',
    'code': 'HQ',
    'name': 'Head Office',
    'version_id': '30000000-0000-0000-0000-000000000001',
    'start_date': '2026-09-01',
    'end_date_exclusive': '2027-01-01',
    'timezone': 'Asia/Colombo',
    'weekly_intervals': <Object?>[],
    'date_overrides': <Object?>[],
    'reason': 'Synthetic setup',
  };
  test(
    'calendar commands reject unknown fields, invalid identities and unbounded dates',
    () {
      validateCalendarPayload('create', payload());
      for (final changed in [
        {...payload(), 'private_profile': 'forbidden'},
        {...payload(), 'id': 'guess'},
        {...payload(), 'end_date_exclusive': null},
        {...payload(), 'end_date_exclusive': '2036-01-01'},
        {...payload(), 'code': 'lowercase'},
        {...payload(), 'reason': ''},
        {
          ...payload(),
          'date_overrides': [
            {
              'date': '2027-01-01',
              'is_working_day': false,
              'reason': 'Out of range',
            },
          ],
        },
      ]) {
        expect(
          () => validateCalendarPayload('create', changed),
          throwsFormatException,
        );
      }
    },
  );
  test('wire patterns round trip and retain immutable snapshots', () {
    final weekly = [
      {
        'day_of_week': 7,
        'start_minute': 1320,
        'end_minute': 360,
        'end_day_offset': 1,
      },
    ];
    final exceptions = [
      {
        'date': '2026-09-28',
        'is_working_day': true,
        'reason': 'Overnight spill',
      },
    ];
    final pattern = WorkCalendarPattern.fromJson(weekly, exceptions);
    expect(pattern.weeklyIntervals.single.toJson(), weekly.single);
    expect(pattern.overrides.single.toJson(), exceptions.single);
    weekly.clear();
    exceptions.clear();
    expect(pattern.weeklyIntervals, hasLength(1));
    expect(() => pattern.overrides.clear(), throwsUnsupportedError);
    expect(
      () => WorkCalendarPattern.fromJson([
        {
          'day_of_week': 1.0,
          'start_minute': 540,
          'end_minute': 1020,
          'end_day_offset': 0,
        },
      ], []),
      throwsFormatException,
    );
  });
  test('coverage makes the exclusive end and missing dates explicit', () {
    final coverage = CalendarCoverage(
      id: '30000000-0000-0000-0000-000000000001',
      startDate: '2026-09-01',
      endDateExclusive: '2026-10-01',
      timezone: 'Asia/Colombo',
    );
    expect(coverage.contains(CivilDate.parse('2026-09-30')), isTrue);
    expect(coverage.contains(CivilDate.parse('2026-10-01')), isFalse);
  });
}
