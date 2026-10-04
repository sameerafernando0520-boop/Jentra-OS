import 'package:test/test.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';

String uid(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
ProjectTaskBasis task(int n, List<int> dependencies, {String? project}) =>
    ProjectTaskBasis(
      id: uid(n),
      projectId: project ?? uid(999),
      ownerId: uid(998),
      start: CivilDate.parse('2026-10-01'),
      endExclusive: CivilDate.parse('2026-10-04'),
      plannedSeconds: 7200,
      progressBasisPoints: 0,
      dependencies: dependencies.map(uid),
    );
ProjectExpenseFx fx({
  int numerator = 1,
  int denominator = 2,
  String original = 'USD',
}) => ProjectExpenseFx(
  originalCurrency: original,
  baseCurrency: 'LKR',
  numerator: numerator,
  denominator: denominator,
  precision: 2,
  rateId: original == 'LKR' ? null : uid(9),
  rateVersion: original == 'LKR' ? null : 4,
);
ProjectBillableUnit unit(
  int n, {
  int source = 1,
  String currency = 'LKR',
  String? project,
}) => ProjectBillableUnit(
  id: uid(n),
  projectId: project ?? uid(999),
  source: ProjectBillingSource.time,
  sourceId: uid(source),
  sourceVersion: 3,
  digest: 'a' * 64,
  amount: projectAmount('0', currency),
  precision: 2,
  payableSeconds: 1,
);

void main() {
  test('task ownership cannot be inferred from resource allocation', () {
    expect(task(1, const []).ownerId, uid(998));
    expect(
      () => ProjectTaskBasis(
        id: uid(1),
        projectId: uid(999),
        ownerId: 'unconfigured',
        start: CivilDate.parse('2026-10-01'),
        endExclusive: CivilDate.parse('2026-10-04'),
        plannedSeconds: 0,
        progressBasisPoints: 0,
        dependencies: const [],
      ),
      throwsFormatException,
    );
  });
  test(
    'whole-second published-zone resolution retains negative UTC offsets',
    () {
      final resolution = ProjectLocalResolution.fromJson({
        'calendar_version_id': uid(1),
        'date': '2026-11-01',
        'minute': 90,
        'second': 1,
        'timezone': 'America/New_York',
        'local_datetime': '2026-11-01T01:30:01',
        'algorithm': 'pg-iana-roundtrip-v1',
        'candidates': [
          {'utc': '2026-11-01T05:30:01Z', 'offset_seconds': -14400},
          {'utc': '2026-11-01T06:30:01Z', 'offset_seconds': -18000},
        ],
      });
      expect(resolution.isAmbiguous, isTrue);
      expect(resolution.second, 1);
      expect(resolution.candidates.last.offsetSeconds, -18000);
      expect(
        () => ProjectLocalResolution.fromJson({
          'calendar_version_id': uid(1),
          'date': '2026-11-01',
          'minute': 90,
          'second': 1,
          'timezone': 'America/New_York',
          'local_datetime': '2026-11-01T01:30:01',
          'algorithm': 'pg-iana-roundtrip-v1',
          'candidates': [
            {'utc': '2026-11-01T05:30:00Z', 'offset_seconds': -14400},
          ],
        }),
        throwsFormatException,
      );
    },
  );
  test('service billing retains whole units with original exact seconds', () {
    final service = ProjectBillableUnit(
      id: uid(1),
      projectId: uid(2),
      source: ProjectBillingSource.service,
      sourceId: uid(3),
      sourceVersion: 1,
      digest: List.filled(64, 'a').join(),
      amount: Money.parse('0.02', 'LKR'),
      precision: 2,
      payableSeconds: 1,
    );
    expect(service.salesQuantity, '1.000000');
    expect(
      () => ProjectBillableUnit(
        id: uid(1),
        projectId: uid(2),
        source: ProjectBillingSource.service,
        sourceId: uid(3),
        sourceVersion: 1,
        digest: List.filled(64, 'a').join(),
        amount: Money.parse('0.02', 'LKR'),
        precision: 2,
      ),
      throwsFormatException,
    );
  });
  test(
    'whole-second time pricing retains even and odd ties without fractional hours',
    () {
      expect(
        projectTimeAmount(projectAmount('18', 'LKR'), 1, 2).toDecimalString(),
        '0.000000',
      );
      expect(
        projectTimeAmount(projectAmount('18', 'LKR'), 3, 2).toDecimalString(),
        '0.020000',
      );
      expect(
        projectTimeAmount(projectAmount('123.456789', 'LKR'), 3600, 6),
        projectAmount('123.456789', 'LKR'),
      );
    },
  );
  test('large rational quotients and signed ties use integer half-even', () {
    final d = BigInt.from(9007199254740991),
        n = BigInt.parse('99999999999999999999');
    expect(projectRoundRatio(n * d - BigInt.one, d, 6), n);
    expect(projectRoundRatio(BigInt.from(-5000), BigInt.one, 2), BigInt.zero);
    expect(
      projectRoundRatio(BigInt.from(-15000), BigInt.one, 2),
      BigInt.from(-20000),
    );
  });
  test(
    'expense FX conserves gross and records rather than hides tax residue',
    () {
      final e = ProjectExpenseBasis(
        net: projectAmount('.01'.replaceFirst('.', '0.'), 'USD'),
        tax: projectAmount('0.01', 'USD'),
        gross: projectAmount('0.02', 'USD'),
        fx: fx(),
        originalPrecision: 2,
        taxDefinitionId: uid(8),
        taxDefinitionVersion: 2,
        noTaxReason: null,
      );
      expect(e.baseNet.toDecimalString(), '0.000000');
      expect(e.baseTax.toDecimalString(), '0.010000');
      expect(e.baseNet + e.baseTax, e.baseGross);
      expect(e.taxRoundingResidue.toDecimalString(), '0.010000');
    },
  );
  test(
    'expense currency, precision, tax evidence and rate ownership cannot be guessed',
    () {
      expect(() => fx(original: 'LKR'), throwsFormatException);
      expect(
        () => ProjectExpenseFx(
          originalCurrency: 'USD',
          baseCurrency: 'LKR',
          numerator: 1,
          denominator: 0,
          precision: 2,
          rateId: uid(1),
          rateVersion: 1,
        ),
        throwsFormatException,
      );
      expect(
        () => ProjectExpenseBasis(
          net: projectAmount('1', 'USD'),
          tax: projectAmount('0', 'USD'),
          gross: projectAmount('1', 'USD'),
          fx: fx(),
          originalPrecision: 2,
          taxDefinitionId: null,
          taxDefinitionVersion: null,
          noTaxReason: null,
        ),
        throwsFormatException,
      );
      expect(() => projectAmount('1.0000001', 'LKR'), throwsFormatException);
      expect(
        () => projectTimeAmount(
          projectAmount('99999999999999.999999', 'LKR'),
          129600,
          2,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'ordered tiny expense allocations conserve exact gross and final residue',
    () {
      final a = allocateProjectExpense(projectAmount('0.03', 'LKR'), [
        for (var i = 1; i <= 5; i++) ProjectAllocationWeight(uid(i), 1),
      ], 2);
      expect(a.map((v) => v.amount.toDecimalString()).toList(), [
        '0.010000',
        '0.000000',
        '0.010000',
        '0.000000',
        '0.010000',
      ]);
      expect(
        a.fold(Money.zero('LKR'), (sum, v) => sum + v.amount),
        projectAmount('0.03', 'LKR'),
      );
      expect(
        () => allocateProjectExpense(projectAmount('1', 'LKR'), [
          ProjectAllocationWeight(uid(1), 1),
          ProjectAllocationWeight(uid(1), 2),
        ], 2),
        throwsFormatException,
      );
    },
  );
  test(
    'dependency graph yields stable prerequisites and rejects cycles and foreign references',
    () {
      final g = ProjectTaskGraph(uid(999), [
        task(3, [2]),
        task(2, [1]),
        task(1, []),
      ]);
      expect(g.topological.map((v) => v.id).toList(), [uid(1), uid(2), uid(3)]);
      expect(
        () => ProjectTaskGraph(uid(999), [
          task(1, [2]),
          task(2, [1]),
        ]),
        throwsFormatException,
      );
      expect(
        () => ProjectTaskGraph(uid(999), [
          task(1, [2]),
        ]),
        throwsFormatException,
      );
      expect(
        () => ProjectTaskGraph(uid(999), [task(1, [], project: uid(998))]),
        throwsFormatException,
      );
      expect(() => task(1, [2, 2]), throwsFormatException);
    },
  );
  test(
    'whole billing units retain seconds and reject duplicate sources and mixed scope',
    () {
      expect(unit(1).salesQuantity, '1.000000');
      expect(unit(1).payableSeconds, 1);
      expect(
        projectBillingSelection(uid(999), 'LKR', [
          unit(3, source: 2),
          unit(1),
        ]).map((v) => v.id).toList(),
        [uid(1), uid(3)],
      );
      expect(
        () => projectBillingSelection(uid(999), 'LKR', [unit(1), unit(2)]),
        throwsFormatException,
      );
      expect(
        () => projectBillingSelection(uid(999), 'LKR', [
          unit(1, currency: 'USD'),
        ]),
        throwsFormatException,
      );
      expect(
        () => projectBillingSelection(uid(999), 'LKR', [
          unit(1, project: uid(998)),
        ]),
        throwsFormatException,
      );
    },
  );
  test('closure requires explicit resolution of every open source family', () {
    expect(
      ProjectClosureBasis(
        openTasks: 0,
        pendingChanges: 0,
        unbilledUnits: 0,
        openBillingBatches: 0,
        openExpenseLiabilities: 0,
      ).resolved,
      isTrue,
    );
    expect(
      () => ProjectClosureBasis(
        openTasks: 0,
        pendingChanges: 0,
        unbilledUnits: 1,
        openBillingBatches: 0,
        openExpenseLiabilities: 0,
      ).requireResolved(),
      throwsFormatException,
    );
    expect(
      () => ProjectClosureBasis(
        openTasks: -1,
        pendingChanges: 0,
        unbilledUnits: 0,
        openBillingBatches: 0,
        openExpenseLiabilities: 0,
      ),
      throwsFormatException,
    );
  });
}
