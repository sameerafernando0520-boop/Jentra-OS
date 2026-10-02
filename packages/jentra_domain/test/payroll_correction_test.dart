import 'package:jentra_domain/jentra_payroll.dart';
import 'package:test/test.dart';
import 'payroll_calculation_test.dart' as fixture;

const seal = '10000000-0000-0000-0000-000000000001',
    revision = '10000000-0000-0000-0000-000000000002',
    replacement = '10000000-0000-0000-0000-000000000003',
    next = '10000000-0000-0000-0000-000000000004',
    correction = '10000000-0000-0000-0000-000000000005';
PayrollCorrectionChain chain(int paid, List<PayrollRule> rules) =>
    PayrollCorrectionChain(
      originalCalculationId: correction,
      originalInput: fixture.input(paid: paid),
      rules: rules,
      sources: [
        SealedPayrollSource(
          sealId: seal,
          revisionId: revision,
          version: 3,
          paidSeconds: paid,
        ),
      ],
    );
PayrollSourceReplacement change(
  int paid, {
  String before = revision,
  String after = replacement,
  int version = 3,
}) => PayrollSourceReplacement(
  sealId: seal,
  beforeRevisionId: before,
  expectedVersion: version,
  replacementRevisionId: after,
  paidSeconds: paid,
);
void main() {
  test(
    'difference rounds complete corrected pay rather than the difference',
    () {
      final original = chain(1, [
        fixture.rule('H', basis: PayrollBasis.hourly, amount: '18'),
      ]);
      final result = original.apply(correction, [change(2)]);
      expect(result.before.gross.toDecimalString(), '0.010000');
      expect(result.after.gross.toDecimalString(), '0.010000');
      expect(result.gross.toDecimalString(), '0.000000');
      expect(result.lines.single.delta.toDecimalString(), '0.000000');
      expect(
        result.after.input.plannedSeconds,
        original.originalInput.plannedSeconds,
      );
      expect(result.after.input.start, original.originalInput.start);
    },
  );
  test(
    'signed ratios reconcile over chained corrections using original rules',
    () {
      final original = chain(3600, [
        fixture.rule('H', basis: PayrollBasis.hourly, amount: '12'),
        fixture.rule(
          'D',
          type: PayrollClassification.deduction,
          basis: PayrollBasis.earningsRatio,
          amount: '0',
          numerator: 1,
          denominator: 10,
        ),
        fixture.rule(
          'E',
          type: PayrollClassification.employerCost,
          basis: PayrollBasis.earningsRatio,
          amount: '0',
          numerator: 3,
          denominator: 100,
        ),
      ]);
      final first = original.apply(correction, [change(1800)]);
      expect(first.gross.toDecimalString(), '-6.000000');
      expect(first.deductions.toDecimalString(), '-0.600000');
      expect(first.net.toDecimalString(), '-5.400000');
      expect(first.employerCost.toDecimalString(), '-0.180000');
      final second = first.next.apply(next, [
        change(900, before: replacement, after: next, version: 4),
      ]);
      expect((first.net + second.net).toDecimalString(), '-8.100000');
      expect(second.after.net.toDecimalString(), '2.700000');
      expect(first.next.sources.single.version, 4);
      expect(original.sources.single.revisionId, revision);
    },
  );
  test('cap changes are recomputed against original full earning basis', () {
    final original = chain(3600, [
      fixture.rule('H', basis: PayrollBasis.hourly, amount: '200', cap: '300'),
    ]);
    final first = original.apply(correction, [change(5400)]);
    expect(first.gross.toDecimalString(), '100.000000');
    final second = first.next.apply(next, [
      change(7200, before: replacement, after: next, version: 4),
    ]);
    expect(second.gross.toDecimalString(), '0.000000');
    expect(second.after.gross.toDecimalString(), '300.000000');
  });
  test(
    'seal totals, duplicate replacements and stale prior revisions fail',
    () {
      expect(
        () => PayrollCorrectionChain(
          originalCalculationId: correction,
          originalInput: fixture.input(paid: 3600),
          rules: [fixture.rule('H')],
          sources: [
            SealedPayrollSource(
              sealId: seal,
              revisionId: revision,
              version: 1,
              paidSeconds: 1800,
            ),
          ],
        ),
        throwsFormatException,
      );
      final original = chain(3600, [fixture.rule('H')]);
      expect(
        () => original.apply(correction, [change(1800), change(900)]),
        throwsFormatException,
      );
      expect(
        () => original.apply(correction, [change(1800, before: next)]),
        throwsFormatException,
      );
      expect(
        () => original.apply(correction, [change(1800, version: 2)]),
        throwsFormatException,
      );
      final first = original.apply(correction, [change(1800)]);
      expect(
        () => first.next.apply(correction, [
          change(900, before: replacement, after: next, version: 4),
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'zero replacement preserves immutable sources without implicit net clamping',
    () {
      final original = chain(3600, [
        fixture.rule('H', basis: PayrollBasis.hourly, amount: '12'),
      ]);
      final zero = original.apply(correction, [change(0)]);
      expect(zero.net.toDecimalString(), '-12.000000');
      expect(zero.after.net.toDecimalString(), '0.000000');
      expect(zero.next.sources.single.sealId, seal);
      expect(() => change(-1), throwsFormatException);
    },
  );
}
