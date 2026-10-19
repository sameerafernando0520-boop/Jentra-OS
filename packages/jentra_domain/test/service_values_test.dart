import 'package:test/test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_service.dart';

void main() {
  test('SLA counts half-open working windows and remaining budgets', () {
    final clock = ServiceClock([
      ServiceWindow(
        DateTime.utc(2026, 10, 1, 9),
        DateTime.utc(2026, 10, 1, 12),
      ),
      ServiceWindow(
        DateTime.utc(2026, 10, 1, 13),
        DateTime.utc(2026, 10, 1, 17),
      ),
    ]);
    expect(
      clock.elapsed(
        DateTime.utc(2026, 10, 1, 11),
        DateTime.utc(2026, 10, 1, 14),
      ),
      7200,
    );
    expect(
      clock.due(DateTime.utc(2026, 10, 1, 11), 7200),
      DateTime.utc(2026, 10, 1, 14),
    );
    expect(
      clock.due(DateTime.utc(2026, 10, 1, 12), 3600),
      DateTime.utc(2026, 10, 1, 14),
    );
    expect(
      () => clock.due(DateTime.utc(2026, 10, 1, 17), 1),
      throwsA(
        isA<DomainError>().having(
          (e) => e.code,
          'code',
          'SERVICE_SLA_HORIZON_EXHAUSTED',
        ),
      ),
    );
  });
  test('SLA rejects overlaps and backward evaluation', () {
    expect(
      () => ServiceClock([
        ServiceWindow(DateTime.utc(2026), DateTime.utc(2026, 1, 1, 2)),
        ServiceWindow(DateTime.utc(2026, 1, 1, 1), DateTime.utc(2026, 1, 1, 3)),
      ]),
      throwsFormatException,
    );
    final clock = ServiceClock([
      ServiceWindow(DateTime.utc(2026), DateTime.utc(2026, 1, 1, 1)),
    ]);
    expect(
      () => clock.elapsed(DateTime.utc(2026, 1, 1, 1), DateTime.utc(2026)),
      throwsFormatException,
    );
  });
  test('labor cost retains seconds and exact half-even rounding', () {
    expect(
      serviceLaborCost(Money.parse('18', 'LKR'), 1, 6).toDecimalString(),
      '0.005000',
    );
    expect(
      serviceLaborCost(
        Money.parse('123.455', 'LKR'),
        3600,
        2,
      ).toDecimalString(),
      '123.460000',
    );
    expect(
      serviceLaborCost(
        Money.parse('123.445', 'LKR'),
        3600,
        2,
      ).toDecimalString(),
      '123.440000',
    );
    expect(
      () => serviceLaborCost(Money.parse('99999999999999', 'LKR'), 129600, 6),
      throwsFormatException,
    );
  });
  test('meter reset and rollover conserve cumulative units', () {
    final meter = ServiceMeter(90, 90)
        .next(ServiceMeterKind.rollover, 9, rolloverMaximum: 99)
        .next(ServiceMeterKind.reset, 0);
    expect(meter.logical, 109);
    expect(meter.raw, 0);
    expect(
      () => meter
          .next(ServiceMeterKind.reading, 1)
          .next(ServiceMeterKind.reading, 0),
      throwsFormatException,
    );
    expect(
      () => ServiceMeter(
        9007199254740991,
        9007199254740991,
      ).next(ServiceMeterKind.reset, 1),
      throwsFormatException,
    );
  });
  test('UTC and financial inputs reject fractional and floating evidence', () {
    expect(() => serviceUtc('2026-10-01T01:00:00.001Z'), throwsFormatException);
    expect(() => serviceUtc('2026-10-01T01:00:00'), throwsFormatException);
    expect(() => serviceAmount(2.5, 'LKR'), throwsFormatException);
    expect(() => serviceAmount('01.00', 'LKR'), throwsFormatException);
    expect(() => serviceInt(9007199254740992), throwsFormatException);
  });
  test('ownership validates breaks and billing separately from cost', () {
    final p = <String, Object?>{
      'action': 'labor',
      'id': '10000000-0000-0000-0000-000000000001',
      'reason': 'Synthetic',
      'order_id': '10000000-0000-0000-0000-000000000002',
      'employee_id': '10000000-0000-0000-0000-000000000003',
      'calendar_version_id': '10000000-0000-0000-0000-000000000004',
      'start_utc': '2026-10-01T09:00:00Z',
      'end_utc': '2026-10-01T10:00:00Z',
      'breaks': <Object?>[],
      'claim_id': null,
      'hourly_cost': '10',
      'currency_code': 'LKR',
      'precision': 2,
      'billing_kind': 'billable',
      'hourly_billing': '25',
      'billing_reference': 'Synthetic contract',
    };
    ServiceCommands.validate('labor', p);
    expect(
      () => ServiceCommands.validate('labor', {
        ...p,
        'billing_kind': 'nonbillable',
      }),
      throwsFormatException,
    );
    expect(
      () => ServiceCommands.validate('labor', {
        ...p,
        'breaks': [
          {
            'start_utc': '2026-10-01T09:00:00Z',
            'end_utc': '2026-10-01T10:00:00Z',
          },
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => ServiceCommands.validate('labor', {...p, 'salary': 'private'}),
      throwsFormatException,
    );
    expect(ServiceCommands.kind('approve_labor'), ServiceKind.labor);
  });
}
