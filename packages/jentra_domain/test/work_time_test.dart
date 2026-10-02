import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

WorkSpan span(String start, String end) =>
    WorkSpan(parseWorkUtc(start), parseWorkUtc(end));

void main() {
  test('AC-405 exact UTC duration excludes breaks once', () {
    final work = PayableWork(
      span('2026-09-28T03:30:00Z', '2026-09-28T06:30:00Z'),
      [span('2026-09-28T04:30:00Z', '2026-09-28T04:45:00Z')],
    );
    expect(work.span.seconds, 10800);
    expect(work.breakSeconds, 900);
    expect(work.payableSeconds, 9900);
    expect(work.segments.map((item) => item.seconds), [3600, 6300]);
  });

  test('AC-405 a fold interval uses elapsed UTC time', () {
    final work = PayableWork(
      span('2026-11-01T05:30:00Z', '2026-11-01T06:30:00Z'),
      [],
    );
    expect(work.payableSeconds, 3600);
  });

  test('AC-405 malformed, fractional, reversed and long intervals fail', () {
    expect(
      () => parseWorkUtc('2026-09-28T03:30:00+00:00'),
      throwsFormatException,
    );
    expect(
      () => parseWorkUtc('2026-09-28T03:30:00.001Z'),
      throwsFormatException,
    );
    expect(
      () => span('2026-09-28T06:30:00Z', '2026-09-28T03:30:00Z'),
      throwsFormatException,
    );
    expect(
      () => span('2026-09-28T00:00:00Z', '2026-09-30T00:00:00Z'),
      throwsFormatException,
    );
  });

  test('AC-405 breaks must be contained, ordered, disjoint and partial', () {
    final work = span('2026-09-28T03:30:00Z', '2026-09-28T06:30:00Z');
    final before = span('2026-09-28T03:00:00Z', '2026-09-28T03:45:00Z');
    final first = span('2026-09-28T04:30:00Z', '2026-09-28T04:45:00Z');
    final overlap = span('2026-09-28T04:40:00Z', '2026-09-28T05:00:00Z');
    expect(() => PayableWork(work, [before]), throwsFormatException);
    expect(() => PayableWork(work, [first, overlap]), throwsFormatException);
    expect(() => PayableWork(work, [overlap, first]), throwsFormatException);
    expect(() => PayableWork(work, [work]), throwsFormatException);
  });

  test('AC-411 half-open segments can touch but cannot overlap', () {
    final first = span('2026-09-28T03:30:00Z', '2026-09-28T04:30:00Z');
    final next = span('2026-09-28T04:30:00Z', '2026-09-28T05:00:00Z');
    final overlap = span('2026-09-28T04:29:59Z', '2026-09-28T05:00:00Z');
    expect(() => assertExclusiveWork([first], [next]), returnsNormally);
    expect(
      () => assertExclusiveWork([first], [overlap]),
      throwsFormatException,
    );
    expect(
      () => assertExclusiveWork([], [first, overlap]),
      throwsFormatException,
    );
  });

  test('AC-406 deterministic leave allocation uses earliest expiry first', () {
    final ledger = LeaveLedger(
      [
        LeaveGrant('later', 7200, '2026-09-01', '2026-11-01'),
        LeaveGrant('earlier', 3600, '2026-09-01', '2026-10-02'),
      ],
      [LeaveEffect('debit-1', 'earlier', -1800, 'leave-1')],
    );
    expect(ledger.availableSeconds('2026-09-28'), 9000);
    final debit = ledger.allocate('2026-09-28', 4000);
    expect(debit.map((item) => '${item.grantId}:${item.seconds}'), [
      'earlier:1800',
      'later:2200',
    ]);
    expect(() => ledger.allocate('2026-09-28', 9001), throwsFormatException);
    expect(ledger.availableSeconds('2026-10-03'), 7200);
  });

  test('AC-406 cancellation restores only the original grant and once', () {
    final grant = LeaveGrant('grant', 3600, '2026-09-01', '2026-10-01');
    final debit = LeaveEffect('debit', 'grant', -1800, 'request');
    final reverse = LeaveEffect(
      'reverse',
      'grant',
      1800,
      'cancel',
      reversalOf: 'debit',
    );
    expect(
      LeaveLedger([grant], [debit, reverse]).availableSeconds('2026-09-28'),
      3600,
    );
    expect(
      () => LeaveLedger(
        [grant],
        [
          debit,
          reverse,
          LeaveEffect('again', 'grant', 1800, 'cancel-2', reversalOf: 'debit'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => LeaveLedger(
        [grant],
        [
          debit,
          LeaveEffect('wrong', 'grant', 900, 'cancel', reversalOf: 'debit'),
        ],
      ),
      throwsFormatException,
    );
    expect(
      LeaveLedger([grant], [debit, reverse]).availableSeconds('2026-10-01'),
      0,
    );
  });

  test('AC-406 overdraw and unknown grants are rejected', () {
    final grant = LeaveGrant('grant', 3600, '2026-09-01', '2026-10-01');
    expect(
      () => LeaveLedger(
        [grant],
        [LeaveEffect('overdraw', 'grant', -3601, 'request')],
      ),
      throwsFormatException,
    );
    expect(
      () => LeaveLedger(
        [grant],
        [LeaveEffect('unknown', 'other', -1, 'request')],
      ),
      throwsFormatException,
    );
  });
}
