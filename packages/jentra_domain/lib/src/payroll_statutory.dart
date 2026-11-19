import 'employee.dart';
import 'money.dart';
import 'payroll_calculation.dart';

enum SriLankaApitCase {
  regularPrimary,
  lumpSumOrArrears,
  terminalBenefit,
  secondaryEmployment,
  employerPaidTax,
  foreignEmployer,
}

/// A researched source snapshot, not a finance-approved production policy.
abstract final class SriLankaPayrollSources {
  static const version = 'LK-2025-04-01-review-2026-11-05';
  static const checkedOn = '2026-11-05';
  static const effectiveFrom = '2025-04-01';
  static const apitTable =
      'https://www.ird.gov.lk/en/publications/APIT_Tax_Tables/2025-2026/'
      'Table%20-%201/02.%20APIT_2526_Table_01_Text.pdf';
  static const apitIndex =
      'https://www.ird.gov.lk/en/publications/APIT_Tax_Tables/2025-2026/'
      'Index/01.%20APIT_2526_Index.pdf';
  static const apitAmendment =
      'https://www.ird.gov.lk/en/publications/Acts_Income%20Tax_2017/'
      'IR_Act_No_11-2026_E.pdf';
  // The circular is listed by IRD, but its PDF was unavailable at this check.
  // Salary arrears remain outside this regular-pay preview.
  static const apitSalaryArrearsCredit =
      'https://www.ird.gov.lk/en/publications/Circulars_Circulars/'
      'SEC_2026_E_05_E.pdf';
  static const epf = 'https://www.cbsl.gov.lk/en/node/147';
  static const etf = 'https://etfb.lk/employer-details/';
}

/// Bases are independently classified amounts, not a shared basic-salary field.
/// Noncash benefits can make APIT profits larger than cash earnings.
final class SriLankaPayrollInput {
  const SriLankaPayrollInput({
    required this.month,
    required this.cashEarnings,
    required this.epfEarnings,
    required this.etfEarnings,
    required this.apitRegularProfits,
    required this.cumulativeRegularProfits,
    required this.otherDeductions,
    this.apitCase = SriLankaApitCase.regularPrimary,
    this.residentOrCitizen = false,
    this.primaryDeclarationOrOnlyEmployment = false,
    this.joinedOrLeftDuringTaxYear = false,
    this.contributionCoverageConfirmed = false,
    this.earningsClassificationConfirmed = false,
  });

  /// First day of the calendar month in which regular pay is payable.
  final CivilDate month;
  final Money cashEarnings,
      epfEarnings,
      etfEarnings,
      apitRegularProfits,
      cumulativeRegularProfits,
      otherDeductions;
  final SriLankaApitCase apitCase;
  final bool residentOrCitizen,
      primaryDeclarationOrOnlyEmployment,
      joinedOrLeftDuringTaxYear,
      contributionCoverageConfirmed,
      earningsClassificationConfirmed;
}

final class SriLankaPayrollPreview {
  SriLankaPayrollPreview._({
    required this.input,
    required this.employeeEpf,
    required this.employerEpf,
    required this.employerEtf,
    required this.apitFormula,
    required this.netCash,
    required Iterable<String> blockers,
  }) : blockers = List.unmodifiable(blockers);

  final SriLankaPayrollInput input;
  final Money? employeeEpf, employerEpf, employerEtf, apitFormula, netCash;
  final List<String> blockers;

  /// Formula rounding and employee/company applicability still need review.
  /// Nothing in this preview authorizes production posting or bank execution.
  static const reviewRequirements = <String>[
    'Qualified payroll review of applicability and earnings classifications',
    'Approved APIT table lookup and EPF/ETF rounding policy',
    'Current statutory sources and employer/employee registrations',
    'Installed server calculation, independent approval and company acceptance',
  ];

  bool get hasEstimate => netCash != null;
  Money? get employerContributions => employerEpf == null || employerEtf == null
      ? null
      : employerEpf! + employerEtf!;
  Money? get epfRemittance => employeeEpf == null || employerEpf == null
      ? null
      : employeeEpf! + employerEpf!;
}

SriLankaPayrollPreview previewSriLankaPayroll(SriLankaPayrollInput input) {
  final amounts = [
    input.cashEarnings,
    input.epfEarnings,
    input.etfEarnings,
    input.apitRegularProfits,
    input.cumulativeRegularProfits,
    input.otherDeductions,
  ];
  final bound = BigInt.parse('99999999999999999999');
  if (amounts.any(
        (a) =>
            a.currencyCode != 'LKR' ||
            a.minorUnits.isNegative ||
            a.minorUnits > bound,
      ) ||
      input.month.utc.day != 1) {
    throw const FormatException(
      'Use a calendar month and nonnegative exact LKR amounts within numeric(20,6).',
    );
  }
  final blockers = <String>[
    if (input.month.value.compareTo(SriLankaPayrollSources.effectiveFrom) < 0 ||
        input.month.value.compareTo(SriLankaPayrollSources.checkedOn) > 0)
      'This month is outside the researched source snapshot. Refresh the statutory review.',
    if (!input.contributionCoverageConfirmed)
      'Confirm that standard EPF and ETF coverage applies; exemptions need separate review.',
    if (!input.earningsClassificationConfirmed)
      'Classify EPF earnings, ETF earnings and APIT profits separately.',
    if (input.apitCase != SriLankaApitCase.regularPrimary)
      'This payment requires another APIT table; Table 01 cannot be used.',
    if (input.apitCase == SriLankaApitCase.lumpSumOrArrears)
      'Salary arrears also require review of Section 96A and IRD circular SEC/2026/E/05; this preview does not calculate the credit.',
    if (!input.residentOrCitizen)
      'Nonresident noncitizens require separate APIT treatment.',
    if (!input.primaryDeclarationOrOnlyEmployment)
      'Confirm the primary declaration or sole employment before using Table 01.',
    if (input.joinedOrLeftDuringTaxYear)
      'Joining or leaving during the assessment year requires APIT Table 05.',
    if (input.cumulativeRegularProfits.compareTo(input.apitRegularProfits) < 0)
      'Cumulative regular profits must include this month.',
    if (input.apitRegularProfits.compareTo(Money.parse('150000', 'LKR')) < 0 &&
        input.cumulativeRegularProfits.compareTo(
              Money.parse('1800000', 'LKR'),
            ) >
            0)
      'Cumulative regular profits require APIT Table 05.',
  ];
  if (blockers.isNotEmpty) {
    return SriLankaPayrollPreview._(
      input: input,
      employeeEpf: null,
      employerEpf: null,
      employerEtf: null,
      apitFormula: null,
      netCash: null,
      blockers: blockers,
    );
  }
  // Draft rounding is explicit: cents, half away from zero. This is an estimate
  // of the official summary formula, not the IRD's published rupee lookup table.
  Money percentage(Money amount, int percent) => Money.fromMinorUnits(
    payrollRoundRatio(
      amount.minorUnits * BigInt.from(percent),
      BigInt.from(100),
      2,
      PayrollRounding.halfAway,
    ),
    'LKR',
  );
  final profits = input.apitRegularProfits;
  final (rate, reduction) = profits.compareTo(Money.parse('150000', 'LKR')) <= 0
      ? (0, '0')
      : profits.compareTo(Money.parse('233333', 'LKR')) <= 0
      ? (6, '9000')
      : profits.compareTo(Money.parse('275000', 'LKR')) <= 0
      ? (18, '37000')
      : profits.compareTo(Money.parse('316667', 'LKR')) <= 0
      ? (24, '53500')
      : profits.compareTo(Money.parse('358333', 'LKR')) <= 0
      ? (30, '72500')
      : (36, '94000');
  final apit = percentage(profits, rate) - Money.parse(reduction, 'LKR');
  final employeeEpf = percentage(input.epfEarnings, 8);
  final net = input.cashEarnings - employeeEpf - apit - input.otherDeductions;
  return SriLankaPayrollPreview._(
    input: input,
    employeeEpf: employeeEpf,
    employerEpf: percentage(input.epfEarnings, 12),
    employerEtf: percentage(input.etfEarnings, 3),
    apitFormula: apit,
    netCash: net.minorUnits.isNegative ? null : net,
    blockers: [
      if (net.minorUnits.isNegative)
        'Employee deductions exceed cash earnings. Review noncash benefits and deductions.',
    ],
  );
}
