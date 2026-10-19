import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Named, scoped service APIs only. Base tables never participate in client reads.
final class SupabaseServiceGateway implements ServiceRepository {
  SupabaseServiceGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  });
  final SupabaseClient client;
  final Duration timeout;
  void _auth(TenantContext scope) {
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
    _auth(scope);
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
          )
          .timeout(timeout);
      if (!command && client.auth.currentUser?.id != scope.actorId) {
        throw DomainError(
          code: command ? 'UNCERTAIN_RESULT' : 'AUTHENTICATION_REQUIRED',
          message: command
              ? 'The account changed. Reconcile the exact saved request.'
              : 'The account changed.',
          retryable: command,
        );
      }
      return raw;
    } on PostgrestException catch (e) {
      final code = switch ((e.code, e.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'SERVICE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('23505', _) => 'IDENTITY_EXISTS',
        ('23P01', _) => 'WORK_INTERVAL_CONFLICT',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('55000', 'PAYROLL_INPUT_SEALED') => 'PAYROLL_INPUT_SEALED',
        ('55000', 'SERVICE_PARTS_PROVIDER_UNAVAILABLE') =>
          'SERVICE_PARTS_PROVIDER_UNAVAILABLE',
        ('55000', 'SERVICE_BILLING_ADAPTER_UNAVAILABLE') =>
          'SERVICE_BILLING_ADAPTER_UNAVAILABLE',
        ('55000', 'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE') =>
          'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE',
        ('55000', _) => 'STATE_CONFLICT',
        ('22023' || '22007' || '22008' || '22P02' || '23514' || '23503', _) =>
          'VALIDATION_ERROR',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'Service needs its reviewed development update.',
          'FEATURE_NOT_ENTITLED' => 'Service is not enabled on this plan.',
          'PERMISSION_DENIED' =>
            'Current scope, permission and MFA are required.',
          'VERSION_CONFLICT' =>
            'The service record changed. Compare the current version before editing.',
          'RESOURCE_NOT_FOUND' =>
            'This service record is unavailable in the selected scope.',
          'WORK_INTERVAL_CONFLICT' =>
            'This employee already has work in the selected interval.',
          'PAYROLL_INPUT_SEALED' =>
            'This original work is sealed. Use the linked payroll correction workflow.',
          'SERVICE_PARTS_PROVIDER_UNAVAILABLE' =>
            'Service parts require the reviewed reservation, issue and return provider.',
          'SERVICE_BILLING_ADAPTER_UNAVAILABLE' =>
            'Service billing requires the reviewed source consumption adapter.',
          'SERVICE_EQUIPMENT_PROVIDER_UNAVAILABLE' =>
            'This equipment identity requires its installed asset or stock adapter.',
          'IDENTITY_EXISTS' =>
            'This equipment identity or occurrence already exists.',
          'VALIDATION_ERROR' =>
            'Check the exact dates, times, named choices and evidence.',
          'STATE_CONFLICT' =>
            'This service transition requires its original state and independent authority.',
          'IDEMPOTENCY_MISMATCH' =>
            'The saved request key belongs to different content. Reconcile its original request.',
          'SERVICE_UNAVAILABLE' =>
            'Service is unavailable. Retry the scoped read.',
          _ =>
            'The result is uncertain. Reconcile the exact encrypted request.',
        },
        retryable: {'UNCERTAIN_RESULT', 'SERVICE_UNAVAILABLE'}.contains(code),
      );
    } catch (e) {
      if (e is DomainError) {
        rethrow;
      }
      throw DomainError(
        code: command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
        message: command
            ? 'The result is uncertain. Reconcile the exact encrypted request.'
            : 'Service is unavailable. Retry the scoped read.',
        retryable: true,
      );
    }
  }

  @override
  Future<ServiceAuthority> authorize(
    TenantContext scope,
    String capability,
  ) async {
    if (!serviceCapabilities.contains(capability)) {
      throw const FormatException('Service capability is invalid.');
    }
    final r = serviceMap(
      await _rpc('service_authorize', scope, {'p_capability': capability}),
    );
    calendarFields(r, {
      'actor_id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'capability',
      'authorized',
      'parts_provider',
      'billing_provider',
      'asset_provider',
      'currency_code',
      'precision',
    });
    serviceScope(r, scope);
    if (r['actor_id'] != scope.actorId ||
        r['capability'] != capability ||
        r['authorized'] != true ||
        [
          r['parts_provider'],
          r['billing_provider'],
          r['asset_provider'],
        ].any((x) => x is! bool)) {
      throw const FormatException('Service authority changed.');
    }
    return ServiceAuthority(
      serviceAmount('0', r['currency_code']).currencyCode,
      serviceInt(r['precision'], max: 6),
      parts: r['parts_provider'] as bool,
      billing: r['billing_provider'] as bool,
      assets: r['asset_provider'] as bool,
    );
  }

  ServicePage<T> _page<T>(
    Map<String, Object?> r,
    TenantContext scope,
    String kind,
    String? after,
    T Function(Map<String, Object?>) parse,
  ) {
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'kind',
      'items',
      'next_cursor',
    });
    serviceScope(r, scope);
    if (r['kind'] != kind ||
        r['items'] is! List ||
        (r['items'] as List).length > 50) {
      throw const FormatException('Service page is invalid.');
    }
    final rows = (r['items'] as List).map(serviceMap).toList();
    String? previous = after;
    for (final row in rows) {
      final id = calendarUuid(row['id']);
      if (previous != null && id.compareTo(previous) <= 0) {
        throw const FormatException('Service page order changed.');
      }
      previous = id;
    }
    final next = r['next_cursor'] == null
        ? null
        : calendarUuid(r['next_cursor']);
    if (next != null && (rows.length != 50 || next != previous)) {
      throw const FormatException('Service continuation changed.');
    }
    return ServicePage(List.unmodifiable(rows.map(parse)), next);
  }

  @override
  Future<ServicePage<ServiceRecord>> list(
    TenantContext scope,
    ServiceKind kind, {
    String? after,
    String? parent,
  }) async {
    final raw = await _rpc('service_list', scope, {
      'p_kind': kind.name,
      'p_after': after,
      'p_parent': parent,
    });
    return _page(serviceMap(raw), scope, kind.name, after, (row) {
      serviceScope(row, scope);
      return ServiceRecord.fromJson(kind, row);
    });
  }

  @override
  Future<ServiceDetail> detail(
    TenantContext scope,
    ServiceKind kind,
    String id, {
    String? after,
  }) async {
    calendarUuid(id);
    final r = serviceMap(
      await _rpc('service_detail', scope, {
        'p_kind': kind.name,
        'p_id': id,
        'p_after': after,
      }),
    );
    calendarFields(r, {'record', 'events', 'next_cursor'});
    final row = serviceMap(r['record']);
    serviceScope(row, scope);
    final record = ServiceRecord.fromJson(kind, row);
    if (record.id != id ||
        r['events'] is! List ||
        (r['events'] as List).length > 50) {
      throw const FormatException('Service detail identity changed.');
    }
    String? previous = after;
    final events = <ServiceEvent>[];
    for (final value in r['events'] as List) {
      final event = serviceMap(value);
      serviceScope(event, scope);
      final parsed = ServiceEvent.fromJson(event);
      if (parsed.aggregateId != id ||
          previous != null && parsed.id.compareTo(previous) <= 0) {
        throw const FormatException('Service event order changed.');
      }
      previous = parsed.id;
      events.add(parsed);
    }
    final next = r['next_cursor'] == null
        ? null
        : calendarUuid(r['next_cursor']);
    if (next != null && (events.length != 50 || next != previous)) {
      throw const FormatException('Service event continuation changed.');
    }
    return ServiceDetail(record, List.unmodifiable(events), next);
  }

  @override
  Future<ServicePage<ServiceChoice>> choices(
    TenantContext scope,
    String kind, {
    String? after,
    String? parent,
  }) async {
    if (!{
      'customer',
      'contact',
      'employee',
      'calendar',
      'claim',
    }.contains(kind)) {
      throw const FormatException('Service choice is invalid.');
    }
    return _page(
      serviceMap(
        await _rpc('service_choices', scope, {
          'p_kind': kind,
          'p_after': after,
          'p_parent': parent,
        }),
      ),
      scope,
      kind,
      after,
      ServiceChoice.fromJson,
    );
  }

  Map<String, Object?> _receipt(
    Object? raw,
    TenantContext scope,
    String? commandId,
  ) {
    final r = serviceMap(raw);
    calendarFields(r, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    calendarUuid(r['request_id']);
    calendarUuid(r['command_id']);
    calendarUuid(r['correlation_id']);
    if (commandId != null && r['command_id'] != commandId ||
        r['warnings'] is! List ||
        (r['warnings'] as List).isNotEmpty) {
      throw const FormatException('Service confirmation changed.');
    }
    final entity = serviceMap(r['entity']);
    calendarFields(entity, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'kind',
      'version',
      'status',
    });
    serviceScope(entity, scope);
    calendarUuid(entity['id']);
    serviceInt(entity['version'], min: 1);
    ServiceKind.values.byName(entity['kind'] as String);
    return Map<String, Object?>.from(jsonDecode(jsonEncode(r)) as Map);
  }

  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final copy = serviceMap(jsonDecode(jsonEncode(command.payload)));
    ServiceCommands.validate(action, copy);
    try {
      final raw = await _rpc('service_command', command.context, {
        'p_command_id': command.commandId,
        'p_idempotency_key': command.idempotencyKey,
        'p_issued_at': command.clientTimestamp.toIso8601String(),
        'p_payload': copy,
        'p_expected_version': command.expectedEntityVersion,
      }, command: true);
      final result = _receipt(raw, command.context, command.commandId),
          entity = serviceMap(result['entity']);
      if (entity['kind'] != ServiceCommands.kind(action).name ||
          entity['id'] != copy['id'] ||
          entity['version'] != (command.expectedEntityVersion ?? 0) + 1) {
        throw const FormatException('Service version confirmation changed.');
      }
      return result;
    } catch (e) {
      if (e is DomainError) {
        rethrow;
      }
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The confirmation is uncertain. Reconcile the exact saved request.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext scope,
    String action,
    String key,
  ) async {
    ServiceCommands.fields(action);
    calendarUuid(key);
    final raw = await _rpc('service_own_receipt', scope, {
      'p_idempotency_key': key,
      'p_action': action,
    }, command: true);
    return raw == null ? null : _receipt(raw, scope, null);
  }
}
