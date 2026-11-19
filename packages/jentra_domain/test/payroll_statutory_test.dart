import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll_readiness.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

Money lkr(String amount) => Money.parse(amount, 'LKR');

SriLankaPayrollInput input({
  String month = '2026-10-01',
  String cash = '300000',
  String epf = '250000',
  String etf = '260000',
  String profits = '300000',
  String cumulative = '2100000',
  String deductions = '1000',
  SriLankaApitCase apitCase = SriLankaApitCase.regularPrimary,
  bool resident = true,
  bool primary = true,
  bool joined = false,
  bool coverage = true,
  bool classified = true,
}) => SriLankaPayrollInput(
  month: CivilDate.parse(month),
  cashEarnings: lkr(cash),
  epfEarnings: lkr(epf),
  etfEarnings: lkr(etf),
  apitRegularProfits: lkr(profits),
  cumulativeRegularProfits: lkr(cumulative),
  otherDeductions: lkr(deductions),
  apitCase: apitCase,
  residentOrCitizen: resident,
  primaryDeclarationOrOnlyEmployment: primary,
  joinedOrLeftDuringTaxYear: joined,
  contributionCoverageConfirmed: coverage,
  earningsClassificationConfirmed: classified,
);

void main() {
  test('keeps contribution bases, APIT profits and cash net independent', () {
    final result = previewSriLankaPayroll(input());
    expect(result.blockers, isEmpty);
    expect(result.employeeEpf, lkr('20000'));
    expect(result.employerEpf, lkr('30000'));
    expect(result.employerEtf, lkr('7800'));
    expect(result.apitFormula, lkr('18500'));
    expect(result.netCash, lkr('260500'));
    expect(result.epfRemittance, lkr('50000'));
    expect(result.employerContributions, lkr('37800'));
    expect(SriLankaPayrollPreview.reviewRequirements, isNotEmpty);
  });

  for (final (profits, tax) in [
    ('0', '0'),
    ('150000', '0'),
    ('150000.01', '0'),
    ('200000', '3000'),
    ('233333', '4999.98'),
    ('233334', '5000.12'),
    ('275000', '12500'),
    ('275001', '12500.24'),
    ('316667', '22500.08'),
    ('316668', '22500.40'),
    ('358333', '34999.90'),
    ('358334', '35000.24'),
    ('400000', '50000'),
    ('1000000', '266000'),
  ]) {
    test('official summary formula at LKR $profits estimates $tax', () {
      expect(
        previewSriLankaPayroll(
          input(profits: profits, cumulative: profits),
        ).apitFormula,
        lkr(tax),
      );
    });
  }

  test('noncash benefits affect tax without increasing cash or EPF base', () {
    final result = previewSriLankaPayroll(input(profits: '400000'));
    expect(result.apitFormula, lkr('50000'));
    expect(result.netCash, lkr('229000'));
  });

  test('ETF and employer EPF never reduce employee net pay', () {
    final result = previewSriLankaPayroll(input(epf: '0', etf: '900000'));
    expect(result.netCash, lkr('280500'));
    expect(result.employerEtf, lkr('27000'));
  });

  test('preview contributions use explicit cents and exact tie rounding', () {
    final result = previewSriLankaPayroll(input(epf: '1.0625', etf: '1.5'));
    expect(result.employeeEpf, lkr('0.09'));
    expect(result.employerEpf, lkr('0.13'));
    expect(result.employerEtf, lkr('0.05'));
  });

  for (final (label, value) in [
    ('before snapshot', input(month: '2025-03-01')),
    ('future month', input(month: '2026-12-01')),
    ('unknown coverage', input(coverage: false)),
    ('unknown classification', input(classified: false)),
    ('nonresident noncitizen', input(resident: false)),
    ('no primary declaration', input(primary: false)),
    ('joined or left', input(joined: true)),
    ('cumulative trigger', input(profits: '149999')),
    ('cumulative missing current month', input(cumulative: '1')),
  ]) {
    test('$label blocks a Table 01 estimate', () {
      final result = previewSriLankaPayroll(value);
      expect(result.hasEstimate, isFalse);
      expect(result.blockers, isNotEmpty);
      expect(result.apitFormula, isNull);
    });
  }

  for (final value in SriLankaApitCase.values.skip(1)) {
    test('$value never silently uses Table 01', () {
      final result = previewSriLankaPayroll(input(apitCase: value));
      expect(result.hasEstimate, isFalse);
      expect(result.blockers, contains(contains('another APIT table')));
    });
  }

  test('November refresh retains a review-only regular-pay estimate', () {
    final result = previewSriLankaPayroll(input(month: '2026-11-01'));
    expect(result.hasEstimate, isTrue);
    expect(result.apitFormula, lkr('18500'));
    expect(SriLankaPayrollSources.checkedOn, '2026-11-05');
    expect(
      SriLankaPayrollPreview.reviewRequirements,
      contains(contains('Installed server calculation')),
    );
  });

  test('salary arrears remain blocked pending the 2026 credit review', () {
    final result = previewSriLankaPayroll(
      input(month: '2026-11-01', apitCase: SriLankaApitCase.lumpSumOrArrears),
    );
    expect(result.hasEstimate, isFalse);
    expect(result.apitFormula, isNull);
    expect(result.blockers, contains(contains('Section 96A')));
  });

  test('exact cumulative boundary does not trigger Table 05', () {
    expect(
      previewSriLankaPayroll(
        input(profits: '149999', cumulative: '1800000'),
      ).hasEstimate,
      isTrue,
    );
  });

  test('negative net retains explanations but blocks a payable estimate', () {
    final result = previewSriLankaPayroll(input(cash: '1'));
    expect(result.hasEstimate, isFalse);
    expect(result.apitFormula, lkr('18500'));
    expect(result.blockers, contains(contains('exceed cash earnings')));
  });

  test('rejects negative, overflow and non-month input', () {
    for (final value in [
      input(cash: '-1'),
      input(epf: '100000000000000'),
      input(month: '2026-10-02'),
    ]) {
      expect(() => previewSriLankaPayroll(value), throwsFormatException);
    }
    final mixed = SriLankaPayrollInput(
      month: CivilDate.parse('2026-10-01'),
      cashEarnings: Money.parse('100', 'USD'),
      epfEarnings: lkr('100'),
      etfEarnings: lkr('100'),
      apitRegularProfits: lkr('100'),
      cumulativeRegularProfits: lkr('100'),
      otherDeductions: lkr('0'),
    );
    expect(() => previewSriLankaPayroll(mixed), throwsFormatException);
  });
}
