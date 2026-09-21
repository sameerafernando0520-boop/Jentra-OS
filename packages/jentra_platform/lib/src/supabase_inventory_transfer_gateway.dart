import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class InventoryTransferGateway {
  Future<Map<String, Object?>> page(TenantContext scope, {String? after});
  Future<Map<String, Object?>> holdings(
    TenantContext scope,
    String asOf, {
    String? after,
  });
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
    String search = '',
  });
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseInventoryTransferGateway
    implements InventoryTransferGateway {
  SupabaseInventoryTransferGateway(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, Object?>> holdings(
    TenantContext scope,
    String asOf, {
    String? after,
  }) => _rpc('inventory_transfer_holdings', {
    ..._scope(scope),
    'p_as_of': asOf,
    'p_after': after,
  });
  Map<String, Object?> _scope(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your current authenticated entity and branch.',
      );
    }
    return {
      'p_tenant_id': scope.tenantId,
      'p_legal_entity_id': scope.legalEntityId,
      'p_branch_id': scope.branchId,
    };
  }

  Future<Map<String, Object?>> _rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final raw = await client.schema('api').rpc(name, params: params);
      if (raw is! Map) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Response could not be verified. Retain the saved command.',
        );
      }
      return raw.cast<String, Object?>();
    } on PostgrestException catch (e) {
      final code = e.code == '40001'
          ? 'VERSION_CONFLICT'
          : e.code == '42501'
          ? 'PERMISSION_DENIED'
          : RegExp(r'^(22|23|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: switch (code) {
          'VERSION_CONFLICT' =>
            'This transfer changed. Refresh before preparing another action.',
          'PERMISSION_DENIED' =>
            'Transfer authority and MFA are required for both warehouse branches.',
          'VALIDATION_ERROR' =>
            'Check available stock, tracking, units, date and transfer state. No changes were posted.',
          _ => 'The result is uncertain. Retry the same saved command.',
        },
      );
    }
  }

  @override
  Future<Map<String, Object?>> page(TenantContext scope, {String? after}) =>
      _rpc('inventory_transfers', {..._scope(scope), 'p_after': after});
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
    String search = '',
  }) => _rpc('inventory_transfer_options', {
    ..._scope(scope),
    'p_resource': resource,
    'p_warehouse_id': warehouse,
    'p_product_id': product,
    'p_after': after,
    'p_search': search,
  });
  @override
  Future<Map<String, Object?>> execute(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final raw = await _rpc('transfer_stock', {
      ..._scope(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    });
    if (raw['command_id'] != command.commandId ||
        raw['request_id'] is! String ||
        raw['entity'] is! Map ||
        (raw['entity'] as Map)['id'] != command.payload['id']) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'The response identity could not be verified. Retry the saved command.',
      );
    }
    return (raw['entity'] as Map).cast<String, Object?>();
  }
}
