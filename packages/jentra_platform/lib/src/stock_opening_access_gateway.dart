import 'package:supabase_flutter/supabase_flutter.dart';

/// A server response, distinct from an unconfirmed transport outcome.
final class StockOpeningAccessFailure implements Exception {
  const StockOpeningAccessFailure(this.message);
  final String message;
}

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
    final Object? result;
    try {
      result = await _client.schema('api').rpc(name, params: params);
    } on PostgrestException catch (error) {
      const safeMessages = {
        'Multi-factor authentication required.':
            'Complete MFA for your owner session, then retry this request.',
        'Choose an independent approver.':
            'Use a different account from the signed-in owner. The owner cannot approve their own opening.',
        'This account already has workspace membership; review its access separately.':
            'This account already belongs to the workspace. Its existing access must be reviewed separately.',
        'Stock opening approver role differs from the governed permission set.':
            'The existing approver role has conflicting permissions. Ask the workspace administrator to review it.',
        'Choose an active branch in this legal entity.':
            'Close this form and select an active branch in the correct legal entity.',
        'Permission denied.':
            'Your session does not have permission for this action. Verify owner access and MFA.',
      };
      final code = error.code;
      final safeCode =
          code != null && RegExp(r'^[A-Z0-9]{5,12}$').hasMatch(code)
          ? code
          : 'unknown';
      throw StockOpeningAccessFailure(
        safeMessages[error.message] ??
            'The server returned error $safeCode. Keep this request for retry and report this code. Confirmation is still required.',
      );
    }
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
