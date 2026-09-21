import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ReservationGateway {
  Future<Map<String, Object?>> asOf(
    TenantContext scope,
    String instant, {
    String? after,
  });
  Future<Map<String, Object?>> queue(
    TenantContext scope, {
    required String filter,
    String? after,
  });
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    int? beforeVersion,
  });
  Future<Map<String, Object?>> release(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseReservationGateway implements ReservationGateway {
  SupabaseReservationGateway(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, Object?>> asOf(
    TenantContext scope,
    String instant, {
    String? after,
  }) => rpc('stock_reservations_as_of', {
    ...scopeParams(scope),
    'p_as_of': instant,
    'p_after': after,
  });
  Map<String, Object?> scopeParams(TenantContext scope) {
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

  Future<Map<String, Object?>> rpc(
    String name,
    Map<String, Object?> params,
  ) async {
    try {
      final result = await client.schema('api').rpc(name, params: params);
      if (result is! Map) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Response could not be verified. Retry the saved command.',
        );
      }
      return result.cast<String, Object?>();
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
            'This reservation changed. Close the saved selection, refresh and review it again.',
          'PERMISSION_DENIED' =>
            'Your current reservation permission or scope check failed.',
          'VALIDATION_ERROR' => switch (e.message) {
            'RESERVATION_NOT_EXPIRED' =>
              'This reservation has not expired at server time.',
            'PRODUCT_STILL_ACTIVE' =>
              'This product is still active. Review the release mode.',
            'RESERVATION_NOT_ACTIVE' =>
              'This reservation is no longer active. Refresh the queue.',
            'RESERVATION_ASOF_OUTSIDE_COVERAGE' =>
              'Choose a past time within recorded history. Open a reservation history to see its coverage start.',
            _ =>
              'The release was rejected. Check its current state, version and reason.',
          },
          _ => 'The result is uncertain. Retry the saved command.',
        },
      );
    }
  }

  @override
  Future<Map<String, Object?>> queue(
    TenantContext scope, {
    required String filter,
    String? after,
  }) => rpc('stock_reservation_queue', {
    ...scopeParams(scope),
    'p_filter': filter,
    'p_after': after,
  });
  @override
  Future<Map<String, Object?>> history(
    TenantContext scope,
    String id, {
    int? beforeVersion,
  }) => rpc('stock_reservation_history', {
    ...scopeParams(scope),
    'p_id': id,
    'p_before_version': beforeVersion,
  });
  @override
  Future<Map<String, Object?>> release(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final result = await rpc('release_stock_reservation', {
      ...scopeParams(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    });
    if (result['command_id'] != command.commandId ||
        result['request_id'] is! String ||
        result['entity'] is! Map ||
        (result['entity'] as Map)['id'] != command.payload['id']) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Response identity could not be verified. Retry the saved command.',
      );
    }
    final entity = (result['entity'] as Map).cast<String, Object?>();
    final expectedStatus = command.payload['mode'] == 'expired'
        ? 'expired'
        : 'released';
    if (command.expectedEntityVersion == null ||
        entity['version'] != command.expectedEntityVersion! + 1 ||
        entity['status'] != expectedStatus ||
        entity['base_quantity'] is! String ||
        !RegExp(
          r'^\d{1,14}(\.\d{1,6})?$',
        ).hasMatch(entity['base_quantity'] as String) ||
        entity['released_at'] is! String ||
        DateTime.tryParse(entity['released_at'] as String) == null) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Release state could not be verified. Retry the saved command.',
      );
    }
    return entity;
  }
}
