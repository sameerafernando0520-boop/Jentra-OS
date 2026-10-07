import '../exact_decimal.dart';
import 'process_metrics.dart';

final class CashControl {
  CashControl({
    required this.scope,
    required this.accountId,
    required this.currency,
    required this.units,
    required String asOf,
    required String publicationId,
    required String sourceVersion,
  }) : asOf = parseProcessMetricUtc(asOf),
       publicationId = _sourceId(publicationId),
       sourceVersion = _sourceVersion(sourceVersion);
  final ProcessMetricScope scope;
  final String accountId, currency;
  final BigInt units;
  final DateTime asOf;
  final String publicationId, sourceVersion;
}

final class CashObligation {
  CashObligation({
    required this.scope,
    required this.provider,
    required this.id,
    required this.currency,
    required String dueDate,
    required this.remainingUnits,
    required this.inflow,
    required String publicationId,
    required String sourceVersion,
  }) : dueDate = parseProcessMetricUtc('${dueDate}T00:00:00Z'),
       publicationId = _sourceId(publicationId),
       sourceVersion = _sourceVersion(sourceVersion);
  final ProcessMetricScope scope;
  final String provider, id, currency;
  final DateTime dueDate;
  final BigInt remainingUnits;
  final bool inflow;
  final String publicationId, sourceVersion;
}

String _sourceId(String value) {
  ProcessMetricScope(tenantId: value, legalEntityId: value);
  return value;
}

String _sourceVersion(String value) {
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('Invalid cash source revision.');
  }
  return value;
}

final class CashBucket {
  const CashBucket(
    this.date,
    this.currency,
    this.inflow,
    this.outflow,
    this.balance,
  );
  final DateTime date;
  final String currency;
  final BigInt inflow, outflow, balance;
  String get exactBalance =>
      ExactDecimal.fromScaledValue(balance, scale: 6).toDecimalString();
}

final class CashScenario {
  const CashScenario._(this.buckets, this.unavailableProviders);
  final List<CashBucket> buckets;
  final List<String> unavailableProviders;
  bool get available => unavailableProviders.isEmpty;
  static CashScenario calculate({
    required ProcessMetricScope scope,
    required String horizonStart,
    required String horizonEnd,
    required Set<String> requiredProviders,
    required Set<String> completeProviders,
    required List<CashControl> controls,
    required List<CashObligation> obligations,
  }) {
    const allowed = {
      'bank_cash',
      'receivables',
      'payables',
      'payroll',
      'project_expenses',
    };
    if (!allowed.containsAll(requiredProviders) ||
        !allowed.containsAll(completeProviders) ||
        !requiredProviders.contains('bank_cash')) {
      throw const FormatException('Unsupported cash provider contract.');
    }
    final start = parseProcessMetricUtc('${horizonStart}T00:00:00Z'),
        end = parseProcessMetricUtc('${horizonEnd}T00:00:00Z');
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366) ||
        controls.length + obligations.length > 10000) {
      throw const FormatException(
        'Cash scenario exceeds a complete bounded horizon.',
      );
    }
    final missing = requiredProviders.difference(completeProviders).toList()
      ..sort();
    if (missing.isNotEmpty) {
      return CashScenario._(const [], List.unmodifiable(missing));
    }
    final identities = <String>{},
        opening = <String, BigInt>{},
        flows = <String, (BigInt, BigInt)>{};
    bool same(ProcessMetricScope s) =>
        s.tenantId == scope.tenantId &&
        s.legalEntityId == scope.legalEntityId &&
        (scope.branchId == null || s.branchId == scope.branchId);
    void identity(String id) {
      ProcessMetricScope(tenantId: id, legalEntityId: id);
    }

    void currency(String c) {
      if (!RegExp(r'^[A-Z]{3}$').hasMatch(c)) {
        throw const FormatException('Invalid cash currency.');
      }
    }

    for (final c in controls) {
      identity(c.accountId);
      currency(c.currency);
      if (!same(c.scope) ||
          c.asOf != start ||
          !identities.add('control:${c.accountId}')) {
        throw const FormatException('Duplicate or foreign cash control.');
      }
      opening[c.currency] = (opening[c.currency] ?? BigInt.zero) + c.units;
    }
    for (final o in obligations) {
      identity(o.id);
      currency(o.currency);
      if (!same(o.scope) ||
          !requiredProviders.contains(o.provider) ||
          o.provider == 'bank_cash' ||
          o.inflow != (o.provider == 'receivables') ||
          o.remainingUnits.isNegative ||
          o.dueDate.isBefore(start) ||
          !o.dueDate.isBefore(end) ||
          !identities.add('${o.provider}:${o.id}')) {
        throw const FormatException(
          'Invalid, duplicate or foreign remaining obligation.',
        );
      }
      // A dated-control basis is required even for a zero balance in a currency.
      if (!opening.containsKey(o.currency)) {
        throw const FormatException('Missing currency cash control.');
      }
      final key = '${o.currency}:${o.dueDate.toIso8601String()}',
          prior = flows[key] ?? (BigInt.zero, BigInt.zero);
      flows[key] = (
        prior.$1 + (o.inflow ? o.remainingUnits : BigInt.zero),
        prior.$2 + (o.inflow ? BigInt.zero : o.remainingUnits),
      );
    }
    if (opening.length > 100) {
      throw const FormatException('Too many cash currency groups.');
    }
    final result = <CashBucket>[], currencies = opening.keys.toList()..sort();
    for (final c in currencies) {
      var balance = opening[c]!;
      for (
        var date = start;
        date.isBefore(end);
        date = date.add(const Duration(days: 1))
      ) {
        final flow =
            flows['$c:${date.toIso8601String()}'] ?? (BigInt.zero, BigInt.zero);
        balance += flow.$1 - flow.$2;
        result.add(CashBucket(date, c, flow.$1, flow.$2, balance));
      }
    }
    // 100 currencies x 366 days is an explicit bounded pure result. Export and
    // source permission/completeness are established by the trusted adapter.
    return CashScenario._(List.unmodifiable(result), const []);
  }
}
