import 'dart:convert';
import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'expense_evidence.dart';
import 'money.dart';
import 'project_values.dart';
import 'projects_repository.dart';
import 'tenant_context.dart';
import 'workforce.dart';

enum ProjectFinanceSection {
  expenses,
  obligations,
  settlements,
  billing,
  units,
  history,
  serviceCosts,
}

const projectFinanceActions = {
  'expense_create',
  'expense_correct',
  'expense_submit',
  'expense_approve',
  'expense_reject',
  'expense_cancel',
  'expense_post',
  'expense_reverse',
  'settle',
  'settlement_reverse',
  'billing_prepare',
  'billing_submit',
  'billing_decide',
  'billing_post',
  'billing_cancel',
  'service_source',
};
String projectFinanceCapability(String action) {
  if (!projectFinanceActions.contains(action)) {
    throw const FormatException('Unknown project finance command.');
  }
  if (action.startsWith('billing_') || action == 'service_source') {
    return 'projects.billing.manage';
  }
  if (action == 'settle' || action == 'settlement_reverse') {
    return 'projects.expenses.settle';
  }
  if (action == 'expense_approve' || action == 'expense_reject') {
    return 'projects.expenses.approve';
  }
  if (action == 'expense_post' || action == 'expense_reverse') {
    return 'projects.expenses.post';
  }
  return 'projects.expenses.manage';
}

Set<String> projectFinanceFields(String action) {
  projectFinanceCapability(action);
  const base = {'action', 'id', 'project_id', 'reason'};
  if (action == 'service_source') {
    return {...base, 'service_source_id', 'source_version', 'source_digest'};
  }
  if (action == 'expense_create' || action == 'expense_correct') {
    return {
      ...base,
      'employee_id',
      'external_reference',
      'service_date',
      'purpose',
      'evidence_reference',
      'evidence_documents',
      'original_currency',
      'original_precision',
      'net',
      'tax',
      'gross',
      'tax_definition_id',
      'tax_version',
      'no_tax_reason',
      'exchange_rate_id',
      'exchange_rate_version',
      'expense_account_id',
      'tax_account_id',
      'liability_account_id',
      'billable',
      'bill_amount',
      'allocations',
    };
  }
  if (action == 'expense_approve' || action == 'expense_reject') {
    return {...base, 'digest'};
  }
  if (action == 'expense_post' ||
      action == 'expense_reverse' ||
      action == 'settlement_reverse') {
    return {...base, 'posting_date'};
  }
  if (action == 'settle') {
    return {
      ...base,
      'obligation_id',
      'posting_date',
      'amount',
      'bank_id',
      'bank_version',
      'evidence_reference',
    };
  }
  if (action == 'billing_prepare') {
    return {
      ...base,
      'invoice_id',
      'document_date',
      'due_date',
      'exchange_rate_id',
      'units',
    };
  }
  if (action.startsWith('billing_')) {
    return {
      ...base,
      'invoice_version',
      if (action == 'billing_decide') 'decision',
    };
  }
  return base;
}

void validateProjectFinanceCommand(String action, Map<String, Object?> p) {
  if (p['action'] != action ||
      p.keys.any((k) => !projectFinanceFields(action).contains(k)) ||
      utf8.encode(jsonEncode(p)).length > 65536) {
    throw const FormatException('Unexpected or oversized finance command.');
  }
  for (final k in ['id', 'project_id']) {
    projectIdentity(p[k]);
  }
  projectText(p['reason'], 1000);
  if (action == 'service_source') {
    projectIdentity(p['service_source_id']);
    workforceInteger(p['source_version'], positive: true);
    projectDigest(p['source_digest']);
  }
  if (action == 'expense_create' || action == 'expense_correct') {
    expenseEvidenceProofs(p['evidence_documents'] ?? const []);
    for (final k in [
      'employee_id',
      'expense_account_id',
      'liability_account_id',
    ]) {
      projectIdentity(p[k]);
    }
    for (final k in [
      'tax_account_id',
      'tax_definition_id',
      'exchange_rate_id',
    ]) {
      projectOptionalIdentity(p[k]);
    }
    for (final k in ['tax_version', 'exchange_rate_version']) {
      if (p[k] != null) {
        workforceInteger(p[k], positive: true);
      }
    }
    CivilDate.parse(p['service_date'] as String);
    projectText(p['purpose'], 500);
    projectText(p['external_reference'], 160);
    final evidence = projectText(p['evidence_reference'], 160);
    if (RegExp(
      r'https?://|file:|[\\/]',
      caseSensitive: false,
    ).hasMatch(evidence)) {
      throw const FormatException('Protected attachments are unavailable.');
    }
    final c = p['original_currency'] as String;
    final precision = projectPrecision(p['original_precision']);
    final net = projectAmount(p['net'] as String, c),
        tax = projectAmount(p['tax'] as String, c),
        gross = projectAmount(p['gross'] as String, c);
    final q = BigInt.from(10).pow(6 - precision);
    if (net + tax != gross ||
        gross.minorUnits <= BigInt.zero ||
        [net, tax, gross].any((m) => m.minorUnits % q != BigInt.zero) ||
        p['billable'] is! bool) {
      throw const FormatException('Expense original amounts do not conserve.');
    }
    final bill = projectAmount(p['bill_amount'] as String, 'XXX');
    if (p['billable'] == false && bill.minorUnits != BigInt.zero) {
      throw const FormatException('Nonbillable expense has a billing amount.');
    }
    if (p['tax_definition_id'] == null) {
      if (tax.minorUnits != BigInt.zero || p['tax_version'] != null) {
        throw const FormatException(
          'Expense tax needs a versioned definition.',
        );
      }
      projectText(p['no_tax_reason'], 1000);
    } else if (p['tax_version'] == null || p['no_tax_reason'] != null) {
      throw const FormatException('Expense tax evidence is inconsistent.');
    }
    final list = p['allocations'];
    if (list is! List || list.isEmpty || list.length > 50) {
      throw const FormatException('One to fifty allocations required.');
    }
    final ids = <String>{};
    var total = BigInt.zero;
    for (final value in list) {
      final row = projectMap(value);
      calendarFields(row, {'task_id', 'weight'});
      if (!ids.add(projectIdentity(row['task_id']))) {
        throw const FormatException('Duplicate expense allocation.');
      }
      total += BigInt.from(workforceInteger(row['weight'], positive: true));
    }
    if (total > BigInt.from(9007199254740990)) {
      throw const FormatException('Allocation weights overflow.');
    }
  }
  if (action == 'expense_approve' || action == 'expense_reject') {
    projectDigest(p['digest']);
  }
  if (p.containsKey('posting_date')) {
    CivilDate.parse(p['posting_date'] as String);
  }
  if (action == 'settle') {
    projectIdentity(p['obligation_id']);
    projectIdentity(p['bank_id']);
    workforceInteger(p['bank_version'], positive: true);
    projectText(p['evidence_reference'], 160);
    if (projectAmount(p['amount'] as String, 'XXX').minorUnits <= BigInt.zero) {
      throw const FormatException('Settlement amount must be positive.');
    }
  }
  if (action == 'billing_prepare') {
    projectIdentity(p['invoice_id']);
    CivilDate.parse(p['document_date'] as String);
    CivilDate.parse(p['due_date'] as String);
    projectOptionalIdentity(p['exchange_rate_id']);
    final list = p['units'];
    if (list is! List || list.isEmpty || list.length > 200) {
      throw const FormatException('One to two hundred whole sources required.');
    }
    final ids = <String>{};
    for (final value in list) {
      final row = projectMap(value);
      calendarFields(row, {
        'unit_id',
        'source_version',
        'source_digest',
        'product_id',
        'product_version',
        'tax_definition_id',
        'tax_version',
        'description',
      });
      if (!ids.add(projectIdentity(row['unit_id']))) {
        throw const FormatException('Duplicate billing source.');
      }
      projectIdentity(row['product_id']);
      workforceInteger(row['source_version'], positive: true);
      workforceInteger(row['product_version'], positive: true);
      projectDigest(row['source_digest']);
      projectOptionalIdentity(row['tax_definition_id']);
      if (row['tax_definition_id'] != null) {
        workforceInteger(row['tax_version'], positive: true);
      } else if (row['tax_version'] != null) {
        throw const FormatException('Tax version has no source.');
      }
      projectText(row['description'], 1000);
    }
  } else if (action.startsWith('billing_')) {
    workforceInteger(p['invoice_version'], positive: true);
    if (action == 'billing_decide') {
      projectState(p['decision'], {'approved', 'rejected'});
    }
  }
}

final class ProjectFinanceRow {
  ProjectFinanceRow._(
    this.section,
    this.id,
    this.version,
    this.status,
    this.title,
    this.amount,
    this.values,
  );
  factory ProjectFinanceRow.fromJson(
    ProjectFinanceSection section,
    Map<String, Object?> j,
    String currency,
  ) {
    final id = projectIdentity(j['id']);
    int version = 1;
    String status = 'recorded', title = section.name;
    Money? amount;
    final common = {'id'};
    Set<String> allow;
    switch (section) {
      case ProjectFinanceSection.expenses:
        allow = {
          ...common,
          'tenant_id',
          'legal_entity_id',
          'branch_id',
          'project_id',
          'employee_id',
          'version',
          'status',
          'revision_id',
          'employee_name',
          'external_reference',
          'purpose',
          'service_date',
          'evidence_reference',
          'evidence_documents',
          'original_currency',
          'base_currency',
          'original_precision',
          'base_precision',
          'net',
          'tax',
          'gross',
          'base_net',
          'base_tax',
          'base_gross',
          'tax_rounding_residue',
          'tax_definition_id',
          'tax_version',
          'tax_basis',
          'no_tax_reason',
          'exchange_rate_id',
          'exchange_rate_version',
          'fx_numerator',
          'fx_denominator',
          'fx_basis',
          'expense_account_id',
          'tax_account_id',
          'liability_account_id',
          'billable',
          'bill_amount',
          'digest',
          'recorded_by',
          'reason',
          'allocations',
        };
        version = workforceInteger(j['version'], positive: true);
        status = projectState(j['status'], {
          'draft',
          'submitted',
          'approved',
          'rejected',
          'posted',
          'reversed',
          'cancelled',
        });
        title = projectText(j['purpose'], 500);
        projectIdentity(j['revision_id']);
        projectIdentity(j['employee_id']);
        projectDigest(j['digest']);
        expenseEvidenceProofs(j['evidence_documents']);
        final c = j['original_currency'] as String,
            base = j['base_currency'] as String;
        final net = projectAmount(j['net'] as String, c),
            tax = projectAmount(j['tax'] as String, c),
            gross = projectAmount(j['gross'] as String, c);
        final baseNet = projectAmount(j['base_net'] as String, base),
            baseTax = projectAmount(j['base_tax'] as String, base),
            baseGross = projectAmount(j['base_gross'] as String, base);
        if (net + tax != gross ||
            baseNet + baseTax != baseGross ||
            base != currency ||
            gross.minorUnits <= BigInt.zero) {
          throw const FormatException(
            'Expense projection lost original money.',
          );
        }
        final n = BigInt.parse(j['fx_numerator'] as String),
            d = BigInt.parse(j['fx_denominator'] as String),
            precision = projectPrecision(j['base_precision']);
        if (n <= BigInt.zero ||
            d <= BigInt.zero ||
            projectRoundRatio(gross.minorUnits * n, d, precision) !=
                baseGross.minorUnits ||
            projectRoundRatio(net.minorUnits * n, d, precision) !=
                baseNet.minorUnits) {
          throw const FormatException('Expense FX evidence changed.');
        }
        final residue = Money.parse(j['tax_rounding_residue'] as String, base);
        if (baseTax.minorUnits -
                projectRoundRatio(tax.minorUnits * n, d, precision) !=
            residue.minorUnits) {
          throw const FormatException('Expense residue changed.');
        }
        final list = j['allocations'];
        if (list is! List || list.isEmpty || list.length > 50) {
          throw const FormatException('Invalid expense allocations.');
        }
        var total = BigInt.zero;
        final weights = <ProjectAllocationWeight>[];
        for (var i = 0; i < list.length; i++) {
          final a = projectMap(list[i]);
          calendarFields(a, {
            'id',
            'task_id',
            'task_name',
            'ordinal',
            'weight',
            'amount',
          });
          if (a['ordinal'] != i + 1) {
            throw const FormatException('Expense allocation order changed.');
          }
          weights.add(
            ProjectAllocationWeight(
              projectIdentity(a['task_id']),
              workforceInteger(a['weight'], positive: true),
            ),
          );
          total += projectAmount(a['amount'] as String, base).minorUnits;
        }
        final expected = allocateProjectExpense(baseGross, weights, precision);
        if (total != baseGross.minorUnits) {
          throw const FormatException(
            'Expense allocation lost original total.',
          );
        }
        for (var i = 0; i < expected.length; i++) {
          if (expected[i].amount.minorUnits !=
              projectAmount(
                projectMap(list[i])['amount'] as String,
                base,
              ).minorUnits) {
            throw const FormatException('Expense allocation rounding changed.');
          }
        }
        amount = baseGross;
        break;
      case ProjectFinanceSection.obligations:
        allow = {
          ...common,
          'expense_id',
          'revision_id',
          'currency_code',
          'amount',
          'outstanding',
          'account_id',
          'journal_id',
          'posting_date',
        };
        projectIdentity(j['expense_id']);
        projectIdentity(j['revision_id']);
        projectIdentity(j['journal_id']);
        CivilDate.parse(j['posting_date'] as String);
        amount = projectAmount(
          j['amount'] as String,
          j['currency_code'] as String,
        );
        final due = projectAmount(j['outstanding'] as String, currency);
        if (due.minorUnits > amount.minorUnits) {
          throw const FormatException(
            'Obligation outstanding exceeds original.',
          );
        }
        title = 'Reimbursement obligation';
        status = due.minorUnits == BigInt.zero ? 'resolved' : 'outstanding';
        break;
      case ProjectFinanceSection.settlements:
        allow = {
          ...common,
          'obligation_id',
          'posting_date',
          'amount',
          'bank_id',
          'bank_version',
          'evidence_reference',
          'journal_id',
          'status',
          'version',
        };
        version = workforceInteger(j['version'], positive: true);
        status = projectState(j['status'], {'recorded', 'reversed'});
        title = projectText(j['evidence_reference'], 160);
        projectIdentity(j['bank_id']);
        projectIdentity(j['obligation_id']);
        projectIdentity(j['journal_id']);
        amount = projectAmount(j['amount'] as String, currency);
        break;
      case ProjectFinanceSection.billing:
        allow = {
          ...common,
          'version',
          'status',
          'invoice_id',
          'digest',
          'prepared_by',
          'invoice_status',
          'invoice_version',
          'document_date',
          'currency_code',
          'total',
          'unit_count',
        };
        version = workforceInteger(j['version'], positive: true);
        status = projectState(j['status'], {'prepared', 'posted', 'cancelled'});
        projectIdentity(j['invoice_id']);
        projectDigest(j['digest']);
        workforceInteger(j['invoice_version'], positive: true);
        final count = workforceInteger(j['unit_count'], positive: true);
        if (count > 200) {
          throw const FormatException('Oversized billing projection.');
        }
        title = '$count whole billing units';
        amount = projectAmount(
          j['total'] as String,
          j['currency_code'] as String,
        );
        break;
      case ProjectFinanceSection.units:
        allow = {
          ...common,
          'source_kind',
          'source_id',
          'source_version',
          'source_digest',
          if (j.containsKey('source_name')) 'source_name',
          if (j['source_kind'] == 'milestone') ...{
            'payment_terms',
            'payment_due_days',
          },
          'amount',
          'payable_seconds',
          'status',
        };
        final source = ProjectBillingSource.values.byName(
          j['source_kind'] as String,
        );
        if (source == ProjectBillingSource.milestone) {
          projectText(j['payment_terms'], 1000);
          final days = workforceInteger(j['payment_due_days']);
          if (days < 0 || days > 365) {
            throw const FormatException('Milestone payment term changed.');
          }
        }
        version = workforceInteger(j['source_version'], positive: true);
        amount = projectAmount(j['amount'] as String, currency);
        ProjectBillableUnit(
          id: id,
          projectId: '00000000-0000-0000-0000-000000000000',
          source: source,
          sourceId: projectIdentity(j['source_id']),
          sourceVersion: version,
          digest: projectDigest(j['source_digest']),
          amount: amount,
          precision: 6,
          payableSeconds: j['payable_seconds'] == null
              ? null
              : workforceInteger(j['payable_seconds'], positive: true),
        );
        status = projectState(j['status'], {
          'available',
          'reserved',
          'billed',
          'waived',
          'cancelled',
        });
        title = j['source_name'] == null
            ? '${source.name} · whole approved source'
            : projectText(j['source_name'], 500);
        break;
      case ProjectFinanceSection.serviceCosts:
        allow = {
          ...common,
          'provider_source_id',
          'source_revision_id',
          'source_version',
          'source_digest',
          'currency_code',
          'precision',
          'service_date',
          'payable_seconds',
          'hourly_cost',
          'amount',
          'status',
          'recorded_at',
        };
        projectIdentity(j['provider_source_id']);
        projectIdentity(j['source_revision_id']);
        projectDigest(j['source_digest']);
        version = workforceInteger(j['source_version'], positive: true);
        status = projectState(j['status'], {'approved', 'cancelled'});
        final precision = projectPrecision(j['precision']);
        if (j['currency_code'] != currency) {
          throw const FormatException('Service cost currency changed.');
        }
        final seconds = workforceInteger(j['payable_seconds']);
        if (seconds < 0 ||
            seconds > 2678400 ||
            status == 'cancelled' && seconds != 0) {
          throw const FormatException('Service cost duration changed.');
        }
        final rate = projectAmount(j['hourly_cost'] as String, currency);
        amount = projectAmount(j['amount'] as String, currency);
        if (projectRoundRatio(
              rate.minorUnits * BigInt.from(seconds),
              BigInt.from(3600),
              precision,
            ) !=
            amount.minorUnits) {
          throw const FormatException('Service cost evidence changed.');
        }
        title =
            'Service labor cost · ${CivilDate.parse(j['service_date'] as String).value}';
        DateTime.parse(j['recorded_at'] as String);
        break;
      case ProjectFinanceSection.history:
        allow = {
          ...common,
          'aggregate_id',
          'action',
          'version',
          'reason',
          'actor_id',
          'recorded_at',
        };
        projectIdentity(j['aggregate_id']);
        projectIdentity(j['actor_id']);
        projectFinanceCapability(j['action'] as String);
        version = workforceInteger(j['version'], positive: true);
        title = projectText(j['reason'], 1000);
        DateTime.parse(j['recorded_at'] as String);
        break;
    }
    calendarFields(j, allow);
    return ProjectFinanceRow._(
      section,
      id,
      version,
      status,
      title,
      amount,
      Map.unmodifiable(jsonDecode(jsonEncode(j)) as Map<String, Object?>),
    );
  }
  final ProjectFinanceSection section;
  final String id, status, title;
  final int version;
  final Money? amount;
  final Map<String, Object?> values;
}

final class ProjectFinancePage<T> {
  const ProjectFinancePage(this.rows, this.nextAfter);
  final List<T> rows;
  final String? nextAfter;
}

final class ProjectFinanceChoice {
  ProjectFinanceChoice.fromJson(Map<String, Object?> j)
    : id = projectIdentity(j['id']),
      name = projectText(j['name'], 180),
      code = projectText(j['code'], 80),
      version = workforceInteger(j['version'], positive: true),
      values = Map.unmodifiable(j) {
    const allowed = {
      'id',
      'name',
      'code',
      'version',
      'currency_code',
      'unit_id',
      'rate',
      'inclusive',
      'valid_from',
      'valid_to',
      'source_currency',
      'target_currency',
      'effective_date',
      'source_digest',
      'source_version',
      'seconds',
      'amount',
    };
    if (!j.keys.toSet().containsAll({'id', 'name', 'code', 'version'}) ||
        j.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Finance choice fields changed.');
    }
    if (j['unit_id'] != null) {
      projectIdentity(j['unit_id']);
    }
    if (j['source_digest'] != null) {
      projectDigest(j['source_digest']);
      workforceInteger(j['source_version'], positive: true);
      workforceInteger(j['seconds'], positive: true);
      projectAmount(j['amount'] as String, j['currency_code'] as String);
    }
  }
  final String id, name, code;
  final int version;
  final Map<String, Object?> values;
}

final class ProjectMargin {
  ProjectMargin.fromJson(Map<String, Object?> j)
    : currency = j['currency_code'] as String,
      asOf = DateTime.parse(j['as_of'] as String),
      effectiveDate = CivilDate.parse(j['effective_date'] as String),
      values = Map.unmodifiable({
        for (final k in fields)
          k: Money.parse(j[k] as String, j['currency_code'] as String),
      }) {
    calendarFields(j, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'as_of',
      'effective_date',
      'currency_code',
      ...fields,
    });
    if (values['posted_revenue']! -
            values['posted_credits']! -
            values['time_cost']! -
            values['service_cost']! -
            values['expense_cost']! !=
        values['margin']) {
      throw const FormatException('Margin projection does not reconcile.');
    }
  }
  static const fields = {
    'budget',
    'commitments',
    'time_cost',
    'service_cost',
    'expense_cost',
    'posted_revenue',
    'posted_credits',
    'margin',
    'outstanding_reimbursements',
  };
  final String currency;
  final DateTime asOf;
  final CivilDate effectiveDate;
  final Map<String, Money> values;
}

abstract interface class ProjectFinanceRepository {
  Future<void> authorize(TenantContext scope, String capability);
  Future<void> authorizeEvidence(
    TenantContext scope,
    String projectId,
    String expenseId,
  );
  Future<ProjectFinancePage<ProjectFinanceRow>> detail(
    TenantContext scope,
    String projectId,
    String currency,
    ProjectFinanceSection section, {
    String? after,
    String? targetId,
  });
  Future<ProjectFinancePage<ProjectFinanceChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
    String? projectId,
  });
  Future<ProjectMargin> margin(
    TenantContext scope,
    String projectId,
    DateTime asOf,
    CivilDate effectiveDate,
  );
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>?> receipt(
    TenantContext scope,
    String commandId,
    String action,
  );
}
