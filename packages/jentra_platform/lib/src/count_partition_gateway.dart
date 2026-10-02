import 'package:jentra_domain/count_partitions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class CountPartitionGateway {
  Future<CountPartitionProgress> capture(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<CountPartitionProgress> page(
    TenantContext scope,
    String groupId, {
    int after = 0,
    int limit = 50,
  });
}

final class SupabaseCountPartitionGateway implements CountPartitionGateway {
  SupabaseCountPartitionGateway(this.client);
  final SupabaseClient client;
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
      final response = await client.schema('api').rpc(name, params: params);
      if (response is! Map) {
        throw const FormatException('Invalid partition response.');
      }
      return response.cast<String, Object?>();
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
        message: e.message == 'LIMIT_EXCEEDED'
            ? 'This product exceeds the 10,000-identity partition capture limit. No count was saved.'
            : code == 'PERMISSION_DENIED'
            ? 'Current cost access, count permission or MFA is required.'
            : code == 'VERSION_CONFLICT'
            ? 'This group already exists. Reopen the current group.'
            : code == 'VALIDATION_ERROR'
            ? 'Check tracked holdings, active warehouse, account, date and reason.'
            : 'The capture result is uncertain. Retry the saved command.',
      );
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'The capture result is uncertain. Retry the saved command.',
      );
    }
  }

  CountPartitionProgress _progress(Map<String, Object?> json, String id) {
    try {
      final value = CountPartitionProgress.fromJson(json);
      if (value.id != id) {
        throw const FormatException('Group identity mismatch.');
      }
      return value;
    } catch (_) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Partition progress could not be verified. Retry the saved command.',
      );
    }
  }

  @override
  Future<CountPartitionProgress> capture(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final payload = countPartitionCapturePayload(command.payload);
    final response = await _rpc('capture_stock_count_partitions', {
      ..._scope(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': payload,
    });
    if (response['command_id'] != command.commandId ||
        response['request_id'] is! String ||
        response['entity'] is! Map) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Capture receipt identity could not be verified. Retry the saved command.',
      );
    }
    return _progress(
      (response['entity'] as Map).cast<String, Object?>(),
      payload['id'] as String,
    );
  }

  @override
  Future<CountPartitionProgress> page(
    TenantContext scope,
    String groupId, {
    int after = 0,
    int limit = 50,
  }) async {
    if (after < 0 || limit < 1 || limit > 50) {
      throw const FormatException('Load 1–50 partition documents per page.');
    }
    return _progress(
      await _rpc('stock_count_partitions_page', {
        ..._scope(scope),
        'p_group_id': groupId,
        'p_after': after,
        'p_limit': limit,
      }),
      groupId,
    );
  }
}
