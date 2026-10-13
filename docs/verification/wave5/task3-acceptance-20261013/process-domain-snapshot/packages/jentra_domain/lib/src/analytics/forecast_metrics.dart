import '../exact_decimal.dart';
import 'process_metrics.dart';

BigInt _roundQuotient(BigInt numerator, BigInt denominator) {
  if (denominator <= BigInt.zero) {
    throw const FormatException('Positive denominator required.');
  }
  final magnitude = numerator.abs(),
      q = magnitude ~/ denominator,
      r = magnitude % denominator;
  return (r * BigInt.two >= denominator ? q + BigInt.one : q) *
      BigInt.from(numerator.sign);
}

ExactDecimal _decimal(String s) {
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,13})(?:\.[0-9]{1,6})?$').hasMatch(s)) {
    throw const FormatException(
      'An exact bounded nonnegative decimal is required.',
    );
  }
  return ExactDecimal.parse(s, scale: 6);
}

String _uuid(String value) {
  ProcessMetricScope(tenantId: value, legalEntityId: value);
  return value;
}

final class ForecastOpportunity {
  ForecastOpportunity({
    required String id,
    required String version,
    required this.scope,
    required String amount,
    required String probability,
    required this.currency,
    required String expectedCloseDate,
  }) : id = _uuid(id),
       version = BigInt.parse(version),
       amount = _decimal(amount),
       probability = _decimal(probability),
       expectedClose = parseProcessMetricUtc('${expectedCloseDate}T00:00:00Z') {
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(version) ||
        this.version > BigInt.parse('9223372036854775807') ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        this.probability.scaledValue > BigInt.from(100000000)) {
      throw const FormatException(
        'Invalid opportunity revision, currency or probability.',
      );
    }
  }
  final String id, currency;
  final BigInt version;
  final ProcessMetricScope scope;
  final ExactDecimal amount, probability;
  final DateTime expectedClose;
  BigInt get weightedUnits => _roundQuotient(
    amount.scaledValue * probability.scaledValue,
    BigInt.from(100000000),
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version.toString(),
    'tenantId': scope.tenantId,
    'legalEntityId': scope.legalEntityId,
    'branchId': scope.branchId,
    'amount': amount.toDecimalString(),
    'probability': probability.toDecimalString(),
    'currency': currency,
    'expectedCloseDate': expectedClose.toIso8601String().substring(0, 10),
  };
}

final class CurrencyForecast {
  const CurrencyForecast(
    this.currency,
    this.population,
    this.amountUnits,
    this.weightedUnits,
  );
  final String currency;
  final int population;
  final BigInt amountUnits, weightedUnits;
  String get amount =>
      ExactDecimal.fromScaledValue(amountUnits, scale: 6).toDecimalString();
  String get weightedAmount =>
      ExactDecimal.fromScaledValue(weightedUnits, scale: 6).toDecimalString();
}

/// Calculation accepts a complete provider selection; it does not authorize or certify one.
List<CurrencyForecast> calculatePipelineForecast(
  ProcessMetricScope scope,
  List<ForecastOpportunity> rows, {
  required String horizonStart,
  required String horizonEnd,
  required bool complete,
}) {
  final start = parseProcessMetricUtc('${horizonStart}T00:00:00Z'),
      end = parseProcessMetricUtc('${horizonEnd}T00:00:00Z');
  if (!complete ||
      !end.isAfter(start) ||
      end.difference(start) > const Duration(days: 366) ||
      rows.length > 10000) {
    throw const FormatException(
      'A complete bounded forecast cohort is required.',
    );
  }
  final ids = <String>{}, groups = <String, CurrencyForecast>{};
  for (final row in rows) {
    if (row.scope.tenantId != scope.tenantId ||
        row.scope.legalEntityId != scope.legalEntityId ||
        (scope.branchId != null && row.scope.branchId != scope.branchId) ||
        !ids.add(row.id) ||
        row.expectedClose.isBefore(start) ||
        !row.expectedClose.isBefore(end)) {
      throw const FormatException(
        'Forecast source scope, identity or horizon mismatch.',
      );
    }
    final prior = groups[row.currency];
    groups[row.currency] = CurrencyForecast(
      row.currency,
      (prior?.population ?? 0) + 1,
      (prior?.amountUnits ?? BigInt.zero) + row.amount.scaledValue,
      (prior?.weightedUnits ?? BigInt.zero) + row.weightedUnits,
    );
    if (groups.length > 100) {
      throw const FormatException('Too many forecast currency groups.');
    }
  }
  return List.unmodifiable(
    groups.keys.toList()..sort(),
  ).map((key) => groups[key]!).toList(growable: false);
}

final class StatementBasis {
  StatementBasis({
    required this.scope,
    required String publicationId,
    required this.currency,
    required String periodStart,
    required String periodEnd,
    required this.formulaVersion,
    required this.complete,
  }) : publicationId = _uuid(publicationId),
       periodStart = parseProcessMetricUtc('${periodStart}T00:00:00Z'),
       periodEnd = parseProcessMetricUtc('${periodEnd}T00:00:00Z') {
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        formulaVersion < 1 ||
        !this.periodEnd.isAfter(this.periodStart)) {
      throw const FormatException('Invalid publication basis.');
    }
  }
  final ProcessMetricScope scope;
  final String publicationId, currency;
  final DateTime periodStart, periodEnd;
  final int formulaVersion;
  final bool complete;
  bool matches(StatementBasis other) =>
      scope == other.scope &&
      publicationId == other.publicationId &&
      currency == other.currency &&
      periodStart == other.periodStart &&
      periodEnd == other.periodEnd &&
      formulaVersion == other.formulaVersion &&
      complete &&
      other.complete;
}

final class ExactRatio {
  const ExactRatio(
    this.numerator,
    this.denominator,
    this.exactValue,
    this.unavailableReason,
  );
  final BigInt numerator, denominator;
  final String? exactValue, unavailableReason;
}

ExactRatio calculateStatementRatio(
  StatementBasis numeratorBasis,
  StatementBasis denominatorBasis,
  BigInt numerator,
  BigInt denominator, {
  bool allowNegativeDenominator = false,
}) {
  if (!numeratorBasis.matches(denominatorBasis)) {
    throw const FormatException(
      'Statement publication bases must match and be complete.',
    );
  }
  if (denominator == BigInt.zero) {
    return ExactRatio(numerator, denominator, null, 'ZERO_DENOMINATOR');
  }
  if (denominator.isNegative && !allowNegativeDenominator) {
    return ExactRatio(numerator, denominator, null, 'NEGATIVE_DENOMINATOR');
  }
  final sign = denominator.sign;
  final scaled = _roundQuotient(
    numerator * BigInt.from(1000000) * BigInt.from(sign),
    denominator.abs(),
  );
  return ExactRatio(
    numerator,
    denominator,
    ExactDecimal.fromScaledValue(scaled, scale: 6).toDecimalString(),
    null,
  );
}
