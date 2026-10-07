import 'dart:convert';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_people.dart';
import 'package:jentra_domain/jentra_asset_equipment.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service_gateway.dart';

final class SupabaseAssetEquipmentGateway implements AssetEquipmentRepository {
  SupabaseAssetEquipmentGateway(
    this.client, {
    this.timeout = const Duration(seconds: 30),
  }) : base = SupabaseServiceGateway(client, timeout: timeout);
  final SupabaseClient client;
  final SupabaseServiceGateway base;
  final Duration timeout;
  Future<Object?> _rpc(
    TenantContext s,
    String name,
    Map<String, Object?> args, {
    bool command = false,
  }) async {
    if (!s.hasOperationalScope || client.auth.currentUser?.id != s.actorId) {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Select your signed-in entity and branch.',
      );
    }
    try {
      final r = await client
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
      if (!command && client.auth.currentUser?.id != s.actorId) {
        throw const DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: 'The account changed.',
        );
      }
      return r;
    } on PostgrestException catch (e) {
      final code = switch ((e.code, e.message)) {
        ('PGRST202', _) => 'FEATURE_NOT_INSTALLED',
        ('42501', 'ASSET_ENTITLEMENT_REQUIRED') ||
        ('42501', 'SERVICE_ENTITLEMENT_REQUIRED') => 'FEATURE_NOT_ENTITLED',
        ('42501', _) => 'PERMISSION_DENIED',
        ('40001', _) => 'VERSION_CONFLICT',
        ('23505', _) => 'IDENTITY_EXISTS',
        ('P0002', _) => 'RESOURCE_NOT_FOUND',
        ('22023', 'IDEMPOTENCY_MISMATCH') => 'IDEMPOTENCY_MISMATCH',
        ('22023', _) => 'VALIDATION_ERROR',
        ('55000', _) => 'STATE_CONFLICT',
        _ => command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
      };
      throw DomainError(
        code: code,
        message: switch (code) {
          'FEATURE_NOT_INSTALLED' =>
            'The internal asset equipment provider is not installed.',
          'FEATURE_NOT_ENTITLED' =>
            'Service and assets must both be enabled on this plan.',
          'PERMISSION_DENIED' =>
            'Current service and asset permissions, branch scope and MFA are required.',
          'VERSION_CONFLICT' =>
            'The asset changed. Choose its current named source before creating a new link.',
          'IDENTITY_EXISTS' =>
            'This asset or equipment identity already has a link.',
          'RESOURCE_NOT_FOUND' =>
            'This asset or equipment link is unavailable in the selected branch.',
          'IDEMPOTENCY_MISMATCH' =>
            'The saved request key belongs to different content. Reconcile its original request.',
          'VALIDATION_ERROR' =>
            'Check the equipment fields, link reason and exact selected asset source.',
          'STATE_CONFLICT' =>
            'The asset must have its required active status and accountable branch.',
          'SERVICE_UNAVAILABLE' =>
            'The scoped asset source is unavailable. Retry its current read.',
          _ =>
            'The result is uncertain. Reconcile the original encrypted request.',
        },
        retryable: code == 'UNCERTAIN_RESULT' || code == 'SERVICE_UNAVAILABLE',
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw DomainError(
        code: command ? 'UNCERTAIN_RESULT' : 'SERVICE_UNAVAILABLE',
        message: command
            ? 'Reconcile the original encrypted request.'
            : 'The scoped asset source is unavailable.',
        retryable: true,
      );
    }
  }

  @override
  Future<ServiceAuthority> authorize(TenantContext s, String cap) async {
    final a = await base.authorize(s, cap);
    final r = serviceMap(
      await _rpc(s, 'service_asset_authorize', {'p_capability': cap}),
    );
    calendarFields(r, {
      'actor_id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'capability',
      'authorized',
    });
    serviceScope(r, s);
    if (r['actor_id'] != s.actorId ||
        r['capability'] != cap ||
        r['authorized'] != true) {
      throw const FormatException('Asset equipment authority changed.');
    }
    return ServiceAuthority(
      a.currency,
      a.precision,
      parts: a.parts,
      billing: a.billing,
      assets: true,
    );
  }

  @override
  Future<ServicePage<AssetEquipmentSource>> sources(
    TenantContext s, {
    String? after,
  }) async {
    final r = serviceMap(
      await _rpc(s, 'service_asset_sources', {'p_after': after}),
    );
    calendarFields(r, {
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'items',
      'next_cursor',
    });
    serviceScope(r, s);
    if (r['items'] is! List || (r['items'] as List).length > 50) {
      throw const FormatException('Asset page exceeds boundary.');
    }
    String? previous = after;
    final rows = <AssetEquipmentSource>[];
    for (final v in r['items'] as List) {
      final item = AssetEquipmentSource.fromJson(serviceMap(v), s);
      if (previous != null && item.id.compareTo(previous) <= 0) {
        throw const FormatException('Asset page order changed.');
      }
      previous = item.id;
      rows.add(item);
    }
    final next = r['next_cursor'] == null
        ? null
        : calendarUuid(r['next_cursor']);
    if (next != null && (rows.length != 50 || next != previous)) {
      throw const FormatException('Asset page continuation changed.');
    }
    return ServicePage(List.unmodifiable(rows), next);
  }

  @override
  Future<AssetEquipmentLink> link(TenantContext s, String id) async {
    final r = AssetEquipmentLink.fromJson(
      serviceMap(
        await _rpc(s, 'service_asset_link', {
          'p_equipment_id': calendarUuid(id),
        }),
      ),
      s,
    );
    if (r.equipmentId != id) {
      throw const FormatException('Equipment link identity changed.');
    }
    return r;
  }

  Map<String, Object?> _receipt(
    Object? raw,
    TenantContext s, {
    CommandEnvelope<Map<String, Object?>>? c,
  }) {
    final r = serviceMap(raw);
    calendarFields(r, {
      'request_id',
      'command_id',
      'correlation_id',
      'entity',
      'warnings',
    });
    for (final k in ['request_id', 'command_id', 'correlation_id']) {
      calendarUuid(r[k]);
    }
    final e = serviceMap(r['entity']);
    calendarFields(e, {
      'id',
      'tenant_id',
      'legal_entity_id',
      'branch_id',
      'kind',
      'version',
      'status',
    });
    serviceScope(e, s);
    calendarUuid(e['id']);
    if (e['kind'] != 'equipment' ||
        e['version'] != 1 ||
        e['status'] != 'active' ||
        r['warnings'] is! List ||
        (r['warnings'] as List).isNotEmpty ||
        c != null &&
            (r['command_id'] != c.commandId || e['id'] != c.payload['id'])) {
      throw const FormatException('Asset link confirmation changed.');
    }
    return serviceMap(jsonDecode(jsonEncode(r)));
  }

  @override
  Future<Map<String, Object?>> execute(
    String action,
    CommandEnvelope<Map<String, Object?>> c,
  ) async {
    final payload = serviceMap(jsonDecode(jsonEncode(c.payload)));
    AssetEquipmentCommands.validate(action, payload);
    try {
      return _receipt(
        await _rpc(c.context, 'service_asset_equipment_command', {
          'p_command_id': c.commandId,
          'p_idempotency_key': c.idempotencyKey,
          'p_issued_at': c.clientTimestamp.toIso8601String(),
          'p_payload': payload,
          'p_expected_version': c.expectedEntityVersion,
        }, command: true),
        c.context,
        c: c,
      );
    } on DomainError {
      rethrow;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Reconcile the exact original encrypted asset link request.',
        retryable: true,
      );
    }
  }

  @override
  Future<Map<String, Object?>?> ownReceipt(
    TenantContext s,
    String action,
    String key,
  ) async {
    if (action != 'equipment') {
      throw const FormatException('Asset link action required.');
    }
    final r = await _rpc(s, 'service_asset_own_receipt', {
      'p_idempotency_key': calendarUuid(key),
    }, command: true);
    return r == null ? null : _receipt(r, s);
  }

  @override
  Future<ServicePage<ServiceRecord>> list(
    TenantContext s,
    ServiceKind kind, {
    String? after,
    String? parent,
  }) => base.list(s, kind, after: after, parent: parent);
  @override
  Future<ServiceDetail> detail(
    TenantContext s,
    ServiceKind kind,
    String id, {
    String? after,
  }) => base.detail(s, kind, id, after: after);
  @override
  Future<ServicePage<ServiceChoice>> choices(
    TenantContext s,
    String kind, {
    String? after,
    String? parent,
  }) => base.choices(s, kind, after: after, parent: parent);
}
