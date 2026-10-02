import 'package:jentra_domain/jentra_inventory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class DispositionGateway {
  Future<Map<String, Object?>> detail(TenantContext scope, String id);
  Future<Map<String, Object?>> page(TenantContext scope, {String? after});
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
  });
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseDispositionGateway implements DispositionGateway {
  SupabaseDispositionGateway(this.client);
  final SupabaseClient client;
  static Never invalid() => throw const DomainError(
    code: 'UNCERTAIN_RESULT',
    message:
        'Response could not be verified. Refresh or retry the saved command.',
  );
  static bool exact(Object? value) =>
      value is String && RegExp(r'^\d{1,14}(\.\d{1,6})?$').hasMatch(value);
  void checkScope(Map<String, Object?> result, TenantContext scope) {
    if (result['tenant_id'] != scope.tenantId ||
        result['legal_entity_id'] != scope.legalEntityId ||
        result['branch_id'] != scope.branchId) {
      invalid();
    }
  }

  Map<String, Object?> checkDocument(
    Map<String, Object?> result,
    TenantContext scope,
    String id,
  ) {
    checkScope(result, scope);
    if (result['id'] != id ||
        result['version'] is! int ||
        (result['version'] as int) < 1 ||
        !{
          'draft',
          'pending_approval',
          'approved',
          'rejected',
          'posted',
          'cancelled',
        }.contains(result['status']) ||
        result['currency_code'] is! String ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(result['currency_code'] as String) ||
        !exact(result['grand_total']) ||
        result['lines'] is! List) {
      invalid();
    }
    final lines = result['lines'] as List;
    final ids = <String>{}, serials = <String>{};
    if (lines.isEmpty || lines.length > 100) invalid();
    for (final raw in lines) {
      if (raw is! Map ||
          raw['line_id'] is! String ||
          !ids.add(raw['line_id'] as String) ||
          !exact(raw['quantity']) ||
          !exact(raw['base_quantity']) ||
          !exact(raw['carrying_value']) ||
          raw['product_id'] is! String ||
          raw['serial_ids'] is! List ||
          !{'none', 'lot', 'serial'}.contains(raw['tracking_mode'])) {
        invalid();
      }
      for (final id in raw['serial_ids'] as List) {
        if (id is! String || !serials.add(id) || serials.length > 500) {
          invalid();
        }
      }
    }
    if (result['status'] == 'posted' &&
        (result['journal_entry_id'] is! String ||
            result['stock_movement_id'] is! String)) {
      invalid();
    }
    return result;
  }

  Map<String, Object?> checkPage(
    Map<String, Object?> result,
    TenantContext scope,
    String? after, {
    String? resource,
  }) {
    checkScope(result, scope);
    if (resource != null && result['resource'] != resource) invalid();
    final rows = result['items'];
    if (rows is! List || rows.length > 50) invalid();
    String? previous = after;
    for (final raw in rows) {
      if (raw is! Map ||
          raw['id'] is! String ||
          (previous != null &&
              (raw['id'] as String).compareTo(previous) <= 0)) {
        invalid();
      }
      previous = raw['id'] as String;
      if (resource == null &&
          (!exact(raw['grand_total']) ||
              raw['version'] is! int ||
              (raw['version'] as int) < 1)) {
        invalid();
      }
    }
    if (result['next_cursor'] != null &&
        (rows.length != 50 || result['next_cursor'] != previous)) {
      invalid();
    }
    return result;
  }

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
        'stock_disposition_options',
        'stock_dispositions_page',
        'stock_disposition_detail',
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
            'This disposition changed. Discard the local copy and reopen the current disposition.',
          'PERMISSION_DENIED' =>
            'The current permission, independent approval or MFA check failed.',
          'VALIDATION_ERROR' =>
            e.message == 'DISPOSITION_REAPPROVAL_REQUIRED'
                ? 'Stock valuation changed. Recall, save and obtain fresh approval.'
                : e.message == 'DISPOSITION_SERIAL_UNAVAILABLE'
                ? 'A selected serial is no longer held. Recall and select the available identities.'
                : e.message == 'DISPOSITION_LATER_HISTORY'
                ? 'Later stock or value history prevents this reversal.'
                : e.message == 'DISPOSITION_SERIAL_REVERSAL_DENIED'
                ? 'Disposed serial identities cannot be restored.'
                : 'Check the disposition state, active accounts, quantity, period and configured approval.',
          _ => 'The result is uncertain. Retry the saved command.',
        },
      );
    }
  }

  @override
  Future<Map<String, Object?>> detail(TenantContext scope, String id) async =>
      checkDocument(
        await rpc('stock_disposition_detail', {
          ...scopeParams(scope),
          'p_id': id,
        }),
        scope,
        id,
      );
  @override
  Future<Map<String, Object?>> page(
    TenantContext scope, {
    String? after,
  }) async => checkPage(
    await rpc('stock_dispositions_page', {
      ...scopeParams(scope),
      'p_after': after,
    }),
    scope,
    after,
  );
  @override
  Future<Map<String, Object?>> options(
    TenantContext scope,
    String resource, {
    String? warehouse,
    String? product,
    String? after,
  }) async {
    if (!{
      'warehouses',
      'products',
      'lots',
      'serials',
      'accounts',
    }.contains(resource)) {
      throw const FormatException('Unsupported disposition picker.');
    }
    return checkPage(
      await rpc('stock_disposition_options', {
        ...scopeParams(scope),
        'p_resource': resource,
        'p_warehouse_id': warehouse,
        'p_product_id': product,
        'p_after': after,
      }),
      scope,
      after,
      resource: resource,
    );
  }

  @override
  Future<Map<String, Object?>> execute(
    String verb,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    final name = switch (verb) {
      'save' => 'upsert_stock_disposition',
      'post' => 'post_stock_disposition',
      'submit' ||
      'recall' ||
      'cancel' ||
      'approve' ||
      'reject' => 'transition_stock_disposition',
      _ => throw const FormatException('Unsupported disposition action.'),
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
    final result = checkDocument(
      (r['entity'] as Map).cast<String, Object?>(),
      command.context,
      (command.payload['id'] ?? command.payload['document_id']) as String,
    );
    final expectedStates = switch (verb) {
      'save' || 'recall' => {'draft'},
      'submit' => {'pending_approval'},
      'approve' => {'approved', 'pending_approval'},
      'reject' => {'rejected'},
      'cancel' => {'cancelled'},
      'post' => {'posted'},
      _ => <String>{},
    };
    if (result['version'] != (command.expectedEntityVersion ?? 0) + 1 ||
        !expectedStates.contains(result['status'])) {
      invalid();
    }
    return result;
  }
}
