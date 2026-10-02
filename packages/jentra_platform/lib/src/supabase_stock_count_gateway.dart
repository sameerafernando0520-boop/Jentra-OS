import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class StockCountGateway {
  Future<Map<String, Object?>> detail(TenantContext scope, String id);
  Future<Map<String, Object?>> page(TenantContext scope, {String? after});
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? after,
    String search = '',
  });
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseStockCountGateway implements StockCountGateway {
  SupabaseStockCountGateway(this.client);
  final SupabaseClient client;
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
      final r = await client.schema('api').rpc(name, params: params);
      if (r is! Map) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Response could not be verified. Retry the saved command.',
        );
      }
      return r.cast<String, Object?>();
    } on PostgrestException catch (e) {
      if ({
        'stock_count_options',
        'stock_counts_page',
        'stock_count_detail',
      }.contains(name)) {
        const denied = {
          'PERMISSION_DENIED',
          'ACCESS_DENIED',
          'MFA_REQUIRED',
          'AUTHENTICATION_REQUIRED',
        };
        final code = denied.contains(e.message)
            ? e.message
            : const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(e.code)
            ? 'AUTHENTICATION_REQUIRED'
            : null;
        if (code != null) {
          throw DomainError(
            code: code,
            message:
                'Evidence is unavailable with your current access. Recheck your role and scope.',
          );
        }
      }
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
            'This count changed. Discard the local copy and reopen the current count.',
          'PERMISSION_DENIED' =>
            'The current permission, independent approval or MFA check failed.',
          'VALIDATION_ERROR' =>
            e.message == 'COUNT_REAPPROVAL_REQUIRED'
                ? 'Stock valuation changed. Recall, save and obtain fresh approval.'
                : e.message == 'COUNT_SERIAL_CHANGED'
                ? 'A captured serial changed. Cancel this count and capture a new cutoff.'
                : e.message == 'COUNT_IDENTITY_LIMIT'
                ? 'This product exceeds the 500-identity count limit. No partial cutoff was saved.'
                : 'Check the count state, active accounts, quantity, period and configured approval.',
          _ => 'The result is uncertain. Retry the saved command.',
        },
      );
    }
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) =>
      rpc('stock_count_detail', {...scopeParams(scope), 'p_id': id});
  @override
  Future<Map<String, Object?>> page(TenantContext scope, {String? after}) =>
      rpc('stock_counts_page', {...scopeParams(scope), 'p_after': after});
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? after,
    String search = '',
  }) => rpc('stock_count_options', {
    ...scopeParams(scope),
    'p_resource': resource,
    'p_warehouse_id': warehouse,
    'p_after': after,
    'p_search': search,
  });
  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final name = switch (verb) {
      'save' => 'upsert_stock_count',
      'post' => 'post_stock_adjustment',
      'submit' ||
      'recall' ||
      'cancel' ||
      'approve' ||
      'reject' => 'transition_stock_count',
      _ => throw const FormatException('Unsupported count action.'),
    };
    final r = await rpc(name, {
      ...scopeParams(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    });
    if (r['command_id'] != command.commandId ||
        r['request_id'] is! String ||
        r['entity'] is! Map ||
        (r['entity'] as Map)['id'] !=
            (command.payload['id'] ?? command.payload['document_id'])) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Response identity could not be verified. Retry the saved command.',
      );
    }
    return (r['entity'] as Map).cast<String, Object?>();
  }
}
