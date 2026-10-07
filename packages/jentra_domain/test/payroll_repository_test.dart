import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_payroll.dart';
import 'package:test/test.dart';

const id = '20000000-0000-0000-0000-000000000001';
const reviewer = '20000000-0000-0000-0000-000000000002';
final digest = 'a' * 64;
Map<String, Object?> line() => {
  'rule_version_id': id,
  'code': 'BASE',
  'classification': 'earning',
  'basis': 'fixed',
  'proration': 'none',
  'raw_numerator_units': '1250000',
  'raw_denominator': '1',
  'rounding': 'half_even',
  'precision': 1,
  'rounded_amount': '1.200000',
  'cap': null,
  'capped': false,
  'amount': '1.200000',
};
Map<String, Object?> run() => {
  'id': id,
  'tenant_id': id,
  'legal_entity_id': id,
  'branch_id': id,
  'name': 'Synthetic September',
  'start_date': '2026-09-01',
  'end_date_exclusive': '2026-10-01',
  'posting_date': '2026-09-30',
  'currency_code': 'LKR',
  'version': 4,
  'status': 'approved',
  'current_revision_id': id,
  'digest': digest,
  'employee_count': 1,
  'prepared_by': id,
  'submitted_by': id,
  'approved_by': reviewer,
  'posted_journal_id': null,
  'reversal_journal_id': null,
  'created_by': id,
};
Map<String, Object?> rule() => {
  'id': id,
  'component_id': id,
  'code': 'BASE',
  'name': 'Synthetic salary',
  'classification': 'earning',
  'version': 1,
  'start_date': '2026-09-01',
  'end_date_exclusive': '2026-10-01',
  'currency_code': 'LKR',
  'basis': 'fixed',
  'proration': 'eligible_days',
  'rounding': 'half_even',
  'precision': 2,
  'amount': '1000.000000',
  'ratio_numerator': 1,
  'ratio_denominator': 1,
  'cap': null,
  'expense_account_id': id,
  'liability_account_id': null,
  'reason': 'Synthetic rule',
  'published_by': id,
  'published_at': '2026-09-30T00:00:00.123456+00:00',
};
void main() {
  test('each explanation reproduces exact rounding and configured cap', () {
    expect(
      PayrollExplainedLine.fromJson(line(), 'LKR').amount.toDecimalString(),
      '1.200000',
    );
    expect(
      () => PayrollExplainedLine.fromJson({
        ...line(),
        'rounded_amount': '1.300000',
      }, 'LKR'),
      throwsFormatException,
    );
    expect(
      () => PayrollExplainedLine.fromJson({
        ...line(),
        'amount': '1.300000',
      }, 'LKR'),
      throwsFormatException,
    );
    final capped = {
      ...line(),
      'cap': '1.100000',
      'capped': true,
      'amount': '1.100000',
    };
    expect(PayrollExplainedLine.fromJson(capped, 'LKR').capped, isTrue);
    expect(
      () => PayrollExplainedLine.fromJson({...capped, 'capped': false}, 'LKR'),
      throwsFormatException,
    );
    expect(
      () => PayrollExplainedLine.fromJson({
        ...line(),
        'raw_numerator_units': 1250000,
      }, 'LKR'),
      throwsFormatException,
    );
  });
  test(
    'run evidence rejects self approval, invalid lifecycle and response mutation',
    () {
      final wire = run(), parsed = PayrollRun.fromJson(wire);
      wire['status'] = 'posted';
      expect(parsed.status, 'approved');
      parsed.toJson()['name'] = 'Changed';
      expect(parsed.name, 'Synthetic September');
      expect(
        () => PayrollRun.fromJson({...run(), 'approved_by': id}),
        throwsFormatException,
      );
      expect(
        () => PayrollRun.fromJson({...run(), 'status': 'posted'}),
        throwsFormatException,
      );
      expect(
        () => PayrollRun.fromJson({...run(), 'employee_count': 201}),
        throwsFormatException,
      );
      expect(
        () => PayrollRun.fromJson({...run(), 'digest': null}),
        throwsFormatException,
      );
      expect(
        () => PayrollRun.fromJson({...run(), 'bank_details': 'private'}),
        throwsFormatException,
      );
    },
  );
  test(
    'private totals conserve gross less deductions with exact decimal strings',
    () {
      const amounts = {
        'gross': '1000.000000',
        'deductions': '100.000000',
        'employer_cost': '30.000000',
        'net': '900.000000',
      };
      expect(
        PayrollAmounts.fromJson(amounts, 'LKR').net.toDecimalString(),
        '900.000000',
      );
      expect(
        () => PayrollAmounts.fromJson({...amounts, 'net': '900.000001'}, 'LKR'),
        throwsFormatException,
      );
      expect(
        () => PayrollAmounts.fromJson({...amounts, 'gross': 1000}, 'LKR'),
        throwsA(isA<TypeError>()),
      );
    },
  );
  test('rule vocabulary and private account attribution are strict', () {
    expect(
      PayrollRuleVersion.fromJson(rule()).rule.proration,
      PayrollProration.eligibleDays,
    );
    expect(
      () => PayrollRuleVersion.fromJson({...rule(), 'basis': 'earningsRatio'}),
      throwsFormatException,
    );
    expect(
      () =>
          PayrollRuleVersion.fromJson({...rule(), 'liability_account_id': id}),
      throwsFormatException,
    );
    expect(
      () => PayrollRuleVersion.fromJson({...rule(), 'amount': '1000.0000001'}),
      throwsFormatException,
    );
    expect(
      () =>
          PayrollRuleVersion.fromJson({...rule(), 'personal_email': 'hidden'}),
      throwsFormatException,
    );
  });
  test(
    'commands bind revision, employee bounds and exact settlement money',
    () {
      final create = {
        'action': 'create',
        'id': id,
        'name': 'Synthetic',
        'start_date': '2026-09-01',
        'end_date_exclusive': '2026-10-01',
        'posting_date': '2026-09-30',
        'employee_ids': [id],
        'reason': 'Synthetic run',
      };
      PayrollCommands.validate(PayrollCommandKind.run, create, 0);
      expect(
        () => PayrollCommands.validate(PayrollCommandKind.run, {
          ...create,
          'employee_ids': [id, id],
        }, 0),
        throwsFormatException,
      );
      expect(
        () => PayrollCommands.validate(PayrollCommandKind.run, {
          'action': 'post',
          'id': id,
          'reason': 'Synthetic',
        }, 4),
        throwsFormatException,
      );
      final settlement = {
        'action': 'record',
        'id': id,
        'run_id': id,
        'posting_date': '2026-09-30',
        'bank_id': id,
        'bank_version': 1,
        'evidence_reference': 'SYNTHETIC-001',
        'allocations': [
          {'obligation_id': id, 'amount': '1.25'},
        ],
        'reason': 'Synthetic',
      };
      PayrollCommands.validate(PayrollCommandKind.settlement, settlement, 0);
      expect(
        () => PayrollCommands.validate(PayrollCommandKind.settlement, {
          ...settlement,
          'allocations': [
            {'obligation_id': id, 'amount': '1e3'},
          ],
        }, 0),
        throwsFormatException,
      );
      expect(
        PayrollCommands.capability(PayrollCommandKind.run, 'post'),
        'people.payroll.post',
      );
      final publish = {...rule()}
        ..remove('version')
        ..remove('currency_code')
        ..remove('published_by')
        ..remove('published_at')
        ..['action'] = 'publish';
      PayrollCommands.validate(PayrollCommandKind.configuration, publish, 0);
    },
  );
  test('client explanation serializes the SQL vocabulary', () {
    final r = PayrollRuleVersion.fromJson(rule()).rule;
    final result = calculatePayroll(
      PayrollCalculationInput(
        employeeId: id,
        start: CivilDate.parse('2026-09-01'),
        endExclusive: CivilDate.parse('2026-10-01'),
        periodDays: 30,
        eligibleDays: 15,
        paidSeconds: 0,
        plannedSeconds: 0,
      ),
      [r],
    );
    final row = result.lines.single.toJson();
    expect(row['proration'], 'eligible_days');
    expect(row['rounding'], 'half_even');
    expect(PayrollExplainedLine.fromJson(row, 'LKR').amount, result.gross);
  });
}
