import '../exact_decimal.dart';
import 'forecast_metrics.dart';
import 'process_metrics.dart';

/// The authority adapter supplies complete immutable revisions. Missing revision
/// 1 or a gap prevents stage-duration and closed-cohort certification.
final class PipelineRevision {
  PipelineRevision({
    required this.id,
    required this.revisionId,
    required this.version,
    required this.scope,
    required this.recordedAt,
    required this.createdAt,
    required this.stage,
    required this.status,
    required this.ownerId,
    required this.amount,
    required this.probability,
    required this.currency,
  }) {
    for (final value in [id, revisionId, ownerId]) {
      ProcessMetricScope(tenantId: value, legalEntityId: value);
    }
    if (version <= BigInt.zero ||
        version > BigInt.parse('9223372036854775807') ||
        !recordedAt.isUtc ||
        !createdAt.isUtc ||
        createdAt.isAfter(recordedAt) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        amount.isNegative ||
        probability.isNegative ||
        probability > BigInt.from(100000000)) {
      throw const FormatException('Invalid historical opportunity revision.');
    }
  }
  final String id, revisionId, stage, status, ownerId, currency;
  final BigInt version, amount, probability;
  final ProcessMetricScope scope;
  final DateTime recordedAt, createdAt;
}

final class HistoricalPipelineMetrics {
  const HistoricalPipelineMetrics(
    this.population,
    this.decided,
    this.won,
    this.conversion,
    this.stageAgeMicroseconds,
    this.wonUnitsByCurrency,
    this.unavailableReasons,
    this.wonValuePerMeanCycleDay,
  );
  final int population, decided, won;
  final ExactRatio? conversion;
  final Map<String, BigInt> stageAgeMicroseconds, wonUnitsByCurrency;
  final List<String> unavailableReasons;

  /// Closed-cohort won value / mean won lifecycle days, by original currency.
  /// This is opportunity throughput, never posted financial revenue.
  final Map<String, ExactRatio?> wonValuePerMeanCycleDay;
}

HistoricalPipelineMetrics calculateHistoricalPipeline(
  ProcessMetricScope scope,
  List<PipelineRevision> revisions,
  DateTime asOf, {
  required bool complete,
}) {
  if (!complete || !asOf.isUtc || revisions.length > 10000) {
    throw const FormatException('Complete bounded historical cohort required.');
  }
  final groups = <String, List<PipelineRevision>>{}, ids = <String>{};
  for (final r in revisions) {
    if (r.scope.tenantId != scope.tenantId ||
        r.scope.legalEntityId != scope.legalEntityId ||
        r.recordedAt.isAfter(asOf) ||
        !ids.add(r.revisionId)) {
      throw const FormatException(
        'Historical scope, cutoff or identity mismatch.',
      );
    }
    (groups[r.id] ??= []).add(r);
  }
  var population = 0, decided = 0, won = 0;
  final ages = <String, BigInt>{},
      values = <String, BigInt>{},
      cycles = <String, BigInt>{},
      cycleCounts = <String, int>{},
      reasons = <String>{};
  for (final rows in groups.values) {
    rows.sort((a, b) => a.version.compareTo(b.version));
    var full = rows.first.version == BigInt.one;
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].version != rows[i - 1].version + BigInt.one) full = false;
      if (rows[i].version == rows[i - 1].version ||
          rows[i].recordedAt.isBefore(rows[i - 1].recordedAt) ||
          rows[i].createdAt != rows.first.createdAt) {
        throw const FormatException('Historical revision order mismatch.');
      }
    }
    final last = rows.last;
    if (scope.branchId != null && last.scope.branchId != scope.branchId) {
      continue;
    }
    if (last.status == 'inactive') continue;
    population++;
    if (!full) {
      // A partial cohort cannot publish a plausible conversion or velocity
      // from its remaining rows. The authority must repair the historical gap.
      throw const FormatException('Historical cohort contains revision gaps.');
    }
    if (last.status == 'won' || last.status == 'lost') {
      decided++;
      if (last.status == 'won') won++;
    }
    if (last.status == 'open') {
      var entry = rows.first.recordedAt;
      for (var i = 1; i < rows.length; i++) {
        if (rows[i].stage != rows[i - 1].stage) entry = rows[i].recordedAt;
      }
      ages[last.id] =
          BigInt.from(asOf.microsecondsSinceEpoch) -
          BigInt.from(entry.microsecondsSinceEpoch);
    }
    if (last.status == 'won') {
      values[last.currency] =
          (values[last.currency] ?? BigInt.zero) + last.amount;
      var closed = rows.first.recordedAt;
      for (var i = 1; i < rows.length; i++) {
        if (rows[i].status == 'won' && rows[i - 1].status != 'won') {
          closed = rows[i].recordedAt;
        }
      }
      cycles[last.currency] =
          (cycles[last.currency] ?? BigInt.zero) +
          BigInt.from(closed.difference(last.createdAt).inMicroseconds);
      cycleCounts[last.currency] = (cycleCounts[last.currency] ?? 0) + 1;
    }
  }
  if (values.length > 100) throw const FormatException('Too many currencies.');
  // Win conversion is explicitly won/decided, never lead conversion or revenue.
  final scaled = decided == 0
      ? BigInt.zero
      : BigInt.from(won) * BigInt.from(1000000);
  final denominator = BigInt.from(decided);
  final quotient = decided == 0
      ? BigInt.zero
      : scaled ~/ denominator +
            ((scaled % denominator) * BigInt.two >= denominator
                ? BigInt.one
                : BigInt.zero);
  return HistoricalPipelineMetrics(
    population,
    decided,
    won,
    decided == 0
        ? null
        : ExactRatio(
            BigInt.from(won),
            denominator,
            exactHistoricalAmount(quotient),
            null,
          ),
    Map.unmodifiable(ages),
    Map.unmodifiable(values),
    List.unmodifiable(reasons.toList()..sort()),
    Map.unmodifiable({
      for (final c in values.keys)
        c: cycles[c] == BigInt.zero
            ? null
            : _historicalRatio(
                values[c]! *
                    BigInt.from(cycleCounts[c]!) *
                    BigInt.from(86400000000),
                cycles[c]!,
                scaleNumerator: false,
              ),
    }),
  );
}

ExactRatio _historicalRatio(
  BigInt numerator,
  BigInt denominator, {
  bool scaleNumerator = true,
}) {
  final scaled = scaleNumerator ? numerator * BigInt.from(1000000) : numerator;
  final q =
      scaled ~/ denominator +
      ((scaled % denominator) * BigInt.two >= denominator
          ? BigInt.one
          : BigInt.zero);
  return ExactRatio(numerator, denominator, exactHistoricalAmount(q), null);
}

String exactHistoricalAmount(BigInt units) =>
    ExactDecimal.fromScaledValue(units, scale: 6).toDecimalString();

/// Currency-relative error stays undefined for an actual zero; absolute error
/// remains valid. Realized input must be a complete reviewed document mapping.
Map<String, (BigInt, ExactRatio?)> calculateForecastAccuracy(
  List<CurrencyForecast> predicted,
  Map<String, BigInt> realized, {
  required bool complete,
}) {
  if (!complete || predicted.length > 100 || realized.length > 100) {
    throw const FormatException('Complete realized mapping required.');
  }
  final values = <String, (BigInt, ExactRatio?)>{}, seen = <String>{};
  for (final p in predicted) {
    if (!seen.add(p.currency)) {
      throw const FormatException('Duplicate forecast currency.');
    }
    final actual = realized[p.currency] ?? BigInt.zero;
    final error = p.weightedUnits - actual;
    final denominator = actual.abs(),
        scaled = error.abs() * BigInt.from(1000000);
    final q = denominator == BigInt.zero
        ? BigInt.zero
        : scaled ~/ denominator +
              ((scaled % denominator) * BigInt.two >= denominator
                  ? BigInt.one
                  : BigInt.zero);
    values[p.currency] = (
      error,
      denominator == BigInt.zero
          ? null
          : ExactRatio(
              error.abs(),
              denominator,
              exactHistoricalAmount(q),
              null,
            ),
    );
  }
  if (realized.keys.any((k) => !seen.contains(k))) {
    throw const FormatException(
      'Realized currency differs from frozen forecast.',
    );
  }
  return Map.unmodifiable(values);
}
