import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

void main() {
  WeeklyWorkInterval shift(
    int weekday,
    int start,
    int end, {
    int nextDay = 0,
  }) => WeeklyWorkInterval(
    dayOfWeek: weekday,
    startMinute: start,
    endMinute: end,
    endDayOffset: nextDay,
  );

  test('AC-405 overnight Sunday work is checked against Monday', () {
    expect(
      () => WorkCalendarPattern(
        weeklyIntervals: [
          shift(7, 22 * 60, 6 * 60, nextDay: 1),
          shift(1, 5 * 60, 8 * 60),
        ],
        overrides: const [],
      ),
      throwsFormatException,
    );
    expect(
      () => WorkCalendarPattern(
        weeklyIntervals: [
          shift(7, 22 * 60, 6 * 60, nextDay: 1),
          shift(1, 6 * 60, 8 * 60),
        ],
        overrides: const [],
      ),
      returnsNormally,
    );
  });

  test('AC-405 zero, overlong and malformed local intervals are denied', () {
    expect(() => shift(1, 8 * 60, 8 * 60), throwsFormatException);
    expect(() => shift(1, 8 * 60, 9 * 60, nextDay: 1), throwsFormatException);
    expect(() => shift(0, 8 * 60, 9 * 60), throwsFormatException);
    expect(() => shift(1, 8 * 60, 1440), throwsFormatException);
  });

  test('AC-405 dated exceptions cannot collide or use invalid civil dates', () {
    WorkdayOverride override(String date) => WorkdayOverride(
      date: date,
      isWorkingDay: false,
      reason: 'Synthetic closure',
    );
    expect(() => override('2026-02-29'), throwsFormatException);
    expect(
      () => WorkCalendarPattern(
        weeklyIntervals: const [],
        overrides: [override('2028-02-29'), override('2028-02-29')],
      ),
      throwsFormatException,
    );
    expect(
      () => WorkCalendarPattern(
        weeklyIntervals: const [],
        overrides: [override('2028-02-29'), override('2028-03-01')],
      ),
      returnsNormally,
    );
  });

  test('validated schedule cannot be changed through caller-owned lists', () {
    final intervals = [shift(1, 8 * 60, 12 * 60)];
    final pattern = WorkCalendarPattern(
      weeklyIntervals: intervals,
      overrides: const [],
    );
    intervals.add(shift(1, 9 * 60, 10 * 60));
    expect(pattern.weeklyIntervals, hasLength(1));
    expect(
      () => pattern.weeklyIntervals.add(shift(1, 13 * 60, 14 * 60)),
      throwsUnsupportedError,
    );
  });

  test(
    'working override must use configured hours, including overnight spill',
    () {
      final monday = WorkdayOverride(
        date: '2026-09-28',
        isWorkingDay: true,
        reason: 'Use normal hours',
      );
      expect(
        () =>
            WorkCalendarPattern(weeklyIntervals: const [], overrides: [monday]),
        throwsFormatException,
      );
      expect(
        () => WorkCalendarPattern(
          weeklyIntervals: [shift(7, 22 * 60, 6 * 60, nextDay: 1)],
          overrides: [monday],
        ),
        returnsNormally,
      );
    },
  );

  test(
    'calendar editor rejects unbounded weekly payloads before submission',
    () {
      expect(
        () => WorkCalendarPattern(
          weeklyIntervals: List.generate(57, (_) => shift(1, 8 * 60, 9 * 60)),
          overrides: const [],
        ),
        throwsFormatException,
      );
    },
  );
}
