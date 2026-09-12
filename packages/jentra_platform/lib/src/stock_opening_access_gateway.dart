import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class StockOpeningAccessGateway {
  Future<List<Map<String, Object?>>> pending();
  Future<Map<String, Object?>> invite({
    required String tenantId,
    required String legalEntityId,
    required String branchId,
    required String email,
    required String idempotencyKey,
  });
  Future<Map<String, Object?>> accept({
    required String invitationId,
    required String idempotencyKey,
  });
}

final class SupabaseStockOpeningAccessGateway
    implements StockOpeningAccessGateway {
  SupabaseStockOpeningAccessGateway(this._client);
  final SupabaseClient _client;
  @override
  Future<List<Map<String, Object?>>> pending() async {
    final result = await _client
        .schema('api')
        .rpc('list_my_stock_opening_invitations');
    return (result as List)
        .map((r) => (r as Map).cast<String, Object?>())
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>> invite({
    required String tenantId,
    required String legalEntityId,
    required String branchId,
    required String email,
    required String idempotencyKey,
  }) => _command('invite_stock_opening_approver', {
    'p_tenant_id': tenantId,
    'p_legal_entity_id': legalEntityId,
    'p_branch_id': branchId,
    'p_email': email,
    'p_idempotency_key': idempotencyKey,
  });
  @override
  Future<Map<String, Object?>> accept({
    required String invitationId,
    required String idempotencyKey,
  }) => _command('accept_stock_opening_invitation', {
    'p_invitation_id': invitationId,
    'p_idempotency_key': idempotencyKey,
  });
  Future<Map<String, Object?>> _command(
    String name,
    Map<String, Object?> params,
  ) async {
    final result = await _client.schema('api').rpc(name, params: params);
    if (result is! Map ||
        result['request_id'] is! String ||
        result['entity'] is! Map ||
        (result['entity'] as Map)['id'] is! String) {
      throw const FormatException(
        'Server confirmation is incomplete. Retry the same request.',
      );
    }
    return result.cast<String, Object?>();
  }
}
