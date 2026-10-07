import 'package:jentra_domain/analytics.dart';
import 'package:test/test.dart';

final scope = ProcessMetricScope(
  tenantId: '10000000-0000-0000-0000-000000000001',
  legalEntityId: '20000000-0000-0000-0000-000000000001',
);
const requiredProviders = {'bank_cash', 'receivables', 'payables', 'payroll'};
CashControl control({
  String currency = 'LKR',
  String asOf = '2026-10-01T00:00:00Z',
  String version = '1',
}) => CashControl(
  scope: scope,
  accountId: '30000000-0000-0000-0000-000000000001',
  currency: currency,
  units: BigInt.from(1000000),
  asOf: asOf,
  publicationId: '50000000-0000-0000-0000-000000000001',
  sourceVersion: version,
);
CashObligation obligation(
  int i,
  String provider,
  bool inflow,
  int amount, {
  String currency = 'LKR',
  String date = '2026-10-02',
}) => CashObligation(
  scope: scope,
  provider: provider,
  id: '40000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
  currency: currency,
  dueDate: date,
  remainingUnits: BigInt.from(amount),
  inflow: inflow,
  publicationId: '50000000-0000-0000-0000-000000000002',
  sourceVersion: '9007199254740993',
);
CashScenario calculate(
  List<CashObligation> rows, {
  Set<String> complete = requiredProviders,
  List<CashControl>? controls,
}) => CashScenario.calculate(
  scope: scope,
  horizonStart: '2026-10-01',
  horizonEnd: '2026-10-04',
  requiredProviders: requiredProviders,
  completeProviders: complete,
  controls: controls ?? [control()],
  obligations: rows,
);
void main() {
  test(
    'provider, currency and group bounds reject unsupported complete controls',
    () {
      expect(
        () => CashScenario.calculate(
          scope: scope,
          horizonStart: '2026-10-01',
          horizonEnd: '2026-10-04',
          requiredProviders: {'receivables'},
          completeProviders: {'receivables'},
          controls: [],
          obligations: [],
        ),
        throwsFormatException,
      );
      expect(
        () => calculate([], controls: [control(currency: 'bad')]),
        throwsFormatException,
      );
      final controls = List.generate(
        101,
        (i) => CashControl(
          scope: scope,
          accountId:
              '30000000-0000-0000-0000-${(i + 1).toString().padLeft(12, '0')}',
          currency:
              'A${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}',
          units: BigInt.zero,
          asOf: '2026-10-01T00:00:00Z',
          publicationId: '50000000-0000-0000-0000-000000000001',
          sourceVersion: '1',
        ),
      );
      expect(() => calculate([], controls: controls), throwsFormatException);
    },
  );
  test(
    'opening controls must bind the exact date, publication and canonical source revision',
    () {
      for (final date in ['2026-09-30T23:59:59Z', '2026-10-01T00:00:01Z']) {
        expect(
          () => calculate([], controls: [control(asOf: date)]),
          throwsFormatException,
        );
      }
      for (final version in ['0', '01', '+1', '9223372036854775808']) {
        expect(() => control(version: version), throwsFormatException);
      }
      expect(control().sourceVersion, '1');
    },
  );
  test(
    'dated residual flows reconcile without posting and remain permutation stable',
    () {
      final rows = [
        obligation(1, 'receivables', true, 2000000),
        obligation(2, 'payables', false, 3000000),
        obligation(3, 'payroll', false, 1),
      ];
      final a = calculate(rows), b = calculate(rows.reversed.toList());
      expect(a.buckets.map((b) => b.exactBalance), [
        '1.000000',
        '-0.000001',
        '-0.000001',
      ]);
      expect(a.buckets.map((b) => b.balance), b.buckets.map((b) => b.balance));
      expect(() => a.buckets.clear(), throwsUnsupportedError);
    },
  );
  test(
    'missing payroll remains unavailable even when other obligations are empty',
    () {
      final r = calculate(
        [],
        complete: {'bank_cash', 'receivables', 'payables'},
      );
      expect(r.available, isFalse);
      expect(r.unavailableProviders, ['payroll']);
      expect(r.buckets, isEmpty);
    },
  );
  test('duplicate residual or cash controls denied', () {
    expect(
      () => calculate([obligation(1, 'payroll', true, 1)]),
      throwsFormatException,
    );
    expect(
      () => calculate([obligation(1, 'receivables', false, 1)]),
      throwsFormatException,
    );
    final o = obligation(1, 'receivables', true, 1);
    expect(() => calculate([o, o]), throwsFormatException);
    expect(
      () => calculate([], controls: [control(), control()]),
      throwsFormatException,
    );
  });
  test(
    'negative residual, missing currency control and excluded horizon end rejected',
    () {
      expect(
        () => calculate([obligation(1, 'payables', false, -1)]),
        throwsFormatException,
      );
      expect(
        () => calculate([obligation(1, 'payables', false, 1, currency: 'USD')]),
        throwsFormatException,
      );
      expect(
        () => calculate([
          obligation(1, 'payables', false, 1, date: '2026-10-04'),
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'unknown provider and source bounds fail without truncated balances',
    () {
      expect(
        () => calculate([obligation(1, 'private_hr', false, 1)]),
        throwsFormatException,
      );
      expect(
        () => calculate(
          List.generate(10000, (i) => obligation(i + 1, 'payables', false, 1)),
        ),
        throwsFormatException,
      );
    },
  );
}
