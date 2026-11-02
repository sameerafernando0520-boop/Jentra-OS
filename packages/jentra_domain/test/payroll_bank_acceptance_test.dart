import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_payroll_readiness.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:test/test.dart';

String id(int value) =>
    '10000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';
final asOf = CivilDate.parse('2026-10-31');

PayrollBankExpectation expectation({
  String? tenant,
  String? run,
  String? revision,
  String? digest,
  int obligation = 6,
  int instruction = 7,
  String reference = 'PAY-2026-10-01',
  String amount = '260500',
  String currency = 'LKR',
  int approver = 10,
}) => PayrollBankExpectation(
  tenantId: tenant ?? id(1),
  entityId: id(2),
  branchId: id(3),
  runId: run ?? id(4),
  revisionId: revision ?? id(5),
  runDigest: digest ?? 'a' * 64,
  obligationId: id(obligation),
  instructionId: id(instruction),
  bankConnectionId: id(8),
  sourceAccountToken: 'account.company',
  beneficiaryToken: 'beneficiary.employee',
  paymentReference: reference,
  amount: Money.parse(amount, currency),
  requestedDate: CivilDate.parse('2026-10-28'),
  preparedBy: id(9),
  approvedBy: id(approver),
);

PayrollBankObservation event({
  String eventId = 'event.1',
  String transaction = 'transaction.1',
  int sequence = 1,
  String reference = 'PAY-2026-10-01',
  String amount = '260500',
  String currency = 'LKR',
  String date = '2026-10-28',
  String source = 'account.company',
  String beneficiary = 'beneficiary.employee',
  String? connection,
  String? digest,
  PayrollBankStatus status = PayrollBankStatus.settled,
  PayrollBankOrigin origin = PayrollBankOrigin.verifiedLiveFeed,
  PayrollBankDirection direction = PayrollBankDirection.debit,
}) => PayrollBankObservation(
  bankConnectionId: connection ?? id(8),
  eventId: eventId,
  transactionId: transaction,
  sequence: sequence,
  sourceAccountToken: source,
  beneficiaryToken: beneficiary,
  paymentReference: reference,
  amount: Money.parse(amount, currency),
  valueDate: CivilDate.parse(date),
  status: status,
  origin: origin,
  direction: direction,
  evidenceDigest: digest ?? 'b' * 64,
);

PayrollBankReport match(
  List<PayrollBankObservation> events, {
  List<PayrollBankExpectation>? expected,
}) => matchPayrollBankEvidence(
  expectations: expected ?? [expectation()],
  observations: events,
  asOf: asOf,
);

void main() {
  test('only consistent verified live settled evidence matches', () {
    final result = match([event()]);
    expect(result.allEvidenceMatches, isTrue);
    expect(result.matchedAmount, Money.parse('260500', 'LKR'));
    expect(result.expectedAmount, result.matchedAmount);
    expect(
      result.lines.single.reason,
      contains('Separate accounting acceptance'),
    );
  });

  test('posting with no bank evidence is awaiting evidence', () {
    final result = match([]);
    expect(result.allEvidenceMatches, isFalse);
    expect(result.lines.single.match, PayrollBankMatch.awaitingEvidence);
    expect(result.matchedAmount, Money.zero('LKR'));
  });

  for (final (status, outcome) in [
    (PayrollBankStatus.pending, PayrollBankMatch.pending),
    (PayrollBankStatus.rejected, PayrollBankMatch.rejected),
    (PayrollBankStatus.returned, PayrollBankMatch.returned),
  ]) {
    test('$status is never matched as paid', () {
      final result = match([event(status: status)]);
      expect(result.allEvidenceMatches, isFalse);
      expect(result.lines.single.match, outcome);
    });
  }

  for (final origin in [
    PayrollBankOrigin.sandbox,
    PayrollBankOrigin.unverifiedUpload,
  ]) {
    test('$origin cannot prove real payment', () {
      final result = match([event(origin: origin)]);
      expect(result.allEvidenceMatches, isFalse);
      expect(result.lines.single.match, PayrollBankMatch.unverified);
    });
  }

  for (final (label, value) in [
    ('underpayment', event(amount: '260499.99')),
    ('overpayment', event(amount: '260500.01')),
    ('currency', event(currency: 'USD')),
    ('source account', event(source: 'account.other')),
    ('beneficiary', event(beneficiary: 'beneficiary.other')),
    ('credit', event(direction: PayrollBankDirection.credit)),
    ('before instruction', event(date: '2026-10-27')),
    ('future evidence', event(date: '2026-11-01')),
    ('connection', event(connection: id(99))),
    ('reference', event(reference: 'PAY-other')),
  ]) {
    test('mismatched $label needs review', () {
      final result = match([value]);
      expect(result.allEvidenceMatches, isFalse);
      expect(result.lines.single.match, PayrollBankMatch.reviewRequired);
    });
  }

  test('identical bank-event retries are counted once', () {
    final result = match([event(), event()]);
    expect(result.allEvidenceMatches, isTrue);
    expect(result.matchedAmount, Money.parse('260500', 'LKR'));
  });

  test('conflicting event retries cannot overwrite settled evidence', () {
    for (final changed in [
      event(amount: '1'),
      event(digest: 'c' * 64),
      event(status: PayrollBankStatus.returned),
      event(direction: PayrollBankDirection.credit),
    ]) {
      final result = match([event(), changed]);
      expect(result.lines.single.match, PayrollBankMatch.reviewRequired);
      expect(result.issues, contains(contains('conflicting evidence')));
    }
  });

  test('bank sequence controls replay, independently of arrival order', () {
    final pending = event(status: PayrollBankStatus.pending);
    final settled = event(eventId: 'event.2', sequence: 2);
    expect(match([settled, pending]).allEvidenceMatches, isTrue);
    expect(match([pending, settled]).allEvidenceMatches, isTrue);
  });

  test(
    'return after settlement removes matched evidence without erasing it',
    () {
      final settled = event();
      final returned = event(
        eventId: 'event.2',
        sequence: 2,
        date: '2026-10-30',
        status: PayrollBankStatus.returned,
      );
      final result = match([returned, settled]);
      expect(result.lines.single.match, PayrollBankMatch.returned);
      expect(result.allEvidenceMatches, isFalse);
      expect(result.matchedAmount, Money.zero('LKR'));
    },
  );

  for (final (label, events) in [
    ('same sequence reused', [event(), event(eventId: 'event.2')]),
    (
      'settled to pending',
      [
        event(),
        event(
          eventId: 'event.2',
          sequence: 2,
          status: PayrollBankStatus.pending,
        ),
      ],
    ),
    (
      'rejected to settled',
      [
        event(status: PayrollBankStatus.rejected),
        event(eventId: 'event.2', sequence: 2),
      ],
    ),
    (
      'returned to settled',
      [
        event(status: PayrollBankStatus.returned),
        event(eventId: 'event.2', sequence: 2),
      ],
    ),
    (
      'economic facts change',
      [
        event(status: PayrollBankStatus.pending),
        event(eventId: 'event.2', sequence: 2, amount: '1'),
      ],
    ),
    (
      'dates move backwards',
      [
        event(date: '2026-10-30', status: PayrollBankStatus.pending),
        event(eventId: 'event.2', sequence: 2),
      ],
    ),
    (
      'multiple transfers',
      [event(), event(eventId: 'event.2', transaction: 'transaction.2')],
    ),
  ]) {
    test('$label requires explicit investigation', () {
      expect(match(events).lines.single.match, PayrollBankMatch.reviewRequired);
    });
  }

  test('one bank transaction cannot be reused for another obligation', () {
    final result = match(
      [
        event(),
        event(eventId: 'event.2', sequence: 2, reference: 'PAY-2026-10-02'),
      ],
      expected: [
        expectation(),
        expectation(
          obligation: 16,
          instruction: 17,
          reference: 'PAY-2026-10-02',
        ),
      ],
    );
    expect(
      result.lines.every(
        (line) => line.match == PayrollBankMatch.reviewRequired,
      ),
      isTrue,
    );
  });

  test('mixed bank results conserve the independently matched amount', () {
    final result = match(
      [
        event(),
        event(
          eventId: 'event.2',
          transaction: 'transaction.2',
          reference: 'PAY-2026-10-02',
          amount: '100',
          status: PayrollBankStatus.rejected,
        ),
      ],
      expected: [
        expectation(),
        expectation(
          obligation: 16,
          instruction: 17,
          reference: 'PAY-2026-10-02',
          amount: '100',
        ),
      ],
    );
    expect(result.allEvidenceMatches, isFalse);
    expect(result.expectedAmount, Money.parse('260600', 'LKR'));
    expect(result.matchedAmount, Money.parse('260500', 'LKR'));
    expect(result.lines.last.match, PayrollBankMatch.rejected);
    expect(() => result.lines.clear(), throwsUnsupportedError);
  });

  test(
    'scope, frozen revision and unique obligation/reference are mandatory',
    () {
      for (final other in [
        expectation(
          tenant: id(99),
          obligation: 16,
          instruction: 17,
          reference: 'PAY-other',
        ),
        expectation(
          run: id(99),
          obligation: 16,
          instruction: 17,
          reference: 'PAY-other',
        ),
        expectation(
          revision: id(99),
          obligation: 16,
          instruction: 17,
          reference: 'PAY-other',
        ),
        expectation(
          digest: 'd' * 64,
          obligation: 16,
          instruction: 17,
          reference: 'PAY-other',
        ),
        expectation(obligation: 6, instruction: 17, reference: 'PAY-other'),
        expectation(obligation: 16, instruction: 7, reference: 'PAY-other'),
        expectation(obligation: 16, instruction: 17),
      ]) {
        expect(
          () => match([], expected: [expectation(), other]),
          throwsFormatException,
        );
      }
    },
  );

  test('rejects invalid, fractional-cent and overflowing bank amounts', () {
    for (final amount in ['0', '-1', '1.000001', '100000000000000']) {
      expect(() => expectation(amount: amount), throwsFormatException);
      expect(() => event(amount: amount), throwsFormatException);
    }
    expect(() => expectation(currency: 'USD'), throwsFormatException);
    expect(() => expectation(approver: 9), throwsFormatException);
    expect(() => event(sequence: 0), throwsFormatException);
    expect(() => event(eventId: 'invalid\nreference'), throwsFormatException);
    expect(() => event(digest: 'not-a-digest'), throwsFormatException);
  });

  test('bounded matching refuses empty or oversized batches', () {
    expect(() => match([], expected: []), throwsFormatException);
    expect(
      () => match([], expected: List.filled(201, expectation())),
      throwsFormatException,
    );
    expect(() => match(List.filled(2001, event())), throwsFormatException);
  });
}
