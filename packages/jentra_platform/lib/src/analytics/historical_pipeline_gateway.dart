import 'dart:convert';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show ExactDecimal;
import 'process_metric_gateway.dart';
import 'process_metric_hasher.dart';

final class HistoricalPipelineGateway {
  HistoricalPipelineGateway(this.rpc);
  final ProcessMetricRpc rpc;
  Future<Map<String, (BigInt, ExactRatio?)>> accuracy(
    FrozenPipelineForecast frozen,
    String asOf,
  ) async {
    final scope = frozen.scope, cutoff = parseProcessMetricUtc(asOf);
    if (cutoff.isBefore(
          parseProcessMetricUtc('${frozen.horizonEnd}T00:00:00Z'),
        ) ||
        !frozen.observedAt.isBefore(
          parseProcessMetricUtc('${frozen.horizonEnd}T00:00:00Z'),
        )) {
      throw const FormatException('Realized horizon remains open.');
    }
    final raw = await rpc('wave5_pipeline_realized', {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_forecast_id': frozen.id,
      'p_as_of': asOf,
    });
    if (raw is! Map<String, Object?> ||
        raw.length != 7 ||
        raw['contractRevision'] != 1 ||
        raw['forecastId'] != frozen.id ||
        raw['sourceHash'] != frozen.sourceHash ||
        raw['definition'] !=
            'posted_invoice_less_order_linked_credit_gross.v1' ||
        raw['complete'] != true ||
        raw['asOf'] is! String ||
        parseProcessMetricUtc(raw['asOf'] as String) != cutoff ||
        raw['documents'] is! List ||
        (raw['documents'] as List).length > 10000 ||
        utf8.encode(jsonEncode(raw)).length > 8388608) {
      throw const FormatException('Realized basis differs from frozen cohort.');
    }
    final sums = <String, BigInt>{}, ids = <String>{};
    final cohort = {
      for (final observation in frozen.observations)
        observation.id: observation.currency,
    };
    for (final rawRow in raw['documents'] as List) {
      if (rawRow is! Map || rawRow.length != 8) {
        throw const FormatException('Invalid realized document.');
      }
      final r = rawRow.cast<String, Object?>(), id = r['id'] as String;
      ProcessMetricScope(tenantId: id, legalEntityId: id);
      ProcessMetricScope(
        tenantId: scope.tenantId,
        legalEntityId: scope.legalEntityId,
        branchId: r['branchId'] as String?,
      );
      final amount = r['amount'] as String, currency = r['currency'] as String;
      if (!ids.add(id) ||
          !cohort.containsKey(r['opportunityId']) ||
          cohort[r['opportunityId']] != currency ||
          (scope.branchId != null && r['branchId'] != scope.branchId) ||
          !RegExp(
            r'^-?(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$',
          ).hasMatch(amount) ||
          !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
          !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(r['version'] as String) ||
          BigInt.parse(r['version'] as String) >
              BigInt.parse('9223372036854775807') ||
          parseProcessMetricUtc(r['postedAt'] as String).isAfter(cutoff) ||
          !{'invoice', 'credit_return'}.contains(r['kind'])) {
        throw const FormatException('Invalid realized mapping.');
      }
      final units = ExactDecimal.parse(amount, scale: 6).scaledValue;
      if (units.isNegative != (r['kind'] == 'credit_return') &&
          units != BigInt.zero) {
        throw const FormatException('Realized sign mismatch.');
      }
      sums[currency] = (sums[currency] ?? BigInt.zero) + units;
    }
    return calculateForecastAccuracy(frozen.currencies, sums, complete: true);
  }

  Future<HistoricalPipelineMetrics> read(
    ProcessMetricScope scope,
    String asOf,
    String recordedThrough,
  ) async {
    final businessCutoff = parseProcessMetricUtc(asOf);
    final recordedCutoff = parseProcessMetricUtc(recordedThrough);
    if (businessCutoff.isAfter(recordedCutoff)) {
      throw const FormatException(
        'Business cutoff must not exceed the recorded cutoff.',
      );
    }
    final raw = await rpc('wave5_pipeline_history', {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
      'p_as_of': asOf,
      'p_recorded_through': recordedThrough,
    });
    if (raw is! Map<String, Object?> ||
        raw.length != 2 ||
        raw['canonicalText'] is! String ||
        raw['sourceHash'] is! String) {
      throw const FormatException('Invalid historical publication.');
    }
    final canonical = raw['canonicalText'] as String;
    if (utf8.encode(canonical).length > 8388608 ||
        await ProcessMetricSha256Hasher().sha256(utf8.encode(canonical)) !=
            raw['sourceHash']) {
      throw const FormatException('Historical publication digest mismatch.');
    }
    final data = jsonDecode(canonical) as Map<String, dynamic>;
    final s = data['scope'];
    if (data.length != 7 ||
        data['contractRevision'] != 1 ||
        data['sourceContract'] != 'crm.pipeline_history.v1' ||
        s is! Map ||
        s.length != 3 ||
        s['tenantId'] != scope.tenantId ||
        s['legalEntityId'] != scope.legalEntityId ||
        s['branchId'] != scope.branchId ||
        parseProcessMetricUtc(data['asOf'] as String) != businessCutoff ||
        parseProcessMetricUtc(data['recordedThrough'] as String) !=
            recordedCutoff ||
        data['complete'] != true ||
        data['revisions'] is! List) {
      throw const FormatException('Historical basis mismatch.');
    }
    final rows = <PipelineRevision>[];
    for (final value in data['revisions'] as List) {
      final r = value as Map<String, dynamic>;
      if (r.length != 14) {
        throw const FormatException('Invalid history fields.');
      }
      rows.add(
        PipelineRevision(
          id: r['id'] as String,
          revisionId: r['revisionId'] as String,
          version: BigInt.parse(r['version'] as String),
          scope: ProcessMetricScope(
            tenantId: r['tenantId'] as String,
            legalEntityId: r['legalEntityId'] as String,
            branchId: r['branchId'] as String?,
          ),
          recordedAt: parseProcessMetricUtc(r['recordedAt'] as String),
          createdAt: parseProcessMetricUtc(r['createdAt'] as String),
          stage: r['stage'] as String,
          status: r['status'] as String,
          ownerId: r['ownerId'] as String,
          amount: _decimal(r['amount']),
          probability: _decimal(r['probability']),
          currency: r['currency'] as String,
        ),
      );
    }
    return calculateHistoricalPipeline(
      scope,
      rows,
      businessCutoff,
      complete: true,
    );
  }

  BigInt _decimal(Object? value) {
    if (value is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(value)) {
      throw const FormatException('Exact bounded historical decimal required.');
    }
    return ExactDecimal.parse(value, scale: 6).scaledValue;
  }
}
