import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseOrganizationGateway implements OrganizationRepository {
  SupabaseOrganizationGateway(this.client);
  final SupabaseClient client;
  void _require(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select a signed-in entity and branch.',
      );
    }
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Organization response is invalid.');
    }
    return value;
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext scope,
    Map<String, Object?> args,
  ) async {
    _require(scope);
    try {
      final raw = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...args,
            },
          );
      _require(scope);
      return _map(raw);
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('55000', 'ORGANIZATION_CONSUMED_IMPACT_REQUIRED') =>
          'ORGANIZATION_CONSUMED_IMPACT_REQUIRED',
        ('55000', 'ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED') =>
          'ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED',
        ('23514', 'ORGANIZATION_IMPACT_REQUIRED') =>
          'ORGANIZATION_IMPACT_REQUIRED',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('23P01', _) => 'ORGANIZATION_OVERLAP',
        ('23505', _) => 'ORGANIZATION_ID_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23514' || '23503', _) =>
          'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Organization needs the reviewed development update.',
          'FEATURE_NOT_ENTITLED' =>
            'People is not enabled on this business plan.',
          'PERMISSION_DENIED' =>
            'Organization access requires current scope and MFA. Changes require entity-wide authority.',
          'VERSION_CONFLICT' =>
            'This employee or department changed. Compare its current version before replacing the draft.',
          'RESOURCE_NOT_FOUND' =>
            'This organization record is unavailable in the selected scope.',
          'ORGANIZATION_CONSUMED_IMPACT_REQUIRED' =>
            'These dates were consumed. Resolve downstream impact before changing them.',
          'ORGANIZATION_FUTURE_WITHDRAWAL_REQUIRED' =>
            'Only a future, unconsumed assignment can be withdrawn. Preserve historical facts and resolve their impact.',
          'ORGANIZATION_IMPACT_REQUIRED' =>
            'Employment, branch, manager, department and calendar must cover the entire interval.',
          'ORGANIZATION_OVERLAP' =>
            'An organization assignment already covers these dates.',
          'ORGANIZATION_ID_EXISTS' =>
            'This organization identity or code is already reserved.',
          'IDEMPOTENCY_MISMATCH' =>
            'This saved request key belongs to different content. Preserve the original request.',
          'VALIDATION_ERROR' =>
            'Check the dates, named references and hierarchy. A cycle or incompatible reference is not allowed.',
          _ =>
            'The organization result is uncertain. Retry the original saved request.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  void _scope(
    Map<String, Object?> row,
    TenantContext scope, {
    bool branch = true,
  }) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        branch && row['branch_id'] != scope.branchId) {
      throw const FormatException('Organization response scope changed.');
    }
  }

  List<Map<String, Object?>> _rows(Object? raw, String? after) {
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Organization page exceeds its limit.');
    }
    final rows = raw.map(_map).toList();
    String? last = after;
    for (final row in rows) {
      final id = calendarUuid(row['id']);
      if (last != null && id.compareTo(last) <= 0) {
        throw const FormatException('Organization cursor order changed.');
      }
      last = id;
    }
    return rows;
  }

  String? _next(List<Map<String, Object?>> rows) =>
      rows.length == 50 ? rows.last['id'] as String : null;
  @override
  Future<DepartmentEntry> department(
    TenantContext scope,
    String id,
    CivilDate asOf,
  ) async {
    calendarUuid(id);
    final row = await _call('people_organization_department', scope, {
      'p_department_id': id,
      'p_as_of': asOf.value,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'as_of',
      'department',
    });
    _scope(row, scope);
    final result = DepartmentEntry.fromJson(_map(row['department']));
    if (row['as_of'] != asOf.value ||
        result.id != id ||
        !result.dates.contains(asOf)) {
      throw const FormatException(
        'Department detail changed its identity or date.',
      );
    }
    return result;
  }

  @override
  Future<CalendarPage<DepartmentEntry>> departments(
    TenantContext scope,
    CivilDate asOf, {
    String search = '',
    String? after,
  }) async {
    if (search.length > 160) {
      throw const FormatException('Search is limited to 160 characters.');
    }
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('people_organization_departments', scope, {
      'p_as_of': asOf.value,
      'p_search': search,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'as_of',
      'items',
    });
    _scope(row, scope);
    if (row['as_of'] != asOf.value) {
      throw const FormatException('Organization filter date changed.');
    }
    final rows = _rows(row['items'], after);
    final entries = rows.map(DepartmentEntry.fromJson).toList();
    if (entries.any((d) => !d.dates.contains(asOf))) {
      throw const FormatException('Department is outside its dated coverage.');
    }
    return CalendarPage(entries, _next(rows));
  }

  @override
  Future<CalendarPage<DepartmentRevision>> departmentHistory(
    TenantContext scope,
    String departmentId, {
    String? after,
  }) async {
    calendarUuid(departmentId);
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('people_organization_department_history', scope, {
      'p_department_id': departmentId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'department_id',
      'items',
    });
    _scope(row, scope);
    if (row['department_id'] != departmentId) {
      throw const FormatException('Department history identity changed.');
    }
    final rows = _rows(row['items'], after);
    return CalendarPage(
      rows.map(DepartmentRevision.fromJson).toList(),
      _next(rows),
    );
  }

  @override
  Future<OrganizationEmployeeState> employee(
    TenantContext scope,
    String employeeId,
    CivilDate asOf, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) {
      calendarUuid(after);
    }
    final row = await _call('people_organization_employee', scope, {
      'p_employee_id': employeeId,
      'p_as_of': asOf.value,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'employee_version',
      'as_of',
      'items',
    });
    _scope(row, scope);
    if (row['employee_id'] != employeeId || row['as_of'] != asOf.value) {
      throw const FormatException(
        'Employee organization identity or date changed.',
      );
    }
    final rows = _rows(row['items'], after);
    final assignments = rows.map(OrganizationAssignment.fromJson).toList();
    for (final a in assignments) {
      if (a.employeeId != employeeId ||
          a.tenantId != scope.tenantId ||
          a.legalEntityId != scope.legalEntityId ||
          a.branchId != scope.branchId) {
        throw const FormatException(
          'Organization assignment ancestry changed.',
        );
      }
    }
    return OrganizationEmployeeState(
      employeeId,
      organizationVersion(row['employee_version']),
      asOf,
      CalendarPage(assignments, _next(rows)),
    );
  }

  @override
  Future<OrganizationConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    validateOrganizationPayload(action, command.payload);
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    final version = command.expectedEntityVersion;
    if (version == null ||
        version < 0 ||
        version >= calendarMaxVersion ||
        (action == 'department_create' ? version != 0 : version == 0)) {
      throw const FormatException('Organization expected version is invalid.');
    }
    try {
      final row = await _call('people_organization_command', command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_payload': {...command.payload, 'action': action},
        'p_expected_version': version,
      });
      calendarFields(row, {
        'request_id',
        'command_id',
        'correlation_id',
        'entity',
        'warnings',
      });
      calendarUuid(row['request_id']);
      calendarUuid(row['correlation_id']);
      if (row['command_id'] != command.commandId ||
          row['warnings'] is! List ||
          (row['warnings'] as List).isNotEmpty) {
        throw const FormatException(
          'Organization confirmation envelope changed.',
        );
      }
      final entity = _map(row['entity']);
      if (action.startsWith('department_')) {
        calendarFields(entity, {
          'id',
          'tenant_id',
          'legal_entity_id',
          'code',
          'version',
          'revision_id',
        });
        _scope(entity, command.context, branch: false);
        final v = organizationVersion(entity['version']);
        if (entity['id'] != command.payload['id'] ||
            entity['revision_id'] != command.payload['revision_id'] ||
            v != version + 1 ||
            (action == 'department_create' &&
                entity['code'] != command.payload['code'])) {
          throw const FormatException('Department confirmation changed.');
        }
        return OrganizationConfirmation(
          id: calendarUuid(entity['id']),
          version: v,
          departmentRevisionId: calendarUuid(entity['revision_id']),
        );
      }
      final v = organizationVersion(entity['employee_version']);
      if (action == 'withdraw_assignment') {
        calendarFields(entity, {
          'id',
          'tenant_id',
          'legal_entity_id',
          'branch_id',
          'employee_id',
          'revision_id',
          'reason',
          'recorded_by',
          'recorded_at',
          'employee_version',
        });
        _scope(entity, command.context);
        final withdrawal = OrganizationWithdrawal.fromJson({
          for (final k in ['id', 'reason', 'recorded_by', 'recorded_at'])
            k: entity[k],
        });
        if (entity['id'] != command.payload['id'] ||
            entity['employee_id'] != command.payload['employee_id'] ||
            entity['revision_id'] != command.payload['replace_revision_id'] ||
            withdrawal.recordedBy != command.context.actorId ||
            withdrawal.reason != (command.payload['reason'] as String).trim() ||
            v != version + 1) {
          throw const FormatException(
            'Organization withdrawal confirmation changed.',
          );
        }
        return OrganizationConfirmation(
          id: withdrawal.id,
          version: v,
          withdrawal: withdrawal,
        );
      }
      final assignment = OrganizationAssignment.fromJson(
        {...entity}..remove('employee_version'),
      );
      _scope(entity, command.context);
      if (assignment.id != command.payload['id'] ||
          assignment.employeeId != command.payload['employee_id'] ||
          v != version + 1 ||
          assignment.dates.start.value != command.payload['start_date'] ||
          assignment.dates.endExclusive?.value !=
              command.payload['end_date_exclusive'] ||
          assignment.reason != (command.payload['reason'] as String).trim() ||
          assignment.recordedBy != command.context.actorId ||
          !assignment.active ||
          assignment.supersedesId !=
              (action == 'assign'
                  ? null
                  : command.payload['replace_revision_id'])) {
        throw const FormatException(
          'Organization confirmation does not match its request.',
        );
      }
      if (action != 'end_assignment' &&
          (assignment.spellId != command.payload['spell_id'] ||
              assignment.departmentId != command.payload['department_id'] ||
              assignment.managerId != command.payload['manager_id'] ||
              assignment.calendarVersionId !=
                  command.payload['calendar_version_id'] ||
              assignment.roleTitle !=
                  (command.payload['role_title'] as String).trim())) {
        throw const FormatException('Organization references changed.');
      }
      return OrganizationConfirmation(
        id: assignment.id,
        version: v,
        assignment: assignment,
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Organization confirmation could not be verified. Retry the original saved request.',
        retryable: true,
      );
    }
  }
}
