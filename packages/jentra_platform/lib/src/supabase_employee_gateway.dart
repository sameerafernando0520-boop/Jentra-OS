import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseEmployeeGateway implements EmployeeRepository {
  SupabaseEmployeeGateway(this.client);
  final SupabaseClient client;

  void _require(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select an authenticated entity and branch.',
      );
    }
  }

  Future<Map<String, Object?>> _call(
    String rpc,
    TenantContext scope,
    Map<String, Object?> params,
  ) async {
    _require(scope);
    try {
      final result = await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...params,
            },
          );
      if (result is! Map) {
        throw const FormatException('Invalid employee response.');
      }
      return Map<String, Object?>.from(result);
    } on PostgrestException catch (error) {
      final code = switch ((error.code, error.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('22023', 'EMPLOYMENT_CORRECTION_REQUIRED') =>
          'EMPLOYMENT_CORRECTION_REQUIRED',
        ('22023', 'EMPLOYMENT_DATE_INVALID') => 'EMPLOYMENT_DATE_INVALID',
        ('23514', 'EMPLOYMENT_TIMELINE_INVALID') =>
          'EMPLOYMENT_TIMELINE_INVALID',
        ('23505', final message)
            when message.contains(
              'employees_tenant_id_legal_entity_id_code_key',
            ) =>
          'EMPLOYEE_CODE_EXISTS',
        ('23505', _) => 'VERSION_CONFLICT',
        (final sqlState, _) => switch (sqlState) {
          '42501' => 'PERMISSION_DENIED',
          '40001' => 'VERSION_CONFLICT',
          '23514' => 'EMPLOYMENT_OVERLAP',
          '55000' => 'EMPLOYMENT_FUTURE_EVENT_EXISTS',
          '22023' || '22008' || '22007' || '22P02' => 'VALIDATION_ERROR',
          _ => 'UNCERTAIN_RESULT',
        },
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'PERMISSION_DENIED' =>
            'Employee access or MFA verification is required.',
          'FEATURE_NOT_INSTALLED' =>
            'The employee service has not been installed in this environment.',
          'VERSION_CONFLICT' =>
            'This employee changed. Refresh before editing.',
          'IDEMPOTENCY_MISMATCH' =>
            'The saved request no longer matches its original command.',
          'EMPLOYEE_CODE_EXISTS' => 'That employee code is already in use.',
          'EMPLOYMENT_OVERLAP' => 'Employment dates overlap another period.',
          'EMPLOYMENT_TIMELINE_INVALID' =>
            'Employment dates would leave a gap or inconsistent assignment.',
          'EMPLOYMENT_CORRECTION_REQUIRED' =>
            'This change needs a reviewed historical correction.',
          'EMPLOYMENT_DATE_INVALID' => 'Choose a valid employment date.',
          'EMPLOYMENT_FUTURE_EVENT_EXISTS' =>
            'Resolve the scheduled employment change first.',
          'VALIDATION_ERROR' =>
            'Check the employee, dates, scope, work details and reason.',
          _ => 'The result is uncertain. Retry the saved request.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    } on AuthException {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Sign in again before loading employees.',
      );
    }
  }

  static List<Map<String, Object?>> _page(
    Map<String, Object?> response,
    TenantContext scope, {
    required int max,
  }) {
    final raw = response['items'];
    if (response['tenant_id'] != scope.tenantId ||
        response['legal_entity_id'] != scope.legalEntityId ||
        response['branch_id'] != scope.branchId ||
        raw is! List ||
        raw.length > max ||
        (response['next_cursor'] != null &&
            response['next_cursor'] is! String)) {
      throw const FormatException('Invalid employee page or scope.');
    }
    return [
      for (final item in raw)
        if (item is Map)
          Map<String, Object?>.from(item)
        else
          throw const FormatException('Employee page contains an invalid row.'),
    ];
  }

  @override
  Future<Map<String, Object?>> directory(
    TenantContext scope, {
    String? asOfDate,
    String status = 'employed',
    String search = '',
    String? after,
  }) async {
    if (asOfDate != null) CivilDate.parse(asOfDate);
    if (!{'employed', 'future', 'ended'}.contains(status) ||
        search.length > 160) {
      throw const FormatException('Invalid employee filters.');
    }
    final response = await _call('people_employee_directory', scope, {
      'p_as_of': asOfDate,
      'p_status': status,
      'p_search': search,
      'p_after': after,
    });
    final rows = _page(response, scope, max: 50);
    if (response['as_of'] is! String ||
        (asOfDate != null && response['as_of'] != asOfDate) ||
        response['status'] != status) {
      throw const FormatException('Employee page filters changed.');
    }
    CivilDate.parse(response['as_of'] as String);
    for (final row in rows) {
      _validateRecord(row, scope);
    }
    if (response['next_cursor'] != null &&
        (rows.isEmpty || response['next_cursor'] != rows.last['id'])) {
      throw const FormatException('Employee cursor is invalid.');
    }
    return response;
  }

  static EmployeeRecord _validateRecord(
    Map<String, Object?> row,
    TenantContext scope,
  ) {
    final record = EmployeeRecord.fromJson(row);
    if (record.tenantId != scope.tenantId ||
        record.legalEntityId != scope.legalEntityId ||
        record.branchId != scope.branchId) {
      throw const FormatException('Employee scope changed.');
    }
    return record;
  }

  @override
  Future<Map<String, Object?>> detail(
    TenantContext scope,
    String id,
    String asOfDate,
    String status,
  ) async {
    CivilDate.parse(asOfDate);
    if (!{'employed', 'future', 'ended'}.contains(status)) {
      throw const FormatException('Invalid employee status.');
    }
    final response = await _call('people_employee_detail', scope, {
      'p_employee_id': id,
      'p_as_of': asOfDate,
      'p_status': status,
    });
    if (_validateRecord(response, scope).id != id) {
      throw const FormatException('Employee identity changed.');
    }
    return response;
  }

  @override
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    String? after,
  }) async {
    final response = await _call('people_employee_history', scope, {
      'p_employee_id': id,
      'p_after': after,
    });
    final rows = _page(response, scope, max: 50);
    if (response['employee_id'] != id) {
      throw const FormatException('Employee history identity changed.');
    }
    for (final row in rows) {
      if (row.keys.any(
            (key) => !{
              'id',
              'action',
              'effective_date',
              'reason',
              'recorded_at',
              'actor_id',
              'supersedes_event_id',
            }.contains(key),
          ) ||
          row['id'] is! String ||
          row['action'] is! String ||
          row['effective_date'] is! String) {
        throw const FormatException(
          'Employee history contains a private or invalid field.',
        );
      }
      CivilDate.parse(row['effective_date'] as String);
    }
    if (response['next_cursor'] != null &&
        (rows.isEmpty || response['next_cursor'] != rows.last['id'])) {
      throw const FormatException('Employee history cursor is invalid.');
    }
    return response;
  }

  @override
  Future<Map<String, Object?>> branches(
    TenantContext scope, {
    String search = '',
  }) async {
    if (search.length > 160) throw const FormatException('Search is too long.');
    final response = await _call('people_employee_branches', scope, {
      'p_search': search,
    });
    final rows = _page(response, scope, max: 50);
    for (final row in rows) {
      if (row.keys.any((key) => !{'id', 'name', 'code'}.contains(key)) ||
          row['id'] is! String ||
          row['name'] is! String ||
          row['code'] is! String) {
        throw const FormatException('Branch choice is invalid.');
      }
    }
    return response;
  }

  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    validateEmployeePayload(action, command.payload);
    final version = command.expectedEntityVersion;
    if (version == null || version < 0 || version >= 9007199254740991) {
      throw const FormatException('Employee version is invalid.');
    }
    final response = await _call('people_employee_command', command.context, {
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_payload': {...command.payload, 'action': action},
      'p_expected_version': version,
    });
    try {
      if (response['command_id'] != command.commandId ||
          response['request_id'] is! String ||
          response['entity'] is! Map) {
        throw const FormatException(
          'Employee command confirmation is invalid.',
        );
      }
      final record = _validateRecord(
        Map<String, Object?>.from(response['entity'] as Map),
        command.context,
      );
      if (record.id != command.payload['id'] ||
          record.version != version + 1 ||
          (action == 'create' &&
              (record.code != command.payload['code'] ||
                  record.displayName != command.payload['display_name']))) {
        throw const FormatException(
          'Employee command result does not match the request.',
        );
      }
      return Map<String, Object?>.from(response['entity'] as Map);
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Employee confirmation could not be verified. Retry the saved request.',
        retryable: true,
      );
    }
  }
}
