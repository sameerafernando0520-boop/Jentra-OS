import 'dart:convert';

import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class FinanceOpeningGateway {
  Future<Map<String, Object?>> batches(TenantContext scope, {String? after});
  Future<Map<String, Object?>> detail(TenantContext scope, String id);
  Future<Map<String, Object?>> source(TenantContext scope, String id);
  Future<Map<String, Object?>> reversal(TenantContext scope, String id);
  Future<Map<String, Object?>> reversals(
    TenantContext scope,
    String batchId, {
    String? after,
  });
  Future<Map<String, Object?>> options(
    TenantContext scope, {
    required String kind,
    required String currencyCode,
    required String resource,
    String? after,
  });
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  );
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class FinanceOpeningFailure implements Exception {
  const FinanceOpeningFailure(
    this.code,
    this.message, {
    required this.definite,
    this.issues = const [],
  });

  final String code;
  final String message;
  final bool definite;
  final List<Map<String, Object?>> issues;
}

final class SupabaseFinanceOpeningGateway implements FinanceOpeningGateway {
  SupabaseFinanceOpeningGateway(this._client);

  final SupabaseClient _client;

  static const _uncertain = FinanceOpeningFailure(
    'UNCERTAIN_RESULT',
    'The result could not be confirmed. Retry the saved command.',
    definite: false,
  );

  @override
  Future<Map<String, Object?>> batches(TenantContext scope, {String? after}) =>
      _call('finance_opening_batches', scope, {
        'p_after': after,
        'p_limit': 50,
      });

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) =>
      _call('finance_opening_batch', scope, {'p_id': id});

  @override
  Future<Map<String, Object?>> source(TenantContext scope, String id) =>
      _call('finance_opening_source', scope, {'p_source_id': id});

  @override
  Future<Map<String, Object?>> reversal(TenantContext scope, String id) =>
      _call('finance_opening_reversal', scope, {'p_id': id});

  @override
  Future<Map<String, Object?>> reversals(
    TenantContext scope,
    String batchId, {
    String? after,
  }) => _call('finance_opening_reversals', scope, {
    'p_batch_id': batchId,
    'p_after': after,
    'p_limit': 50,
  });

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope, {
    required String kind,
    required String currencyCode,
    required String resource,
    String? after,
  }) => _call('finance_opening_reference_options', scope, {
    'p_kind': kind,
    'p_currency_code': currencyCode,
    'p_resource': resource,
    'p_after': after,
    'p_limit': 50,
  });

  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) => _call('preview_finance_opening_batch', scope, {'p_payload': payload});

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final rpc = switch (verb) {
      'save' || 'upsert' => 'upsert_finance_opening_batch',
      'transition' => 'transition_finance_opening_batch',
      'post' => 'post_finance_opening_batch',
      'request_reversal' => 'prepare_finance_opening_reversal',
      'transition_reversal' => 'transition_finance_opening_reversal',
      'post_reversal' => 'post_finance_opening_reversal',
      _ => throw const FinanceOpeningFailure(
        'COMMAND_INVALID',
        'Choose a supported opening balance action.',
        definite: true,
      ),
    };
    final id = command.payload['id'] ?? command.payload['document_id'];
    if (id is! String || id.isEmpty) {
      throw const FinanceOpeningFailure(
        'COMMAND_INVALID',
        'An opening batch identifier is required.',
        definite: true,
      );
    }
    final scope = command.context;
    final result = await _call(rpc, scope, {
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    }, write: true);
    final entity = result['entity'];
    final reversal = const {
      'request_reversal',
      'transition_reversal',
      'post_reversal',
    }.contains(verb);
    final batchId = verb == 'request_reversal'
        ? command.payload['document_id']
        : command.payload['batch_id'];
    if (result['request_id'] is! String ||
        result['command_id'] != command.commandId ||
        entity is! Map ||
        entity['id'] != id ||
        entity['tenant_id'] != scope.tenantId ||
        entity['legal_entity_id'] != scope.legalEntityId ||
        entity['branch_id'] != scope.branchId ||
        (reversal && (batchId is! String || entity['batch_id'] != batchId))) {
      throw _uncertain;
    }
    return result;
  }

  Future<Map<String, Object?>> _call(
    String rpc,
    TenantContext scope,
    Map<String, Object?> parameters, {
    bool write = false,
  }) async {
    const denied = FinanceOpeningFailure(
      'PERMISSION_DENIED',
      'Select your current authenticated company and branch.',
      definite: true,
    );
    if (!scope.hasOperationalScope ||
        _client.auth.currentUser?.id != scope.actorId) {
      throw denied;
    }
    try {
      final result = await _client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...parameters,
            },
          );
      if (_client.auth.currentUser?.id != scope.actorId) {
        throw write ? _uncertain : denied;
      }
      if (result is! Map) {
        throw write
            ? _uncertain
            : const FinanceOpeningFailure(
                'INVALID_RESPONSE',
                'Opening balances could not be read.',
                definite: true,
              );
      }
      return result.cast<String, Object?>();
    } on PostgrestException catch (error) {
      final sqlState = error.code ?? '';
      final definite = RegExp(r'^(22|23|40|42|54|55|P0)').hasMatch(sqlState);
      if (write && !definite && sqlState != 'PGRST202') throw _uncertain;
      final openingError = switch (error.message) {
        'OPENING_VALIDATION_FAILED' => FinanceOpeningFailure(
          'OPENING_VALIDATION_FAILED',
          'Review the updated validation issues before saving the batch.',
          definite: definite,
          issues: _validationIssues(error.details),
        ),
        'OPENING_SOURCE_CHANGED' => const FinanceOpeningFailure(
          'OPENING_SOURCE_CHANGED',
          'A party, account or other posting reference changed. Review the batch and prepare a fresh approval.',
          definite: true,
        ),
        'OPENING_DUPLICATE_DOCUMENT' => const FinanceOpeningFailure(
          'OPENING_DUPLICATE_DOCUMENT',
          'A source document was already imported. Review the batch against the opening register.',
          definite: true,
        ),
        'OPENING_REVERSAL_SETTLEMENT_HISTORY' ||
        'OPENING_REVERSAL_FX_HISTORY' => FinanceOpeningFailure(
          error.message,
          'This batch has allocation or FX history. Review its linked records before requesting a correction.',
          definite: true,
        ),
        'PAYABLE_ITEM_ALREADY_SELECTED' => const FinanceOpeningFailure(
          'PAYABLE_ITEM_ALREADY_SELECTED',
          'A supplier payment currently includes an item from this batch. Review the payment selection.',
          definite: true,
        ),
        'OPENING_REVERSAL_STALE' => const FinanceOpeningFailure(
          'OPENING_REVERSAL_STALE',
          'A posting reference changed. Cancel this request and prepare a new one for independent review.',
          definite: true,
        ),
        'OPENING_REVERSAL_FX_PERIOD' => const FinanceOpeningFailure(
          'OPENING_REVERSAL_FX_PERIOD',
          'Choose a reversal date in the original fiscal period for a foreign-currency batch.',
          definite: true,
        ),
        'OPENING_REVERSAL_BUSY' => const FinanceOpeningFailure(
          'OPENING_REVERSAL_BUSY',
          'Another opening action is still running. Retry the saved request.',
          definite: true,
        ),
        _ => null,
      };
      if (openingError != null) throw openingError;
      throw switch (sqlState) {
        '42501' => const FinanceOpeningFailure(
          'PERMISSION_DENIED',
          'Current access, independent approval or MFA verification failed.',
          definite: true,
        ),
        '40001' => const FinanceOpeningFailure(
          'VERSION_CONFLICT',
          'This batch changed. Reopen it before making changes.',
          definite: true,
        ),
        'PGRST202' => const FinanceOpeningFailure(
          'FEATURE_UNAVAILABLE',
          'Opening balance import is unavailable for this company.',
          definite: true,
        ),
        _ => FinanceOpeningFailure(
          RegExp(r'^OPENING_[A-Z_]+$').hasMatch(error.message)
              ? error.message
              : 'OPENING_REQUEST_FAILED',
          'Check the batch, account selections and current period, then try again.',
          definite: definite,
        ),
      };
    } on FinanceOpeningFailure {
      rethrow;
    } on Exception {
      if (write) throw _uncertain;
      rethrow;
    }
  }

  static List<Map<String, Object?>> _validationIssues(Object? detail) {
    try {
      final value = detail is String ? jsonDecode(detail) : detail;
      return [
        if (value is List)
          for (final row in value)
            if (row is Map &&
                row['field'] is String &&
                row['message'] is String)
              {
                'row': row['row'] is int ? row['row'] : null,
                'field': row['field'],
                'message': row['message'],
              },
      ];
    } on FormatException {
      return const [];
    }
  }
}
