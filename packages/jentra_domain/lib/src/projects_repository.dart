import 'dart:convert';
import 'calendar_repository.dart';
import 'calendar_resolution.dart';
import 'commands.dart';
import 'employee.dart';
import 'money.dart';
import 'project_values.dart';
import 'tenant_context.dart';
import 'work_time.dart';
import 'workforce.dart';

const projectCapabilities = {
  'projects.view',
  'projects.manage',
  'projects.approve',
  'projects.cost.view',
  'projects.cost.manage',
  'projects.time.manage',
  'projects.time.approve',
  'projects.billing.manage',
};
Map<String, Object?> projectMap(Object? value) => workforceMap(value);
String projectText(Object? value, int max) {
  final s = workforceText(value, max);
  if (s != s.trim() || RegExp(r'[\x00-\x1f\x7f]').hasMatch(s)) {
    throw const FormatException(
      'Project text must be trimmed and contain no controls.',
    );
  }
  return s;
}

String projectIdentity(Object? value) => projectUuid(calendarUuid(value));
String? projectOptionalIdentity(Object? value) =>
    value == null ? null : projectIdentity(value);
String projectDigest(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw const FormatException('Project digest is invalid.');
  }
  return value;
}

int projectPrecision(Object? value) {
  final n = workforceInteger(value);
  if (n > 6) {
    throw const FormatException('Project precision is invalid.');
  }
  return n;
}

String projectState(Object? value, Set<String> states) {
  if (value is! String || !states.contains(value)) {
    throw const FormatException('Project state is invalid.');
  }
  return value;
}

void projectScope(Map<String, Object?> row, TenantContext scope) {
  if (row['tenant_id'] != scope.tenantId ||
      row['legal_entity_id'] != scope.legalEntityId ||
      row['branch_id'] != scope.branchId) {
    throw const FormatException('Project response scope changed.');
  }
}

void _parent(Map<String, Object?> row, String project) {
  if (projectIdentity(row['project_id']) != project) {
    throw const FormatException('Project child ownership changed.');
  }
}

Money _amount(Object? value, String currency, int precision) {
  if (value is! String) {
    throw const FormatException('Project money must remain a decimal string.');
  }
  final m = projectAmount(value, currency);
  if (m.minorUnits % BigInt.from(10).pow(6 - precision) != BigInt.zero) {
    throw const FormatException(
      'Project amount differs from published precision.',
    );
  }
  return m;
}

final class ProjectRecord {
  ProjectRecord.fromJson(Map<String, Object?> r)
    : id = projectIdentity(r['id']),
      code = projectText(r['code'], 32),
      name = projectText(r['name'], 160),
      customerId = projectOptionalIdentity(r['customer_id']),
      customerName = r['customer_name'] == null
          ? null
          : projectText(r['customer_name'], 160),
      managerId = projectIdentity(r['manager_id']),
      managerName = projectText(r['manager_name'], 160),
      currency = projectAmount('0', r['currency_code'] as String).currencyCode,
      precision = projectPrecision(r['precision']),
      start = CivilDate.parse(r['start_date'] as String),
      end = CivilDate.parse(r['end_date_exclusive'] as String),
      version = workforceInteger(r['version'], positive: true),
      status = projectState(r['status'], {'open', 'closed'}),
      planId = projectOptionalIdentity(r['current_plan_id']) {
    calendarFields(r, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'code',
      'name',
      'customer_id',
      'customer_name',
      'manager_id',
      'manager_name',
      'currency_code',
      'precision',
      'start_date',
      'end_date_exclusive',
      'version',
      'status',
      'current_plan_id',
    });
    for (final k in ['tenant_id', 'legal_entity_id', 'branch_id']) {
      projectIdentity(r[k]);
    }
    final days = end.utc.difference(start.utc).inDays;
    if (days < 1 ||
        days > 366 ||
        !RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code) ||
        (customerId == null) != (customerName == null)) {
      throw const FormatException('Project directory record is invalid.');
    }
  }
  final String id, code, name, managerId, managerName, currency, status;
  final String? customerId, customerName, planId;
  final int precision, version;
  final CivilDate start, end;
}

enum ProjectSection {
  plans,
  tasks,
  resources,
  cost,
  resourceCost,
  time,
  timeCost,
  units,
  timeEvents,
}

extension ProjectSectionWire on ProjectSection {
  String get wire => switch (this) {
    ProjectSection.resourceCost => 'resource_cost',
    ProjectSection.timeCost => 'time_cost',
    ProjectSection.timeEvents => 'time_events',
    _ => name,
  };
  bool get privateCost => {
    ProjectSection.cost,
    ProjectSection.resourceCost,
    ProjectSection.timeCost,
  }.contains(this);
}

sealed class ProjectRow {
  const ProjectRow(this.id);
  final String id;
}

final class ProjectDecision {
  ProjectDecision.fromJson(Map<String, Object?> r)
    : decision = projectState(r['decision'], {'approved', 'rejected'}),
      digest = projectDigest(r['digest']),
      reason = projectText(r['reason'], 1000),
      actorId = projectIdentity(r['decided_by']),
      recordedAt = workforceRecorded(r['decided_at']) {
    calendarFields(r, {
      'decision',
      'digest',
      'reason',
      'decided_by',
      'decided_at',
    });
  }
  final String decision, digest, reason, actorId;
  final DateTime recordedAt;
}

final class ProjectPlan extends ProjectRow {
  ProjectPlan.fromJson(Map<String, Object?> r, String project)
    : version = workforceInteger(r['version'], positive: true),
      digest = projectDigest(r['digest']),
      terms = projectText(r['terms'], 2000),
      reason = projectText(r['reason'], 1000),
      status = projectState(r['status'], {
        'pending',
        'approved',
        'rejected',
        'superseded',
      }),
      actorId = projectIdentity(r['prepared_by']),
      recordedAt = workforceRecorded(r['prepared_at']),
      decision = r['decision'] == null
          ? null
          : ProjectDecision.fromJson(projectMap(r['decision'])),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'project_id',
      'version',
      'digest',
      'terms',
      'reason',
      'status',
      'prepared_by',
      'prepared_at',
      'decision',
    });
    _parent(r, project);
    projectIdentity(r['tenant_id']);
    projectIdentity(r['legal_entity_id']);
    if (decision != null &&
            (decision!.actorId == actorId || decision!.digest != digest) ||
        status == 'pending' && decision != null ||
        status != 'pending' && decision == null ||
        status == 'rejected' && decision!.decision != 'rejected' ||
        {'approved', 'superseded'}.contains(status) &&
            decision!.decision != 'approved') {
      throw const FormatException('Project decision lineage changed.');
    }
  }
  final int version;
  final String digest, terms, reason, status, actorId;
  final DateTime recordedAt;
  final ProjectDecision? decision;
}

final class ProjectTask extends ProjectRow {
  ProjectTask.fromJson(Map<String, Object?> r, String project)
    : planId = projectIdentity(r['plan_id']),
      name = projectText(r['name'], 160),
      basis = ProjectTaskBasis(
        id: projectIdentity(r['id']),
        projectId: project,
        start: CivilDate.parse(r['start_date'] as String),
        endExclusive: CivilDate.parse(r['end_date_exclusive'] as String),
        plannedSeconds: workforceInteger(r['planned_seconds']),
        progressBasisPoints: workforceInteger(r['progress']),
        dependencies: (r['dependencies'] as List).map(projectIdentity),
      ),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'project_id',
      'plan_id',
      'name',
      'start_date',
      'end_date_exclusive',
      'planned_seconds',
      'dependencies',
      'progress',
    });
    _parent(r, project);
  }
  final String planId, name;
  final ProjectTaskBasis basis;
}

final class ProjectResource extends ProjectRow {
  ProjectResource.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
  ) : planId = projectIdentity(r['plan_id']),
      taskId = projectIdentity(r['task_id']),
      employeeId = projectIdentity(r['employee_id']),
      employeeName = projectText(r['employee_name'], 160),
      calendarId = projectIdentity(r['calendar_version_id']),
      startLocal = projectText(r['start_local'], 19),
      endLocal = projectText(r['end_local'], 19),
      startOffset = _offset(r['start_offset_seconds']),
      endOffset = _offset(r['end_offset_seconds']),
      span = WorkSpan(
        workforceInstant(r['start_utc']),
        workforceInstant(r['end_utc']),
      ),
      plannedSeconds = workforceInteger(r['planned_seconds'], positive: true),
      billRate = projectAmount(r['bill_rate'] as String, currency),
      active = r['active'] == true,
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'project_id',
      'plan_id',
      'task_id',
      'employee_id',
      'employee_name',
      'calendar_version_id',
      'start_local',
      'end_local',
      'start_offset_seconds',
      'end_offset_seconds',
      'start_utc',
      'end_utc',
      'planned_seconds',
      'bill_rate',
      'active',
    });
    _parent(r, project);
    _resolved(startLocal, startOffset, span.startUtc);
    _resolved(endLocal, endOffset, span.endUtc);
    if (r['active'] is! bool ||
        plannedSeconds != span.seconds ||
        span.seconds > 86400) {
      throw const FormatException('Project resource capacity changed.');
    }
  }
  final String planId,
      taskId,
      employeeId,
      employeeName,
      calendarId,
      startLocal,
      endLocal;
  final int startOffset, endOffset, plannedSeconds;
  final WorkSpan span;
  final Money billRate;
  final bool active;
}

int _offset(Object? v) {
  if (v is! int || v.abs() > 86400) {
    throw const FormatException('Project offset is invalid.');
  }
  return v;
}

void _resolved(String local, int offset, DateTime utc) {
  if (workforceLocalTime(local).subtract(Duration(seconds: offset)) != utc) {
    throw const FormatException('Project local and UTC evidence differs.');
  }
}

PayableWork _work(Map<String, Object?> r) {
  final breaks = r['breaks'];
  if (breaks is! List) {
    throw const FormatException(
      'Project breaks must be ordered whole-second spans.',
    );
  }
  return PayableWork(
    WorkSpan(workforceInstant(r['start_utc']), workforceInstant(r['end_utc'])),
    breaks.map((v) {
      final b = projectMap(v);
      calendarFields(b, {'start_utc', 'end_utc'});
      return WorkSpan(
        workforceInstant(b['start_utc']),
        workforceInstant(b['end_utc']),
      );
    }),
  );
}

final class ProjectTime extends ProjectRow {
  ProjectTime.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
    int precision,
  ) : employeeId = projectIdentity(r['employee_id']),
      employeeName = projectText(r['employee_name'], 160),
      version = workforceInteger(r['version'], positive: true),
      status = projectState(r['status'], {
        'draft',
        'submitted',
        'approved',
        'rejected',
        'cancelled',
      }),
      revisionId = projectIdentity(r['revision_id']),
      planId = projectIdentity(r['plan_id']),
      taskId = projectIdentity(r['task_id']),
      resourceId = projectIdentity(r['resource_slot_id']),
      startLocal = projectText(r['start_local'], 19),
      endLocal = projectText(r['end_local'], 19),
      startOffset = _offset(r['start_offset_seconds']),
      endOffset = _offset(r['end_offset_seconds']),
      work = _work(r),
      attendanceClaimId = projectOptionalIdentity(r['attendance_claim_id']),
      billAmount = _amount(r['bill_amount'], currency, precision),
      digest = projectDigest(r['digest']),
      reason = projectText(r['reason'], 1000),
      actorId = projectIdentity(r['recorded_by']),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'project_id',
      'employee_id',
      'employee_name',
      'version',
      'status',
      'revision_id',
      'plan_id',
      'task_id',
      'resource_slot_id',
      'start_local',
      'end_local',
      'start_offset_seconds',
      'end_offset_seconds',
      'start_utc',
      'end_utc',
      'breaks',
      'payable_seconds',
      'attendance_claim_id',
      'bill_amount',
      'digest',
      'reason',
      'recorded_by',
    });
    _parent(r, project);
    for (final k in ['tenant_id', 'legal_entity_id', 'branch_id']) {
      projectIdentity(r[k]);
    }
    _resolved(startLocal, startOffset, work.span.startUtc);
    _resolved(endLocal, endOffset, work.span.endUtc);
    if (work.payableSeconds !=
        workforceInteger(r['payable_seconds'], positive: true)) {
      throw const FormatException('Project time duration changed.');
    }
  }
  final String employeeId,
      employeeName,
      status,
      revisionId,
      planId,
      taskId,
      resourceId,
      startLocal,
      endLocal,
      digest,
      reason,
      actorId;
  final String? attendanceClaimId;
  final int version, startOffset, endOffset;
  final PayableWork work;
  final Money billAmount;
}

final class ProjectBudget extends ProjectRow {
  ProjectBudget.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
    int precision,
  ) : planId = projectIdentity(r['plan_id']),
      budget = _amount(r['budget'], currency, precision),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {'id', 'project_id', 'plan_id', 'budget'});
    _parent(r, project);
    if (id != planId) {
      throw const FormatException('Project budget owner changed.');
    }
  }
  final String planId;
  final Money budget;
}

final class ProjectResourceCost extends ProjectRow {
  ProjectResourceCost.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
  ) : planId = projectIdentity(r['plan_id']),
      hourlyRate = projectAmount(r['hourly_rate'] as String, currency),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {'id', 'project_id', 'plan_id', 'hourly_rate'});
    _parent(r, project);
  }
  final String planId;
  final Money hourlyRate;
}

final class ProjectTimeCost extends ProjectRow {
  ProjectTimeCost.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
    int precision,
  ) : entryId = projectIdentity(r['entry_id']),
      revisionId = projectIdentity(r['revision_id']),
      hourlyRate = projectAmount(r['hourly_rate'] as String, currency),
      amount = _amount(r['amount'], currency, precision),
      active = r['active'] == true,
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'project_id',
      'entry_id',
      'revision_id',
      'hourly_rate',
      'amount',
      'active',
    });
    _parent(r, project);
    if (id != revisionId || r['active'] is! bool) {
      throw const FormatException('Project cost source changed.');
    }
  }
  final String entryId, revisionId;
  final Money hourlyRate, amount;
  final bool active;
}

final class ProjectUnit extends ProjectRow {
  ProjectUnit.fromJson(
    Map<String, Object?> r,
    String project,
    String currency,
    int precision,
  ) : basis = ProjectBillableUnit(
        id: projectIdentity(r['id']),
        projectId: project,
        source: ProjectBillingSource.values.firstWhere(
          (x) => x.name == r['source_kind'],
        ),
        sourceId: projectIdentity(r['source_id']),
        sourceVersion: workforceInteger(r['source_version'], positive: true),
        digest: projectDigest(r['source_digest']),
        amount: _amount(r['amount'], currency, precision),
        precision: precision,
        payableSeconds: r['payable_seconds'] == null
            ? null
            : workforceInteger(r['payable_seconds'], positive: true),
      ),
      status = projectState(r['status'], {
        'available',
        'reserved',
        'billed',
        'waived',
        'cancelled',
      }),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'project_id',
      'branch_id',
      'source_kind',
      'source_id',
      'source_version',
      'source_digest',
      'amount',
      'payable_seconds',
      'status',
      'quantity',
    });
    _parent(r, project);
    projectIdentity(r['branch_id']);
    if (r['quantity'] != basis.salesQuantity) {
      throw const FormatException('Project whole-unit quantity changed.');
    }
  }
  final ProjectBillableUnit basis;
  final String status;
}

final class ProjectTimeEvent extends ProjectRow {
  ProjectTimeEvent.fromJson(Map<String, Object?> r, String project)
    : entryId = projectIdentity(r['entry_id']),
      revisionId = projectIdentity(r['revision_id']),
      action = projectText(r['action'], 32),
      version = workforceInteger(r['version'], positive: true),
      reason = projectText(r['reason'], 1000),
      actorId = projectIdentity(r['actor_id']),
      recordedAt = workforceRecorded(r['recorded_at']),
      super(projectIdentity(r['id'])) {
    calendarFields(r, {
      'id',
      'project_id',
      'entry_id',
      'revision_id',
      'action',
      'version',
      'reason',
      'actor_id',
      'recorded_at',
    });
    _parent(r, project);
    ProjectCommands.capability(action);
    if (!action.startsWith('time_')) {
      throw const FormatException('Project time history action changed.');
    }
  }
  final String entryId, revisionId, action, reason, actorId;
  final int version;
  final DateTime recordedAt;
}

final class ProjectPage<T> {
  ProjectPage(Iterable<T> rows, this.next) : rows = List.unmodifiable(rows);
  final List<T> rows;
  final String? next;
}

final class ProjectDetail {
  ProjectDetail(
    this.project,
    this.section,
    Iterable<ProjectRow> rows,
    this.next,
  ) : rows = List.unmodifiable(rows);
  final ProjectRecord project;
  final ProjectSection section;
  final List<ProjectRow> rows;
  final String? next;
}

final class ProjectProviderState {
  const ProjectProviderState(
    this.currency,
    this.precision, {
    required this.expenseEvidence,
    required this.supplierBill,
  });
  final String currency;
  final int precision;
  final bool expenseEvidence, supplierBill;
}

final class ProjectChoice {
  ProjectChoice.fromJson(Map<String, Object?> r, this.kind)
    : id = projectIdentity(r['id']),
      name = projectText(r['name'], 160),
      code = projectText(r['code'], 32),
      version = kind == 'calendars'
          ? null
          : workforceInteger(r['version'], positive: true),
      coverage = kind == 'calendars'
          ? CalendarCoverage(
              id: projectIdentity(r['id']),
              startDate: r['start_date'] as String,
              endDateExclusive: r['end_date_exclusive'] as String,
              timezone: r['timezone'] as String,
            )
          : null {
    if (!{'employees', 'customers', 'calendars'}.contains(kind)) {
      throw const FormatException('Project picker is invalid.');
    }
    calendarFields(
      r,
      kind == 'calendars'
          ? {
              'id',
              'name',
              'code',
              'start_date',
              'end_date_exclusive',
              'timezone',
            }
          : {'id', 'name', 'code', 'version'},
    );
  }
  final String id, name, code, kind;
  final int? version;
  final CalendarCoverage? coverage;
}

final class ProjectCommands {
  static String capability(String action) => switch (action) {
    'create' || 'plan' || 'progress' || 'close' => 'projects.manage',
    'approve_plan' || 'reject_plan' => 'projects.approve',
    'time_create' || 'time_correct' || 'time_submit' => 'projects.time.manage',
    'time_approve' || 'time_reject' || 'time_cancel' => 'projects.time.approve',
    'waive' => 'projects.billing.manage',
    _ => throw const FormatException('Project action is unsupported.'),
  };
  static Set<String> fields(String action) {
    const b = {'action', 'id', 'reason'};
    const time = {'project_id', 'employee_id'};
    return switch (action) {
      'create' => {
        ...b,
        'code',
        'name',
        'customer_id',
        'manager_id',
        'currency_code',
        'start_date',
        'end_date_exclusive',
      },
      'plan' => {...b, 'plan_id', 'terms', 'tasks', 'resources', 'budget'},
      'approve_plan' || 'reject_plan' => {...b, 'plan_id', 'digest'},
      'progress' => {...b, 'task_id', 'progress'},
      'time_create' || 'time_correct' => {
        ...b,
        ...time,
        'resource_slot_id',
        'start_local',
        'end_local',
        'start_offset_seconds',
        'end_offset_seconds',
        'breaks',
        'attendance_claim_id',
      },
      'time_submit' ||
      'time_approve' ||
      'time_reject' ||
      'time_cancel' => {...b, ...time},
      'waive' => {...b, 'unit_id'},
      'close' => b,
      _ => throw const FormatException('Project action is unsupported.'),
    };
  }

  static void validate(Map<String, Object?> p, String currency, int precision) {
    final action = projectText(p['action'], 32);
    capability(action);
    calendarFields(p, fields(action));
    projectIdentity(p['id']);
    projectText(p['reason'], 1000);
    switch (action) {
      case 'create':
        final code = projectText(p['code'], 32);
        if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(code)) {
          throw const FormatException('Project code is invalid.');
        }
        projectText(p['name'], 160);
        projectOptionalIdentity(p['customer_id']);
        projectIdentity(p['manager_id']);
        if (p['currency_code'] != currency) {
          throw const FormatException('Project currency changed.');
        }
        final start = CivilDate.parse(p['start_date'] as String),
            end = CivilDate.parse(p['end_date_exclusive'] as String),
            days = end.utc.difference(start.utc).inDays;
        if (days < 1 || days > 366) {
          throw const FormatException(
            'Project dates must span one to 366 days.',
          );
        }
      case 'plan':
        projectIdentity(p['plan_id']);
        projectText(p['terms'], 2000);
        _amount(p['budget'], currency, precision);
        final tasks = p['tasks'], resources = p['resources'];
        if (tasks is! List ||
            tasks.isEmpty ||
            tasks.length > 200 ||
            resources is! List ||
            resources.length > 366) {
          throw const FormatException(
            'Project plan exceeds its task or resource bound.',
          );
        }
        final graph = ProjectTaskGraph(
          p['id'] as String,
          tasks.map((v) {
            final t = projectMap(v);
            calendarFields(t, {
              'id',
              'name',
              'start_date',
              'end_date_exclusive',
              'planned_seconds',
              'dependencies',
            });
            projectText(t['name'], 160);
            return ProjectTaskBasis(
              id: projectIdentity(t['id']),
              projectId: p['id'] as String,
              start: CivilDate.parse(t['start_date'] as String),
              endExclusive: CivilDate.parse(t['end_date_exclusive'] as String),
              plannedSeconds: workforceInteger(t['planned_seconds']),
              progressBasisPoints: 0,
              dependencies: (t['dependencies'] as List).map(projectIdentity),
            );
          }),
        );
        final sums = <String, int>{}, slots = <String>{};
        for (final v in resources) {
          final s = projectMap(v);
          calendarFields(s, {
            'id',
            'task_id',
            'employee_id',
            'calendar_version_id',
            'start_local',
            'end_local',
            'start_offset_seconds',
            'end_offset_seconds',
            'bill_rate',
            'cost_rate',
          });
          if (!slots.add(projectIdentity(s['id']))) {
            throw const FormatException('Project resource IDs repeat.');
          }
          final task = projectIdentity(s['task_id']);
          projectIdentity(s['employee_id']);
          projectIdentity(s['calendar_version_id']);
          projectAmount(s['bill_rate'] as String, currency);
          projectAmount(s['cost_rate'] as String, currency);
          final a = workforceLocalTime(
                s['start_local'],
              ).subtract(Duration(seconds: _offset(s['start_offset_seconds']))),
              z = workforceLocalTime(
                s['end_local'],
              ).subtract(Duration(seconds: _offset(s['end_offset_seconds']))),
              span = WorkSpan(a, z);
          if (span.seconds > 86400) {
            throw const FormatException('Resource reservation exceeds a day.');
          }
          sums[task] = (sums[task] ?? 0) + span.seconds;
        }
        if (sums.keys.any((id) => !graph.tasks.any((t) => t.id == id)) ||
            graph.tasks.any((t) => t.plannedSeconds != (sums[t.id] ?? 0))) {
          throw const FormatException(
            'Project resources must conserve task planned seconds.',
          );
        }
      case 'approve_plan':
      case 'reject_plan':
        projectIdentity(p['plan_id']);
        projectDigest(p['digest']);
      case 'progress':
        projectIdentity(p['task_id']);
        if (workforceInteger(p['progress']) > 10000) {
          throw const FormatException('Project progress exceeds completion.');
        }
      case 'time_create':
      case 'time_correct':
        projectIdentity(p['project_id']);
        projectIdentity(p['employee_id']);
        projectIdentity(p['resource_slot_id']);
        projectOptionalIdentity(p['attendance_claim_id']);
        final a = workforceLocalTime(
              p['start_local'],
            ).subtract(Duration(seconds: _offset(p['start_offset_seconds']))),
            z = workforceLocalTime(
              p['end_local'],
            ).subtract(Duration(seconds: _offset(p['end_offset_seconds'])));
        if (p['breaks'] is! List) {
          throw const FormatException('Project breaks must be explicit.');
        }
        PayableWork(
          WorkSpan(a, z),
          (p['breaks'] as List).map((v) {
            final b = projectMap(v);
            calendarFields(b, {'start_utc', 'end_utc'});
            return WorkSpan(
              workforceInstant(b['start_utc']),
              workforceInstant(b['end_utc']),
            );
          }),
        );
      case 'time_submit':
      case 'time_approve':
      case 'time_reject':
      case 'time_cancel':
        projectIdentity(p['project_id']);
        projectIdentity(p['employee_id']);
      case 'waive':
        projectIdentity(p['unit_id']);
      case 'close':
        break;
    }
    if (utf8.encode(jsonEncode(p)).length > 65536) {
      throw const FormatException('Project command exceeds its byte bound.');
    }
  }
}

abstract interface class ProjectRepository {
  Future<ProjectLocalResolution> localCandidates(
    TenantContext scope,
    CalendarCoverage version,
    CivilDate date,
    int minute, {
    int second = 0,
  });
  Future<ProjectPage<ProjectAttendanceClaim>> attendanceClaims(
    TenantContext scope,
    String employeeId, {
    String? after,
  });
  Future<ProjectProviderState> authorize(
    TenantContext scope,
    String capability,
  );
  Future<ProjectPage<ProjectRecord>> directory(
    TenantContext scope, {
    String? after,
  });
  Future<ProjectDetail> detail(
    TenantContext scope,
    String projectId,
    ProjectSection section, {
    String? parentId,
    String? after,
  });
  Future<ProjectPage<ProjectChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
  });
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> command,
    String currency,
    int precision,
  );
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String key,
    String action,
  );
}

/// Original whole-second project boundary resolved by the published IANA zone.
final class ProjectLocalResolution {
  ProjectLocalResolution.fromJson(Map<String, Object?> row)
    : versionId = projectIdentity(row['calendar_version_id']),
      date = CivilDate.parse(row['date'] as String),
      minute = workforceInteger(row['minute']),
      second = workforceInteger(row['second']),
      timezone = projectText(row['timezone'], 100),
      candidates = _candidates(row) {
    calendarFields(row, {
      'calendar_version_id',
      'date',
      'minute',
      'second',
      'timezone',
      'local_datetime',
      'algorithm',
      'candidates',
    });
    if (minute < 0 ||
        minute > 1439 ||
        second < 0 ||
        second > 59 ||
        row['algorithm'] != 'pg-iana-roundtrip-v1') {
      throw const FormatException('Project local resolution metadata changed.');
    }
    final expected = date.utc.add(Duration(minutes: minute, seconds: second));
    if (workforceLocalTime(row['local_datetime']) != expected) {
      throw const FormatException('Project local boundary changed.');
    }
    DateTime? previous;
    for (final instant in candidates) {
      if (instant.utc.add(Duration(seconds: instant.offsetSeconds)) !=
              expected ||
          previous != null && !instant.utc.isAfter(previous)) {
        throw const FormatException(
          'Project local instant does not round trip or repeats.',
        );
      }
      previous = instant.utc;
    }
  }
  final String versionId, timezone;
  final CivilDate date;
  final int minute, second;
  final List<CalendarInstant> candidates;
  bool get isGap => candidates.isEmpty;
  bool get isAmbiguous => candidates.length > 1;
  static List<CalendarInstant> _candidates(Map<String, Object?> row) {
    final raw = row['candidates'];
    if (raw is! List || raw.length > 4) {
      throw const FormatException(
        'Project instant candidates exceed their bound.',
      );
    }
    return List.unmodifiable(
      raw.map((v) {
        final r = projectMap(v);
        calendarFields(r, {'utc', 'offset_seconds'});
        final offset = r['offset_seconds'];
        if (offset is! int || offset.abs() > 86400) {
          throw const FormatException('Project UTC offset is invalid.');
        }
        return CalendarInstant(workforceInstant(r['utc']), offset);
      }),
    );
  }
}

final class ProjectAttendanceClaim {
  ProjectAttendanceClaim.fromJson(Map<String, Object?> r)
    : id = projectIdentity(r['id']),
      employeeId = projectIdentity(r['employee_id']),
      calendarId = projectIdentity(r['calendar_version_id']),
      span = WorkSpan(
        workforceInstant(r['start_utc']),
        workforceInstant(r['end_utc']),
      ),
      payableSeconds = workforceInteger(r['payable_seconds'], positive: true) {
    calendarFields(r, {
      'id',
      'employee_id',
      'calendar_version_id',
      'start_utc',
      'end_utc',
      'payable_seconds',
    });
    if (payableSeconds > span.seconds) {
      throw const FormatException('Attendance source duration changed.');
    }
  }
  final String id, employeeId, calendarId;
  final WorkSpan span;
  final int payableSeconds;
}
