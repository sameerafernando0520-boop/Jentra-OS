import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseCalendarGateway implements WorkCalendarRepository {
  SupabaseCalendarGateway(this.client);
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

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('Invalid calendar response.');
    }
    return value;
  }

  Future<Map<String, Object?>> _call(
    String name,
    TenantContext scope,
    Map<String, Object?> params,
  ) async {
    _require(scope);
    try {
      final result = await client
          .schema('api')
          .rpc(
            name,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...params,
            },
          );
      _require(
        scope,
      ); // A response arriving after sign-out must not become visible.
      return _map(result);
    } on PostgrestException catch (cause) {
      final code = switch ((cause.code, cause.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'PEOPLE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('40001', _) => 'VERSION_CONFLICT',
        ('23P01', _) => 'CALENDAR_OVERLAP',
        ('55000', 'CALENDAR_RETROACTIVE_CHANGE_REQUIRED') =>
          'CALENDAR_RETROACTIVE_CHANGE_REQUIRED',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('23505', final message)
            when message.contains(
              'work_calendars_tenant_id_legal_entity_id_code_key',
            ) =>
          'CALENDAR_CODE_EXISTS',
        ('23505', _) => 'CALENDAR_ID_EXISTS',
        ('22023' || '22007' || '22008' || '22P02' || '23514', _) =>
          'VALIDATION_ERROR',
        _ => 'UNCERTAIN_RESULT',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'The calendar service has not been installed in this environment.',
          'FEATURE_NOT_ENTITLED' =>
            'People is not enabled on this business plan.',
          'PERMISSION_DENIED' =>
            'Calendar access requires the appropriate scope and MFA. Changes require entity-wide authority.',
          'RESOURCE_NOT_FOUND' =>
            'This calendar or version is unavailable in the selected scope.',
          'VERSION_CONFLICT' =>
            'This calendar changed. Compare the current calendar before replacing the draft.',
          'CALENDAR_OVERLAP' =>
            'These version dates overlap a published version.',
          'CALENDAR_RETROACTIVE_CHANGE_REQUIRED' =>
            'A new version must start after the current entity date. Historical changes require a separate reviewed correction.',
          'CALENDAR_CODE_EXISTS' => 'That calendar code is already reserved.',
          'CALENDAR_ID_EXISTS' =>
            'That calendar or version identity already exists. Review the saved request.',
          'IDEMPOTENCY_MISMATCH' =>
            'The request does not match its original saved command.',
          'VALIDATION_ERROR' =>
            'Check the dates, time zone, working intervals, exceptions and reason.',
          _ => 'The result is uncertain. Retry the original saved request.',
        },
        retryable: code == 'UNCERTAIN_RESULT',
      );
    } on AuthException {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Sign in again before loading calendars.',
      );
    }
  }

  void _scope(Map<String, Object?> row, TenantContext scope) {
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId) {
      throw const FormatException('Calendar response scope changed.');
    }
  }

  WorkCalendarIdentity _identity(Object? raw, TenantContext scope) {
    final value = WorkCalendarIdentity.fromJson(_map(raw));
    if (value.tenantId != scope.tenantId ||
        value.legalEntityId != scope.legalEntityId) {
      throw const FormatException(
        'Calendar identity belongs to another scope.',
      );
    }
    return value;
  }

  List<Map<String, Object?>> _rows(
    Map<String, Object?> response,
    String? after,
  ) {
    final raw = response['items'];
    if (raw is! List || raw.length > 50) {
      throw const FormatException('Invalid calendar page size.');
    }
    final rows = raw.map(_map).toList();
    String? previous = after;
    for (final row in rows) {
      final id = calendarUuid(row['id']);
      if (previous != null && id.compareTo(previous) <= 0) {
        throw const FormatException(
          'Calendar page order or cursor is invalid.',
        );
      }
      previous = id;
    }
    return rows;
  }

  String? _next(List<Map<String, Object?>> rows) =>
      rows.length == 50 ? rows.last['id'] as String : null;

  @override
  Future<CalendarDirectoryPage> directory(
    TenantContext scope, {
    String? asOfDate,
    String search = '',
    String? after,
  }) async {
    if (asOfDate != null) CivilDate.parse(asOfDate);
    if (after != null) calendarUuid(after);
    if (search.length > 160) {
      throw const FormatException('Search is limited to 160 characters.');
    }
    final response = await _call('people_calendar_directory', scope, {
      'p_as_of': asOfDate,
      'p_search': search,
      'p_after': after,
    });
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'as_of',
      'items',
    });
    _scope(response, scope);
    final date = CivilDate.parse(response['as_of'] as String);
    if (asOfDate != null && date.value != asOfDate) {
      throw const FormatException('Calendar filter date changed.');
    }
    final rows = _rows(response, after);
    final entries = <CalendarDirectoryEntry>[];
    for (final row in rows) {
      calendarFields(row, {
        'id',
        'tenant_id',
        'legal_entity_id',
        'code',
        'name',
        'version',
        'selected_version',
      });
      final identity = _identity({
        for (final entry in row.entries)
          if (entry.key != 'selected_version') entry.key: entry.value,
      }, scope);
      final coverage = row['selected_version'] == null
          ? null
          : CalendarCoverage.fromJson(_map(row['selected_version']));
      if (coverage != null && !coverage.contains(date)) {
        throw const FormatException(
          'Selected calendar version does not cover the filter date.',
        );
      }
      entries.add(CalendarDirectoryEntry(identity, coverage));
    }
    return CalendarDirectoryPage(date, CalendarPage(entries, _next(rows)));
  }

  @override
  Future<CalendarDetail> detail(
    TenantContext scope,
    String calendarId,
    String versionId,
  ) async {
    calendarUuid(calendarId);
    calendarUuid(versionId);
    final response = await _call('people_calendar_detail', scope, {
      'p_calendar_id': calendarId,
      'p_version_id': versionId,
    });
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'calendar',
      'calendar_version',
    });
    _scope(response, scope);
    final calendar = _identity(response['calendar'], scope);
    final version = CalendarVersionDetail.fromJson(
      _map(response['calendar_version']),
    );
    if (calendar.id != calendarId ||
        version.calendarId != calendarId ||
        version.summary.coverage.id != versionId ||
        version.tenantId != scope.tenantId ||
        version.legalEntityId != scope.legalEntityId) {
      throw const FormatException('Calendar version ancestry changed.');
    }
    return CalendarDetail(calendar, version);
  }

  Future<(Map<String, Object?>, List<Map<String, Object?>>)> _calendarPage(
    String name,
    TenantContext scope,
    String id,
    String? after,
  ) async {
    calendarUuid(id);
    if (after != null) calendarUuid(after);
    final response = await _call(name, scope, {
      'p_calendar_id': id,
      'p_after': after,
    });
    calendarFields(response, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'calendar_id',
      'items',
    });
    _scope(response, scope);
    if (response['calendar_id'] != id) {
      throw const FormatException('Calendar page identity changed.');
    }
    return (response, _rows(response, after));
  }

  @override
  Future<CalendarPage<CalendarVersionSummary>> versions(
    TenantContext scope,
    String calendarId, {
    String? after,
  }) async {
    final (_, rows) = await _calendarPage(
      'people_calendar_versions',
      scope,
      calendarId,
      after,
    );
    return CalendarPage(
      rows.map(CalendarVersionSummary.fromJson).toList(),
      _next(rows),
    );
  }

  DateTime _timestamp(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const FormatException('Calendar event timestamp is invalid.');
    }
    return DateTime.parse(value).toUtc();
  }

  CalendarConfirmation _confirmation(Object? raw, TenantContext scope) {
    final row = _map(raw);
    calendarFields(row, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'code',
      'name',
      'version',
      'published_version_id',
    });
    return CalendarConfirmation(
      _identity({
        for (final entry in row.entries)
          if (entry.key != 'published_version_id') entry.key: entry.value,
      }, scope),
      row['published_version_id'] == null
          ? null
          : calendarUuid(row['published_version_id']),
    );
  }

  @override
  Future<CalendarPage<CalendarHistoryEvent>> history(
    TenantContext scope,
    String calendarId, {
    String? after,
  }) async {
    final (_, rows) = await _calendarPage(
      'people_calendar_history',
      scope,
      calendarId,
      after,
    );
    final events = <CalendarHistoryEvent>[];
    for (final row in rows) {
      calendarFields(row, {
        'id',
        'action',
        'published_version_id',
        'effective_date',
        'reason',
        'actor_id',
        'recorded_at',
        'before_state',
        'after_state',
      });
      final action = row['action'];
      if (!{'create', 'publish', 'rename'}.contains(action) ||
          row['reason'] is! String ||
          (row['reason'] as String).trim().isEmpty ||
          (row['reason'] as String).length > 1000) {
        throw const FormatException('Calendar event is invalid.');
      }
      final result = _confirmation(row['after_state'], scope);
      final previous = _map(row['before_state']);
      final before = previous.isEmpty ? null : _identity(previous, scope);
      final versionId = row['published_version_id'] == null
          ? null
          : calendarUuid(row['published_version_id']);
      final date = row['effective_date'] == null
          ? null
          : CivilDate.parse(row['effective_date'] as String);
      if (result.calendar.id != calendarId ||
          result.publishedVersionId != versionId ||
          (action == 'rename') != (versionId == null && date == null) ||
          (action != 'rename' && (versionId == null || date == null)) ||
          (action == 'create'
              ? before != null || result.calendar.version != 1
              : before == null ||
                    before.id != calendarId ||
                    before.version + 1 != result.calendar.version ||
                    before.code != result.calendar.code)) {
        throw const FormatException('Calendar event lineage is invalid.');
      }
      events.add(
        CalendarHistoryEvent(
          id: calendarUuid(row['id']),
          action: action as String,
          publishedVersionId: versionId,
          effectiveDate: date,
          reason: row['reason'] as String,
          actorId: calendarUuid(row['actor_id']),
          recordedAt: _timestamp(row['recorded_at']),
          before: before,
          after: result,
        ),
      );
    }
    return CalendarPage(events, _next(rows));
  }

  @override
  Future<CalendarConfirmation> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    validateCalendarPayload(action, command.payload);
    calendarUuid(command.commandId);
    calendarUuid(command.idempotencyKey);
    final version = command.expectedEntityVersion;
    if (version == null ||
        version < 0 ||
        version >= calendarMaxVersion ||
        (action == 'create' ? version != 0 : version == 0)) {
      throw const FormatException('Calendar expected version is invalid.');
    }
    try {
      final response = await _call('people_calendar_command', command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_client_timestamp': command.clientTimestamp.toIso8601String(),
        'p_payload': {...command.payload, 'action': action},
        'p_expected_version': version,
      });
      calendarFields(response, {
        'request_id',
        'command_id',
        'correlation_id',
        'entity',
        'warnings',
      });
      calendarUuid(response['request_id']);
      calendarUuid(response['correlation_id']);
      if (response['command_id'] != command.commandId ||
          response['warnings'] is! List ||
          (response['warnings'] as List).isNotEmpty) {
        throw const FormatException('Calendar confirmation envelope changed.');
      }
      final result = _confirmation(response['entity'], command.context);
      if (result.calendar.id != command.payload['id'] ||
          result.calendar.version != version + 1 ||
          result.publishedVersionId !=
              (action == 'rename' ? null : command.payload['version_id']) ||
          (action == 'create' &&
              result.calendar.code != command.payload['code']) ||
          (action != 'publish' &&
              result.calendar.name !=
                  (command.payload['name'] as String).trim())) {
        throw const FormatException(
          'Calendar confirmation does not match the request.',
        );
      }
      return result;
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Calendar confirmation could not be verified. Retry the original saved request.',
        retryable: true,
      );
    }
  }
}
