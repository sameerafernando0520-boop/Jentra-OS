import 'package:jentra_domain/jentra_assets.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

AssetBookBasis book({
  String cost = '1000',
  String opening = '0',
  String residual = '100',
  int life = 3,
  AssetDepreciationMethod method = AssetDepreciationMethod.straightLine,
  AssetMonthConvention convention = AssetMonthConvention.inServiceMonth,
  int numerator = 1,
  int denominator = 5,
}) => AssetBookBasis(
  cost: assetAmount(cost, 'LKR'),
  openingAccumulated: assetAmount(opening, 'LKR'),
  residual: assetAmount(residual, 'LKR'),
  remainingMonths: life,
  method: method,
  convention: convention,
  inService: CivilDate.parse('2026-01-31'),
  precision: 2,
  rateNumerator: numerator,
  rateDenominator: denominator,
);
void main() {
  test('cumulative half-even allocation conserves tiny depreciable values', () {
    final schedule = calculateAssetSchedule(
      book(cost: '0.03', residual: '0', life: 5),
    );
    expect(schedule.periods.map((p) => p.depreciation.toDecimalString()), [
      '0.010000',
      '0.000000',
      '0.010000',
      '0.000000',
      '0.010000',
    ]);
    expect(schedule.totalDepreciation.toDecimalString(), '0.030000');
    expect(schedule.periods.last.closingCarrying.toDecimalString(), '0.000000');
    final tie = calculateAssetSchedule(
      book(cost: '0.01', residual: '0', life: 2),
    );
    expect(tie.periods.first.depreciation.toDecimalString(), '0.000000');
  });
  test(
    'opening accumulated value and residual are independently preserved',
    () {
      final schedule = calculateAssetSchedule(
        book(cost: '1', opening: '0.4', residual: '0.1'),
      );
      expect(schedule.periods.map((p) => p.depreciation.toDecimalString()), [
        '0.170000',
        '0.160000',
        '0.170000',
      ]);
      expect(
        schedule.periods.last.accumulatedClosing.toDecimalString(),
        '0.900000',
      );
      expect(
        schedule.periods.last.closingCarrying.toDecimalString(),
        '0.100000',
      );
    },
  );
  test('reducing balance retains exact rate and final life residue', () {
    final schedule = calculateAssetSchedule(
      book(method: AssetDepreciationMethod.reducingBalance),
    );
    expect(schedule.periods.map((p) => p.depreciation.toDecimalString()), [
      '200.000000',
      '160.000000',
      '540.000000',
    ]);
    expect(
      schedule.periods.last.closingCarrying.toDecimalString(),
      '100.000000',
    );
    expect(schedule.totalDepreciation.toDecimalString(), '900.000000');
  });
  test(
    'explicit month conventions retain civil boundaries including leap years',
    () {
      final next = calculateAssetSchedule(
        book(convention: AssetMonthConvention.nextMonth),
      );
      expect(next.periods.first.start.value, '2026-02-01');
      expect(next.periods.first.endExclusive.value, '2026-03-01');
      expect(next.periods.first.postingDate.value, '2026-02-28');
      final leap = AssetBookBasis(
        cost: assetAmount('1', 'LKR'),
        openingAccumulated: assetAmount('0', 'LKR'),
        residual: assetAmount('0', 'LKR'),
        remainingMonths: 1,
        method: AssetDepreciationMethod.straightLine,
        convention: AssetMonthConvention.inServiceMonth,
        inService: CivilDate.parse('2028-02-29'),
        precision: 2,
      );
      expect(
        calculateAssetSchedule(leap).periods.single.postingDate.value,
        '2028-02-29',
      );
    },
  );
  test(
    'prospective revision preserves posted basis and old schedule facts',
    () {
      final old = calculateAssetSchedule(book(residual: '0', life: 5));
      final revised = old.prospective(
        postedPeriods: 2,
        remainingMonths: 3,
        residual: assetAmount('100', 'LKR'),
      );
      expect(revised.periods.first.start.value, '2026-03-01');
      expect(revised.basis.openingAccumulated.toDecimalString(), '400.000000');
      expect(revised.totalDepreciation.toDecimalString(), '500.000000');
      expect(old.periods.last.closingCarrying.toDecimalString(), '0.000000');
      expect(
        revised.periods.last.closingCarrying.toDecimalString(),
        '100.000000',
      );
      expect(
        () => old.prospective(
          postedPeriods: 5,
          remainingMonths: 3,
          residual: assetAmount('0', 'LKR'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'invalid basis, rates, fractional precision and calendar overflow reject',
    () {
      for (final factory in [
        () => book(opening: '1001'),
        () => book(residual: '1001'),
        () => book(life: 0),
        () => book(life: 1201),
        () => book(cost: '1.001'),
        () =>
            book(method: AssetDepreciationMethod.reducingBalance, numerator: 0),
        () =>
            book(method: AssetDepreciationMethod.reducingBalance, numerator: 6),
      ]) {
        expect(factory, throwsFormatException);
      }
      expect(() => assetAmount('1.0000001', 'LKR'), throwsFormatException);
      expect(() => assetAmount('1e3', 'LKR'), throwsFormatException);
    },
  );
  test(
    'disposal proceeds reconcile cost removed, accumulation and signed gain',
    () {
      final result = calculateAssetDisposal(
        cost: assetAmount('1000', 'LKR'),
        accumulated: assetAmount('400', 'LKR'),
        proceeds: assetAmount('650', 'LKR'),
      );
      expect(result.carrying.toDecimalString(), '600.000000');
      expect(result.gainLoss.toDecimalString(), '50.000000');
      final loss = calculateAssetDisposal(
        cost: result.cost,
        accumulated: result.accumulated,
        proceeds: assetAmount('500', 'LKR'),
      );
      expect(loss.gainLoss.toDecimalString(), '-100.000000');
    },
  );
  test('impairment preserves depreciation history and final residual', () {
    final basis = AssetBookBasis(
      cost: assetAmount('1000', 'LKR'),
      openingAccumulated: assetAmount('200', 'LKR'),
      openingImpairment: assetAmount('300', 'LKR'),
      residual: assetAmount('100', 'LKR'),
      remainingMonths: 2,
      method: AssetDepreciationMethod.straightLine,
      convention: AssetMonthConvention.inServiceMonth,
      inService: CivilDate.parse('2026-01-01'),
      precision: 2,
    );
    final schedule = calculateAssetSchedule(basis);
    expect(schedule.totalDepreciation.toDecimalString(), '400.000000');
    expect(
      schedule.periods.last.accumulatedClosing.toDecimalString(),
      '600.000000',
    );
    expect(
      schedule.periods.last.closingCarrying.toDecimalString(),
      '100.000000',
    );
    final disposal = calculateAssetDisposal(
      cost: basis.cost,
      accumulated: basis.openingAccumulated,
      impairment: basis.openingImpairment,
      proceeds: assetAmount('450', 'LKR'),
    );
    expect(disposal.gainLoss.toDecimalString(), '-50.000000');
    expect(() => schedule.periods.clear(), throwsUnsupportedError);
  });
  test('calendar overflow and exact amount bounds are explicit', () {
    expect(
      () => AssetBookBasis(
        cost: assetAmount('1', 'LKR'),
        openingAccumulated: assetAmount('0', 'LKR'),
        residual: assetAmount('0', 'LKR'),
        remainingMonths: 2,
        method: AssetDepreciationMethod.straightLine,
        convention: AssetMonthConvention.inServiceMonth,
        inService: CivilDate.parse('9999-12-01'),
        precision: 2,
      ),
      throwsFormatException,
    );
    expect(() => assetAmount('100000000000000', 'LKR'), throwsFormatException);
  });
}
