import 'package:jentra_domain/jentra_payroll.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

PayrollRule rule(
  String code, {
  PayrollClassification type = PayrollClassification.earning,
  PayrollBasis basis = PayrollBasis.fixed,
  PayrollProration proration = PayrollProration.none,
  PayrollRounding rounding = PayrollRounding.halfAway,
  String amount = '1000',
  String currency = 'LKR',
  int numerator = 1,
  int denominator = 1,
  String? cap,
  int precision = 2,
}) => PayrollRule(
  id: '10000000-0000-0000-0000-${code.codeUnitAt(0).toString().padLeft(12, '0')}',
  code: code,
  classification: type,
  basis: basis,
  proration: proration,
  rounding: rounding,
  precision: precision,
  start: CivilDate.parse('2026-09-01'),
  endExclusive: CivilDate.parse('2026-10-01'),
  amount: payrollAmount(amount, currency),
  ratioNumerator: numerator,
  ratioDenominator: denominator,
  cap: cap == null ? null : payrollAmount(cap, currency),
);
PayrollCalculationInput input({
  int days = 15,
  int paid = 27000,
  int planned = 54000,
}) => PayrollCalculationInput(
  employeeId: '20000000-0000-0000-0000-000000000001',
  start: CivilDate.parse('2026-09-01'),
  endExclusive: CivilDate.parse('2026-10-01'),
  periodDays: 30,
  eligibleDays: days,
  paidSeconds: paid,
  plannedSeconds: planned,
);
void main() {
  test(
    'earning, deduction and employer cost reproduce from exact frozen ratios',
    () {
      final result = calculatePayroll(input(), [
        rule('BASE', proration: PayrollProration.eligibleDays),
        rule('HOURLY', basis: PayrollBasis.hourly, amount: '12.345678'),
        rule(
          'DEDUCT',
          type: PayrollClassification.deduction,
          basis: PayrollBasis.earningsRatio,
          amount: '0',
          numerator: 1,
          denominator: 10,
        ),
        rule(
          'EMPLOYER',
          type: PayrollClassification.employerCost,
          basis: PayrollBasis.earningsRatio,
          amount: '0',
          numerator: 3,
          denominator: 100,
        ),
      ]);
      expect(result.gross.toDecimalString(), '592.590000');
      expect(result.deductions.toDecimalString(), '59.260000');
      expect(result.employerCost.toDecimalString(), '17.780000');
      expect(result.net.toDecimalString(), '533.330000');
      expect(result.lines.first.rawNumerator, BigInt.from(15000000000));
      expect(result.lines.first.rawDenominator, BigInt.from(30));
    },
  );
  test('ties use the published rounding mode including signed differences', () {
    final tie = BigInt.from(1250000);
    expect(
      payrollRoundRatio(tie, BigInt.one, 1, PayrollRounding.halfAway),
      BigInt.from(1300000),
    );
    expect(
      payrollRoundRatio(tie, BigInt.one, 1, PayrollRounding.halfEven),
      BigInt.from(1200000),
    );
    expect(
      payrollRoundRatio(-tie, BigInt.one, 1, PayrollRounding.halfEven),
      BigInt.from(-1200000),
    );
    expect(
      payrollRoundRatio(
        -BigInt.from(1200001),
        BigInt.one,
        1,
        PayrollRounding.floor,
      ),
      BigInt.from(-1300000),
    );
    expect(
      payrollRoundRatio(
        -BigInt.from(1200001),
        BigInt.one,
        1,
        PayrollRounding.truncate,
      ),
      BigInt.from(-1200000),
    );
  });
  test(
    'paid-time fixed proration caps at a whole salary and preserves separate cap evidence',
    () {
      final result = calculatePayroll(input(paid: 108000), [
        rule('BASE', proration: PayrollProration.paidSeconds, cap: '900'),
      ]);
      expect(result.gross.toDecimalString(), '900.000000');
      expect(
        result.lines.single.roundedAmount.toDecimalString(),
        '1000.000000',
      );
      expect(result.lines.single.capped, isTrue);
    },
  );
  test(
    'zero paid seconds cannot invent hourly pay and missing planned basis fails',
    () {
      expect(
        calculatePayroll(input(paid: 0), [
          rule('HOURLY', basis: PayrollBasis.hourly),
        ]).gross.toDecimalString(),
        '0.000000',
      );
      expect(
        () => calculatePayroll(input(planned: 0), [
          rule('BASE', proration: PayrollProration.paidSeconds),
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'duplicate versions, uncovered period, mixed currency and excess deductions fail',
    () {
      final salary = rule('BASE');
      expect(
        () => calculatePayroll(input(), [
          salary,
          rule('FOREIGN', currency: 'USD'),
        ]),
        throwsFormatException,
      );
      expect(
        () => calculatePayroll(input(), [salary, salary]),
        throwsFormatException,
      );
      final later = PayrollCalculationInput(
        employeeId: '20000000-0000-0000-0000-000000000001',
        start: CivilDate.parse('2026-09-01'),
        endExclusive: CivilDate.parse('2026-11-01'),
        periodDays: 61,
        eligibleDays: 15,
        paidSeconds: 1,
        plannedSeconds: 1,
      );
      expect(() => calculatePayroll(later, [salary]), throwsFormatException);
      expect(
        () => calculatePayroll(input(), [
          salary,
          rule('DEDUCT', type: PayrollClassification.deduction, amount: '1001'),
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'six-place decimal contract rejects floating-point or silently rounded rates',
    () {
      for (final amount in [
        '1e3',
        '0.1234567',
        'NaN',
        '-10',
        '100000000000000',
        '1,000',
      ]) {
        expect(() => payrollAmount(amount, 'LKR'), throwsFormatException);
      }
      expect(() => rule('CAP', cap: '1.001'), throwsFormatException);
      expect(
        () => rule('EARN', basis: PayrollBasis.earningsRatio, amount: '0'),
        throwsFormatException,
      );
      expect(
        () => rule(
          'HOURLY',
          basis: PayrollBasis.hourly,
          proration: PayrollProration.paidSeconds,
        ),
        throwsFormatException,
      );
    },
  );
  test('journal precision bounds apply to line and employee totals', () {
    expect(
      () => calculatePayroll(input(paid: 3601), [
        rule(
          'HOURLY',
          basis: PayrollBasis.hourly,
          amount: '99999999999999.999999',
          precision: 6,
        ),
      ]),
      throwsFormatException,
    );
    expect(
      () => calculatePayroll(input(), [
        rule('BASE', amount: '99999999999999.999999', precision: 6),
        rule('OTHER', amount: '1'),
      ]),
      throwsFormatException,
    );
  });
}
