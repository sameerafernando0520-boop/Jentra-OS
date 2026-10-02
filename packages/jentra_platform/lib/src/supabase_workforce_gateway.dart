import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Named, scoped APIs only. Command payloads are copied before the first await
/// so retrying an uncertain result cannot silently change its request body.
final class SupabaseWorkforceGateway implements WorkforceRepository {
  SupabaseWorkforceGateway(this.client);
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

  Future<Object?> _rpc(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
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
      if (client.auth.currentUser?.id != scope.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message: command
              ? 'The signed-in account changed. Retry the exact saved request after signing in.'
              : 'Select a signed-in entity and branch.',
          retryable: command,
        );
      }
      return raw;
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('23P01', _) => 'WORK_INTERVAL_CONFLICT',
        ('23514', 'WORK_INTERVAL_CONFLICT') => 'WORK_INTERVAL_CONFLICT',
        ('23514', 'LEAVE_BALANCE_INSUFFICIENT') => 'LEAVE_BALANCE_INSUFFICIENT',
        ('55000', 'WORK_ALLOCATION_IMPACT_REQUIRED') =>
          'WORK_ALLOCATION_IMPACT_REQUIRED',
        ('55000', 'PAYROLL_INPUT_SEALED') => 'PAYROLL_INPUT_SEALED',
        ('55000', 'CLOCK_SOURCE_CONFLICT') => 'CLOCK_SOURCE_CONFLICT',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('23505', _) => 'IDENTITY_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23514' || '23503', _) =>
          'VALIDATION_ERROR',
        ('55000', _) => 'STATE_CONFLICT',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Attendance and leave need their reviewed development update.',
          'FEATURE_NOT_ENTITLED' =>
            'People is not enabled on this business plan.',
          'PERMISSION_DENIED' =>
            'Current scope, permission and MFA are required.',
          'VERSION_CONFLICT' =>
            'The record changed. Compare the current version before editing.',
          'RESOURCE_NOT_FOUND' =>
            'This record is unavailable in the selected scope.',
          'WORK_INTERVAL_CONFLICT' =>
            'Another approved work or leave entry owns this time.',
          'LEAVE_BALANCE_INSUFFICIENT' =>
            'The available leave balance cannot cover this request.',
          'WORK_ALLOCATION_IMPACT_REQUIRED' =>
            'Project or service time is allocated. Resolve that impact first.',
          'PAYROLL_INPUT_SEALED' =>
            'This time is sealed for payroll. Resolve payroll impact first.',
          'CLOCK_SOURCE_CONFLICT' =>
            'A clock source reference already has different evidence. No batch rows were imported.',
          'IDEMPOTENCY_MISMATCH' =>
            'This saved request key belongs to different content. Retry the original request.',
          'IDENTITY_EXISTS' => 'This record or source key already exists.',
          'STATE_CONFLICT' =>
            'The record cannot make this transition. Refresh its history.',
          'VALIDATION_ERROR' =>
            'Check the selected local time, offset, policy, balance and interval.',
          _ => 'The result is uncertain. Retry the exact saved request.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext scope,
    Map<String, Object?> args, {
    bool command = false,
  }) async => workforceMap(await _rpc(name, scope, args, command: command));

  void _scope(Map<String, Object?> row, TenantContext scope) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId) {
      throw const FormatException('Workforce response scope changed.');
    }
  }

  @override
  Future<void> authorize(
    TenantContext scope,
    String? employeeId,
    String capability,
  ) async {
    if (employeeId != null) calendarUuid(employeeId);
    if (!{
      'people.attendance.view',
      'people.attendance.manage',
      'people.attendance.import',
      'people.attendance.approve',
      'people.work_claims.view',
      'people.leave.view',
      'people.leave.manage',
      'people.leave.approve',
      'people.leave.policy.manage',
      'people.leave.adjust',
    }.contains(capability)) {
      throw const FormatException('Workforce capability is invalid.');
    }
    final row = await _call('people_workforce_authorize', scope, {
      'p_employee_id': employeeId,
      'p_capability': capability,
    });
    calendarFields(row, {
      'authorized',
      'actor_id',
      'employee_id',
      'capability',
    });
    if (row['authorized'] != true ||
        row['actor_id'] != scope.actorId ||
        row['employee_id'] != employeeId ||
        row['capability'] != capability) {
      throw const FormatException('Workforce authorization changed.');
    }
  }

  WorkforcePage<T> _referencePage<T>(
    Map<String, Object?> row,
    TenantContext scope,
    String? after,
    T Function(Map<String, Object?>) parse, {
    String? policyId,
  }) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      if (policyId != null) 'policy_id',
      'items',
      'next_cursor',
    });
    _scope(row, scope);
    if (policyId != null && row['policy_id'] != policyId ||
        row['items'] is! List ||
        (row['items'] as List).length > 50) {
      throw const FormatException('Leave reference page changed.');
    }
    final result = <T>[];
    var prior = after;
    for (final raw in row['items'] as List) {
      final item = workforceMap(raw),
          id = calendarUuid(workforceMap(raw)['id']);
      if (prior != null && id.compareTo(prior) <= 0) {
        throw const FormatException('Leave reference cursor order changed.');
      }
      result.add(parse(item));
      prior = id;
    }
    final next = row['next_cursor'];
    if (next != null && (result.length != 50 || calendarUuid(next) != prior)) {
      throw const FormatException('Leave reference cursor changed.');
    }
    return WorkforcePage(List.unmodifiable(result), next as String?);
  }

  @override
  Future<WorkforcePage<LeavePolicy>> policies(
    TenantContext scope, {
    String? after,
  }) async {
    if (after != null) calendarUuid(after);
    final row = await _call('people_leave_policies', scope, {'p_after': after});
    return _referencePage(row, scope, after, LeavePolicy.fromJson);
  }

  @override
  Future<WorkforcePage<LeavePolicyVersion>> policyVersions(
    TenantContext scope,
    String policyId, {
    String? after,
  }) async {
    calendarUuid(policyId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_leave_policy_versions', scope, {
      'p_policy_id': policyId,
      'p_after': after,
    });
    return _referencePage(
      row,
      scope,
      after,
      LeavePolicyVersion.fromJson,
      policyId: policyId,
    );
  }

  @override
  Future<LeavePolicy> policyForVersion(
    TenantContext scope,
    String versionId,
  ) async {
    calendarUuid(versionId);
    final row = await _call('people_leave_policy_for_version', scope, {
      'p_version_id': versionId,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'policy_version_id',
      'policy',
    });
    _scope(row, scope);
    if (row['policy_version_id'] != versionId) {
      throw const FormatException('Leave policy version context changed.');
    }
    return LeavePolicy.fromJson(workforceMap(row['policy']));
  }

  WorkforcePage<T> _page<T>(
    Map<String, Object?> row,
    TenantContext scope,
    String employeeId,
    String? after,
    T Function(Map<String, Object?>) parse,
    void Function(T) check,
  ) {
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'items',
      'next_cursor',
    });
    _scope(row, scope);
    if (row['employee_id'] != employeeId || row['items'] is! List) {
      throw const FormatException('Workforce page identity changed.');
    }
    final raw = row['items'] as List;
    if (raw.length > 50) {
      throw const FormatException('Workforce page exceeds its limit.');
    }
    final items = <T>[];
    var prior = after;
    for (final item in raw) {
      final map = workforceMap(item);
      final id = calendarUuid(map['id']);
      if (prior != null && id.compareTo(prior) <= 0) {
        throw const FormatException('Workforce cursor order changed.');
      }
      final parsed = parse(map);
      check(parsed);
      items.add(parsed);
      prior = id;
    }
    final next = row['next_cursor'];
    if (next != null && (raw.length != 50 || calendarUuid(next) != prior)) {
      throw const FormatException('Workforce next cursor changed.');
    }
    return WorkforcePage(List.unmodifiable(items), next as String?);
  }

  @override
  Future<WorkforcePage<AttendanceEntry>> attendance(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_attendance_entries', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(
      row,
      scope,
      employeeId,
      after,
      AttendanceEntry.fromJson,
      (item) => item.assertScope(scope, employeeId),
    );
  }

  @override
  Future<WorkforcePage<RawClockBatch>> clockBatches(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_attendance_clock_batches', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(row, scope, employeeId, after, RawClockBatch.fromJson, (_) {});
  }

  @override
  Future<ClockBatchDetail> clockBatchDetail(
    TenantContext scope,
    String employeeId,
    String batchId, {
    int after = 0,
  }) async {
    calendarUuid(employeeId);
    calendarUuid(batchId);
    if (after < 0 || after > maxClockBatchRecords) {
      throw const FormatException('Clock history cursor is invalid.');
    }
    final row = await _call('people_attendance_clock_batch_detail', scope, {
      'p_employee_id': employeeId,
      'p_batch_id': batchId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'employee_id',
      'batch',
      'rows',
      'next_position',
    });
    _scope(row, scope);
    final batch = RawClockBatch.fromJson(workforceMap(row['batch']));
    if (row['employee_id'] != employeeId ||
        batch.id != batchId ||
        row['rows'] is! List ||
        (row['rows'] as List).length > 50) {
      throw const FormatException('Clock history scope or page changed.');
    }
    final rows = (row['rows'] as List)
        .map((r) => ClockBatchLineage.fromJson(workforceMap(r)))
        .toList();
    var prior = after;
    for (final r in rows) {
      if (r.position != prior + 1 || r.position > batch.rowCount) {
        throw const FormatException('Clock lineage order changed.');
      }
      prior = r.position;
    }
    final next = row['next_position'];
    if (next != null && (rows.length != 50 || next != prior) ||
        next == null && prior != batch.rowCount) {
      throw const FormatException('Clock lineage cursor changed.');
    }
    return ClockBatchDetail(batch, List.unmodifiable(rows), next as int?);
  }

  @override
  Future<WorkforcePage<LeaveRequest>> leaveRequests(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_leave_requests', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(
      row,
      scope,
      employeeId,
      after,
      LeaveRequest.fromJson,
      (item) => item.assertScope(scope, employeeId),
    );
  }

  @override
  Future<WorkforceDetail<AttendanceEntry, AttendanceHistoryEntry>>
  attendanceDetail(TenantContext scope, String entryId, {String? after}) async {
    calendarUuid(entryId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_attendance_detail', scope, {
      'p_entry_id': entryId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'entry',
      'history',
      'next_cursor',
    });
    _scope(row, scope);
    final entry = AttendanceEntry.fromJson(workforceMap(row['entry']));
    entry.assertScope(scope, entry.employeeId);
    if (entry.id != entryId) {
      throw const FormatException('Attendance detail identity changed.');
    }
    final history = _referencePage(
      {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'items': row['history'],
        'next_cursor': row['next_cursor'],
      },
      scope,
      after,
      AttendanceHistoryEntry.fromJson,
    );
    return WorkforceDetail(entry, history);
  }

  @override
  Future<WorkforceDetail<LeaveRequest, LeaveHistoryEntry>> leaveDetail(
    TenantContext scope,
    String requestId, {
    String? after,
  }) async {
    calendarUuid(requestId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_leave_detail', scope, {
      'p_request_id': requestId,
      'p_after': after,
    });
    calendarFields(row, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'request',
      'history',
      'next_cursor',
    });
    _scope(row, scope);
    final request = LeaveRequest.fromJson(workforceMap(row['request']));
    request.assertScope(scope, request.employeeId);
    if (request.id != requestId) {
      throw const FormatException('Leave detail identity changed.');
    }
    final history = _referencePage(
      {
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'items': row['history'],
        'next_cursor': row['next_cursor'],
      },
      scope,
      after,
      LeaveHistoryEntry.fromJson,
    );
    return WorkforceDetail(request, history);
  }

  @override
  Future<WorkforcePage<RawClockEvent>> rawEvents(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_attendance_raw_events', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(row, scope, employeeId, after, RawClockEvent.fromJson, (_) {});
  }

  @override
  Future<WorkforcePage<WorkClaim>> workClaims(
    TenantContext scope,
    String employeeId, {
    String? after,
  }) async {
    calendarUuid(employeeId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_work_claims', scope, {
      'p_employee_id': employeeId,
      'p_after': after,
    });
    return _page(row, scope, employeeId, after, WorkClaim.fromJson, (_) {});
  }

  @override
  Future<LeaveBalance> leaveBalance(
    TenantContext scope,
    String employeeId,
    String policyId,
    CivilDate asOf, {
    DateTime? recordedBefore,
    String? after,
  }) async {
    calendarUuid(employeeId);
    calendarUuid(policyId);
    if (after != null) calendarUuid(after);
    final row = await _call('people_leave_balance', scope, {
      'p_employee_id': employeeId,
      'p_policy_id': policyId,
      'p_as_of': asOf.value,
      'p_recorded_before': recordedBefore?.toUtc().toIso8601String(),
      'p_after': after,
    });
    _scope(row, scope);
    final balance = LeaveBalance.fromJson(row);
    if (balance.employeeId != employeeId ||
        balance.policyId != policyId ||
        balance.asOf.value != asOf.value ||
        (recordedBefore == null) != (row['recorded_before'] == null)) {
      throw const FormatException('Leave balance filter changed.');
    }
    if (recordedBefore != null &&
        workforceRecorded(row['recorded_before']) != recordedBefore.toUtc()) {
      throw const FormatException('Leave balance cutoff changed.');
    }
    String? previous = after;
    for (final grant in balance.grants) {
      if (previous != null && grant.id.compareTo(previous) <= 0) {
        throw const FormatException('Leave grant ordering changed.');
      }
      previous = grant.id;
    }
    return balance;
  }

  @override
  Future<Map<String, Object?>?> leaveOwnReceipt(
    TenantContext scope,
    String commandId,
  ) async {
    calendarUuid(commandId);
    _require(scope);
    try {
      final raw = await _rpc('people_leave_own_receipt', scope, {
        'p_command_id': commandId,
      });
      if (raw == null) return null;
      final receipt = workforceMap(raw);
      calendarFields(receipt, {
        'request_id',
        'command_id',
        'correlation_id',
        'entity',
        'warnings',
      });
      calendarUuid(receipt['request_id']);
      calendarUuid(receipt['correlation_id']);
      if (receipt['command_id'] != commandId ||
          receipt['warnings'] is! List ||
          (receipt['warnings'] as List).isNotEmpty) {
        throw const FormatException('Leave receipt envelope changed.');
      }
      final entity = workforceMap(receipt['entity']);
      calendarFields(entity, {
        'id',
        'employee_id',
        'policy_id',
        'policy_version_id',
        'calendar_version_id',
        'version',
        'status',
        'start_utc',
        'end_utc',
        'charge_seconds',
        'unpaid_seconds',
        'active_claim_id',
        'created_by',
        'submitted_by',
        'decided_by',
      });
      calendarUuid(entity['id']);
      calendarUuid(entity['employee_id']);
      workforceInteger(entity['version'], positive: true);
      return Map.unmodifiable(entity);
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The leave receipt could not be verified. Keep its recovery entry.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>> execute(
    WorkforceCommandKind kind,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final payload = Map<String, Object?>.from(
      jsonDecode(jsonEncode(command.payload)) as Map,
    );
    final action = payload['action'];
    if (action is! String) {
      throw const FormatException('Workforce command action is required.');
    }
    if (kind == WorkforceCommandKind.attendance && action == 'raw_import') {
      WorkforceCommands.validateRawImport(payload);
    } else {
      WorkforceCommands.validate(kind, action, payload);
    }
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    final version = command.expectedEntityVersion;
    final creating =
        kind == WorkforceCommandKind.attendance &&
            (action == 'create' ||
                action == 'raw_import' ||
                action == 'raw_import_batch') ||
        kind == WorkforceCommandKind.leavePolicy && action == 'create' ||
        kind == WorkforceCommandKind.leaveRequest && action == 'create';
    if (version == null ||
        version < 0 ||
        version >= maxExactWorkInteger ||
        creating && version != 0) {
      throw const FormatException('Workforce expected version is invalid.');
    }
    final rpc =
        action == 'raw_import_batch' && kind == WorkforceCommandKind.attendance
        ? 'people_attendance_clock_batch'
        : switch (kind) {
            WorkforceCommandKind.attendance => 'people_attendance_command',
            WorkforceCommandKind.leavePolicy => 'people_leave_policy_command',
            WorkforceCommandKind.leaveGrant => 'people_leave_grant_command',
            WorkforceCommandKind.leaveRequest => 'people_leave_request_command',
          };
    try {
      final receipt = await _call(rpc, command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_payload': payload,
        'p_expected_version': version,
      }, command: true);
      calendarFields(receipt, {
        'request_id',
        'command_id',
        'correlation_id',
        'entity',
        'warnings',
      });
      calendarUuid(receipt['request_id']);
      calendarUuid(receipt['correlation_id']);
      if (receipt['command_id'] != command.commandId ||
          receipt['warnings'] is! List ||
          (receipt['warnings'] as List).isNotEmpty) {
        throw const FormatException('Workforce confirmation envelope changed.');
      }
      final entity = workforceMap(receipt['entity']);
      if (entity['id'] != payload['id']) {
        throw const FormatException('Workforce confirmation identity changed.');
      }
      if (kind == WorkforceCommandKind.attendance &&
          action == 'raw_import_batch') {
        calendarFields(entity, {
          'id',
          'tenant_id',
          'legal_entity_id',
          'branch_id',
          'employee_id',
          'version',
          'row_count',
          'imported_count',
          'reused_count',
          'manifest_digest',
        });
        _scope(entity, command.context);
        final count = (payload['records'] as List).length;
        final imported = workforceInteger(entity['imported_count']);
        final reused = workforceInteger(entity['reused_count']);
        if (entity['employee_id'] != payload['employee_id'] ||
            entity['version'] != 1 ||
            entity['row_count'] != count ||
            imported + reused != count ||
            entity['manifest_digest'] != payload['manifest_digest']) {
          throw const FormatException(
            'Clock batch conservation confirmation changed.',
          );
        }
      } else if (kind == WorkforceCommandKind.attendance &&
          action != 'raw_import') {
        final entry = AttendanceEntry.fromJson(entity);
        entry.assertScope(command.context, payload['employee_id'] as String);
        if (entry.version != version + 1 || entry.status != _status(action)) {
          throw const FormatException(
            'Attendance confirmation version changed.',
          );
        }
        if (action == 'create' || action == 'correct') {
          final expectedStart = workforceLocalTime(
            payload['start_local'],
          ).subtract(Duration(seconds: payload['start_offset_seconds'] as int));
          final expectedEnd = workforceLocalTime(
            payload['end_local'],
          ).subtract(Duration(seconds: payload['end_offset_seconds'] as int));
          if (entry.revision.calendarVersionId !=
                  payload['calendar_version_id'] ||
              entry.revision.span.startUtc != expectedStart ||
              entry.revision.span.endUtc != expectedEnd ||
              entry.revision.reason != (payload['reason'] as String).trim() ||
              entry.revision.recordedBy != command.context.actorId) {
            throw const FormatException(
              'Attendance resolution confirmation changed.',
            );
          }
        }
      } else if (kind == WorkforceCommandKind.leaveRequest) {
        calendarFields(entity, {
          'id',
          'employee_id',
          'policy_id',
          'policy_version_id',
          'calendar_version_id',
          'version',
          'status',
          'start_utc',
          'end_utc',
          'charge_seconds',
          'unpaid_seconds',
          'active_claim_id',
          'created_by',
          'submitted_by',
          'decided_by',
        });
        if (entity['employee_id'] != payload['employee_id'] ||
            workforceInteger(entity['version'], positive: true) !=
                version + 1 ||
            entity['status'] != _status(action)) {
          throw const FormatException('Leave confirmation version changed.');
        }
        final charge = workforceInteger(
          entity['charge_seconds'],
          positive: true,
        );
        if (workforceInteger(entity['unpaid_seconds']) > charge ||
            (entity['status'] == 'approved') !=
                (entity['active_claim_id'] != null)) {
          throw const FormatException('Leave confirmation claim changed.');
        }
        if (action == 'create' &&
            (entity['policy_version_id'] != payload['policy_version_id'] ||
                entity['calendar_version_id'] !=
                    payload['calendar_version_id'] ||
                entity['created_by'] != command.context.actorId ||
                workforceInstant(entity['start_utc']) !=
                    workforceLocalTime(payload['start_local']).subtract(
                      Duration(seconds: payload['start_offset_seconds'] as int),
                    ) ||
                workforceInstant(entity['end_utc']) !=
                    workforceLocalTime(payload['end_local']).subtract(
                      Duration(seconds: payload['end_offset_seconds'] as int),
                    ))) {
          throw const FormatException('Leave resolution confirmation changed.');
        }
      } else if (kind == WorkforceCommandKind.leavePolicy) {
        final policy = LeavePolicy.fromJson(entity);
        if (policy.version != version + 1 ||
            policy.latest.id != payload['version_id'] ||
            policy.latest.reason != (payload['reason'] as String).trim() ||
            policy.latest.publishedBy != command.context.actorId) {
          throw const FormatException('Leave policy version changed.');
        }
      } else if (kind == WorkforceCommandKind.leaveGrant) {
        calendarFields(entity, {
          'id',
          'employee_id',
          'policy_id',
          'policy_version_id',
          'source_kind',
          'source_key',
          'effective_date',
          'seconds',
          'account_version',
          'available_seconds',
        });
        if (entity['employee_id'] != payload['employee_id'] ||
            entity['policy_version_id'] != payload['policy_version_id'] ||
            entity['source_kind'] != action ||
            workforceInteger(entity['account_version'], positive: true) !=
                version + 1) {
          throw const FormatException('Leave grant employee changed.');
        }
        workforceInteger(entity['account_version'], positive: true);
        workforceInteger(entity['available_seconds']);
      } else {
        calendarFields(entity, {
          'id',
          'employee_id',
          'source_system',
          'source_key',
          'observed_utc',
          'checksum',
        });
        if (entity['employee_id'] != payload['employee_id'] ||
            entity['source_key'] != payload['source_key'] ||
            entity['source_system'] != payload['source_system'] ||
            entity['observed_utc'] != payload['observed_utc'] ||
            entity['checksum'] != payload['checksum']) {
          throw const FormatException('Raw import confirmation changed.');
        }
      }
      return Map.unmodifiable(entity);
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Workforce confirmation could not be verified. Retry the exact saved request.',
        retryable: true,
      );
    }
  }

  String _status(String action) => switch (action) {
    'create' || 'correct' => 'draft',
    'submit' => 'submitted',
    'approve' => 'approved',
    'reject' => 'rejected',
    'cancel' => 'cancelled',
    _ => throw const FormatException('Workforce action changed.'),
  };
}
