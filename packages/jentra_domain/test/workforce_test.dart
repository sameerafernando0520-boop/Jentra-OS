import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

const id = '10000000-0000-0000-0000-000000000001';
Map<String, Object?> attendance() => {
  'action': 'create',
  'id': id,
  'employee_id': id,
  'calendar_version_id': id,
  'start_local': '2026-09-30T09:00:00',
  'start_offset_seconds': 19800,
  'end_local': '2026-09-30T17:00:00',
  'end_offset_seconds': 19800,
  'breaks': [
    {'start_utc': '2026-09-30T06:30:00Z', 'end_utc': '2026-09-30T07:00:00Z'},
  ],
  'reason': 'Synthetic attendance',
};
void main() {
  test(
    'valid attendance resolves exact selected offsets and contained breaks',
    () {
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.attendance,
          'create',
          attendance(),
        ),
        returnsNormally,
      );
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.attendance,
          'create',
          attendance()
            ..['breaks'] = [
              {
                'start_utc': '2026-09-30T02:30:00Z',
                'end_utc': '2026-09-30T03:00:00Z',
              },
            ],
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'invalid dates and clock overflow cannot normalize to another interval',
    () {
      for (final text in [
        '2026-02-30T09:00:00Z',
        '2026-09-30T24:00:00Z',
        '2026-09-30T09:60:00Z',
        '0000-09-30T09:00:00Z',
      ]) {
        expect(() => parseWorkUtc(text), throwsFormatException);
      }
      expect(
        () => workforceInstant('2026-02-30T09:00:00+00:00'),
        throwsFormatException,
      );
      expect(
        () => workforceRecorded('2026-09-30T24:00:00.123456+00:00'),
        throwsFormatException,
      );
    },
  );
  test('missing fields, unrelated fields and one-sided raw pairing fail', () {
    expect(
      () => WorkforceCommands.validate(
        WorkforceCommandKind.attendance,
        'create',
        attendance()..remove('end_local'),
      ),
      throwsFormatException,
    );
    expect(
      () => WorkforceCommands.validate(
        WorkforceCommandKind.attendance,
        'create',
        attendance()..['pay_rate'] = '100.00',
      ),
      throwsFormatException,
    );
    expect(
      () => WorkforceCommands.validate(
        WorkforceCommandKind.attendance,
        'create',
        attendance()..['raw_start_id'] = id,
      ),
      throwsFormatException,
    );
  });
  test(
    'leave approval requires exact balance version and a private reason',
    () {
      final payload = <String, Object?>{
        'action': 'approve',
        'id': id,
        'employee_id': id,
        'balance_version': 5,
        'reason': 'Synthetic decision',
      };
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.leaveRequest,
          'approve',
          payload,
        ),
        returnsNormally,
      );
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.leaveRequest,
          'approve',
          {...payload, 'balance_version': 5.0},
        ),
        throwsFormatException,
      );
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.leaveRequest,
          'approve',
          {...payload}..remove('reason'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'leave adjustments retain signed exact seconds and bounded source key',
    () {
      final payload = <String, Object?>{
        'action': 'adjust',
        'id': id,
        'employee_id': id,
        'policy_version_id': id,
        'effective_date': '2026-09-30',
        'seconds': -3600,
        'source_key': 'synthetic-adjustment',
        'reason': 'Synthetic correction',
      };
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.leaveGrant,
          'adjust',
          payload,
        ),
        returnsNormally,
      );
      expect(
        () => WorkforceCommands.validate(
          WorkforceCommandKind.leaveGrant,
          'adjust',
          {...payload, 'seconds': 0},
        ),
        throwsFormatException,
      );
    },
  );
}
