import 'dart:convert';
import 'calendar_repository.dart';
import 'commands.dart';
import 'employee.dart';
import 'money.dart';
import 'projects_repository.dart';
import 'project_values.dart';
import 'tenant_context.dart';
import 'workforce.dart';

const milestoneActions = {
  'create',
  'correct',
  'submit',
  'approve',
  'reject',
  'cancel',
};
const milestoneStates = {
  'draft',
  'submitted',
  'approved',
  'rejected',
  'cancelled',
};
Map<String, Object?> milestoneMap(Object? x) => projectMap(x);
Map<String, Object?> _copy(Map<String, Object?> x) =>
    milestoneMap(jsonDecode(jsonEncode(x)));
Money milestoneAmount(Object? x, String currency, int precision) {
  if (x is! String) {
    throw const FormatException('An exact milestone amount is required.');
  }
  final m = projectAmount(x, currency);
  if (precision < 0 ||
      precision > 6 ||
      m.minorUnits % BigInt.from(10).pow(6 - precision) != BigInt.zero) {
    throw const FormatException('Amount differs from project precision.');
  }
  return m;
}

abstract final class MilestoneCommands {
  static String capability(String a) {
    if (!milestoneActions.contains(a)) {
      throw const FormatException('Unknown milestone action.');
    }
    return {'approve', 'reject'}.contains(a)
        ? 'projects.approve'
        : 'projects.manage';
  }

  static Set<String> fields(String a) {
    capability(a);
    return {
      'action',
      'id',
      'project_id',
      'reason',
      if ({'create', 'correct'}.contains(a)) ...{
        'plan_id',
        'task_id',
        'owner_id',
        'name',
        'due_date',
        'amount',
        'commercial_terms',
        'payment_terms',
        'payment_due_days',
        'evidence_reference',
      } else
        'digest',
    };
  }

  static void validate(String a, Map<String, Object?> p) {
    calendarFields(p, fields(a));
    if (p['action'] != a) {
      throw const FormatException('Milestone action changed.');
    }
    for (final k in ['id', 'project_id']) {
      projectIdentity(p[k]);
    }
    projectText(p['reason'], 1000);
    if ({'create', 'correct'}.contains(a)) {
      for (final k in ['plan_id', 'task_id', 'owner_id']) {
        projectIdentity(p[k]);
      }
      projectText(p['name'], 160);
      CivilDate.parse(p['due_date'] as String);
      milestoneAmount(p['amount'], 'XXX', 6);
      projectText(p['commercial_terms'], 2000);
      projectText(p['payment_terms'], 1000);
      projectText(p['evidence_reference'], 160);
      final days = workforceInteger(p['payment_due_days']);
      if (days > 365) {
        throw const FormatException('Payment duration exceeds365 days.');
      }
    } else {
      projectDigest(p['digest']);
    }
  }
}

final class MilestoneRecord {
  MilestoneRecord.fromJson(
    Map<String, Object?> r,
    TenantContext scope,
    String project,
  ) : id = projectIdentity(r['id']),
      projectId = projectIdentity(r['project_id']),
      version = workforceInteger(r['version'], positive: true),
      status = projectState(r['status'], milestoneStates),
      revisionId = projectIdentity(r['revision_id']),
      planId = projectIdentity(r['plan_id']),
      taskId = projectIdentity(r['task_id']),
      ownerId = projectIdentity(r['owner_id']),
      name = projectText(r['name'], 160),
      taskName = projectText(r['task_name'], 160),
      ownerName = projectText(r['owner_name'], 160),
      customerId = projectIdentity(r['customer_id']),
      customerName = projectText(r['customer_name'], 160),
      currency = projectText(r['currency_code'], 3),
      precision = projectPrecision(r['precision']),
      due = CivilDate.parse(r['due_date'] as String),
      amount = milestoneAmount(
        r['amount'],
        r['currency_code'] as String,
        projectPrecision(r['precision']),
      ),
      commercialTerms = projectText(r['commercial_terms'], 2000),
      paymentTerms = projectText(r['payment_terms'], 1000),
      paymentDays = workforceInteger(r['payment_due_days']),
      evidence = projectText(r['evidence_reference'], 160),
      digest = projectDigest(r['digest']),
      actorId = projectIdentity(r['recorded_by']),
      reason = projectText(r['reason'], 1000),
      unitStatus = r['unit_status'] == null
          ? null
          : projectState(r['unit_status'], {
              'available',
              'reserved',
              'billed',
              'waived',
              'cancelled',
            }),
      facts = Map.unmodifiable(_copy(r)) {
    calendarFields(r, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'version',
      'status',
      'revision_id',
      'plan_id',
      'task_id',
      'task_name',
      'owner_id',
      'owner_name',
      'customer_id',
      'customer_name',
      'currency_code',
      'precision',
      'name',
      'due_date',
      'amount',
      'commercial_terms',
      'payment_terms',
      'payment_due_days',
      'evidence_reference',
      'digest',
      'recorded_by',
      'reason',
      'unit_status',
    });
    projectScope(r, scope);
    if (projectId != project ||
        paymentDays > 365 ||
        version > 9007199254740990 ||
        status == 'approved' && unitStatus == null ||
        status != 'approved' &&
            unitStatus != null &&
            unitStatus != 'cancelled') {
      throw const FormatException(
        'Milestone source ownership or lifecycle changed.',
      );
    }
  }
  final String id,
      projectId,
      status,
      revisionId,
      planId,
      taskId,
      ownerId,
      name,
      taskName,
      ownerName,
      customerId,
      customerName,
      currency,
      commercialTerms,
      paymentTerms,
      evidence,
      digest,
      actorId,
      reason;
  final int version, precision, paymentDays;
  final CivilDate due;
  final Money amount;
  final String? unitStatus;
  final Map<String, Object?> facts;
  Map<String, Object?> form(String a) => {
    'action': a,
    'id': id,
    'project_id': projectId,
    'reason': '',
    if ({'create', 'correct'}.contains(a))
      for (final k in [
        'plan_id',
        'task_id',
        'owner_id',
        'name',
        'due_date',
        'amount',
        'commercial_terms',
        'payment_terms',
        'payment_due_days',
        'evidence_reference',
      ])
        k: facts[k]
    else
      'digest': digest,
  };
}

final class MilestoneHistory {
  MilestoneHistory.fromJson(
    Map<String, Object?> row,
    TenantContext scope,
    String project,
    String milestone,
    this.kind,
  ) : id = projectIdentity(row['id']),
      version = workforceInteger(row['version'], positive: true),
      actorId = projectIdentity(
        row[kind == 'events' ? 'actor_id' : 'recorded_by'],
      ),
      recordedAt = workforceRecorded(
        row[kind == 'events' ? 'recorded_at' : 'recorded_at'],
      ),
      _facts = Map.unmodifiable(_copy(row)) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['project_id'] != project ||
        row['milestone_id'] != milestone) {
      throw const FormatException('Historical milestone ownership changed.');
    }
    projectText(row['reason'], 1000);
    projectDigest(row['digest']);
    if (kind == 'events') {
      calendarFields(row, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'project_id',
        'milestone_id',
        'revision_id',
        'version',
        'action',
        'digest',
        'reason',
        'eligibility',
        'actor_id',
        'recorded_at',
      });
      projectScope(row, scope);
      projectIdentity(row['revision_id']);
      MilestoneCommands.capability(row['action'] as String);
      final e = milestoneMap(row['eligibility']);
      if (row['action'] == 'approve') {
        calendarFields(e, {
          'plan_id',
          'task_id',
          'progress_event_id',
          'project_version',
          'progress',
          'completion_evidence',
        });
        for (final k in ['plan_id', 'task_id', 'progress_event_id']) {
          projectIdentity(e[k]);
        }
        workforceInteger(e['project_version'], positive: true);
        projectText(e['completion_evidence'], 160);
        if (e['progress'] != 10000) {
          throw const FormatException(
            'Approved milestone eligibility changed.',
          );
        }
      } else if (e.isNotEmpty) {
        throw const FormatException('Unexpected milestone eligibility.');
      }
    } else if (kind == 'revisions') {
      calendarFields(row, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'project_id',
        'milestone_id',
        'version',
        'plan_id',
        'task_id',
        'task_name',
        'owner_id',
        'owner_name',
        'customer_id',
        'customer_name',
        'currency_code',
        'precision',
        'name',
        'due_date',
        'amount',
        'commercial_terms',
        'payment_terms',
        'payment_due_days',
        'evidence_reference',
        'digest',
        'reason',
        'supersedes_id',
        'recorded_by',
        'recorded_at',
      });
      for (final k in ['plan_id', 'task_id', 'owner_id', 'customer_id']) {
        projectIdentity(row[k]);
      }
      projectOptionalIdentity(row['supersedes_id']);
      for (final k in [
        'task_name',
        'owner_name',
        'customer_name',
        'name',
        'evidence_reference',
      ]) {
        projectText(row[k], 160);
      }
      CivilDate.parse(row['due_date'] as String);
      milestoneAmount(
        row['amount'],
        row['currency_code'] as String,
        projectPrecision(row['precision']),
      );
      projectText(row['commercial_terms'], 2000);
      projectText(row['payment_terms'], 1000);
      if (workforceInteger(row['payment_due_days']) > 365) {
        throw const FormatException('Historical payment duration changed.');
      }
    } else {
      throw const FormatException('Unknown milestone history section.');
    }
  }
  final String id, actorId, kind;
  final int version;
  final DateTime recordedAt;
  final Map<String, Object?> _facts;
  Map<String, Object?> get facts => Map.unmodifiable(_copy(_facts));
}

final class MilestoneDetail {
  MilestoneDetail(
    this.record,
    this.kind,
    Iterable<MilestoneHistory> rows,
    this.next,
  ) : rows = List.unmodifiable(rows);
  final MilestoneRecord record;
  final String kind;
  final List<MilestoneHistory> rows;
  final String? next;
}

Map<String, Object?> milestoneReceipt(
  Object? raw,
  TenantContext scope,
  String project, {
  CommandEnvelope<Map<String, Object?>>? request,
}) {
  final r = milestoneMap(raw);
  calendarFields(r, {
    'request_id',
    'command_id',
    'correlation_id',
    'entity',
    'warnings',
  });
  for (final k in ['request_id', 'command_id', 'correlation_id']) {
    projectIdentity(r[k]);
  }
  final e = milestoneMap(r['entity']);
  calendarFields(e, {
    'id',
    'tenant_id',
    'legal_entity_id',
    'branch_id',
    'project_id',
    'version',
    'status',
    'revision_id',
  });
  projectScope(e, scope);
  projectIdentity(e['id']);
  projectIdentity(e['revision_id']);
  projectState(e['status'], milestoneStates);
  workforceInteger(e['version'], positive: true);
  if (e['project_id'] != project ||
      r['warnings'] is! List ||
      (r['warnings'] as List).isNotEmpty ||
      request != null &&
          (r['command_id'] != request.commandId ||
              e['id'] != request.payload['id'] ||
              e['version'] != request.expectedEntityVersion! + 1)) {
    throw const FormatException('Milestone confirmation changed.');
  }
  return _copy(r);
}

abstract interface class MilestoneRepository {
  ProjectRepository get projects;
  Future<void> authorize(TenantContext scope, String capability);
  Future<ProjectPage<MilestoneRecord>> list(
    TenantContext scope,
    String project, {
    String? after,
  });
  Future<MilestoneDetail> detail(
    TenantContext scope,
    String project,
    String id, {
    String kind = 'events',
    String? after,
  });
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String project,
    String action,
    String key,
  );
}
