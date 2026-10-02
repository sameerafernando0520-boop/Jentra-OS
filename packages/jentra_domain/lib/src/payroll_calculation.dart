import 'employee.dart';
import 'money.dart';
import 'work_time.dart';

enum PayrollClassification { earning, deduction, employerCost }

enum PayrollBasis { fixed, hourly, earningsRatio }

enum PayrollProration { none, eligibleDays, paidSeconds }

enum PayrollRounding { halfAway, halfEven, truncate, floor }

final _payrollAmountBound = BigInt.parse('99999999999999999999');
Money payrollAmount(String text, String currency) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(text)) {
    throw const FormatException(
      'Payroll amounts require nonnegative exact decimal strings with at most six places.',
    );
  }
  return Money.parse(text, currency);
}

BigInt payrollRoundRatio(
  BigInt numerator,
  BigInt denominator,
  int precision,
  PayrollRounding mode,
) {
  if (denominator <= BigInt.zero || precision < 0 || precision > Money.scale) {
    throw const FormatException('Payroll rounding basis is invalid.');
  }
  final quantum = BigInt.from(10).pow(Money.scale - precision),
      divisor = denominator * quantum;
  var quotient = numerator ~/ divisor;
  final remainder = numerator.remainder(divisor).abs();
  if (remainder != BigInt.zero) {
    switch (mode) {
      case PayrollRounding.halfAway:
        if (remainder * BigInt.two >= divisor) {
          quotient += BigInt.from(numerator.sign);
        }
      case PayrollRounding.halfEven:
        if (remainder * BigInt.two > divisor ||
            remainder * BigInt.two == divisor && quotient.abs().isOdd) {
          quotient += BigInt.from(numerator.sign);
        }
      case PayrollRounding.floor:
        if (numerator.isNegative) {
          quotient -= BigInt.one;
        }
      case PayrollRounding.truncate:
        break;
    }
  }
  return quotient * quantum;
}

/// Immutable synthetic rule. The server freezes its published identity and dates.
final class PayrollRule {
  PayrollRule({
    required this.id,
    required this.code,
    required this.classification,
    required this.basis,
    required this.proration,
    required this.rounding,
    required this.precision,
    required this.start,
    required this.endExclusive,
    required this.amount,
    required this.ratioNumerator,
    required this.ratioDenominator,
    this.cap,
  }) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(id) ||
        !RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code) ||
        endExclusive.compareTo(start) <= 0 ||
        precision < 0 ||
        precision > Money.scale ||
        amount.minorUnits < BigInt.zero ||
        amount.minorUnits > _payrollAmountBound ||
        ratioNumerator < 0 ||
        ratioNumerator > maxExactWorkInteger ||
        ratioDenominator <= 0 ||
        ratioDenominator > maxExactWorkInteger ||
        basis == PayrollBasis.earningsRatio &&
            classification == PayrollClassification.earning ||
        basis != PayrollBasis.fixed && proration != PayrollProration.none ||
        basis != PayrollBasis.earningsRatio &&
            (ratioNumerator != 1 || ratioDenominator != 1) ||
        basis == PayrollBasis.earningsRatio &&
            amount.minorUnits != BigInt.zero ||
        cap != null &&
            (cap!.currencyCode != amount.currencyCode ||
                cap!.minorUnits < BigInt.zero ||
                cap!.minorUnits > _payrollAmountBound ||
                cap!.minorUnits %
                        BigInt.from(10).pow(Money.scale - precision) !=
                    BigInt.zero)) {
      throw const FormatException('Synthetic payroll rule is invalid.');
    }
  }
  final String id, code;
  final PayrollClassification classification;
  final PayrollBasis basis;
  final PayrollProration proration;
  final PayrollRounding rounding;
  final int precision, ratioNumerator, ratioDenominator;
  final CivilDate start, endExclusive;
  final Money amount;
  final Money? cap;
  bool covers(CivilDate from, CivilDate until) =>
      start.compareTo(from) <= 0 && endExclusive.compareTo(until) >= 0;
}

/// Approved source projection. Exact source IDs/digests are sealed by the database.
final class PayrollCalculationInput {
  PayrollCalculationInput({
    required this.employeeId,
    required this.start,
    required this.endExclusive,
    required this.periodDays,
    required this.eligibleDays,
    required this.paidSeconds,
    required this.plannedSeconds,
  }) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(employeeId) ||
        endExclusive.compareTo(start) <= 0 ||
        periodDays < 1 ||
        periodDays > 366 ||
        endExclusive.utc.difference(start.utc).inDays != periodDays ||
        eligibleDays < 1 ||
        eligibleDays > periodDays ||
        paidSeconds < 0 ||
        paidSeconds > maxExactWorkInteger ||
        plannedSeconds < 0 ||
        plannedSeconds > maxExactWorkInteger) {
      throw const FormatException('Payroll approved input is invalid.');
    }
  }
  final String employeeId;
  final CivilDate start, endExclusive;
  final int periodDays, eligibleDays, paidSeconds, plannedSeconds;
}

final class PayrollCalculationLine {
  const PayrollCalculationLine({
    required this.rule,
    required this.rawNumerator,
    required this.rawDenominator,
    required this.roundedAmount,
    required this.amount,
    required this.capped,
  });
  final PayrollRule rule;
  final BigInt rawNumerator, rawDenominator;
  final Money roundedAmount, amount;
  final bool capped;
  Map<String, Object?> toJson() => {
    'rule_version_id': rule.id,
    'code': rule.code,
    'classification': rule.classification == PayrollClassification.employerCost
        ? 'employer_cost'
        : rule.classification.name,
    'basis': rule.basis == PayrollBasis.earningsRatio
        ? 'earnings_ratio'
        : rule.basis.name,
    'proration': switch (rule.proration) {
      PayrollProration.eligibleDays => 'eligible_days',
      PayrollProration.paidSeconds => 'paid_seconds',
      PayrollProration.none => 'none',
    },
    'raw_numerator_units': rawNumerator.toString(),
    'raw_denominator': rawDenominator.toString(),
    'rounding': switch (rule.rounding) {
      PayrollRounding.halfAway => 'half_away',
      PayrollRounding.halfEven => 'half_even',
      PayrollRounding.truncate => 'truncate',
      PayrollRounding.floor => 'floor',
    },
    'precision': rule.precision,
    'rounded_amount': roundedAmount.toDecimalString(),
    'cap': rule.cap?.toDecimalString(),
    'capped': capped,
    'amount': amount.toDecimalString(),
  };
}

final class PayrollCalculation {
  const PayrollCalculation({
    required this.input,
    required this.lines,
    required this.gross,
    required this.deductions,
    required this.employerCost,
    required this.net,
  });
  final PayrollCalculationInput input;
  final List<PayrollCalculationLine> lines;
  final Money gross, deductions, employerCost, net;
}

PayrollCalculation calculatePayroll(
  PayrollCalculationInput input,
  Iterable<PayrollRule> source,
) {
  final rules = List<PayrollRule>.of(source)
    ..sort((a, b) => a.code.compareTo(b.code));
  if (rules.isEmpty ||
      rules.length > 100 ||
      rules.map((r) => r.code).toSet().length != rules.length ||
      rules.map((r) => r.id).toSet().length != rules.length ||
      rules.any(
        (r) =>
            !r.covers(input.start, input.endExclusive) ||
            r.amount.currencyCode != rules.first.amount.currencyCode,
      )) {
    throw const FormatException(
      'Payroll requires one covering version per component and one currency.',
    );
  }
  final currency = rules.first.amount.currencyCode,
      lines = <PayrollCalculationLine>[];
  var gross = Money.zero(currency),
      deductions = Money.zero(currency),
      employerCost = Money.zero(currency);
  PayrollCalculationLine line(PayrollRule rule) {
    BigInt numerator, denominator;
    switch (rule.basis) {
      case PayrollBasis.fixed:
        numerator = rule.amount.minorUnits;
        denominator = BigInt.one;
        switch (rule.proration) {
          case PayrollProration.eligibleDays:
            numerator *= BigInt.from(input.eligibleDays);
            denominator = BigInt.from(input.periodDays);
          case PayrollProration.paidSeconds:
            if (input.plannedSeconds == 0) {
              throw const FormatException(
                'Fixed paid-time proration requires planned seconds.',
              );
            }
            final eligible = input.paidSeconds > input.plannedSeconds
                ? input.plannedSeconds
                : input.paidSeconds;
            numerator *= BigInt.from(eligible);
            denominator = BigInt.from(input.plannedSeconds);
          case PayrollProration.none:
            break;
        }
      case PayrollBasis.hourly:
        numerator = rule.amount.minorUnits * BigInt.from(input.paidSeconds);
        denominator = BigInt.from(3600);
      case PayrollBasis.earningsRatio:
        numerator = gross.minorUnits * BigInt.from(rule.ratioNumerator);
        denominator = BigInt.from(rule.ratioDenominator);
    }
    final roundedUnits = payrollRoundRatio(
      numerator,
      denominator,
      rule.precision,
      rule.rounding,
    );
    final rounded = Money.fromMinorUnits(roundedUnits, currency),
        capped = rule.cap != null && rounded.compareTo(rule.cap!) > 0,
        amount = capped ? rule.cap! : rounded;
    if (amount.minorUnits > _payrollAmountBound) {
      throw const FormatException(
        'Payroll calculated amount exceeds journal precision.',
      );
    }
    return PayrollCalculationLine(
      rule: rule,
      rawNumerator: numerator,
      rawDenominator: denominator,
      roundedAmount: rounded,
      amount: amount,
      capped: capped,
    );
  }

  // Earnings first; dependent percentages never feed earnings or each other.
  for (final rule in rules.where(
    (r) => r.classification == PayrollClassification.earning,
  )) {
    final value = line(rule);
    lines.add(value);
    gross += value.amount;
  }
  for (final rule in rules.where(
    (r) => r.classification != PayrollClassification.earning,
  )) {
    final value = line(rule);
    lines.add(value);
    if (rule.classification == PayrollClassification.deduction) {
      deductions += value.amount;
    } else {
      employerCost += value.amount;
    }
  }
  if (deductions.compareTo(gross) > 0 ||
      [
        gross,
        deductions,
        employerCost,
      ].any((m) => m.minorUnits > _payrollAmountBound)) {
    throw const FormatException(
      'Payroll totals exceed earned pay or journal precision.',
    );
  }
  return PayrollCalculation(
    input: input,
    lines: List.unmodifiable(lines),
    gross: gross,
    deductions: deductions,
    employerCost: employerCost,
    net: gross - deductions,
  );
}
