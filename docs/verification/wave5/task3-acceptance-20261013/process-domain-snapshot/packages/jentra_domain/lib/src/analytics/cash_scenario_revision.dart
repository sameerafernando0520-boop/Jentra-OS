import 'cash_scenarios.dart';
import 'process_metrics.dart';

/// Immutable user assumptions affect projections only. Source values are never
/// rewritten; an override references one original obligation and records why.
final class CashScenarioRevision {
  CashScenarioRevision({
    required this.id,
    required this.scope,
    required this.sourceHash,
    required this.horizonStart,
    required this.horizonEnd,
    required this.recordedThrough,
    required Map<String, Map<String, String>> overrides,
  }) : overrides = Map.unmodifiable(
         overrides.map(
           (k, v) => MapEntry(k, Map<String, String>.unmodifiable(v)),
         ),
       ) {
    ProcessMetricScope(tenantId: id, legalEntityId: id);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceHash) ||
        overrides.length > 10000) {
      throw const FormatException('Invalid scenario basis.');
    }
    parseProcessMetricUtc(recordedThrough);
    final start = parseProcessMetricUtc('${horizonStart}T00:00:00Z'),
        end = parseProcessMetricUtc('${horizonEnd}T00:00:00Z');
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366)) {
      throw const FormatException('Invalid scenario horizon.');
    }
    for (final entry in overrides.entries) {
      ProcessMetricScope(tenantId: entry.key, legalEntityId: entry.key);
      final v = entry.value;
      if (v.length != 3 ||
          !v.keys.toSet().containsAll({
            'dueDate',
            'remainingUnits',
            'reasonCode',
          }) ||
          !RegExp(r'^(0|[1-9][0-9]{0,19})$').hasMatch(v['remainingUnits']!) ||
          !{
            'collection_delay',
            'payment_delay',
            'reviewed_amount',
          }.contains(v['reasonCode'])) {
        throw const FormatException('Invalid immutable scenario override.');
      }
      final date = parseProcessMetricUtc('${v['dueDate']}T00:00:00Z');
      if (date.isBefore(start) || !date.isBefore(end)) {
        throw const FormatException('Override date outside scenario.');
      }
    }
  }
  final String id, sourceHash, horizonStart, horizonEnd, recordedThrough;
  final ProcessMetricScope scope;
  final Map<String, Map<String, String>> overrides;
  List<CashObligation> apply(List<CashObligation> obligations) {
    final seen = <String>{};
    final rows = obligations
        .map((o) {
          if (!seen.add(o.id)) {
            throw const FormatException(
              'Scenario source identity is ambiguous across providers.',
            );
          }
          final v = overrides[o.id];
          if (v == null) return o;
          return CashObligation(
            scope: o.scope,
            provider: o.provider,
            id: o.id,
            currency: o.currency,
            dueDate: v['dueDate']!,
            remainingUnits: BigInt.parse(v['remainingUnits']!),
            inflow: o.inflow,
            publicationId: o.publicationId,
            sourceVersion: o.sourceVersion,
          );
        })
        .toList(growable: false);
    if (!seen.containsAll(overrides.keys)) {
      throw const FormatException(
        'Scenario override lacks an authorized source.',
      );
    }
    return List.unmodifiable(rows);
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceHash': sourceHash,
    'horizonStart': horizonStart,
    'horizonEnd': horizonEnd,
    'recordedThrough': recordedThrough,
    'overrides': overrides,
  };
  static CashScenarioRevision fromJson(
    ProcessMetricScope scope,
    Map<String, Object?> wire,
  ) {
    if (wire.length != 6 || wire['overrides'] is! Map) {
      throw const FormatException('Invalid saved scenario.');
    }
    final overrides = <String, Map<String, String>>{};
    for (final entry in (wire['overrides'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid saved override.');
      }
      overrides[entry.key as String] = (entry.value as Map).map((k, v) {
        if (k is! String || v is! String) {
          throw const FormatException('Exact scenario parameter required.');
        }
        return MapEntry(k, v);
      });
    }
    return CashScenarioRevision(
      id: wire['id'] as String,
      scope: scope,
      sourceHash: wire['sourceHash'] as String,
      horizonStart: wire['horizonStart'] as String,
      horizonEnd: wire['horizonEnd'] as String,
      recordedThrough: wire['recordedThrough'] as String,
      overrides: overrides,
    );
  }
}
