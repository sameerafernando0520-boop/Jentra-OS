import 'employee.dart';
import 'money.dart';
import 'work_time.dart';

final _projectMoneyBound = BigInt.parse('99999999999999999999');
String projectUuid(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(value)) {
    throw const FormatException('Project identity must be a canonical UUID.');
  }
  return value;
}

Money projectAmount(String value, String currency) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,13})(\.[0-9]{1,6})?$').hasMatch(value) ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
    throw const FormatException(
      'Project amounts require exact nonnegative decimal strings and one currency.',
    );
  }
  return Money.parse(value, currency);
}

void _money(Money value, {bool positive = false}) {
  if (value.minorUnits < (positive ? BigInt.one : BigInt.zero) ||
      value.minorUnits > _projectMoneyBound) {
    throw const FormatException(
      'Project amount exceeds its original money contract.',
    );
  }
}

void _integer(int value, {bool positive = false}) {
  if (value < (positive ? 1 : 0) || value > maxExactWorkInteger) {
    throw const FormatException('Project integer exceeds its exact contract.');
  }
}

BigInt _quantum(int precision) {
  if (precision < 0 || precision > Money.scale) {
    throw const FormatException(
      'Project precision must be published between zero and six.',
    );
  }
  return BigInt.from(10).pow(Money.scale - precision);
}

BigInt projectRoundRatio(BigInt numerator, BigInt denominator, int precision) {
  if (denominator <= BigInt.zero) {
    throw const FormatException(
      'Project rational denominator must be positive.',
    );
  }
  final quantum = _quantum(precision), divisor = denominator * quantum;
  var units = numerator ~/ divisor;
  final remainder = numerator.remainder(divisor).abs();
  if (remainder * BigInt.two > divisor ||
      remainder * BigInt.two == divisor && units.abs().isOdd) {
    units += BigInt.from(numerator.sign);
  }
  return units * quantum;
}

Money projectTimeAmount(Money hourlyRate, int payableSeconds, int precision) {
  _money(hourlyRate);
  if (payableSeconds < 1 || payableSeconds > maxWorkSeconds) {
    throw const FormatException(
      'Project work requires a bounded positive whole-second interval.',
    );
  }
  final result = Money.fromMinorUnits(
    projectRoundRatio(
      hourlyRate.minorUnits * BigInt.from(payableSeconds),
      BigInt.from(3600),
      precision,
    ),
    hourlyRate.currencyCode,
  );
  _money(result);
  return result;
}

/// Explicit versioned expense conversion. Identity currency uses no fabricated rate.
final class ProjectExpenseFx {
  ProjectExpenseFx({
    required this.originalCurrency,
    required this.baseCurrency,
    required this.numerator,
    required this.denominator,
    required this.precision,
    required this.rateId,
    required this.rateVersion,
  }) {
    projectAmount('0', originalCurrency);
    projectAmount('0', baseCurrency);
    _integer(numerator, positive: true);
    _integer(denominator, positive: true);
    _quantum(precision);
    if (originalCurrency == baseCurrency) {
      if (numerator != denominator || rateId != null || rateVersion != null) {
        throw const FormatException(
          'Identity expense currency must retain a one-to-one basis without an external rate.',
        );
      }
    } else {
      if (rateId == null || rateVersion == null) {
        throw const FormatException(
          'Foreign expense currency requires its original versioned rate.',
        );
      }
      projectUuid(rateId!);
      _integer(rateVersion!, positive: true);
    }
  }
  final String originalCurrency, baseCurrency;
  final int numerator, denominator, precision;
  final String? rateId;
  final int? rateVersion;
  Money convert(Money value) {
    _money(value);
    if (value.currencyCode != originalCurrency) {
      throw const FormatException(
        'Expense currency differs from its frozen rate.',
      );
    }
    final amount = Money.fromMinorUnits(
      projectRoundRatio(
        value.minorUnits * BigInt.from(numerator),
        BigInt.from(denominator),
        precision,
      ),
      baseCurrency,
    );
    _money(amount);
    return amount;
  }
}

final class ProjectExpenseBasis {
  ProjectExpenseBasis({
    required this.net,
    required this.tax,
    required this.gross,
    required this.fx,
    required this.originalPrecision,
    required this.taxDefinitionId,
    required this.taxDefinitionVersion,
    required this.noTaxReason,
  }) {
    final quantum = _quantum(originalPrecision);
    for (final value in [net, tax, gross]) {
      _money(value);
      if (value.currencyCode != fx.originalCurrency ||
          value.minorUnits % quantum != BigInt.zero) {
        throw const FormatException(
          'Expense source amounts must retain their currency and published precision.',
        );
      }
    }
    if (net + tax != gross || gross.minorUnits <= BigInt.zero) {
      throw const FormatException(
        'Expense source net and tax must conserve its positive original gross.',
      );
    }
    if (taxDefinitionId == null) {
      if (taxDefinitionVersion != null ||
          tax.minorUnits != BigInt.zero ||
          noTaxReason == null ||
          noTaxReason!.trim().isEmpty ||
          noTaxReason!.length > 1000) {
        throw const FormatException(
          'An expense without a tax definition requires zero tax and explicit evidence.',
        );
      }
    } else {
      projectUuid(taxDefinitionId!);
      if (taxDefinitionVersion == null || noTaxReason != null) {
        throw const FormatException(
          'Expense tax requires its exact definition version.',
        );
      }
      _integer(taxDefinitionVersion!, positive: true);
    }
    baseGross = fx.convert(gross);
    baseNet = fx.convert(net);
    baseTax = baseGross - baseNet;
    taxRoundingResidue = baseTax - fx.convert(tax);
  }
  final Money net, tax, gross;
  final ProjectExpenseFx fx;
  final int originalPrecision;
  final String? taxDefinitionId, noTaxReason;
  final int? taxDefinitionVersion;
  late final Money baseNet, baseTax, baseGross, taxRoundingResidue;
}

final class ProjectAllocationWeight {
  ProjectAllocationWeight(this.id, this.weight) {
    projectUuid(id);
    _integer(weight, positive: true);
  }
  final String id;
  final int weight;
}

final class ProjectExpenseAllocation {
  const ProjectExpenseAllocation(
    this.id,
    this.ordinal,
    this.weight,
    this.amount,
  );
  final String id;
  final int ordinal, weight;
  final Money amount;
}

List<ProjectExpenseAllocation> allocateProjectExpense(
  Money originalTotal,
  List<ProjectAllocationWeight> weights,
  int precision,
) {
  _money(originalTotal);
  final quantum = _quantum(precision);
  if (originalTotal.minorUnits % quantum != BigInt.zero ||
      weights.isEmpty ||
      weights.length > 50 ||
      weights.map((v) => v.id).toSet().length != weights.length) {
    throw const FormatException(
      'Expense allocations require a published total and one to fifty unique ordered weights.',
    );
  }
  final total = weights.fold(
    BigInt.zero,
    (sum, v) => sum + BigInt.from(v.weight),
  );
  if (total > BigInt.from(maxExactWorkInteger)) {
    throw const FormatException(
      'Expense weight total exceeds the exact bound.',
    );
  }
  var cumulative = BigInt.zero, allocated = BigInt.zero;
  final result = <ProjectExpenseAllocation>[];
  for (var i = 0; i < weights.length; i++) {
    cumulative += BigInt.from(weights[i].weight);
    final rounded = projectRoundRatio(
      originalTotal.minorUnits * cumulative,
      total,
      precision,
    );
    result.add(
      ProjectExpenseAllocation(
        weights[i].id,
        i + 1,
        weights[i].weight,
        Money.fromMinorUnits(rounded - allocated, originalTotal.currencyCode),
      ),
    );
    allocated = rounded;
  }
  if (allocated != originalTotal.minorUnits) {
    throw const FormatException('Expense allocation lost original money.');
  }
  return List.unmodifiable(result);
}

final class ProjectTaskBasis {
  ProjectTaskBasis({
    required this.id,
    required this.projectId,
    required this.ownerId,
    required this.start,
    required this.endExclusive,
    required this.plannedSeconds,
    required this.progressBasisPoints,
    required Iterable<String> dependencies,
  }) : dependencies = List.unmodifiable(dependencies) {
    projectUuid(id);
    projectUuid(projectId);
    projectUuid(ownerId);
    _integer(plannedSeconds);
    if (start.compareTo(endExclusive) >= 0 ||
        plannedSeconds > endExclusive.utc.difference(start.utc).inSeconds ||
        progressBasisPoints < 0 ||
        progressBasisPoints > 10000 ||
        this.dependencies.length > 50 ||
        this.dependencies.toSet().length != this.dependencies.length) {
      throw const FormatException(
        'Project task dates, planned time, progress or dependency bound is invalid.',
      );
    }
    for (final dependency in this.dependencies) {
      projectUuid(dependency);
      if (dependency == id) {
        throw const FormatException('A project task cannot depend on itself.');
      }
    }
  }
  final String id, projectId, ownerId;
  final CivilDate start, endExclusive;
  final int plannedSeconds, progressBasisPoints;
  final List<String> dependencies;
}

final class ProjectTaskGraph {
  ProjectTaskGraph(this.projectId, Iterable<ProjectTaskBasis> tasks)
    : tasks = List.unmodifiable(tasks) {
    projectUuid(projectId);
    if (this.tasks.length > 200 ||
        this.tasks.map((v) => v.id).toSet().length != this.tasks.length ||
        this.tasks.any((v) => v.projectId != projectId)) {
      throw const FormatException(
        'Project task graph scope, identity or size is invalid.',
      );
    }
    final byId = {for (final t in this.tasks) t.id: t},
        visited = <String>{},
        active = <String>{},
        ordered = <ProjectTaskBasis>[];
    void visit(String id) {
      if (active.contains(id)) {
        throw const FormatException(
          'Project task dependencies contain a cycle.',
        );
      }
      if (visited.contains(id)) return;
      final task = byId[id];
      if (task == null) {
        throw const FormatException(
          'Project dependency must reference a task in the same project.',
        );
      }
      active.add(id);
      final dependencies = [...task.dependencies]..sort();
      for (final dependency in dependencies) {
        visit(dependency);
      }
      active.remove(id);
      visited.add(id);
      ordered.add(task);
    }

    final ids = byId.keys.toList()..sort();
    for (final id in ids) {
      visit(id);
    }
    topological = List.unmodifiable(ordered);
  }
  final String projectId;
  final List<ProjectTaskBasis> tasks;
  late final List<ProjectTaskBasis> topological;
}

enum ProjectBillingSource { time, expense, milestone, service }

final class ProjectBillableUnit {
  ProjectBillableUnit({
    required this.id,
    required this.projectId,
    required this.source,
    required this.sourceId,
    required this.sourceVersion,
    required this.digest,
    required this.amount,
    required this.precision,
    this.payableSeconds,
  }) {
    projectUuid(id);
    projectUuid(projectId);
    projectUuid(sourceId);
    _integer(sourceVersion, positive: true);
    _money(amount);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        amount.minorUnits % _quantum(precision) != BigInt.zero ||
        {
              ProjectBillingSource.time,
              ProjectBillingSource.service,
            }.contains(source) &&
            (payableSeconds == null ||
                payableSeconds! < 1 ||
                payableSeconds! > maxWorkSeconds) ||
        !{
              ProjectBillingSource.time,
              ProjectBillingSource.service,
            }.contains(source) &&
            payableSeconds != null) {
      throw const FormatException(
        'Project billing unit must retain its exact approved amount, version, digest and whole-second time basis.',
      );
    }
  }
  final String id, projectId, sourceId, digest;
  final ProjectBillingSource source;
  final int sourceVersion, precision;
  final int? payableSeconds;
  final Money amount;
  String get salesQuantity => '1.000000';
}

List<ProjectBillableUnit> projectBillingSelection(
  String projectId,
  String currency,
  Iterable<ProjectBillableUnit> values,
) {
  projectUuid(projectId);
  projectAmount('0', currency);
  final units = List<ProjectBillableUnit>.of(values), sources = <String>{};
  if (units.isEmpty ||
      units.length > 200 ||
      units.map((v) => v.id).toSet().length != units.length) {
    throw const FormatException(
      'A project billing batch requires one to two hundred distinct whole units.',
    );
  }
  for (final unit in units) {
    if (unit.projectId != projectId ||
        unit.amount.currencyCode != currency ||
        !sources.add('${unit.source.name}/${unit.sourceId}')) {
      throw const FormatException(
        'Project billing cannot mix scopes, currencies or duplicate a source.',
      );
    }
  }
  units.sort((a, b) => a.id.compareTo(b.id));
  return List.unmodifiable(units);
}

final class ProjectClosureBasis {
  ProjectClosureBasis({
    required this.openTasks,
    required this.pendingChanges,
    required this.unbilledUnits,
    required this.openBillingBatches,
    required this.openExpenseLiabilities,
  }) {
    for (final n in [
      openTasks,
      pendingChanges,
      unbilledUnits,
      openBillingBatches,
      openExpenseLiabilities,
    ]) {
      _integer(n);
    }
  }
  final int openTasks,
      pendingChanges,
      unbilledUnits,
      openBillingBatches,
      openExpenseLiabilities;
  bool get resolved =>
      openTasks == 0 &&
      pendingChanges == 0 &&
      unbilledUnits == 0 &&
      openBillingBatches == 0 &&
      openExpenseLiabilities == 0;
  void requireResolved() {
    if (!resolved) {
      throw const FormatException(
        'Project closure requires explicit resolution of tasks, changes, unbilled work and expense/billing obligations.',
      );
    }
  }
}
