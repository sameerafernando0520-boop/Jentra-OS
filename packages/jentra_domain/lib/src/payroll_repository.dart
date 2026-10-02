import 'dart:convert';

import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'money.dart';
import 'payroll_calculation.dart';
import 'tenant_context.dart';
import 'workforce.dart';

const payrollCapabilities = {
  'people.payroll.view',
  'people.payroll.configure',
  'people.payroll.prepare',
  'people.payroll.approve',
  'people.payroll.post',
  'people.payroll.reverse',
  'people.payroll.payslip.view',
  'people.payroll.payslip.self',
  'people.payroll.export',
  'people.payroll.settle',
};

String payrollDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Payroll digest is invalid.');
  }
  return value;
}

void assertPayrollScope(Map<String, Object?> row, TenantContext scope) {
  if (row['tenant_id'] != scope.tenantId ||
      row['legal_entity_id'] != scope.legalEntityId ||
      row['branch_id'] != scope.branchId) {
    throw const FormatException('Payroll response scope changed.');
  }
}

T _enum<T extends Object>(Object? value, Map<String, T> values) {
  if (!values.containsKey(value)) {
    throw const FormatException('Payroll rule vocabulary is invalid.');
  }
  return values[value]!;
}

final class PayrollRuleVersion {
  PayrollRuleVersion.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      componentId = calendarUuid(row['component_id']),
      version = workforceInteger(row['version'], positive: true),
      name = workforceText(row['name'], 160),
      reason = workforceText(row['reason'], 1000),
      publishedBy = calendarUuid(row['published_by']),
      publishedAt = workforceRecorded(row['published_at']),
      expenseAccountId = row['expense_account_id'] == null
          ? null
          : calendarUuid(row['expense_account_id']),
      liabilityAccountId = row['liability_account_id'] == null
          ? null
          : calendarUuid(row['liability_account_id']),
      rule = PayrollRule(
        id: calendarUuid(row['id']),
        code: workforceText(row['code'], 32),
        classification: _enum(row['classification'], {
          'earning': PayrollClassification.earning,
          'deduction': PayrollClassification.deduction,
          'employer_cost': PayrollClassification.employerCost,
        }),
        basis: _enum(row['basis'], {
          'fixed': PayrollBasis.fixed,
          'hourly': PayrollBasis.hourly,
          'earnings_ratio': PayrollBasis.earningsRatio,
        }),
        proration: _enum(row['proration'], {
          'none': PayrollProration.none,
          'eligible_days': PayrollProration.eligibleDays,
          'paid_seconds': PayrollProration.paidSeconds,
        }),
        rounding: _enum(row['rounding'], {
          'half_away': PayrollRounding.halfAway,
          'half_even': PayrollRounding.halfEven,
          'truncate': PayrollRounding.truncate,
          'floor': PayrollRounding.floor,
        }),
        precision: workforceInteger(row['precision']),
        start: CivilDate.parse(row['start_date'] as String),
        endExclusive: CivilDate.parse(row['end_date_exclusive'] as String),
        amount: payrollAmount(
          row['amount'] as String,
          row['currency_code'] as String,
        ),
        ratioNumerator: workforceInteger(row['ratio_numerator']),
        ratioDenominator: workforceInteger(
          row['ratio_denominator'],
          positive: true,
        ),
        cap: row['cap'] == null
            ? null
            : payrollAmount(
                row['cap'] as String,
                row['currency_code'] as String,
              ),
      ) {
    calendarFields(row, {
      'id',
      'component_id',
      'code',
      'name',
      'classification',
      'version',
      'start_date',
      'end_date_exclusive',
      'currency_code',
      'basis',
      'proration',
      'rounding',
      'precision',
      'amount',
      'ratio_numerator',
      'ratio_denominator',
      'cap',
      'expense_account_id',
      'liability_account_id',
      'reason',
      'published_by',
      'published_at',
    });
    if ((rule.classification == PayrollClassification.deduction) !=
            (expenseAccountId == null) ||
        (rule.classification == PayrollClassification.earning) !=
            (liabilityAccountId == null)) {
      throw const FormatException('Payroll account attribution is invalid.');
    }
  }
  final String id, componentId, name, reason, publishedBy;
  final int version;
  final DateTime publishedAt;
  final String? expenseAccountId, liabilityAccountId;
  final PayrollRule rule;
}

final class PayrollRun {
  PayrollRun.fromJson(Map<String, Object?> row)
    : id = calendarUuid(row['id']),
      version = workforceInteger(row['version'], positive: true),
      name = workforceText(row['name'], 160),
      status = workforceText(row['status'], 20),
      start = CivilDate.parse(row['start_date'] as String),
      endExclusive = CivilDate.parse(row['end_date_exclusive'] as String),
      postingDate = CivilDate.parse(row['posting_date'] as String),
      currency = row['currency_code'] as String,
      revisionId = row['current_revision_id'] == null
          ? null
          : calendarUuid(row['current_revision_id']),
      digest = row['digest'] == null ? null : payrollDigest(row['digest']),
      employeeCount = row['employee_count'] == null
          ? null
          : workforceInteger(row['employee_count'], positive: true),
      preparedBy = row['prepared_by'] == null
          ? null
          : calendarUuid(row['prepared_by']),
      submittedBy = row['submitted_by'] == null
          ? null
          : calendarUuid(row['submitted_by']),
      approvedBy = row['approved_by'] == null
          ? null
          : calendarUuid(row['approved_by']),
      journalId = row['posted_journal_id'] == null
          ? null
          : calendarUuid(row['posted_journal_id']),
      reversalId = row['reversal_journal_id'] == null
          ? null
          : calendarUuid(row['reversal_journal_id']),
      createdBy = calendarUuid(row['created_by']),
      _wire = jsonEncode(row) {
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'name',
      'start_date',
      'end_date_exclusive',
      'posting_date',
      'currency_code',
      'version',
      'status',
      'current_revision_id',
      'digest',
      'employee_count',
      'prepared_by',
      'submitted_by',
      'approved_by',
      'posted_journal_id',
      'reversal_journal_id',
      'created_by',
    });
    calendarUuid(row['tenant_id']);
    calendarUuid(row['legal_entity_id']);
    calendarUuid(row['branch_id']);
    final days = endExclusive.utc.difference(start.utc).inDays;
    if (days < 1 ||
        days > 366 ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        !{
          'draft',
          'prepared',
          'submitted',
          'approved',
          'posted',
          'reversed',
          'cancelled',
        }.contains(status) ||
        (revisionId == null) != (digest == null) ||
        (revisionId == null) != (employeeCount == null) ||
        employeeCount != null && employeeCount! > 200 ||
        {
              'prepared',
              'submitted',
              'approved',
              'posted',
              'reversed',
            }.contains(status) &&
            revisionId == null ||
        {'approved', 'posted', 'reversed'}.contains(status) &&
            (approvedBy == null ||
                approvedBy == preparedBy ||
                approvedBy == submittedBy) ||
        {'posted', 'reversed'}.contains(status) != (journalId != null) ||
        (status == 'reversed') != (reversalId != null)) {
      throw const FormatException(
        'Payroll run state or frozen evidence is invalid.',
      );
    }
  }
  final String id, name, status, currency, createdBy, _wire;
  final int version;
  final CivilDate start, endExclusive, postingDate;
  final String? revisionId,
      digest,
      preparedBy,
      submittedBy,
      approvedBy,
      journalId,
      reversalId;
  final int? employeeCount;
  Map<String, Object?> toJson() => workforceMap(jsonDecode(_wire));
  void assertScope(TenantContext scope) => assertPayrollScope(toJson(), scope);
}

final class PayrollAmounts {
  PayrollAmounts.fromJson(Map<String, Object?> row, String currency)
    : gross = payrollAmount(row['gross'] as String, currency),
      deductions = payrollAmount(row['deductions'] as String, currency),
      employerCost = payrollAmount(row['employer_cost'] as String, currency),
      net = payrollAmount(row['net'] as String, currency) {
    if (deductions.compareTo(gross) > 0 || gross - deductions != net) {
      throw const FormatException('Payroll totals do not conserve earned pay.');
    }
  }
  final Money gross, deductions, employerCost, net;
}

final class PayrollEmployeeCalculation {
  PayrollEmployeeCalculation.fromJson(Map<String, Object?> row, String currency)
    : id = calendarUuid(row['id']),
      employeeId = calendarUuid(row['employee_id']),
      employeeName = workforceText(row['employee_name'], 160),
      digest = payrollDigest(row['input_digest']),
      amounts = PayrollAmounts.fromJson(row, currency) {
    calendarFields(row, {
      'id',
      'employee_id',
      'employee_name',
      'input_digest',
      'gross',
      'deductions',
      'employer_cost',
      'net',
    });
  }
  final String id, employeeId, employeeName, digest;
  final PayrollAmounts amounts;
}

final class PayrollRunDetail {
  const PayrollRunDetail(this.run, this.employeeIds, this.calculations);
  final PayrollRun run;
  final List<String> employeeIds;
  final WorkforcePage<PayrollEmployeeCalculation> calculations;
}

final class PayrollExplainedLine {
  PayrollExplainedLine.fromJson(Map<String, Object?> row, String currency)
    : ruleId = calendarUuid(row['rule_version_id']),
      code = workforceText(row['code'], 32),
      classification = workforceText(row['classification'], 20),
      basis = workforceText(row['basis'], 20),
      proration = workforceText(row['proration'], 20),
      rounding = workforceText(row['rounding'], 20),
      precision = workforceInteger(row['precision']),
      rawNumerator = _integer(row['raw_numerator_units']),
      rawDenominator = _integer(row['raw_denominator']),
      amount = payrollAmount(row['amount'] as String, currency),
      rounded = _rounded(row['rounded_amount'], currency),
      cap = row['cap'] == null
          ? null
          : payrollAmount(row['cap'] as String, currency),
      capped = row['capped'] as bool {
    calendarFields(row, {
      'rule_version_id',
      'code',
      'classification',
      'basis',
      'proration',
      'raw_numerator_units',
      'raw_denominator',
      'rounding',
      'precision',
      'rounded_amount',
      'cap',
      'capped',
      'amount',
    });
    final mode = _enum(rounding, {
      'half_away': PayrollRounding.halfAway,
      'half_even': PayrollRounding.halfEven,
      'truncate': PayrollRounding.truncate,
      'floor': PayrollRounding.floor,
    });
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code) ||
        !{'earning', 'deduction', 'employer_cost'}.contains(classification) ||
        !{'fixed', 'hourly', 'earnings_ratio'}.contains(basis) ||
        !{'none', 'eligible_days', 'paid_seconds'}.contains(proration) ||
        rawNumerator < BigInt.zero ||
        rawDenominator <= BigInt.zero ||
        rounded.minorUnits !=
            payrollRoundRatio(rawNumerator, rawDenominator, precision, mode) ||
        capped != (cap != null && rounded.compareTo(cap!) > 0) ||
        amount != (capped ? cap : rounded) ||
        cap != null &&
            cap!.minorUnits % BigInt.from(10).pow(6 - precision) !=
                BigInt.zero) {
      throw const FormatException(
        'Payroll explanation cannot reproduce its exact amount.',
      );
    }
  }
  static BigInt _integer(Object? value) {
    if (value is! String ||
        value.length > 80 ||
        !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
      throw const FormatException('Payroll exact basis is invalid.');
    }
    return BigInt.parse(value);
  }

  static Money _rounded(Object? value, String currency) {
    if (value is! String ||
        !RegExp(r'^(0|[1-9][0-9]{0,60})(\.[0-9]{1,6})?$').hasMatch(value)) {
      throw const FormatException('Payroll rounded basis is invalid.');
    }
    return Money.parse(value, currency);
  }

  final String ruleId, code, classification, basis, proration, rounding;
  final int precision;
  final BigInt rawNumerator, rawDenominator;
  final Money amount, rounded;
  final Money? cap;
  final bool capped;
}

enum PayrollCommandKind { configuration, run, settlement, export }

final class PayrollCommands {
  static const fields = <PayrollCommandKind, Map<String, Set<String>>>{
    PayrollCommandKind.run: {
      'create': {
        'action',
        'id',
        'name',
        'start_date',
        'end_date_exclusive',
        'posting_date',
        'employee_ids',
        'reason',
      },
      'prepare': {'action', 'id', 'reason'},
      'submit': {'action', 'id', 'revision_id', 'digest', 'reason'},
      'approve': {'action', 'id', 'revision_id', 'digest', 'reason'},
      'post': {'action', 'id', 'revision_id', 'digest', 'reason'},
      'reverse': {'action', 'id', 'revision_id', 'digest', 'reason'},
      'cancel': {'action', 'id', 'reason'},
    },
    PayrollCommandKind.configuration: {
      'settings': {'action', 'id', 'net_account_id', 'reason'},
      'assign': {
        'action',
        'id',
        'employee_id',
        'component_id',
        'start_date',
        'end_date_exclusive',
        'reason',
      },
      'publish': {
        'action',
        'id',
        'component_id',
        'code',
        'name',
        'classification',
        'start_date',
        'end_date_exclusive',
        'basis',
        'proration',
        'rounding',
        'precision',
        'amount',
        'ratio_numerator',
        'ratio_denominator',
        'cap',
        'expense_account_id',
        'liability_account_id',
        'reason',
      },
    },
    PayrollCommandKind.settlement: {
      'record': {
        'action',
        'id',
        'run_id',
        'posting_date',
        'bank_id',
        'bank_version',
        'evidence_reference',
        'allocations',
        'reason',
      },
      'reverse': {'action', 'id', 'run_id', 'posting_date', 'reason'},
    },
    PayrollCommandKind.export: {
      'prepare': {'action', 'id', 'payslip_id'},
    },
  };
  static String capability(PayrollCommandKind kind, String action) =>
      switch (kind) {
        PayrollCommandKind.configuration => 'people.payroll.configure',
        PayrollCommandKind.settlement => 'people.payroll.settle',
        PayrollCommandKind.export => 'people.payroll.export',
        PayrollCommandKind.run => switch (action) {
          'approve' => 'people.payroll.approve',
          'post' => 'people.payroll.post',
          'reverse' => 'people.payroll.reverse',
          _ => 'people.payroll.prepare',
        },
      };
  static void validate(
    PayrollCommandKind kind,
    Map<String, Object?> p,
    int version,
  ) {
    final allowed = fields[kind]?[p['action']];
    if (allowed == null) {
      throw const FormatException('Payroll action is invalid.');
    }
    calendarFields(p, allowed);
    calendarUuid(p['id']);
    if (version < 0 || version >= calendarMaxVersion) {
      throw const FormatException('Payroll expected version is invalid.');
    }
    final action = p['action'];
    switch (kind) {
      case PayrollCommandKind.run:
        if (!{
          'create',
          'prepare',
          'submit',
          'approve',
          'post',
          'cancel',
          'reverse',
        }.contains(action)) {
          throw const FormatException('Payroll action is invalid.');
        }
        workforceText(p['reason'], 1000);
        if (action == 'create') {
          calendarFields(p, {
            'action',
            'id',
            'name',
            'start_date',
            'end_date_exclusive',
            'posting_date',
            'employee_ids',
            'reason',
          });
          workforceText(p['name'], 160);
          final start = CivilDate.parse(p['start_date'] as String),
              end = CivilDate.parse(p['end_date_exclusive'] as String);
          CivilDate.parse(p['posting_date'] as String);
          final employees = p['employee_ids'] as List;
          final days = end.utc.difference(start.utc).inDays;
          if (version != 0 ||
              days < 1 ||
              days > 366 ||
              employees.isEmpty ||
              employees.length > 200 ||
              employees.map(calendarUuid).toSet().length != employees.length) {
            throw const FormatException(
              'Payroll run scope or bound is invalid.',
            );
          }
        } else if ({'submit', 'approve', 'post', 'reverse'}.contains(action)) {
          calendarFields(p, {
            'action',
            'id',
            'revision_id',
            'digest',
            'reason',
          });
          calendarUuid(p['revision_id']);
          payrollDigest(p['digest']);
        } else {
          calendarFields(p, {'action', 'id', 'reason'});
        }
      case PayrollCommandKind.configuration:
        workforceText(p['reason'], 1000);
        if (action == 'settings') {
          calendarFields(p, {'action', 'id', 'net_account_id', 'reason'});
          calendarUuid(p['net_account_id']);
        } else if (action == 'assign') {
          calendarFields(p, {
            'action',
            'id',
            'employee_id',
            'component_id',
            'start_date',
            'end_date_exclusive',
            'reason',
          });
          calendarUuid(p['employee_id']);
          calendarUuid(p['component_id']);
          final from = CivilDate.parse(p['start_date'] as String),
              to = CivilDate.parse(p['end_date_exclusive'] as String);
          if (version != 0 ||
              to.utc.difference(from.utc).inDays < 1 ||
              to.utc.difference(from.utc).inDays > 1830) {
            throw const FormatException(
              'Payroll assignment dates are invalid.',
            );
          }
        } else if (action == 'publish') {
          calendarFields(p, {
            'action',
            'id',
            'component_id',
            'code',
            'name',
            'classification',
            'start_date',
            'end_date_exclusive',
            'basis',
            'proration',
            'rounding',
            'precision',
            'amount',
            'ratio_numerator',
            'ratio_denominator',
            'cap',
            'expense_account_id',
            'liability_account_id',
            'reason',
          });
          calendarUuid(p['component_id']);
          workforceText(p['name'], 160);
          // The entity supplies currency; validation reuses the exact rule contract.
          PayrollRuleVersion.fromJson(
            {...p}
              ..remove('action')
              ..addAll({
                'version': version + 1,
                'currency_code': 'XXX',
                'published_by': p['component_id'],
                'published_at': '2026-09-30T00:00:00Z',
              }),
          );
        } else {
          throw const FormatException(
            'Payroll configuration action is invalid.',
          );
        }
      case PayrollCommandKind.settlement:
        calendarUuid(p['run_id']);
        CivilDate.parse(p['posting_date'] as String);
        workforceText(p['reason'], 1000);
        if (action == 'record') {
          calendarFields(p, {
            'action',
            'id',
            'run_id',
            'posting_date',
            'bank_id',
            'bank_version',
            'evidence_reference',
            'allocations',
            'reason',
          });
          calendarUuid(p['bank_id']);
          workforceInteger(p['bank_version'], positive: true);
          workforceText(p['evidence_reference'], 160);
          final allocations = p['allocations'] as List, ids = <String>{};
          if (version != 0 || allocations.isEmpty || allocations.length > 200) {
            throw const FormatException('Payroll allocation bound is invalid.');
          }
          for (final value in allocations) {
            final row = workforceMap(value);
            calendarFields(row, {'obligation_id', 'amount'});
            if (!ids.add(calendarUuid(row['obligation_id'])) ||
                payrollAmount(row['amount'] as String, 'XXX').minorUnits <=
                    BigInt.zero) {
              throw const FormatException('Payroll allocation is invalid.');
            }
          }
        } else if (action == 'reverse') {
          calendarFields(p, {
            'action',
            'id',
            'run_id',
            'posting_date',
            'reason',
          });
        } else {
          throw const FormatException('Payroll settlement action is invalid.');
        }
      case PayrollCommandKind.export:
        calendarFields(p, {'action', 'id', 'payslip_id'});
        calendarUuid(p['payslip_id']);
        if (action != 'prepare' || version != 0) {
          throw const FormatException('Payroll export action is invalid.');
        }
    }
  }
}

abstract interface class PayrollRepository {
  Future<void> authorize(TenantContext scope, String capability);
  Future<Map<String, Object?>?> settings(TenantContext scope);
  Future<WorkforcePage<Map<String, Object?>>> assignments(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<Map<String, Object?>> snapshot(
    TenantContext scope,
    String calculationId,
    String section, {
    int after = 0,
  });
  Future<WorkforcePage<PayrollRuleVersion>> rules(
    TenantContext scope, {
    String? after,
  });
  Future<WorkforcePage<PayrollRun>> runs(TenantContext scope, {String? after});
  Future<PayrollRunDetail> detail(
    TenantContext scope,
    String runId, {
    String? after,
  });
  Future<Map<String, Object?>> calculation(
    TenantContext scope,
    String calculationId,
    String currency, {
    String? afterCode,
    String? sourceAfter,
  });
  Future<WorkforcePage<Map<String, Object?>>> accounts(
    TenantContext scope,
    String kind, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> obligations(
    TenantContext scope,
    String runId, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> settlements(
    TenantContext scope,
    String runId, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> history(
    TenantContext scope,
    String runId, {
    String? after,
  });
  Future<WorkforcePage<Map<String, Object?>>> payslips(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<Map<String, Object?>> payslip(
    TenantContext scope,
    String payslipId, {
    String? afterCode,
  });
  Future<WorkforcePage<Map<String, Object?>>> selfPayslips(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> exportContent(
    TenantContext scope,
    String exportId,
  );
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String commandId,
    String capability,
  );
  Future<Map<String, Object?>> execute(
    PayrollCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  );
}
