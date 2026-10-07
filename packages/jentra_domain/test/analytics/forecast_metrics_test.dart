import 'package:jentra_domain/analytics.dart';
import 'package:test/test.dart';

final scope = ProcessMetricScope(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '20000000-0000-0000-0000-000000000001',
);
ForecastOpportunity row(
  int i, {
  String amount = '10.000001',
  String probability = '50',
  String currency = 'LKR',
  String version = '9007199254740993',
}) => ForecastOpportunity(
  id: '30000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
  version: version,
  scope: scope,
  amount: amount,
  probability: probability,
  currency: currency,
  expectedCloseDate: '2026-10-15',
);
List<CurrencyForecast> forecast(
  List<ForecastOpportunity> r, {
  bool complete = true,
}) => calculatePipelineForecast(
  scope,
  r,
  horizonStart: '2026-10-01',
  horizonEnd: '2026-11-01',
  complete: complete,
);
StatementBasis basis({String currency = 'LKR', bool complete = true}) =>
    StatementBasis(
      scope: scope,
      publicationId: '40000000-0000-0000-0000-000000000001',
      currency: currency,
      periodStart: '2026-01-01',
      periodEnd: '2027-01-01',
      formulaVersion: 1,
      complete: complete,
    );
void main() {
  test(
    'complete forecast transport preserves exact amounts and rejects 101 currencies',
    () {
      expect(row(1).toJson()['version'], '9007199254740993');
      expect(forecast([row(1)]).single.amount, '10.000001');
      final rows = List.generate(
        101,
        (i) => row(
          i + 1,
          currency:
              'A${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}',
        ),
      );
      expect(() => forecast(rows), throwsFormatException);
      expect(
        () => StatementBasis(
          scope: scope,
          publicationId: '40000000-0000-0000-0000-000000000001',
          currency: 'LKR',
          periodStart: '2026-10-01',
          periodEnd: '2026-10-01',
          formulaVersion: 1,
          complete: true,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'source revisions require canonical positive PostgreSQL bigint strings',
    () {
      for (final version in [
        '0',
        '-1',
        '+1',
        '01',
        '1.0',
        '9223372036854775808',
      ]) {
        expect(() => row(1, version: version), throwsFormatException);
      }
    },
  );
  test('half-away exact opportunity weighting and currency separation', () {
    final r = forecast([row(1), row(2, currency: 'USD')]);
    expect(r.map((r) => r.currency), ['LKR', 'USD']);
    expect(r.first.weightedAmount, '5.000001');
  });
  test('permutation preserves grouped totals and huge integer versions', () {
    final a = forecast([row(1), row(2)]), b = forecast([row(2), row(1)]);
    expect(a.single.weightedAmount, b.single.weightedAmount);
    expect(row(1).version, BigInt.parse('9007199254740993'));
  });
  test('zero and empty remain distinct populations', () {
    expect(forecast([]), isEmpty);
    expect(forecast([row(1, amount: '0')]).single.population, 1);
    expect(forecast([row(1, amount: '0')]).single.weightedAmount, '0.000000');
  });
  test('partial and duplicate source snapshots fail', () {
    expect(() => forecast([row(1)], complete: false), throwsFormatException);
    expect(() => forecast([row(1), row(1)]), throwsFormatException);
  });
  test(
    'excess probability and precision fail without rounding malformed input',
    () {
      expect(() => row(1, probability: '100.000001'), throwsFormatException);
      expect(() => row(1, amount: '1.0000001'), throwsFormatException);
    },
  );
  test('horizon end excluded and row bounds enforced', () {
    expect(
      () => calculatePipelineForecast(
        scope,
        [row(1)],
        horizonStart: '2026-10-01',
        horizonEnd: '2026-10-15',
        complete: true,
      ),
      throwsFormatException,
    );
    expect(() => forecast(List.filled(10001, row(1))), throwsFormatException);
  });
  test('ratios preserve exact numerator denominator and half-away sign', () {
    final r = calculateStatementRatio(
      basis(),
      basis(),
      BigInt.from(-1),
      BigInt.from(6),
    );
    expect(r.exactValue, '-0.166667');
    expect(r.denominator, BigInt.from(6));
  });
  test('zero and negative denominator unavailable', () {
    expect(
      calculateStatementRatio(
        basis(),
        basis(),
        BigInt.one,
        BigInt.zero,
      ).unavailableReason,
      'ZERO_DENOMINATOR',
    );
    expect(
      calculateStatementRatio(
        basis(),
        basis(),
        BigInt.one,
        -BigInt.one,
      ).unavailableReason,
      'NEGATIVE_DENOMINATOR',
    );
    expect(
      calculateStatementRatio(
        basis(),
        basis(),
        BigInt.one,
        -BigInt.one,
        allowNegativeDenominator: true,
      ).exactValue,
      '-1.000000',
    );
  });
  test('mixed publication currencies or incomplete statements rejected', () {
    expect(
      () => calculateStatementRatio(
        basis(),
        basis(currency: 'USD'),
        BigInt.one,
        BigInt.one,
      ),
      throwsFormatException,
    );
    expect(
      () => calculateStatementRatio(
        basis(complete: false),
        basis(),
        BigInt.one,
        BigInt.one,
      ),
      throwsFormatException,
    );
  });
}
