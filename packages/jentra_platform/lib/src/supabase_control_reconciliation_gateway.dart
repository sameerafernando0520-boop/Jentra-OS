import 'package:jentra_domain/jentra_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ControlReconciliationGateway {
  Future<Map<String, Object?>> reports(TenantContext scope, {String? after});
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? accountId,
  });
  Future<Map<String, Object?>> reverse(
    String kind,
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseControlReconciliationGateway
    implements ControlReconciliationGateway {
  SupabaseControlReconciliationGateway(this.client);
  final SupabaseClient client;
  Future<Map<String, Object?>> call(
    String rpc,
    TenantContext scope,
    Map<String, Object?> params,
  ) async {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Select your authenticated entity and branch.',
      );
    }
    try {
      final r = await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              ...params,
            },
          );
      if (r is! Map) {
        throw const FormatException('Invalid reconciliation response.');
      }
      return r.cast<String, Object?>();
    } on PostgrestException catch (e) {
      final code = e.code == '42501'
          ? 'PERMISSION_DENIED'
          : e.code == '40001'
          ? 'VERSION_CONFLICT'
          : RegExp(r'^(22|23|54|55|P0)').hasMatch(e.code ?? '')
          ? 'VALIDATION_ERROR'
          : 'UNCERTAIN_RESULT';
      throw DomainError(
        code: code,
        message: switch (code) {
          'PERMISSION_DENIED' =>
            'Current finance, reconciliation or reversal access is required.',
          'VERSION_CONFLICT' =>
            'The requested version changed. Refresh the source.',
          'VALIDATION_ERROR' =>
            e.message == 'OPEN_ITEM_CONTROL_BASIS_REQUIRED'
                ? 'A source journal has no unique control account. Review its posting evidence.'
                : e.message == 'ALLOCATION_ALREADY_REVERSED'
                ? 'This allocation is already reversed. Generate a fresh report.'
                : e.code == '54000'
                ? 'The report exceeds its supported size. No partial report was saved.'
                : 'Check the date, control setup, open period and allocation history.',
          _ => 'The outcome is uncertain. Retry the identical saved request.',
        },
      );
    }
  }

  ExactDecimal decimal(Object? v) {
    if (v is! String || !RegExp(r'^-?\d+(\.\d{1,6})?$').hasMatch(v)) {
      throw const FormatException(
        'Financial values must be exact decimal strings.',
      );
    }
    return ExactDecimal.parse(v, scale: 6);
  }

  void totals(Map r) {
    if (decimal(r['subledger_value']) - decimal(r['gl_value']) !=
        decimal(r['difference'])) {
      throw const FormatException('Control totals do not reconcile.');
    }
  }

  void summary(Map r, TenantContext scope) {
    if (r['tenant_id'] != scope.tenantId ||
        r['legal_entity_id'] != scope.legalEntityId ||
        r['branch_id'] != scope.branchId ||
        !['AR', 'AP'].contains(r['kind']) ||
        r['status'] != 'generated' ||
        r['version'] != 1) {
      throw const FormatException('Report scope or state does not match.');
    }
    for (final k in [
      'id',
      'as_of',
      'generated_at',
      'currency_code',
      'entity_name',
      'branch_name',
    ]) {
      if (r[k] is! String) {
        throw const FormatException('Missing report identity.');
      }
    }
    for (final k in ['item_count', 'difference_count']) {
      if (r[k] is! int || r[k] < 0 || r[k] > 50000) {
        throw const FormatException('Invalid report count.');
      }
    }
    totals(r);
    if (r['accounts'] is! List ||
        (r['accounts'] as List).isEmpty ||
        (r['accounts'] as List).length > 50) {
      throw const FormatException('Missing control account basis.');
    }
    var s = ExactDecimal.parse('0', scale: 6), g = s;
    final ids = <String>{};
    for (final a in r['accounts'] as List) {
      if (a is! Map ||
          a['id'] is! String ||
          a['code'] is! String ||
          a['name'] is! String ||
          !ids.add(a['id'])) {
        throw const FormatException('Invalid account basis.');
      }
      totals(a);
      s += decimal(a['subledger_value']);
      g += decimal(a['gl_value']);
    }
    if (s != decimal(r['subledger_value']) || g != decimal(r['gl_value'])) {
      throw const FormatException('Account totals do not match the report.');
    }
  }

  void rows(Map r) {
    if (r['items'] is! List ||
        (r['items'] as List).length > 50 ||
        (r['items'] as List).any((x) => x is! Map || x['id'] is! String) ||
        (r['next_cursor'] != null && r['next_cursor'] is! String)) {
      throw const FormatException('Invalid bounded evidence page.');
    }
  }

  Map<String, Object?> envelope(CommandEnvelope<Map<String, Object?>> c) => {
    'p_command_id': c.commandId,
    'p_idempotency_key': c.idempotencyKey,
    'p_client_timestamp': c.clientTimestamp.toIso8601String(),
    'p_expected_entity_version': c.expectedEntityVersion,
    'p_payload': c.payload,
  };
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> c,
    void Function(Map<String, Object?>) validate,
  ) async {
    try {
      final r = await call(rpc, c.context, envelope(c));
      if (r['command_id'] != c.commandId ||
          r['request_id'] is! String ||
          r['entity'] is! Map) {
        throw const FormatException('Invalid command receipt.');
      }
      final entity = (r['entity'] as Map).cast<String, Object?>();
      validate(entity);
      return entity;
    } on FormatException {
      throw const DomainError(
        code: 'UNCERTAIN_RESULT',
        message: 'Confirmation could not be verified. Retry the saved request.',
      );
    }
  }

  @override
  Future<Map<String, Object?>> reports(
    TenantContext scope, {
    String? after,
  }) async {
    final r = await call('control_reconciliation_reports', scope, {
      'p_resource': 'reports',
      'p_after': after,
    });
    rows(r);
    for (final x in r['items'] as List) {
      summary(x as Map, scope);
    }
    return r;
  }

  @override
  Future<Map<String, Object?>> generate(
    CommandEnvelope<Map<String, Object?>> c,
  ) => command('generate_control_reconciliation_report', c, (r) {
    summary(r, c.context);
    for (final k in ['id', 'kind', 'as_of']) {
      if (r[k] != c.payload[k]) {
        throw const FormatException('Report request mismatch.');
      }
    }
  });
  @override
  Future<Map<String, Object?>> reverse(
    String kind,
    CommandEnvelope<Map<String, Object?>> c,
  ) {
    if (!['AR', 'AP'].contains(kind)) {
      throw const FormatException('Invalid ledger kind.');
    }
    return command(
      kind == 'AR'
          ? 'reverse_customer_allocation'
          : 'reverse_supplier_allocation',
      c,
      (r) {
        if (r['id'] is! String ||
            r['allocation_id'] != c.payload['allocation_id'] ||
            r['posting_date'] != c.payload['posting_date'] ||
            r['reason'] != c.payload['reason']) {
          throw const FormatException('Reversal request mismatch.');
        }
        for (final k in ['source_residual', 'target_residual']) {
          if (r[k] is! Map) {
            throw const FormatException('Missing exact residual.');
          }
          decimal((r[k] as Map)['amount']);
          decimal((r[k] as Map)['base_amount']);
        }
      },
    );
  }

  @override
  Future<Map<String, Object?>> page(
    TenantContext scope,
    String id,
    String section, {
    String? after,
    String? accountId,
  }) async {
    final cursor = after == null ? 0 : int.tryParse(after);
    if (cursor == null ||
        cursor < 0 ||
        cursor > 50000 ||
        ![
          'items',
          'allocations',
          'entries',
          'journals',
          'accounts',
          'differences',
        ].contains(section)) {
      throw const FormatException('Invalid evidence page request.');
    }
    final r = await call('control_reconciliation_report_page', scope, {
      'p_id': id,
      'p_section': section,
      'p_after': cursor,
      'p_evidence_key': accountId,
    });
    rows(r);
    if (r['summary'] is! Map ||
        r['section'] != section ||
        r['evidence_key'] != accountId ||
        (r['summary'] as Map)['id'] != id) {
      throw const FormatException('Evidence identity mismatch.');
    }
    summary(r['summary'] as Map, scope);
    for (final x in r['items'] as List) {
      if (section == 'accounts' || section == 'differences') {
        totals(x as Map);
      } else if (section == 'items') {
        for (final k in [
          'original_amount',
          'original_base_amount',
          'open_amount',
          'open_base_amount',
          'settled_amount',
          'settled_base_amount',
        ]) {
          decimal(x[k]);
        }
        if (decimal(x['original_amount']) - decimal(x['settled_amount']) !=
                decimal(x['open_amount']) ||
            decimal(x['original_base_amount']) -
                    decimal(x['settled_base_amount']) !=
                decimal(x['open_base_amount'])) {
          throw const FormatException('Item residual mismatch.');
        }
      } else if (section == 'allocations') {
        for (final k in [
          'source_amount',
          'transaction_amount',
          'source_base_amount',
          'target_base_amount',
          'write_off',
          'discount_amount',
          'adjustment_base_amount',
          'exchange_difference',
        ]) {
          decimal(x[k]);
        }
      } else {
        decimal(x['value']);
      }
    }
    return r;
  }
}
