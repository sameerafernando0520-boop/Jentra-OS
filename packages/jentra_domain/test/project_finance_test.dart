import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:jentra_domain/jentra_project_finance.dart';

String id(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> expense() => {
  'action': 'expense_create',
  'id': id(1),
  'project_id': id(2),
  'employee_id': id(3),
  'external_reference': 'synthetic-expense',
  'service_date': '2026-10-01',
  'purpose': 'Approved project expense',
  'evidence_reference': 'synthetic-receipt',
  'original_currency': 'LKR',
  'original_precision': 2,
  'net': '0.03',
  'tax': '0',
  'gross': '0.03',
  'tax_definition_id': null,
  'tax_version': null,
  'no_tax_reason': 'No input tax',
  'exchange_rate_id': null,
  'exchange_rate_version': null,
  'expense_account_id': id(4),
  'tax_account_id': null,
  'liability_account_id': id(5),
  'billable': false,
  'bill_amount': '0',
  'allocations': [
    {'task_id': id(6), 'weight': 1},
    {'task_id': id(7), 'weight': 1},
  ],
  'reason': 'Synthetic original evidence',
};

void main() {
  final samples = projectMap(
    jsonDecode(
      File(
        '../jentra_platform/test/fixtures/project_finance_rollback_projections.json',
      ).readAsStringSync(),
    ),
  );
  test('AC-414 expense preserves exact minor units and no-tax evidence', () {
    validateProjectFinanceCommand('expense_create', expense());
    for (final changed in [
      {'gross': '0.04'},
      {'net': '0.031', 'gross': '0.031'},
      {'tax': '0.01', 'net': '0.02'},
      {'no_tax_reason': ''},
      {'bill_amount': '0.01'},
    ]) {
      expect(
        () => validateProjectFinanceCommand('expense_create', {
          ...expense(),
          ...changed,
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'AC-414 allocation identities and whole positive weights are bounded',
    () {
      for (final values in [
        <Object?>[],
        [
          {'task_id': id(6), 'weight': 0},
        ],
        [
          {'task_id': id(6), 'weight': 1},
          {'task_id': id(6), 'weight': 2},
        ],
        [
          {'task_id': id(6), 'weight': 9007199254740990},
          {'task_id': id(7), 'weight': 1},
        ],
      ]) {
        expect(
          () => validateProjectFinanceCommand('expense_create', {
            ...expense(),
            'allocations': values,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'AC-414 protected expense attachments and unexpected fields fail closed',
    () {
      for (final reference in [
        'https://example.com/private',
        'storage://bucket/key',
      ]) {
        expect(
          () => validateProjectFinanceCommand('expense_create', {
            ...expense(),
            'evidence_reference': reference,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => validateProjectFinanceCommand('expense_create', {
          ...expense(),
          'actor_id': id(9),
        }),
        throwsFormatException,
      );
    },
  );
  test('AC-415 service import freezes source version and digest', () {
    final p = {
      'action': 'service_source',
      'id': id(1),
      'project_id': id(2),
      'service_source_id': id(3),
      'source_version': 4,
      'source_digest': 'a' * 64,
      'reason': 'Synthetic effective revision',
    };
    validateProjectFinanceCommand('service_source', p);
    expect(
      () => validateProjectFinanceCommand('service_source', {
        ...p,
        'source_digest': 'b',
      }),
      throwsFormatException,
    );
    expect(
      () => validateProjectFinanceCommand('service_source', {
        ...p,
        'source_version': 0,
      }),
      throwsFormatException,
    );
  });
  test(
    'AC-414 actual rollback expense projection reconciles FX and allocations',
    () {
      final row = projectMap(
        (projectMap(samples['expenses'])['rows'] as List).single,
      );
      final parsed = ProjectFinanceRow.fromJson(
        ProjectFinanceSection.expenses,
        row,
        'LKR',
      );
      expect(parsed.amount!.toDecimalString(), '0.030000');
      expect(
        () => ProjectFinanceRow.fromJson(ProjectFinanceSection.expenses, {
          ...row,
          'fx_numerator': '2',
        }, 'LKR'),
        throwsFormatException,
      );
      expect(
        () => ProjectFinanceRow.fromJson(ProjectFinanceSection.expenses, {
          ...row,
          'allocations': [],
        }, 'LKR'),
        throwsFormatException,
      );
    },
  );
  test(
    'AC-415 service units retain exact seconds and immutable revision evidence',
    () {
      final row = {
        'id': id(1),
        'source_kind': 'service',
        'source_id': id(2),
        'source_version': 4,
        'source_digest': 'a' * 64,
        'source_name': 'Approved labor · 1 second',
        'amount': '0.01',
        'payable_seconds': 1,
        'status': 'available',
      };
      final parsed = ProjectFinanceRow.fromJson(
        ProjectFinanceSection.units,
        row,
        'LKR',
      );
      expect(parsed.values['payable_seconds'], 1);
      expect(parsed.title, 'Approved labor · 1 second');
      expect(
        () => ProjectFinanceRow.fromJson(ProjectFinanceSection.units, {
          ...row,
          'payable_seconds': null,
        }, 'LKR'),
        throwsFormatException,
      );
    },
  );
  test(
    'AC-415 as-of margin retains and reconciles original posted revenue',
    () {
      final row = projectMap(samples['margin']);
      final margin = ProjectMargin.fromJson(row);
      expect(margin.values['margin']!.toDecimalString(), '0.020000');
      expect(
        () => ProjectMargin.fromJson({...row, 'margin': '0.03'}),
        throwsFormatException,
      );
    },
  );
  test('AC-415 service named choices reject malformed frozen evidence', () {
    final row = {
      'id': id(1),
      'name': 'Approved labor',
      'code': 'SERVICE',
      'version': 4,
      'source_version': 4,
      'source_digest': 'a' * 64,
      'seconds': 1,
      'amount': '0.01',
      'currency_code': 'LKR',
    };
    expect(ProjectFinanceChoice.fromJson(row).version, 4);
    expect(
      () => ProjectFinanceChoice.fromJson({...row, 'source_digest': 'bad'}),
      throwsFormatException,
    );
    expect(
      () => ProjectFinanceChoice.fromJson({...row, 'seconds': 0}),
      throwsFormatException,
    );
  });
}
