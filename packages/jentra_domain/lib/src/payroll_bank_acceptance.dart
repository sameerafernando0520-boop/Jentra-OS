import 'calendar_repository.dart';
import 'employee.dart';
import 'money.dart';
import 'payroll_repository.dart';

enum PayrollBankStatus { pending, settled, rejected, returned }

enum PayrollBankDirection { debit, credit }

/// Origin is assigned by the trusted server adapter, never by a browser claim.
/// This matcher does not authenticate a feed or verify a statement signature.
enum PayrollBankOrigin { unverifiedUpload, sandbox, verifiedLiveFeed }

enum PayrollBankMatch {
  awaitingEvidence,
  unverified,
  pending,
  matched,
  rejected,
  returned,
  reviewRequired,
}

void _token(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:/-]{0,159}$').hasMatch(value)) {
    throw const FormatException('Use a bounded opaque bank reference.');
  }
}

void _amount(Money value, {bool positive = true}) {
  if (value.minorUnits.isNegative ||
      positive && value.minorUnits == BigInt.zero ||
      value.minorUnits > BigInt.parse('99999999999999999999') ||
      value.minorUnits % BigInt.from(10000) != BigInt.zero) {
    throw const FormatException(
      'Bank amounts require exact cents within numeric(20,6).',
    );
  }
}

/// Immutable expectation captured from one approved payroll revision/obligation.
/// Tokens refer to protected bank mappings; account numbers are not needed here.
final class PayrollBankExpectation {
  PayrollBankExpectation({
    required this.tenantId,
    required this.entityId,
    required this.branchId,
    required this.runId,
    required this.revisionId,
    required this.runDigest,
    required this.obligationId,
    required this.instructionId,
    required this.bankConnectionId,
    required this.sourceAccountToken,
    required this.beneficiaryToken,
    required this.paymentReference,
    required this.amount,
    required this.requestedDate,
    required this.preparedBy,
    required this.approvedBy,
  }) {
    for (final id in [
      tenantId,
      entityId,
      branchId,
      runId,
      revisionId,
      obligationId,
      instructionId,
      bankConnectionId,
      preparedBy,
      approvedBy,
    ]) {
      calendarUuid(id);
    }
    payrollDigest(runDigest);
    for (final token in [
      sourceAccountToken,
      beneficiaryToken,
      paymentReference,
    ]) {
      _token(token);
    }
    _amount(amount);
    if (amount.currencyCode != 'LKR' || preparedBy == approvedBy) {
      throw const FormatException(
        'LKR payroll requires an independent approver.',
      );
    }
  }

  final String tenantId,
      entityId,
      branchId,
      runId,
      revisionId,
      runDigest,
      obligationId,
      instructionId,
      bankConnectionId,
      sourceAccountToken,
      beneficiaryToken,
      paymentReference,
      preparedBy,
      approvedBy;
  final Money amount;
  final CivilDate requestedDate;
}

/// A normalized bank observation, not a client-provided settlement command.
/// Sequences must be authoritative per bank transaction, not ingestion order.
final class PayrollBankObservation {
  PayrollBankObservation({
    required this.bankConnectionId,
    required this.eventId,
    required this.transactionId,
    required this.sequence,
    required this.sourceAccountToken,
    required this.beneficiaryToken,
    required this.paymentReference,
    required this.amount,
    required this.valueDate,
    required this.status,
    required this.direction,
    required this.origin,
    required this.evidenceDigest,
  }) {
    calendarUuid(bankConnectionId);
    for (final token in [
      eventId,
      transactionId,
      sourceAccountToken,
      beneficiaryToken,
      paymentReference,
    ]) {
      _token(token);
    }
    _amount(amount);
    payrollDigest(evidenceDigest);
    if (sequence < 1 || sequence > calendarMaxVersion) {
      throw const FormatException(
        'A bounded bank transaction sequence is required.',
      );
    }
  }

  final String bankConnectionId,
      eventId,
      transactionId,
      sourceAccountToken,
      beneficiaryToken,
      paymentReference,
      evidenceDigest;
  final int sequence;
  final Money amount;
  final CivilDate valueDate;
  final PayrollBankStatus status;
  final PayrollBankDirection direction;
  final PayrollBankOrigin origin;

  String get _eventKey => '$bankConnectionId/$eventId';
  String get _transactionKey => '$bankConnectionId/$transactionId';
  List<Object> get _economicFacts => [
    bankConnectionId,
    transactionId,
    sourceAccountToken,
    beneficiaryToken,
    paymentReference,
    amount,
    origin,
    direction,
  ];
  List<Object> get _facts => [
    ..._economicFacts,
    eventId,
    sequence,
    valueDate.value,
    status,
    evidenceDigest,
  ];
}

final class PayrollBankMatchLine {
  const PayrollBankMatchLine(this.expected, this.match, this.reason);
  final PayrollBankExpectation expected;
  final PayrollBankMatch match;
  final String reason;
}

final class PayrollBankReport {
  PayrollBankReport._(
    Iterable<PayrollBankMatchLine> lines,
    Iterable<String> issues,
  ) : lines = List.unmodifiable(lines),
      issues = List.unmodifiable(issues);
  final List<PayrollBankMatchLine> lines;
  final List<String> issues;

  /// Evidence consistency only. Current permissions, approvals, durable receipts,
  /// verified adapter provenance and atomic accounting acceptance are separate.
  bool get allEvidenceMatches =>
      issues.isEmpty &&
      lines.isNotEmpty &&
      lines.every((line) => line.match == PayrollBankMatch.matched);
  Money get expectedAmount =>
      lines.fold(Money.zero('LKR'), (sum, line) => sum + line.expected.amount);
  Money get matchedAmount => lines
      .where((line) => line.match == PayrollBankMatch.matched)
      .fold(Money.zero('LKR'), (sum, line) => sum + line.expected.amount);
}

bool _same(List<Object> a, List<Object> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

PayrollBankReport matchPayrollBankEvidence({
  required List<PayrollBankExpectation> expectations,
  required List<PayrollBankObservation> observations,
  required CivilDate asOf,
}) {
  if (expectations.isEmpty ||
      expectations.length > 200 ||
      observations.length > 2000) {
    throw const FormatException(
      'Match 1–200 obligations and at most 2,000 bank events.',
    );
  }
  final first = expectations.first;
  if (expectations.any(
        (e) =>
            e.tenantId != first.tenantId ||
            e.entityId != first.entityId ||
            e.branchId != first.branchId ||
            e.runId != first.runId ||
            e.revisionId != first.revisionId ||
            e.runDigest != first.runDigest,
      ) ||
      expectations.map((e) => e.instructionId).toSet().length !=
          expectations.length ||
      expectations.map((e) => e.obligationId).toSet().length !=
          expectations.length ||
      expectations
              .map((e) => '${e.bankConnectionId}/${e.paymentReference}')
              .toSet()
              .length !=
          expectations.length) {
    throw const FormatException(
      'Match one frozen scope/revision with unique obligations and references.',
    );
  }
  final issues = <String>[];
  final events = <String, PayrollBankObservation>{};
  for (final event in observations) {
    final old = events[event._eventKey];
    if (old != null && !_same(old._facts, event._facts)) {
      issues.add('A repeated bank event has conflicting evidence.');
    } else {
      events[event._eventKey] = event;
    }
  }
  final transactions = <String, List<PayrollBankObservation>>{};
  for (final event in events.values) {
    transactions.putIfAbsent(event._transactionKey, () => []).add(event);
    if (!expectations.any(
      (e) =>
          e.bankConnectionId == event.bankConnectionId &&
          e.paymentReference == event.paymentReference,
    )) {
      issues.add(
        'Bank evidence has an unmatched connection or payment reference.',
      );
    }
  }
  final invalidTransactions = <String>{};
  for (final entry in transactions.entries) {
    final history = entry.value
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (var i = 1; i < history.length; i++) {
      final prior = history[i - 1], next = history[i];
      final allowed =
          prior.status == next.status ||
          prior.status == PayrollBankStatus.pending &&
              {
                PayrollBankStatus.settled,
                PayrollBankStatus.rejected,
              }.contains(next.status) ||
          prior.status == PayrollBankStatus.settled &&
              next.status == PayrollBankStatus.returned;
      if (prior.sequence == next.sequence ||
          !_same(prior._economicFacts, next._economicFacts) ||
          !allowed ||
          next.valueDate.compareTo(prior.valueDate) < 0) {
        invalidTransactions.add(entry.key);
      }
    }
  }
  final lines = <PayrollBankMatchLine>[];
  for (final expected in expectations) {
    final candidates = transactions.entries
        .where(
          (entry) => entry.value.any(
            (event) =>
                event.bankConnectionId == expected.bankConnectionId &&
                event.paymentReference == expected.paymentReference,
          ),
        )
        .toList();
    PayrollBankMatchLine line(PayrollBankMatch match, String reason) =>
        PayrollBankMatchLine(expected, match, reason);
    if (issues.isNotEmpty ||
        candidates.length > 1 ||
        candidates.any((entry) => invalidTransactions.contains(entry.key))) {
      lines.add(
        line(
          PayrollBankMatch.reviewRequired,
          'Conflicting evidence or multiple transfer attempts need review.',
        ),
      );
      continue;
    }
    if (candidates.isEmpty) {
      lines.add(
        line(PayrollBankMatch.awaitingEvidence, 'No bank evidence received.'),
      );
      continue;
    }
    final history = candidates.single.value, latest = history.last;
    if (history.any(
      (event) =>
          event.direction != PayrollBankDirection.debit ||
          event.sourceAccountToken != expected.sourceAccountToken ||
          event.beneficiaryToken != expected.beneficiaryToken ||
          event.amount != expected.amount ||
          event.valueDate.compareTo(expected.requestedDate) < 0 ||
          event.valueDate.compareTo(asOf) > 0,
    )) {
      lines.add(
        line(
          PayrollBankMatch.reviewRequired,
          'Direction, account, beneficiary, amount, currency or value date differs.',
        ),
      );
      continue;
    }
    if (latest.origin != PayrollBankOrigin.verifiedLiveFeed) {
      lines.add(
        line(
          PayrollBankMatch.unverified,
          'Sandbox or uploaded evidence needs a verified live bank adapter.',
        ),
      );
      continue;
    }
    lines.add(switch (latest.status) {
      PayrollBankStatus.pending => line(
        PayrollBankMatch.pending,
        'Bank processing is pending.',
      ),
      PayrollBankStatus.settled => line(
        PayrollBankMatch.matched,
        'Settled bank evidence matches. Separate accounting acceptance is required.',
      ),
      PayrollBankStatus.rejected => line(
        PayrollBankMatch.rejected,
        'Bank rejected the transfer.',
      ),
      PayrollBankStatus.returned => line(
        PayrollBankMatch.returned,
        'Bank returned the transfer. Review any recorded settlement.',
      ),
    });
  }
  return PayrollBankReport._(lines, issues.toSet());
}
