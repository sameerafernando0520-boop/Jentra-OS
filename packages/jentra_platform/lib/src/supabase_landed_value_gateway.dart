import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class LandedValueGateway {
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  });
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  );
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseLandedValueGateway implements LandedValueGateway {
  SupabaseLandedValueGateway(this.client);
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
      final code = e.code == '40001'
          ? 'VERSION_CONFLICT'
          : e.code == '42501'
          ? 'PERMISSION_DENIED'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: switch (e.message) {
          'LANDED_PREVIEW_CHANGED' =>
            'Stock or valuation changed. Refresh the preview before posting.',
          'LANDED_REVERSAL_STOCK_CHANGED' =>
            'Stock valuation changed after this adjustment. An accounting correction is required.',
          'LANDED_RECEIPT_IN_TRANSIT' =>
            'Complete or reverse the transfer before allocating landed value.',
          'LANDED_RECEIPT_DISPOSITION_REVIEW' =>
            'This receipt has supplier-return or count effects requiring accounting review.',
          'LANDED_RECEIPT_CONSUMED_OR_UNCOVERED' =>
            'Choose a covered receipt with stock remaining.',
          _ =>
            code == 'PERMISSION_DENIED'
                ? 'Valuation, cost access and MFA are required in every affected branch.'
                : code == 'UNCERTAIN_RESULT'
                ? 'The outcome is uncertain. Retry the identical saved command.'
                : 'Check the receipt, accounts, amount, date, period and reference.',
        },
      );
    }
  }

  void validate(Map<String, Object?> r) {
    for (final key in [
      'amount',
      'inventory_amount',
      'variance_amount',
      'received_quantity',
      'held_quantity',
      'consumed_quantity',
    ]) {
      if (r[key] is! String ||
          !RegExp(r'^-?\d+(\.\d{1,6})?$').hasMatch(r[key] as String)) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'Exact allocation could not be verified. Retry the saved command.',
        );
      }
    }
    if (r['legs'] is! List || (r['legs'] as List).length > 100) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Allocation details could not be verified.',
      );
    }
    for (final leg in r['legs'] as List) {
      if (leg is! Map ||
          leg['warehouse_id'] is! String ||
          leg['value'] is! String ||
          !RegExp(r'^-?\d+(\.\d{1,6})?$').hasMatch(leg['value'] as String)) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message: 'Allocation details could not be verified.',
        );
      }
    }
    ExactDecimal decimal(Object? value) =>
        ExactDecimal.parse(value as String, scale: 6);
    final inventory = decimal(r['inventory_amount']);
    final sum = (r['legs'] as List).fold(
      ExactDecimal.zero(scale: 6),
      (total, leg) => total + decimal(leg['value']),
    );
    if (sum != inventory ||
        decimal(r['amount']) != inventory + decimal(r['variance_amount']) ||
        decimal(r['received_quantity']) !=
            decimal(r['held_quantity']) + decimal(r['consumed_quantity'])) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Allocation totals could not be verified. Retry the saved command.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? after,
  }) async {
    final r = await rpc('inventory_value_options', {
      ...scopeParams(scope),
      'p_resource': resource,
      'p_after': after,
    });
    final rows = r['items'];
    if (rows is! List ||
        rows.length > 50 ||
        rows.any((row) => row is! Map || row['id'] is! String) ||
        (r['next_cursor'] != null && r['next_cursor'] is! String)) {
      throw const FormatException('Register response could not be verified.');
    }
    if (resource == 'posted') {
      for (final row in rows) {
        validate((row as Map).cast<String, Object?>());
      }
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> preview(
    TenantContext scope,
    Map<String, Object?> payload,
  ) async {
    final r = await rpc('preview_inventory_value_adjustment', {
      ...scopeParams(scope),
      'p_payload': payload,
    });
    validate(r);
    if (r['receipt_line_id'] != payload['receipt_line_id'] ||
        r['basis_hash'] is! String) {
      throw const FormatException(
        'Preview identity does not match the selected receipt.',
      );
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> post(
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final r = await rpc('post_inventory_value_adjustment', {
      ...scopeParams(command.context),
      'p_command_id': command.commandId,
      'p_idempotency_key': command.idempotencyKey,
      'p_client_timestamp': command.clientTimestamp.toIso8601String(),
      'p_expected_entity_version': command.expectedEntityVersion,
      'p_payload': command.payload,
    });
    if (r['command_id'] != command.commandId ||
        r['request_id'] is! String ||
        r['entity'] is! Map) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Posting receipt could not be verified. Retry the saved command.',
      );
    }
    final result = (r['entity'] as Map).cast<String, Object?>();
    validate(result);
    if (result['id'] != command.payload['id'] ||
        result['status'] != 'posted' ||
        result['version'] != 1 ||
        result['reverse_of'] != command.payload['reverse_of'] ||
        ExactDecimal.parse(
              result['amount'] as String,
              scale: 6,
            ).scaledValue.sign !=
            (command.payload['reverse_of'] == null ? 1 : -1) ||
        (command.payload['reverse_of'] == null &&
            (result['receipt_line_id'] != command.payload['receipt_line_id'] ||
                ExactDecimal.parse(result['amount'] as String, scale: 6) !=
                    ExactDecimal.parse(
                      command.payload['amount'] as String,
                      scale: 6,
                    ))) ||
        result['journal_ids'] is! List ||
        (result['journal_ids'] as List).isEmpty ||
        (result['journal_ids'] as List).any(
          (id) => id is! String || id.isEmpty,
        )) {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message:
            'Posting identity could not be verified. Retry the saved command.',
      );
    }
    return result;
  }
}
