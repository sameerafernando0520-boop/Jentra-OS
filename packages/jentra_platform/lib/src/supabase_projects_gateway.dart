import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_projects.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseProjectGateway implements ProjectRepository {
  @override
  Future<ProjectLocalResolution> localCandidates(
    TenantContext scope,
    CalendarCoverage version,
    CivilDate date,
    int minute, {
    int second = 0,
  }) async {
    if (!version.contains(date) ||
        minute < 0 ||
        minute > 1439 ||
        second < 0 ||
        second > 59) {
      throw const FormatException('Project calendar boundary is invalid.');
    }
    final r = await _call('projects_calendar_candidates', scope, {
      'p_version_id': version.id,
      'p_date': date.value,
      'p_minute': minute,
      'p_second': second,
    });
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'resolution',
    });
    projectScope(r, scope);
    final value = ProjectLocalResolution.fromJson(projectMap(r['resolution']));
    if (value.versionId != version.id ||
        value.date.value != date.value ||
        value.minute != minute ||
        value.second != second ||
        value.timezone != version.timezone) {
      throw const FormatException('Project calendar resolution changed.');
    }
    return value;
  }

  @override
  Future<ProjectPage<ProjectAttendanceClaim>> attendanceClaims(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    projectIdentity(employeeId);
    projectOptionalIdentity(after);
    final r = await _call('projects_attendance_claims', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    calendarFields(r, {'rows', 'next_after'});
    return _page(r, after, (row) {
      final c = ProjectAttendanceClaim.fromJson(row);
      if (c.employeeId != employeeId) {
        throw const FormatException('Attendance source employee changed.');
      }
      return c;
    });
  }

  SupabaseProjectGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  });
  final SupabaseClient client;
  final Duration timeout;
  void _require(TenantContext s) {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
  }

  Future<Object?> _rpc(
    String name,
    TenantContext s,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    _require(s);
    try {
      final result = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': s.tenantId,
              'p_legal_entity_id': s.legalEntityId,
              'p_branch_id': s.branchId,
              ...args,
            },
          )
          .timeout(timeout);
      if (client.auth.currentUser?.id != s.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message:
              'The account changed. Reconcile the exact saved request after signing in.',
          retryable: command,
        );
      }
      return result;
    } on PostgrestException catch (e) {
      final code = switch ((e.code, e.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PROJECT_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('55000', 'PAYROLL_INPUT_SEALED') => 'PAYROLL_INPUT_SEALED',
        ('23514', 'WORK_INTERVAL_CONFLICT') => 'WORK_INTERVAL_CONFLICT',
        ('23514', 'PROJECT_RESOURCE_CAPACITY_CONFLICT') =>
          'PROJECT_RESOURCE_CAPACITY_CONFLICT',
        ('23514', 'PROJECT_TASK_CYCLE') => 'PROJECT_TASK_CYCLE',
        ('55000', _) => 'STATE_CONFLICT',
        ('23505', _) => 'IDENTITY_EXISTS',
        (
          '22023' ||
              '22007' ||
              '22008' ||
              '22P02' ||
              '23514' ||
              '23503' ||
              '23502',
          _,
        ) =>
          'VALIDATION_ERROR',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'This project feature is awaiting development installation.',
          'FEATURE_NOT_ENTITLED' =>
            'Projects are unavailable under the current workspace plan.',
          'PERMISSION_DENIED' =>
            'Current scope, capability or MFA does not allow this action.',
          'VERSION_CONFLICT' =>
            'The source changed. Compare its current version before editing.',
          'PAYROLL_INPUT_SEALED' =>
            'Payroll consumed this work. A governed linked correction is required.',
          'WORK_INTERVAL_CONFLICT' =>
            'An approved payable claim or project/service allocation already owns this time.',
          'PROJECT_RESOURCE_CAPACITY_CONFLICT' =>
            'Another approved project reserves this employee capacity.',
          'PROJECT_TASK_CYCLE' => 'Task dependencies contain a cycle.',
          'IDEMPOTENCY_MISMATCH' =>
            'This key belongs to different content. Reconcile its original request.',
          'STATE_CONFLICT' =>
            'Refresh the current approved plan, work source and decision history.',
          'VALIDATION_ERROR' =>
            'Check the named sources, exact amounts, dates, intervals and dependencies.',
          'IDENTITY_EXISTS' =>
            'This immutable project or source identity already exists.',
          'RESOURCE_NOT_FOUND' =>
            'The requested source is unavailable in this scope.',
          'SERVICE_UNAVAILABLE' =>
            'The project service is unavailable. Retry the scoped read.',
          _ =>
            'The result is uncertain. Reconcile the exact encrypted request.',
        },
        retryable: {'UNCERTAIN_RESULT', 'SERVICE_UNAVAILABLE'}.contains(code),
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw DomainError(
        code: command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
        message: command
            ? 'The result is uncertain. Reconcile the exact encrypted request.'
            : 'The project service is unavailable.',
        retryable: true,
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext s,
    Map<String, Object?> p,
  ) async => projectMap(await _rpc(name, s, p));
  @override
  Future<ProjectProviderState> authorize(
    TenantContext scope,
    String capability,
  ) async {
    if (!projectCapabilities.contains(capability)) {
      throw const FormatException('Project capability is invalid.');
    }
    final r = await _call('projects_authorize', scope, {
      'p_capability': capability,
    });
    calendarFields(r, {
      'actor_id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'capability',
      'authorized',
      'currency_code',
      'precision',
      'expense_evidence_provider',
      'supplier_bill_provider',
    });
    projectScope(r, scope);
    if (r['actor_id'] != scope.actorId ||
        r['capability'] != capability ||
        r['authorized'] != true ||
        r['expense_evidence_provider'] is! bool ||
        r['supplier_bill_provider'] is! bool) {
      throw const FormatException('Project authorization changed.');
    }
    return ProjectProviderState(
      projectAmount('0', r['currency_code'] as String).currencyCode,
      projectPrecision(r['precision']),
      expenseEvidence: r['expense_evidence_provider'] as bool,
      supplierBill: r['supplier_bill_provider'] as bool,
    );
  }

  ProjectPage<T> _page<T>(
    Map<String, Object?> page,
    String? after,
    T Function(Map<String, Object?>) parse,
  ) {
    final raw = page['rows'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Project page exceeds its bound.');
    }
    final result = <T>[];
    String? prior = after;
    for (final v in raw) {
      final r = projectMap(v), id = projectIdentity(r['id']);
      if (prior != null && id.compareTo(prior) <= 0) {
        throw const FormatException('Project page order changed.');
      }
      result.add(parse(r));
      prior = id;
    }
    final next = projectOptionalIdentity(page['next_after']);
    if (next != (raw.length == 50 ? prior : null)) {
      throw const FormatException('Project continuation changed.');
    }
    return ProjectPage(result, next);
  }

  @override
  Future<ProjectPage<ProjectRecord>> directory(
    TenantContext scope, {
    String? after,
  }) async {
    projectOptionalIdentity(after);
    final r = await _call('projects_directory', scope, {'p_after': after});
    calendarFields(r, {'rows', 'next_after'});
    return _page(r, after, (v) {
      projectScope(v, scope);
      return ProjectRecord.fromJson(v);
    });
  }

  @override
  Future<ProjectDetail> detail(
    TenantContext scope,
    String projectId,
    ProjectSection section, {
    String? parentId,
    String? after,
  }) async {
    projectIdentity(projectId);
    projectOptionalIdentity(parentId);
    projectOptionalIdentity(after);
    final r = await _call('projects_detail', scope, {
      'p_project_id': projectId,
      'p_kind': section.wire,
      'p_parent_id': parentId,
      'p_after': after,
    });
    calendarFields(r, {'project', 'kind', 'rows', 'next_after'});
    final p = projectMap(r['project']);
    projectScope(p, scope);
    final project = ProjectRecord.fromJson(p);
    if (project.id != projectId || r['kind'] != section.wire) {
      throw const FormatException('Project detail changed.');
    }
    final plan = parentId ?? project.planId;
    final page = _page<ProjectRow>(r, after, (row) {
      final result = switch (section) {
        ProjectSection.plans => ProjectPlan.fromJson(row, projectId),
        ProjectSection.tasks => ProjectTask.fromJson(row, projectId),
        ProjectSection.resources => ProjectResource.fromJson(
          row,
          projectId,
          project.currency,
        ),
        ProjectSection.time => ProjectTime.fromJson(
          row,
          projectId,
          project.currency,
          project.precision,
        ),
        ProjectSection.cost => ProjectBudget.fromJson(
          row,
          projectId,
          project.currency,
          project.precision,
        ),
        ProjectSection.resourceCost => ProjectResourceCost.fromJson(
          row,
          projectId,
          project.currency,
        ),
        ProjectSection.timeCost => ProjectTimeCost.fromJson(
          row,
          projectId,
          project.currency,
          project.precision,
        ),
        ProjectSection.units => ProjectUnit.fromJson(
          row,
          projectId,
          project.currency,
          project.precision,
        ),
        ProjectSection.timeEvents => ProjectTimeEvent.fromJson(row, projectId),
      };
      if (row.containsKey('tenant_id') && row['tenant_id'] != scope.tenantId ||
          row.containsKey('legal_entity_id') &&
              row['legal_entity_id'] != scope.legalEntityId ||
          row.containsKey('branch_id') && row['branch_id'] != scope.branchId) {
        throw const FormatException('Project child scope changed.');
      }
      if ({
                ProjectSection.tasks,
                ProjectSection.resources,
                ProjectSection.cost,
                ProjectSection.resourceCost,
              }.contains(section) &&
              row['plan_id'] != plan ||
          section == ProjectSection.timeEvents && row['entry_id'] != parentId ||
          {ProjectSection.plans, ProjectSection.time}.contains(section) &&
              parentId != null &&
              result.id != parentId) {
        throw const FormatException('Project child parent changed.');
      }
      return result;
    });
    return ProjectDetail(project, section, page.rows, page.next);
  }

  @override
  Future<ProjectPage<ProjectChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
  }) async {
    if (!{'employees', 'customers', 'calendars'}.contains(kind)) {
      throw const FormatException('Project picker is unsupported.');
    }
    projectOptionalIdentity(after);
    final r = await _call('projects_pickers', scope, {
      'p_kind': kind,
      'p_after': after,
    });
    calendarFields(r, {'rows', 'next_after'});
    return _page(r, after, (v) => ProjectChoice.fromJson(v, kind));
  }

  Map<String, Object?> _response(
    Map<String, Object?> row,
    TenantContext scope,
    String action, {
    String? commandId,
    Map<String, Object?>? payload,
    int? version,
  }) {
    calendarFields(row, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    for (final key in ['request_id', 'command_id', 'correlation_id']) {
      projectIdentity(row[key]);
    }
    if (commandId != null && row['command_id'] != commandId ||
        row['warnings'] is! List ||
        (row['warnings'] as List).isNotEmpty) {
      throw const FormatException('Project confirmation changed.');
    }
    final e = projectMap(row['entity']);
    projectScope(e, scope);
    projectIdentity(e['id']);
    final v = workforceInteger(e['version'], positive: true);
    if (payload != null && e['id'] != payload['id'] ||
        version != null && v != version + 1) {
      throw const FormatException(
        'Project confirmation identity/version changed.',
      );
    }
    if (action.startsWith('time_')) {
      calendarFields(e, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'project_id',
        'employee_id',
        'version',
        'status',
        'revision_id',
      });
      projectIdentity(e['project_id']);
      projectIdentity(e['employee_id']);
      projectIdentity(e['revision_id']);
      final expected = switch (action) {
        'time_create' || 'time_correct' => 'draft',
        'time_submit' => 'submitted',
        'time_approve' => 'approved',
        'time_reject' => 'rejected',
        'time_cancel' => 'cancelled',
        _ => throw const FormatException('Project time action changed.'),
      };
      if (e['status'] != expected ||
          payload != null &&
              (e['project_id'] != payload['project_id'] ||
                  e['employee_id'] != payload['employee_id'])) {
        throw const FormatException('Project time transition changed.');
      }
    } else {
      calendarFields(e, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'branch_id',
        'version',
        'status',
        'current_plan_id',
      });
      projectOptionalIdentity(e['current_plan_id']);
      if (e['status'] != (action == 'close' ? 'closed' : 'open') ||
          action == 'create' && e['current_plan_id'] != null ||
          action == 'approve_plan' &&
              payload != null &&
              e['current_plan_id'] != payload['plan_id']) {
        throw const FormatException('Project transition changed.');
      }
    }
    return projectMap(jsonDecode(jsonEncode(row)));
  }

  @override
  Future<Map<String, Object?>> command(
    CommandEnvelope<Map<String, Object?>> c,
    String currency,
    int precision,
  ) async {
    _require(c.context);
    final p = projectMap(jsonDecode(jsonEncode(c.payload)));
    ProjectCommands.validate(p, currency, precision);
    projectIdentity(c.commandId);
    projectIdentity(c.idempotencyKey);
    final version = c.expectedEntityVersion, action = p['action'] as String;
    if (version == null ||
        version < 0 ||
        version >= 9007199254740991 ||
        {'create', 'time_create'}.contains(action) && version != 0 ||
        !{'create', 'time_create'}.contains(action) && version == 0) {
      throw const FormatException('Project expected version is invalid.');
    }
    try {
      final raw = await _rpc('projects_command', c.context, {
        'p_command_id': c.commandId,
        'p_idempotency_key': c.idempotencyKey,
        'p_issued_at': c.clientTimestamp.toIso8601String(),
        'p_payload': p,
        'p_expected_version': version,
      }, command: true);
      return _response(
        projectMap(raw),
        c.context,
        action,
        commandId: c.commandId,
        payload: p,
        version: version,
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The result is uncertain. Reconcile the exact encrypted request.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String key,
    String action,
  ) async {
    projectIdentity(key);
    ProjectCommands.capability(action);
    final raw = await _rpc('projects_own_receipt', scope, {
      'p_idempotency_key': key,
      'p_action': action,
    });
    if (raw == null) {
      return null;
    }
    final r = projectMap(raw);
    calendarFields(r, {
      'command_id',
      'idempotency_key',
      'request_hash',
      'response',
    });
    if (r['idempotency_key'] != key) {
      throw const FormatException('Project receipt key changed.');
    }
    projectIdentity(r['command_id']);
    projectDigest(r['request_hash']);
    _response(
      projectMap(r['response']),
      scope,
      action,
      commandId: r['command_id'] as String,
    );
    return projectMap(jsonDecode(jsonEncode(r)));
  }
}
