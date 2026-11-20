import 'money.dart';
import 'payroll_calculation.dart';

/// Client mirror of the statutory step in the server candidate
/// `people_payroll.calculate` (supabase/candidates/20261120090000_lk_statutory_payroll.sql).
/// The server result is authoritative; this mirror explains and previews it.
/// Blockers are checked in the same order as the server.
abstract final class LkStatutoryBlocker {
  static const approvedRuleSetRequired = 'STATUTORY_APPROVED_RULE_SET_REQUIRED';
  static const employeeDetailsRequired = 'STATUTORY_EMPLOYEE_DETAILS_REQUIRED';
  static const nicRequired = 'STATUTORY_NIC_REQUIRED';
  static const coverageReviewRequired = 'STATUTORY_COVERAGE_REVIEW_REQUIRED';
  static const epfMemberNumberRequired = 'STATUTORY_EPF_MEMBER_NUMBER_REQUIRED';
  static const apitOtherTableRequired = 'STATUTORY_APIT_OTHER_TABLE_REQUIRED';
  static const apitNonresidentReviewRequired =
      'STATUTORY_APIT_NONRESIDENT_REVIEW_REQUIRED';
  static const apitPrimaryDeclarationRequired =
      'STATUTORY_APIT_PRIMARY_DECLARATION_REQUIRED';
  static const apitTable05Required = 'STATUTORY_APIT_TABLE_05_REQUIRED';
  static const apitMonthlyPeriodRequired =
      'STATUTORY_APIT_MONTHLY_PERIOD_REQUIRED';
  static const earningsRequired = 'STATUTORY_EARNINGS_REQUIRED';
  static const earningsUnclassified = 'STATUTORY_EARNINGS_UNCLASSIFIED';
}

/// The statutory component codes, with their payroll classification.
const lkStatutoryCodes = <String, String>{
  'EPF_EE': 'deduction',
  'APIT': 'deduction',
  'EPF_ER': 'employer_cost',
  'ETF_ER': 'employer_cost',
};

final class LkStatutoryBlocked implements Exception {
  const LkStatutoryBlocked(this.reason);
  final String reason;

  @override
  String toString() => 'LkStatutoryBlocked($reason)';
}

final class LkApitBand {
  const LkApitBand({
    required this.upto,
    required this.rate,
    required this.reduction,
  });

  factory LkApitBand.fromJson(Map<String, Object?> json) => LkApitBand(
    upto: json['upto'] == null
        ? null
        : payrollAmount(json['upto']! as String, 'LKR'),
    rate: json['rate']! as String,
    reduction: payrollAmount(json['reduction']! as String, 'LKR'),
  );

  /// Inclusive monthly upper bound; null for the top band.
  final Money? upto;

  /// Percent as an exact decimal string, e.g. "6".
  final String rate;
  final Money reduction;
}

final class LkStatutoryRuleSet {
  LkStatutoryRuleSet({
    required this.effectiveFrom,
    required this.effectiveToExclusive,
    required this.epfEmployeePercent,
    required this.epfEmployerPercent,
    required this.etfEmployerPercent,
    required List<LkApitBand> apitBands,
  }) : apitBands = List.unmodifiable(apitBands);

  factory LkStatutoryRuleSet.fromJson(Map<String, Object?> json) =>
      LkStatutoryRuleSet(
        effectiveFrom: json['effective_from']! as String,
        effectiveToExclusive: json['effective_to_exclusive']! as String,
        epfEmployeePercent: json['epf_employee_percent']! as String,
        epfEmployerPercent: json['epf_employer_percent']! as String,
        etfEmployerPercent: json['etf_employer_percent']! as String,
        apitBands: [
          for (final band in json['apit_bands']! as List<Object?>)
            LkApitBand.fromJson(band! as Map<String, Object?>),
        ],
      );

  /// ISO dates; the set covers [effectiveFrom, effectiveToExclusive).
  final String effectiveFrom, effectiveToExclusive;
  final String epfEmployeePercent, epfEmployerPercent, etfEmployerPercent;
  final List<LkApitBand> apitBands;
}

/// Frozen employee facts. Identifiers themselves never reach payroll inputs.
final class LkStatutoryEmployee {
  const LkStatutoryEmployee({
    required this.coverage,
    required this.apitCase,
    required this.residentOrCitizen,
    required this.primaryEmploymentDeclared,
    required this.joinedOrLeftInYear,
    required this.hasNic,
    required this.hasEpfMemberNumber,
  });

  factory LkStatutoryEmployee.fromJson(Map<String, Object?> json) =>
      LkStatutoryEmployee(
        coverage: json['coverage']! as String,
        apitCase: json['apit_case']! as String,
        residentOrCitizen: json['resident_or_citizen']! as bool,
        primaryEmploymentDeclared: json['primary_employment_declared']! as bool,
        joinedOrLeftInYear: json['joined_or_left_in_year']! as bool,
        hasNic: json['has_nic']! as bool,
        hasEpfMemberNumber: json['has_epf_member_number']! as bool,
      );

  final String coverage, apitCase;
  final bool residentOrCitizen,
      primaryEmploymentDeclared,
      joinedOrLeftInYear,
      hasNic,
      hasEpfMemberNumber;
}

final class LkStatutoryEarning {
  const LkStatutoryEarning({
    required this.code,
    required this.amount,
    this.epfLiable,
    this.etfLiable,
    this.apitRegularProfit,
  });

  final String code;
  final Money amount;

  /// Null when the component has no statutory classification.
  final bool? epfLiable, etfLiable, apitRegularProfit;

  bool get classified =>
      epfLiable != null && etfLiable != null && apitRegularProfit != null;
}

final class LkStatutoryResult {
  LkStatutoryResult._({
    required Map<String, Money> lines,
    required this.epfBase,
    required this.etfBase,
    required this.apitBase,
    required this.gross,
    required this.deductions,
    required this.employerCost,
  }) : lines = Map.unmodifiable(lines);

  /// Statutory line amounts by code.
  final Map<String, Money> lines;
  final Money epfBase, etfBase, apitBase, gross, deductions, employerCost;
  Money get net => gross - deductions;
}

LkStatutoryResult calculateLkStatutory({
  required LkStatutoryRuleSet? ruleSet,
  required LkStatutoryEmployee? employee,
  required List<LkStatutoryEarning> earnings,
  required Set<String> statutoryCodes,
  required String periodStart,
  required String periodEndExclusive,
  required Money cumulativeRegularProfitsBefore,
  Money? otherDeductions,
  Money? otherEmployerCost,
  int precision = 2,
  PayrollRounding rounding = PayrollRounding.halfAway,
}) {
  if (statutoryCodes.isEmpty ||
      statutoryCodes.any((c) => !lkStatutoryCodes.containsKey(c))) {
    throw const FormatException(
      'Use one or more of EPF_EE, EPF_ER, ETF_ER and APIT.',
    );
  }
  Never block(String reason) => throw LkStatutoryBlocked(reason);
  final hasEpf = statutoryCodes.any((c) => c != 'APIT');
  final hasApit = statutoryCodes.contains('APIT');
  if (ruleSet == null ||
      ruleSet.effectiveFrom.compareTo(periodStart) > 0 ||
      ruleSet.effectiveToExclusive.compareTo(periodEndExclusive) < 0) {
    block(LkStatutoryBlocker.approvedRuleSetRequired);
  }
  if (employee == null) block(LkStatutoryBlocker.employeeDetailsRequired);
  if (!employee.hasNic) block(LkStatutoryBlocker.nicRequired);
  if (hasEpf) {
    if (employee.coverage != 'standard') {
      block(LkStatutoryBlocker.coverageReviewRequired);
    }
    if (!employee.hasEpfMemberNumber) {
      block(LkStatutoryBlocker.epfMemberNumberRequired);
    }
  }
  if (hasApit) {
    if (employee.apitCase != 'regular_primary') {
      block(LkStatutoryBlocker.apitOtherTableRequired);
    }
    if (!employee.residentOrCitizen) {
      block(LkStatutoryBlocker.apitNonresidentReviewRequired);
    }
    if (!employee.primaryEmploymentDeclared) {
      block(LkStatutoryBlocker.apitPrimaryDeclarationRequired);
    }
    if (employee.joinedOrLeftInYear) {
      block(LkStatutoryBlocker.apitTable05Required);
    }
    final start = DateTime.parse('${periodStart}T00:00:00Z');
    final nextMonth = DateTime.utc(start.year, start.month + 1, 1);
    if (start.day != 1 ||
        DateTime.parse('${periodEndExclusive}T00:00:00Z') != nextMonth) {
      block(LkStatutoryBlocker.apitMonthlyPeriodRequired);
    }
  }
  if (earnings.isEmpty) block(LkStatutoryBlocker.earningsRequired);
  var epfBase = Money.zero('LKR'),
      etfBase = Money.zero('LKR'),
      apitBase = Money.zero('LKR');
  var gross = Money.zero('LKR');
  for (final earning in earnings) {
    if (!earning.classified) block(LkStatutoryBlocker.earningsUnclassified);
    gross += earning.amount;
    if (earning.epfLiable!) epfBase += earning.amount;
    if (earning.etfLiable!) etfBase += earning.amount;
    if (earning.apitRegularProfit!) apitBase += earning.amount;
  }
  var rate = '0', reduction = Money.zero('LKR');
  if (hasApit) {
    final band = ruleSet.apitBands.firstWhere(
      (b) => b.upto == null || apitBase.compareTo(b.upto!) <= 0,
    );
    rate = band.rate;
    reduction = band.reduction;
    final firstBand = ruleSet.apitBands.first.upto;
    final cumulative = cumulativeRegularProfitsBefore + apitBase;
    // Low monthly profits with high year-to-date profits need the Table 05 method.
    if (firstBand != null &&
        apitBase.compareTo(firstBand) < 0 &&
        cumulative.minorUnits > firstBand.minorUnits * BigInt.from(12)) {
      block(LkStatutoryBlocker.apitTable05Required);
    }
  }
  final micro = BigInt.from(1000000);
  Money line(Money base, String percent, Money less) {
    final percentUnits = Money.parse(percent, 'LKR').minorUnits;
    var numerator =
        base.minorUnits * percentUnits -
        less.minorUnits * BigInt.from(100) * micro;
    if (numerator.isNegative) numerator = BigInt.zero;
    return Money.fromMinorUnits(
      payrollRoundRatio(
        numerator,
        BigInt.from(100) * micro,
        precision,
        rounding,
      ),
      'LKR',
    );
  }

  final lines = <String, Money>{
    for (final code in statutoryCodes.toList()..sort())
      code: switch (code) {
        'EPF_EE' => line(
          epfBase,
          ruleSet.epfEmployeePercent,
          Money.zero('LKR'),
        ),
        'EPF_ER' => line(
          epfBase,
          ruleSet.epfEmployerPercent,
          Money.zero('LKR'),
        ),
        'ETF_ER' => line(
          etfBase,
          ruleSet.etfEmployerPercent,
          Money.zero('LKR'),
        ),
        _ => line(apitBase, rate, reduction),
      },
  };
  var deductions = otherDeductions ?? Money.zero('LKR');
  var employerCost = otherEmployerCost ?? Money.zero('LKR');
  for (final MapEntry(:key, :value) in lines.entries) {
    if (lkStatutoryCodes[key] == 'deduction') {
      deductions += value;
    } else {
      employerCost += value;
    }
  }
  if (deductions.compareTo(gross) > 0) {
    throw const FormatException(
      'Deductions exceed earnings (PAYROLL_NEGATIVE_NET).',
    );
  }
  return LkStatutoryResult._(
    lines: lines,
    epfBase: epfBase,
    etfBase: etfBase,
    apitBase: apitBase,
    gross: gross,
    deductions: deductions,
    employerCost: employerCost,
  );
}
