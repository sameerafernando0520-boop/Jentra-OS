import 'employee.dart';
import 'money.dart';

enum AssetDepreciationMethod { straightLine, reducingBalance }

enum AssetMonthConvention { inServiceMonth, nextMonth }

final _assetAmountBound = BigInt.parse('99999999999999999999');

Money assetAmount(String value, String currency) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(value) ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const FormatException(
      'Asset amounts require exact nonnegative decimals and one ISO currency.',
    );
  }
  return Money.parse(value, currency);
}

void _assetMoney(Money value, {bool positive = false}) {
  if (value.minorUnits < (positive ? BigInt.one : BigInt.zero) ||
      value.minorUnits > _assetAmountBound) {
    throw const FormatException('Asset amount exceeds the journal contract.');
  }
}

String _date(DateTime date) {
  if (date.year < 1 || date.year > 9999) {
    throw const FormatException(
      'Asset schedule exceeds the supported civil calendar.',
    );
  }
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

BigInt _halfEven(BigInt numerator, BigInt denominator, int precision) {
  final quantum = BigInt.from(10).pow(Money.scale - precision),
      divisor = denominator * quantum;
  var whole = numerator ~/ divisor;
  final remainder = numerator.remainder(divisor);
  if (remainder * BigInt.two > divisor ||
      remainder * BigInt.two == divisor && whole.isOdd) {
    whole += BigInt.one;
  }
  return whole * quantum;
}

final class AssetBookBasis {
  AssetBookBasis({
    required this.cost,
    required this.openingAccumulated,
    required this.residual,
    required this.remainingMonths,
    required this.method,
    required this.convention,
    required this.inService,
    required this.precision,
    Money? openingImpairment,
    this.rateNumerator = 1,
    this.rateDenominator = 1,
    CivilDate? scheduleStart,
  }) : openingImpairment = openingImpairment ?? Money.zero(cost.currencyCode) {
    _assetMoney(cost, positive: true);
    _assetMoney(openingAccumulated);
    _assetMoney(residual);
    _assetMoney(this.openingImpairment);
    if (cost.currencyCode != openingAccumulated.currencyCode ||
        cost.currencyCode != residual.currencyCode ||
        cost.currencyCode != this.openingImpairment.currencyCode ||
        remainingMonths < 1 ||
        remainingMonths > 1200 ||
        precision < 0 ||
        precision > Money.scale ||
        openingAccumulated.minorUnits + this.openingImpairment.minorUnits >
            cost.minorUnits ||
        residual.minorUnits >
            cost.minorUnits -
                openingAccumulated.minorUnits -
                this.openingImpairment.minorUnits ||
        rateNumerator < 1 ||
        rateDenominator < 1 ||
        rateNumerator > rateDenominator ||
        rateNumerator > 9007199254740991 ||
        rateDenominator > 9007199254740991) {
      throw const FormatException(
        'Asset book cost, residual, life, precision or rate is invalid.',
      );
    }
    final quantum = BigInt.from(10).pow(Money.scale - precision);
    if ([
      cost,
      openingAccumulated,
      this.openingImpairment,
      residual,
    ].any((m) => m.minorUnits % quantum != BigInt.zero)) {
      throw const FormatException(
        'Asset book amounts must fit the published currency precision.',
      );
    }
    final naturalStart = DateTime.utc(
      inService.utc.year,
      inService.utc.month +
          (convention == AssetMonthConvention.nextMonth ? 1 : 0),
    );
    final start = scheduleStart?.utc ?? naturalStart;
    if (start.day != 1 || start.isBefore(naturalStart)) {
      throw const FormatException(
        'Prospective asset schedules start at a supported month boundary.',
      );
    }
    firstPeriod = CivilDate.parse(_date(start));
    _date(DateTime.utc(start.year, start.month + remainingMonths));
  }
  final Money cost, openingAccumulated, openingImpairment, residual;
  final int remainingMonths, precision, rateNumerator, rateDenominator;
  final AssetDepreciationMethod method;
  final AssetMonthConvention convention;
  final CivilDate inService;
  late final CivilDate firstPeriod;
  String get currency => cost.currencyCode;
  Money get openingCarrying => cost - openingAccumulated - openingImpairment;
  Money get depreciable => openingCarrying - residual;
}

final class AssetSchedulePeriod {
  const AssetSchedulePeriod({
    required this.index,
    required this.start,
    required this.endExclusive,
    required this.postingDate,
    required this.openingCarrying,
    required this.depreciation,
    required this.closingCarrying,
    required this.accumulatedClosing,
  });
  final int index;
  final CivilDate start, endExclusive, postingDate;
  final Money openingCarrying,
      depreciation,
      closingCarrying,
      accumulatedClosing;
  Map<String, Object?> toJson() => {
    'period_index': index,
    'start_date': start.value,
    'end_date_exclusive': endExclusive.value,
    'posting_date': postingDate.value,
    'opening_carrying': openingCarrying.toDecimalString(),
    'depreciation': depreciation.toDecimalString(),
    'closing_carrying': closingCarrying.toDecimalString(),
    'accumulated_closing': accumulatedClosing.toDecimalString(),
  };
}

final class AssetSchedule {
  const AssetSchedule._(this.basis, this.periods);
  final AssetBookBasis basis;
  final List<AssetSchedulePeriod> periods;
  Money get totalDepreciation => periods.fold(
    Money.zero(basis.currency),
    (sum, p) => sum + p.depreciation,
  );

  /// Uses a verified posting boundary; database locking/version checks remain
  /// authoritative. All old schedule periods and effects remain immutable.
  AssetSchedule prospective({
    required int postedPeriods,
    required int remainingMonths,
    required Money residual,
    AssetDepreciationMethod? method,
    int? rateNumerator,
    int? rateDenominator,
  }) {
    if (postedPeriods < 0 || postedPeriods >= periods.length) {
      throw const FormatException(
        'A prospective revision requires an unposted period.',
      );
    }
    final accumulated = postedPeriods == 0
        ? basis.openingAccumulated
        : periods[postedPeriods - 1].accumulatedClosing;
    return calculateAssetSchedule(
      AssetBookBasis(
        cost: basis.cost,
        openingAccumulated: accumulated,
        openingImpairment: basis.openingImpairment,
        residual: residual,
        remainingMonths: remainingMonths,
        method: method ?? basis.method,
        convention: basis.convention,
        inService: basis.inService,
        precision: basis.precision,
        rateNumerator: rateNumerator ?? basis.rateNumerator,
        rateDenominator: rateDenominator ?? basis.rateDenominator,
        scheduleStart: periods[postedPeriods].start,
      ),
    );
  }
}

AssetSchedule calculateAssetSchedule(AssetBookBasis basis) {
  final rows = <AssetSchedulePeriod>[];
  var carrying = basis.openingCarrying,
      accumulated = basis.openingAccumulated,
      previousTarget = BigInt.zero;
  for (var i = 1; i <= basis.remainingMonths; i++) {
    final start = DateTime.utc(
          basis.firstPeriod.utc.year,
          basis.firstPeriod.utc.month + i - 1,
        ),
        end = DateTime.utc(start.year, start.month + 1);
    BigInt units;
    if (i == basis.remainingMonths) {
      units = carrying.minorUnits - basis.residual.minorUnits;
    } else if (basis.method == AssetDepreciationMethod.straightLine) {
      final cumulative = _halfEven(
        basis.depreciable.minorUnits * BigInt.from(i),
        BigInt.from(basis.remainingMonths),
        basis.precision,
      );
      units = cumulative - previousTarget;
      previousTarget = cumulative;
    } else {
      units = _halfEven(
        carrying.minorUnits * BigInt.from(basis.rateNumerator),
        BigInt.from(basis.rateDenominator),
        basis.precision,
      );
      final remaining = carrying.minorUnits - basis.residual.minorUnits;
      if (units > remaining) units = remaining;
    }
    if (units < BigInt.zero ||
        units > carrying.minorUnits - basis.residual.minorUnits) {
      throw const FormatException(
        'Asset schedule does not conserve depreciable value.',
      );
    }
    final expense = Money.fromMinorUnits(units, basis.currency),
        opening = carrying;
    carrying -= expense;
    accumulated += expense;
    rows.add(
      AssetSchedulePeriod(
        index: i,
        start: CivilDate.parse(_date(start)),
        endExclusive: CivilDate.parse(_date(end)),
        postingDate: CivilDate.parse(
          _date(end.subtract(const Duration(days: 1))),
        ),
        openingCarrying: opening,
        depreciation: expense,
        closingCarrying: carrying,
        accumulatedClosing: accumulated,
      ),
    );
  }
  if (carrying != basis.residual) {
    throw const FormatException('Asset final residual changed.');
  }
  return AssetSchedule._(basis, List.unmodifiable(rows));
}

final class AssetDisposalCalculation {
  const AssetDisposalCalculation._(
    this.cost,
    this.accumulated,
    this.impairment,
    this.proceeds,
  );
  final Money cost, accumulated, impairment, proceeds;
  Money get carrying => cost - accumulated - impairment;
  Money get gainLoss => proceeds - carrying;
}

AssetDisposalCalculation calculateAssetDisposal({
  required Money cost,
  required Money accumulated,
  required Money proceeds,
  Money? impairment,
}) {
  impairment ??= Money.zero(cost.currencyCode);
  _assetMoney(cost, positive: true);
  _assetMoney(accumulated);
  _assetMoney(proceeds);
  _assetMoney(impairment);
  if (cost.currencyCode != accumulated.currencyCode ||
      cost.currencyCode != proceeds.currencyCode ||
      cost.currencyCode != impairment.currencyCode ||
      accumulated.minorUnits + impairment.minorUnits > cost.minorUnits) {
    throw const FormatException('Asset disposal basis or currency changed.');
  }
  return AssetDisposalCalculation._(cost, accumulated, impairment, proceeds);
}
