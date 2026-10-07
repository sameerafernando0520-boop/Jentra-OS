import 'dart:convert';
import 'forecast_metrics.dart';
import 'process_metrics.dart';

void _keys(Map<String, Object?> value, Set<String> keys) {
  if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) {
    throw const FormatException('Unsupported forecast projection.');
  }
}

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  throw const FormatException('Unsupported forecast wire value.');
}

final class FrozenPipelineForecast {
  FrozenPipelineForecast._(
    this.id,
    this.sourceHash,
    this.scope,
    this.observedAt,
    this.horizonStart,
    this.horizonEnd,
    this.observations,
    this.currencies,
  );
  final String id, sourceHash, horizonStart, horizonEnd;
  final ProcessMetricScope scope;
  final DateTime observedAt;
  final List<ForecastOpportunity> observations;
  final List<CurrencyForecast> currencies;
  static Future<FrozenPipelineForecast> verify(
    Map<String, Object?> raw,
    ProcessMetricScope scope,
    String id,
    ProcessMetricHasher hasher,
  ) async {
    _keys(raw, {'id', 'sourceHash', 'canonicalText', 'evidence'});
    if (raw['id'] != id ||
        raw['sourceHash'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw['sourceHash'] as String) ||
        raw['canonicalText'] is! String ||
        raw['evidence'] is! Map<String, Object?>) {
      throw const FormatException('Invalid frozen forecast envelope.');
    }
    ProcessMetricScope(tenantId: id, legalEntityId: id);
    final bytes = utf8.encode(raw['canonicalText'] as String);
    if (bytes.length > 8388608 ||
        await hasher.sha256(bytes) != raw['sourceHash']) {
      throw const FormatException('Forecast digest mismatch.');
    }
    final e = raw['evidence'] as Map<String, Object?>;
    if (jsonEncode(_canonical(jsonDecode(raw['canonicalText'] as String))) !=
        jsonEncode(_canonical(e))) {
      throw const FormatException(
        'Forecast evidence differs from captured bytes.',
      );
    }
    _keys(e, {
      'tenantId',
      'legalEntityId',
      'branchId',
      'definitionCode',
      'definitionVersion',
      'sourceContract',
      'horizonStart',
      'horizonEnd',
      'asOf',
      'recordedThrough',
      'generatedAt',
      'complete',
      'sourceCount',
      'observations',
      'currencies',
      'unavailable',
    });
    if (e['tenantId'] != scope.tenantId ||
        e['legalEntityId'] != scope.legalEntityId ||
        e['branchId'] != scope.branchId ||
        e['definitionCode'] != 'pipeline.current_weighted' ||
        e['definitionVersion'] != 1 ||
        e['sourceContract'] != 'crm.opportunities.current.v1' ||
        e['complete'] != true ||
        e['sourceCount'] is! int ||
        e['observations'] is! List ||
        e['currencies'] is! List ||
        e['horizonStart'] is! String ||
        e['horizonEnd'] is! String ||
        e['asOf'] is! String ||
        e['recordedThrough'] != e['asOf'] ||
        e['generatedAt'] != e['asOf']) {
      throw const FormatException('Forecast scope or definition mismatch.');
    }
    final observed = parseProcessMetricUtc(e['asOf'] as String);
    final rawRows = e['observations'] as List;
    if (rawRows.length > 10000 || rawRows.length != e['sourceCount']) {
      throw const FormatException('Incomplete forecast manifest.');
    }
    final rows = <ForecastOpportunity>[];
    for (final rawRow in rawRows) {
      if (rawRow is! Map<String, Object?>) {
        throw const FormatException('Invalid forecast observation.');
      }
      _keys(rawRow, {
        'id',
        'version',
        'tenantId',
        'legalEntityId',
        'branchId',
        'amount',
        'probability',
        'currency',
        'expectedCloseDate',
      });
      if (rawRow.entries.any(
            (e) => e.key != 'branchId' && e.value is! String,
          ) ||
          (rawRow['branchId'] != null && rawRow['branchId'] is! String)) {
        throw const FormatException('Invalid exact forecast field.');
      }
      rows.add(
        ForecastOpportunity(
          id: rawRow['id'] as String,
          version: rawRow['version'] as String,
          scope: ProcessMetricScope(
            tenantId: rawRow['tenantId'] as String,
            legalEntityId: rawRow['legalEntityId'] as String,
            branchId: rawRow['branchId'] as String?,
          ),
          amount: rawRow['amount'] as String,
          probability: rawRow['probability'] as String,
          currency: rawRow['currency'] as String,
          expectedCloseDate: rawRow['expectedCloseDate'] as String,
        ),
      );
    }
    final totals = calculatePipelineForecast(
      scope,
      rows,
      horizonStart: e['horizonStart'] as String,
      horizonEnd: e['horizonEnd'] as String,
      complete: true,
    );
    final reported = e['currencies'] as List;
    if (reported.length != totals.length) {
      throw const FormatException('Forecast group mismatch.');
    }
    for (var i = 0; i < totals.length; i++) {
      final g = reported[i], t = totals[i];
      if (g is! Map<String, Object?>) {
        throw const FormatException('Invalid currency projection.');
      }
      _keys(g, {'currency', 'population', 'amount', 'weightedAmount'});
      if (g['currency'] != t.currency ||
          g['population'] != t.population ||
          g['amount'] != t.amount ||
          g['weightedAmount'] != t.weightedAmount) {
        throw const FormatException('Server and exact forecast totals differ.');
      }
    }
    if (jsonEncode(_canonical(e['unavailable'])) !=
        jsonEncode(
          _canonical({
            'aging': 'STAGE_HISTORY_UNAVAILABLE',
            'accuracy': 'REALIZED_MAPPING_UNAVAILABLE',
            'conversion': 'HISTORICAL_REVISIONS_UNAVAILABLE',
            'velocity': 'HISTORICAL_REVISIONS_UNAVAILABLE',
          }),
        )) {
      throw const FormatException('Unsupported historical metric projection.');
    }
    return FrozenPipelineForecast._(
      id,
      raw['sourceHash'] as String,
      scope,
      observed,
      e['horizonStart'] as String,
      e['horizonEnd'] as String,
      List.unmodifiable(rows),
      List.unmodifiable(totals),
    );
  }
}

abstract interface class PipelineForecastRepository {
  Future<void> authorize(ProcessMetricScope scope);
  Future<void> authorizeRecovery(ProcessMetricScope scope, String actorId);
  Future<String> freeze(
    ProcessMetricScope scope, {
    required String commandId,
    required String idempotencyKey,
    required String clientTimestamp,
    required String horizonStart,
    required String horizonEnd,
  });
  Future<FrozenPipelineForecast> get(ProcessMetricScope scope, String id);
}
