import 'package:jentra_domain/analytics.dart';
import 'package:test/test.dart';

String id(int i) => '10000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
final scope = ProcessMetricScope(
  tenantId: id(1),
  legalEntityId: id(2),
  branchId: id(3),
);
PipelineRevision revision(
  int v, {
  String stage = 'qualified',
  String status = 'open',
  int? branch,
}) => PipelineRevision(
  id: id(4),
  revisionId: id(v + 10),
  version: BigInt.from(v),
  scope: branch == null
      ? scope
      : ProcessMetricScope(
          tenantId: id(1),
          legalEntityId: id(2),
          branchId: id(branch),
        ),
  recordedAt: DateTime.utc(2026, 10, v),
  createdAt: DateTime.utc(2026, 10, 1),
  stage: stage,
  status: status,
  ownerId: id(5),
  amount: BigInt.from(10000001),
  probability: BigInt.from(50000000),
  currency: 'LKR',
);
void main() {
  test(
    'stage age starts at actual stage change; amount or owner revisions do not reset it',
    () {
      final m = calculateHistoricalPipeline(
        scope,
        [
          revision(3, stage: 'negotiation'),
          revision(1),
          revision(2, stage: 'negotiation'),
        ],
        DateTime.utc(2026, 10, 4),
        complete: true,
      );
      expect(
        m.stageAgeMicroseconds[id(4)],
        BigInt.from(const Duration(days: 2).inMicroseconds),
      );
      expect(m.conversion, null);
    },
  );
  test('legacy baseline and revision gaps do not invent stage entry', () {
    for (final rows in [
      [revision(2)],
      [revision(1), revision(3)],
    ]) {
      expect(
        () => calculateHistoricalPipeline(
          scope,
          rows,
          DateTime.utc(2026, 10, 4),
          complete: true,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'won conversion is explicit and exact; history changes preserve currency grouping',
    () {
      final m = calculateHistoricalPipeline(
        scope,
        [revision(1), revision(2, status: 'won')],
        DateTime.utc(2026, 10, 4),
        complete: true,
      );
      expect(m.conversion!.exactValue, '1.000000');
      expect(m.wonUnitsByCurrency['LKR'], BigInt.from(10000001));
    },
  );
  test(
    'a source moved to another branch is excluded from the last-known branch cohort',
    () {
      final m = calculateHistoricalPipeline(
        scope,
        [revision(1), revision(2, branch: 7)],
        DateTime.utc(2026, 10, 4),
        complete: true,
      );
      expect(m.population, 0);
    },
  );
  test('duplicates and incomplete provider fail without a partial total', () {
    expect(
      () => calculateHistoricalPipeline(
        scope,
        [revision(1), revision(1)],
        DateTime.utc(2026, 10, 4),
        complete: true,
      ),
      throwsFormatException,
    );
    expect(
      () => calculateHistoricalPipeline(
        scope,
        [],
        DateTime.utc(2026, 10, 4),
        complete: false,
      ),
      throwsFormatException,
    );
  });
  test(
    'accuracy zero actual is undefined; exact error does not pass through double',
    () {
      final p = CurrencyForecast(
        'LKR',
        1,
        BigInt.from(10000001),
        BigInt.from(5000001),
      );
      expect(
        calculateForecastAccuracy([p], {}, complete: true)['LKR']!.$2,
        null,
      );
      final a = calculateForecastAccuracy(
        [p],
        {'LKR': BigInt.from(10000000)},
        complete: true,
      )['LKR']!;
      expect(a.$1, BigInt.from(-4999999));
      expect(a.$2!.exactValue, '0.500000');
    },
  );
  test('named ratios retain undefined negative/zero denominators', () {
    final b = StatementBasis(
      scope: scope,
      publicationId: id(9),
      currency: 'LKR',
      periodStart: '2026-10-01',
      periodEnd: '2026-11-01',
      formulaVersion: 1,
      complete: true,
    );
    final ratios = calculateNamedRatios(
      b,
      revenue: BigInt.zero,
      netProfit: BigInt.from(-1),
      assets: BigInt.from(2),
      liabilities: BigInt.one,
      equity: BigInt.from(-1),
    );
    expect(ratios['net_profit_margin']!.unavailableReason, 'ZERO_DENOMINATOR');
    expect(
      ratios['assets_to_equity']!.unavailableReason,
      'NEGATIVE_DENOMINATOR',
    );
    expect(ratios['liabilities_to_assets']!.exactValue, '0.500000');
  });
}
