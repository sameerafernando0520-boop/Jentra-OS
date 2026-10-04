import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseNegativeStockPolicyGateway
    implements NegativeStockPolicyRepository {
  SupabaseNegativeStockPolicyGateway(this.client);
  final SupabaseClient client;
  void _scope(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Choose your authenticated entity and branch.',
      );
    }
  }

  Map<String, Object?> _json(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Policy response is unavailable.');
    }
    return raw.cast<String, Object?>();
  }

  Map<String, Object?> _params(TenantContext scope) => {
    'p_tenant_id': scope.tenantId,
    'p_legal_entity_id': scope.legalEntityId,
    'p_branch_id': scope.branchId,
  };
  NegativeStockPolicy _policy(Object? raw, TenantContext scope) {
    final policy = NegativeStockPolicy.fromJson(_json(raw));
    if (policy.tenantId != scope.tenantId ||
        policy.legalEntityId != scope.legalEntityId) {
      throw const FormatException(
        'Policy response does not match the requested entity.',
      );
    }
    return policy;
  }

  DomainError _error(PostgrestException error) {
    final message = error.message;
    final exact = RegExp(
      r'NEGATIVE_STOCK_[A-Z_]+',
    ).firstMatch(message)?.group(0);
    final denial = switch (message) {
      'AUTHENTICATION_REQUIRED' => 'AUTHENTICATION_REQUIRED',
      'ACCESS_DENIED' => 'ACCESS_DENIED',
      'PERMISSION_DENIED' => 'PERMISSION_DENIED',
      'MFA_REQUIRED' || 'RECENT_MFA_REQUIRED' => 'MFA_REQUIRED',
      _ =>
        const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)
            ? 'AUTHENTICATION_REQUIRED'
            : null,
    };
    final code =
        denial ??
        (error.code == '42501'
            ? (message.contains('MFA') ? 'MFA_REQUIRED' : 'PERMISSION_DENIED')
            : error.code == '40001'
            ? 'VERSION_CONFLICT'
            : exact != null
            ? 'VALIDATION_ERROR'
            : RegExp(r'^(22|23|55)').hasMatch(error.code ?? '')
            ? 'VALIDATION_ERROR'
            : 'UNCERTAIN_RESULT');
    return DomainError(
      code: code,
      message: exact == null
          ? (code == 'PERMISSION_DENIED' || code == 'ACCESS_DENIED'
                ? 'Your current scope or capability does not permit this operation.'
                : code == 'MFA_REQUIRED'
                ? 'Verify your authentication before this operation.'
                : code == 'AUTHENTICATION_REQUIRED'
                ? 'Restore your authenticated session before this operation.'
                : 'The policy response could not be confirmed. Retry the saved request.')
          : switch (exact) {
              'NEGATIVE_STOCK_POLICY_VERSION_CONFLICT' =>
                'Policy changed. Review the current policy before configuring it.',
              'NEGATIVE_STOCK_COST_BASIS_UNKNOWN' =>
                'No authoritative positive cost basis exists for this stock.',
              'NEGATIVE_STOCK_TRACKING_REQUIRED' =>
                'Lot or serial shortages cannot use this policy.',
              'NEGATIVE_STOCK_POLICY_INACTIVE' =>
                'The negative-stock policy is inactive.',
              _ => 'Check the policy version, active selection and reason.',
            },
      fieldDetails: exact == null ? {} : {'policy': exact},
      retryable: code == 'UNCERTAIN_RESULT',
    );
  }

  @override
  Future<NegativeStockPolicy> readPolicy(TenantContext scope) async {
    _scope(scope);
    try {
      final raw = await client
          .schema('api')
          .rpc('negative_stock_policy', params: _params(scope));
      return _policy(raw, scope);
    } on PostgrestException catch (error) {
      throw _error(error);
    } on AuthException {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Sign in again to read this policy.',
      );
    }
  }

  @override
  Future<NegativeStockEvidencePage> evidence(
    TenantContext scope,
    NegativeStockEvidenceKind kind, {
    BigInt? after,
  }) async {
    _scope(scope);
    try {
      final raw = await client
          .schema('api')
          .rpc(
            'negative_stock_evidence',
            params: {
              ..._params(scope),
              'p_resource': kind.name,
              'p_after': after?.toString(),
            },
          );
      final page = NegativeStockEvidencePage.fromJson(kind, _json(raw));
      if (after != null && page.items.any((row) => row.ledgerId <= after)) {
        throw const FormatException('Evidence cursor did not advance.');
      }
      return page;
    } on PostgrestException catch (error) {
      throw _error(error);
    } on AuthException {
      throw const DomainError(
        code: 'AUTHENTICATION_REQUIRED',
        message: 'Sign in again to read this evidence.',
      );
    }
  }

  @override
  Future<CommandResult<NegativeStockPolicy>> configure(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    try {
      _scope(command.context);
      final reason = command.payload['reason'];
      if (command.expectedEntityVersion == null ||
          command.expectedEntityVersion! < 0 ||
          command.payload['active'] is! bool ||
          reason is! String ||
          reason.trim().isEmpty ||
          reason.length > 1000) {
        throw const DomainError(
          code: 'VALIDATION_ERROR',
          message: 'Choose a current policy version, active state and reason.',
        );
      }
      final raw = _json(
        await client
            .schema('api')
            .rpc(
              'configure_negative_stock_policy',
              params: {
                ..._params(command.context),
                'p_command_id': command.commandId,
                'p_idempotency_key': command.idempotencyKey,
                'p_client_timestamp': command.clientTimestamp.toIso8601String(),
                'p_payload': command.payload,
                'p_expected_entity_version': command.expectedEntityVersion,
              },
            ),
      );
      final request = raw['request_id'];
      if (request is! String ||
          request.isEmpty ||
          raw['command_id'] != command.commandId) {
        throw const FormatException('Policy receipt identity is unavailable.');
      }
      final entity = _policy(raw['entity'], command.context);
      if (entity.id != command.commandId ||
          entity.createdBy != command.context.actorId ||
          command.expectedEntityVersion == null ||
          entity.version !=
              BigInt.from(command.expectedEntityVersion!) + BigInt.one ||
          entity.active != command.payload['active'] ||
          entity.reason != reason.trim()) {
        throw const FormatException(
          'Policy receipt does not match the saved command.',
        );
      }
      return CommandResult.success(requestId: request, entity: entity);
    } on PostgrestException catch (error) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: _error(error),
      );
    } on DomainError catch (error) {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: error,
      );
    } on AuthException {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'AUTHENTICATION_REQUIRED',
          message: 'Sign in again before recording this policy.',
        ),
      );
    } on Object {
      return CommandResult.failure(
        requestId: command.idempotencyKey,
        error: const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'Configuration outcome is uncertain. Retry the identical saved request.',
          retryable: true,
        ),
      );
    }
  }
}
