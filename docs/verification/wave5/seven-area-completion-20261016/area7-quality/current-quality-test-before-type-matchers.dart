import 'dart:convert';

import 'package:jentra_domain/analytics.dart';
import 'package:test/test.dart';

String qid(int n) => '70000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final qscope = ProcessMetricScope(tenantId: qid(1), legalEntityId: qid(2));
const qdigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// Controlled dependency: recognizes exact bytes, does not claim SHA computation.
final class CapturedBytesHasher implements ProcessMetricHasher {
  CapturedBytesHasher(this.text, {this.accept = true});
  final String text;
  final bool accept;
  @override
  Future<String> sha256(List<int> bytes) async =>
      accept && utf8.decode(bytes) == text ? qdigest : 'b' * 64;
}

Map<String, String> assumption([String date = '2026-10-02']) => {
  'dueDate': date,
  'remainingUnits': '1',
  'reasonCode': 'reviewed_amount',
};
CashScenarioRevision scenario({
  String sourceHash = qdigest,
  String start = '2026-10-01',
  String end = '2026-11-01',
  Map<String, Map<String, String>>? overrides,
}) => CashScenarioRevision(
  id: qid(3),
  scope: qscope,
  sourceHash: sourceHash,
  horizonStart: start,
  horizonEnd: end,
  recordedThrough: '2026-10-01T00:00:00Z',
  overrides: overrides ?? {qid(4): assumption()},
);
CashObligation obligation() => CashObligation(
  scope: qscope,
  provider: 'receivables',
  id: qid(4),
  currency: 'LKR',
  dueDate: '2026-10-01',
  remainingUnits: BigInt.one,
  inflow: true,
  publicationId: qid(5),
  sourceVersion: '1',
);

PipelineRevision rev(
  int version, {
  int key = 4,
  int? revisionKey,
  DateTime? recorded,
  DateTime? created,
  String status = 'open',
  String currency = 'LKR',
  ProcessMetricScope? scope,
}) => PipelineRevision(
  id: qid(key),
  revisionId: qid(revisionKey ?? version + 1000),
  version: BigInt.from(version),
  scope: scope ?? qscope,
  recordedAt: recorded ?? DateTime.utc(2026, 10, version),
  createdAt: created ?? DateTime.utc(2026, 10, 1),
  stage: 'qualified',
  status: status,
  ownerId: qid(6),
  amount: BigInt.one,
  probability: BigInt.from(50000000),
  currency: currency,
);

Map<String, Object?> forecastEvidence() => {
  'tenantId': qscope.tenantId,
  'legalEntityId': qscope.legalEntityId,
  'branchId': null,
  'definitionCode': 'pipeline.current_weighted',
  'definitionVersion': 1,
  'sourceContract': 'crm.opportunities.current.v1',
  'horizonStart': '2026-10-01',
  'horizonEnd': '2026-11-01',
  'asOf': '2026-10-01T00:00:00Z',
  'recordedThrough': '2026-10-01T00:00:00Z',
  'generatedAt': '2026-10-01T00:00:00Z',
  'complete': true,
  'sourceCount': 1,
  'observations': [
    <String, Object?>{
      'id': qid(4),
      'version': '9007199254740993',
      'tenantId': qscope.tenantId,
      'legalEntityId': qscope.legalEntityId,
      'branchId': null,
      'amount': '2.000002',
      'probability': '50',
      'currency': 'LKR',
      'expectedCloseDate': '2026-10-02',
    },
  ],
  'currencies': [
    <String, Object?>{
      'currency': 'LKR',
      'population': 1,
      'amount': '2.000002',
      'weightedAmount': '1.000001',
    },
  ],
  'unavailable': {
    'aging': 'STAGE_HISTORY_UNAVAILABLE',
    'accuracy': 'REALIZED_MAPPING_UNAVAILABLE',
    'conversion': 'HISTORICAL_REVISIONS_UNAVAILABLE',
    'velocity': 'HISTORICAL_REVISIONS_UNAVAILABLE',
  },
};
Future<FrozenPipelineForecast> verifyForecast(
  Map<String, Object?> evidence, {
  Map<String, Object?>? envelope,
  bool digestAccept = true,
  String? captured,
}) {
  final text = captured ?? jsonEncode(evidence);
  return FrozenPipelineForecast.verify(
    envelope ??
        {
          'id': qid(7),
          'sourceHash': qdigest,
          'canonicalText': text,
          'evidence': evidence,
        },
    qscope,
    qid(7),
    CapturedBytesHasher(text, accept: digestAccept),
  );
}

void main() {
  test(
    'scenario basis and horizon reject malformed and oversized assumptions',
    () {
      expect(() => scenario(sourceHash: 'bad'), throwsFormatException);
      expect(
        () => scenario(
          overrides: {for (var i = 0; i < 10001; i++) qid(i + 10): assumption()},
        ),
        throwsFormatException,
      );
      for (final end in ['2026-10-01', '2026-09-30', '2027-10-03']) {
        expect(() => scenario(end: end), throwsFormatException);
      }
      expect(scenario(end: '2027-10-02').horizonEnd, '2027-10-02');
    },
  );
  test(
    'scenario overrides enforce exact shape, integer units, reason and half-open dates',
    () {
      for (final value in [
        <String, String>{},
        {'dueDate': '2026-10-02', 'remainingUnits': '1', 'unknown': 'x'},
        {...assumption(), 'remainingUnits': '-1'},
        {...assumption(), 'remainingUnits': '1.0'},
        {...assumption(), 'reasonCode': 'unapproved'},
        assumption('2026-09-30'),
        assumption('2026-11-01'),
      ]) {
        expect(
          () => scenario(overrides: {qid(4): value}),
          throwsFormatException,
        );
      }
      expect(
        scenario(
          overrides: {qid(4): assumption('2026-10-01')},
        ).apply([obligation()]).single.dueDate,
        '2026-10-01',
      );
      expect(
        () => scenario().apply([obligation(), obligation()]),
        throwsFormatException,
      );
      final unchanged = obligation();
      expect(
        scenario(overrides: {}).apply([unchanged]).single,
        same(unchanged),
      );
    },
  );
  test(
    'scenario recovery rejects malformed nested key/value and preserves exact override data',
    () {
      final wire = scenario().toJson();
      for (final overrides in [
        [],
        {1: assumption()},
        {qid(4): 'bad'},
        {
          qid(4): {1: 'bad'},
        },
        {
          qid(4): {
            'dueDate': 1,
            'remainingUnits': '1',
            'reasonCode': 'reviewed_amount',
          },
        },
      ]) {
        expect(
          () => CashScenarioRevision.fromJson(qscope, {
            ...wire,
            'overrides': overrides,
          }),
          throwsFormatException,
        );
      }
      final restored = CashScenarioRevision.fromJson(qscope, wire);
      expect(restored.apply([obligation()]).single.dueDate, '2026-10-02');
      expect(
        () => restored.apply([obligation()]).add(obligation()),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'history refuses invalid versions, scope, cutoffs and excessive complete rows',
    () {
      expect(() => rev(0), throwsFormatException);
      expect(() => rev(1, currency: 'lkr'), throwsFormatException);
      expect(
        () => rev(1, created: DateTime.utc(2026, 10, 2)),
        throwsFormatException,
      );
      for (final rows in [
        [
          rev(
            1,
            scope: ProcessMetricScope(tenantId: qid(9), legalEntityId: qid(2)),
          ),
        ],
        [rev(2)],
        List.filled(10001, rev(1)),
      ]) {
        expect(
          () => calculateHistoricalPipeline(
            qscope,
            rows,
            DateTime.utc(2026, 10, 1),
            complete: true,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'history rejects conflicting revision order rather than publishing partial totals',
    () {
      for (final rows in [
        [rev(1), rev(1, revisionKey: 900)],
        [rev(1, recorded: DateTime.utc(2026, 10, 3)), rev(2)],
        [rev(1), rev(2, created: DateTime.utc(2026, 10, 2))],
      ]) {
        expect(
          () => calculateHistoricalPipeline(
            qscope,
            rows,
            DateTime.utc(2026, 10, 4),
            complete: true,
          ),
          throwsFormatException,
        );
      }
      final inactive = calculateHistoricalPipeline(
        qscope,
        [rev(1, status: 'inactive')],
        DateTime.utc(2026, 10, 2),
        complete: true,
      );
      expect(inactive.population, 0);
      final won = calculateHistoricalPipeline(
        qscope,
        [rev(1, status: 'won')],
        DateTime.utc(2026, 10, 2),
        complete: true,
      );
      expect(won.wonValuePerMeanCycleDay['LKR'], isNull);
    },
  );
  test('history bounds distinct currency groups and accuracy currencies', () {
    final rows = List.generate(
      101,
      (i) => rev(
        1,
        key: i + 20,
        revisionKey: i + 2000,
        status: 'won',
        currency:
            'A${String.fromCharCode(65 + i ~/ 26)}${String.fromCharCode(65 + i % 26)}',
      ),
    );
    expect(
      () => calculateHistoricalPipeline(
        qscope,
        rows,
        DateTime.utc(2026, 10, 2),
        complete: true,
      ),
      throwsFormatException,
    );
    final p = CurrencyForecast('LKR', 1, BigInt.one, BigInt.one);
    for (final predicted in [
      [p, p],
      List.filled(101, p),
    ]) {
      expect(
        () => calculateForecastAccuracy(predicted, {}, complete: true),
        throwsFormatException,
      );
    }
    expect(
      () => calculateForecastAccuracy([p], {'USD': BigInt.one}, complete: true),
      throwsFormatException,
    );
    expect(
      () => calculateForecastAccuracy([p], {}, complete: false),
      throwsFormatException,
    );
  });
  test('named ratios refuse incomplete and unsupported formula versions', () {
    for (final b in [
      StatementBasis(
        scope: qscope,
        publicationId: qid(8),
        currency: 'LKR',
        periodStart: '2026-10-01',
        periodEnd: '2026-11-01',
        formulaVersion: 1,
        complete: false,
      ),
      StatementBasis(
        scope: qscope,
        publicationId: qid(8),
        currency: 'LKR',
        periodStart: '2026-10-01',
        periodEnd: '2026-11-01',
        formulaVersion: 2,
        complete: true,
      ),
    ]) {
      expect(
        () => calculateNamedRatios(
          b,
          revenue: BigInt.one,
          netProfit: BigInt.one,
          assets: BigInt.one,
          liabilities: BigInt.one,
          equity: BigInt.one,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'frozen forecast verifies exact captured publication and immutable observations',
    () async {
      final e = forecastEvidence(),
          verified = await verifyForecast(forecastEvidence());
      expect(verified.currencies.single.weightedAmount, '1.000001');
      expect(verified.observations.single.version, '9007199254740993');
      expect(() => verified.observations.clear(), throwsUnsupportedError);
      final reordered = Map<String, Object?>.fromEntries(
        e.entries.toList().reversed,
      );
      expect(
        (await verifyForecast(reordered, captured: jsonEncode(e))).id,
        qid(7),
      );
    },
  );
  test(
    'frozen forecast rejects unsupported envelope, digest and mismatched captured evidence',
    () async {
      for (final env in [
        <String, Object?>{},
        {
          'id': qid(9),
          'sourceHash': qdigest,
          'canonicalText': '{}',
          'evidence': forecastEvidence(),
        },
        {
          'id': qid(7),
          'sourceHash': 'bad',
          'canonicalText': '{}',
          'evidence': forecastEvidence(),
        },
      ]) {
        await expectLater(
          verifyForecast(forecastEvidence(), envelope: env),
          throwsFormatException,
        );
      }
      await expectLater(
        verifyForecast(forecastEvidence(), digestAccept: false),
        throwsFormatException,
      );
      await expectLater(
        verifyForecast(forecastEvidence(), captured: '{}'),
        throwsFormatException,
      );
      await expectLater(
        verifyForecast({...forecastEvidence(), 'unavailable': 1.5}),
        throwsFormatException,
      );
    },
  );
  test(
    'frozen forecast rejects incompatible definition, incomplete count and malformed observations',
    () async {
      for (final change in [
        <String, Object?>{'tenantId': qid(9)},
        {'definitionVersion': 2},
        {'complete': false},
        {'sourceCount': 2},
        {
          'observations': ['bad'],
        },
        {
          'observations': [<String, Object?>{}],
        },
        {
          'observations': [
            {
              ...(forecastEvidence()['observations'] as List).single
                  as Map<String, Object?>,
              'amount': 2,
            },
          ],
        },
      ]) {
        await expectLater(
          verifyForecast({...forecastEvidence(), ...change}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'frozen forecast recomputes currency groups and unavailable state instead of trusting summaries',
    () async {
      for (final currencies in [
        [],
        ['bad'],
        [<String, Object?>{}],
        [
          {
            ...(forecastEvidence()['currencies'] as List).single
                as Map<String, Object?>,
            'weightedAmount': '99.000000',
          },
        ],
      ]) {
        await expectLater(
          verifyForecast({...forecastEvidence(), 'currencies': currencies}),
          throwsFormatException,
        );
      }
      await expectLater(
        verifyForecast({...forecastEvidence(), 'unavailable': {}}),
        throwsFormatException,
      );
    },
  );
}
