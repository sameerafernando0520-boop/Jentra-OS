import 'calendar_repository.dart';
import 'money.dart';
import 'payroll_calculation.dart';
import 'work_time.dart';

/// A server-supplied original seal or its latest immutable linked replacement.
final class SealedPayrollSource {
  SealedPayrollSource({
    required this.sealId,
    required this.revisionId,
    required this.version,
    required this.paidSeconds,
  }) {
    calendarUuid(sealId);
    calendarUuid(revisionId);
    if (version < 1 ||
        version >= maxExactWorkInteger ||
        paidSeconds < 0 ||
        paidSeconds > maxWorkSeconds) {
      throw const FormatException('Sealed payroll source bounds are invalid.');
    }
  }
  final String sealId, revisionId;
  final int version, paidSeconds;
}

final class PayrollSourceReplacement {
  PayrollSourceReplacement({
    required this.sealId,
    required this.beforeRevisionId,
    required this.expectedVersion,
    required this.replacementRevisionId,
    required this.paidSeconds,
  }) {
    calendarUuid(sealId);
    calendarUuid(beforeRevisionId);
    calendarUuid(replacementRevisionId);
    if (expectedVersion < 1 ||
        expectedVersion >= maxExactWorkInteger ||
        paidSeconds < 0 ||
        paidSeconds > maxWorkSeconds ||
        beforeRevisionId == replacementRevisionId) {
      throw const FormatException('Linked payroll replacement is invalid.');
    }
  }
  final String sealId, beforeRevisionId, replacementRevisionId;
  final int expectedVersion, paidSeconds;
}

final class PayrollDifferenceLine {
  const PayrollDifferenceLine(this.before, this.after);
  final PayrollCalculationLine before, after;
  Money get delta => after.amount - before.amount;
  String get ruleVersionId => before.rule.id;
  Map<String, Object?> toJson() => {
    'rule_version_id': ruleVersionId,
    'code': before.rule.code,
    'classification':
        before.rule.classification == PayrollClassification.employerCost
        ? 'employer_cost'
        : before.rule.classification.name,
    'before': before.toJson(),
    'after': after.toJson(),
    'difference': delta.toDecimalString(),
  };
}

final class PayrollDifference {
  const PayrollDifference({
    required this.correctionId,
    required this.originalCalculationId,
    required this.before,
    required this.after,
    required this.lines,
    required this.next,
  });
  final String correctionId, originalCalculationId;
  final PayrollCalculation before, after;
  final List<PayrollDifferenceLine> lines;
  final PayrollCorrectionChain next;
  Money get gross => after.gross - before.gross;
  Money get deductions => after.deductions - before.deductions;
  Money get employerCost => after.employerCost - before.employerCost;
  Money get net => after.net - before.net;
}

/// Pure reproduction only. Source approval, scope, seals and posting are checked
/// by the authoritative database adapter, never inferred from this preview.
final class PayrollCorrectionChain {
  factory PayrollCorrectionChain({
    required String originalCalculationId,
    required PayrollCalculationInput originalInput,
    required Iterable<PayrollRule> rules,
    required Iterable<SealedPayrollSource> sources,
  }) {
    calendarUuid(originalCalculationId);
    final frozenRules = List<PayrollRule>.unmodifiable(rules);
    final frozenSources = List<SealedPayrollSource>.unmodifiable(sources);
    if (frozenSources.length > 2000 ||
        frozenSources.map((s) => s.sealId).toSet().length !=
            frozenSources.length ||
        frozenSources.map((s) => s.revisionId).toSet().length !=
            frozenSources.length ||
        frozenSources.fold<int>(0, (n, s) => n + s.paidSeconds) !=
            originalInput.paidSeconds) {
      throw const FormatException(
        'Original payroll seals do not reconcile to frozen paid seconds.',
      );
    }
    final original = calculatePayroll(originalInput, frozenRules);
    return PayrollCorrectionChain._(
      originalCalculationId,
      originalInput,
      frozenRules,
      frozenSources,
      original,
      const {},
      Set.unmodifiable(frozenSources.map((s) => s.revisionId)),
    );
  }
  const PayrollCorrectionChain._(
    this.originalCalculationId,
    this.originalInput,
    this.rules,
    this.sources,
    this.current,
    this.appliedCorrectionIds,
    this._seenRevisionIds,
  );
  final String originalCalculationId;
  final PayrollCalculationInput originalInput;
  final List<PayrollRule> rules;
  final List<SealedPayrollSource> sources;
  final PayrollCalculation current;
  final Set<String> appliedCorrectionIds, _seenRevisionIds;

  PayrollDifference apply(
    String correctionId,
    Iterable<PayrollSourceReplacement> replacements,
  ) {
    calendarUuid(correctionId);
    final changes = List<PayrollSourceReplacement>.of(replacements);
    if (changes.isEmpty ||
        changes.length > 200 ||
        appliedCorrectionIds.length >= 2000 ||
        appliedCorrectionIds.contains(correctionId) ||
        changes.map((s) => s.sealId).toSet().length != changes.length ||
        changes.map((s) => s.replacementRevisionId).toSet().length !=
            changes.length) {
      throw const FormatException(
        'Payroll correction identity or job bounds changed.',
      );
    }
    final changed = {for (final s in changes) s.sealId: s};
    final nextSources = <SealedPayrollSource>[];
    final seen = Set<String>.of(_seenRevisionIds);
    for (final source in sources) {
      final change = changed.remove(source.sealId);
      if (change == null) {
        nextSources.add(source);
      } else {
        if (change.beforeRevisionId != source.revisionId ||
            change.expectedVersion != source.version ||
            !seen.add(change.replacementRevisionId)) {
          throw const FormatException(
            'Payroll source revision changed. Compare its latest linked facts.',
          );
        }
        nextSources.add(
          SealedPayrollSource(
            sealId: source.sealId,
            revisionId: change.replacementRevisionId,
            version: source.version + 1,
            paidSeconds: change.paidSeconds,
          ),
        );
      }
    }
    if (changed.isNotEmpty) {
      throw const FormatException(
        'Payroll correction must reference an original input seal.',
      );
    }
    final corrected = PayrollCalculationInput(
      employeeId: originalInput.employeeId,
      start: originalInput.start,
      endExclusive: originalInput.endExclusive,
      periodDays: originalInput.periodDays,
      eligibleDays: originalInput.eligibleDays,
      plannedSeconds: originalInput.plannedSeconds,
      paidSeconds: nextSources.fold<int>(0, (n, s) => n + s.paidSeconds),
    );
    final after = calculatePayroll(corrected, rules);
    final lines = List<PayrollDifferenceLine>.unmodifiable(
      List.generate(
        current.lines.length,
        (i) => PayrollDifferenceLine(current.lines[i], after.lines[i]),
      ),
    );
    final next = PayrollCorrectionChain._(
      originalCalculationId,
      originalInput,
      rules,
      List.unmodifiable(nextSources),
      after,
      Set.unmodifiable({...appliedCorrectionIds, correctionId}),
      Set.unmodifiable(seen),
    );
    return PayrollDifference(
      correctionId: correctionId,
      originalCalculationId: originalCalculationId,
      before: current,
      after: after,
      lines: lines,
      next: next,
    );
  }
}
