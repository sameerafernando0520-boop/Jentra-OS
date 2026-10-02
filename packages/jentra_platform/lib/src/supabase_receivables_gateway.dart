import 'package:jentra_domain/jentra_receivables.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseReceivablesGateway implements ReceivablesRepository {
  SupabaseReceivablesGateway(this.client);
  final SupabaseClient client;
  void _scope(TenantContext scope) {
    if (!scope.hasOperationalScope) {
      throw const ReceivableFailure(
        'BRANCH_REQUIRED',
        'Choose a legal entity and branch.',
        definite: true,
      );
    }
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ReceivableFailure {
      rethrow;
    } on PostgrestException catch (error) {
      final known = const {
        'PERMISSION_DENIED',
        'ACCESS_DENIED',
        'MFA_REQUIRED',
        'AUTHENTICATION_REQUIRED',
      };
      final code = known.contains(error.message)
          ? error.message
          : error.code == '42501'
          ? 'PERMISSION_DENIED'
          : const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)
          ? 'AUTHENTICATION_REQUIRED'
          : 'READ_REJECTED';
      throw ReceivableFailure(
        code,
        code == 'MFA_REQUIRED'
            ? 'Verify your identity before reading this evidence.'
            : code == 'AUTHENTICATION_REQUIRED'
            ? 'Sign in again before reading this evidence.'
            : known.contains(code)
            ? 'Evidence is unavailable with your current access. Recheck your role and scope.'
            : 'The evidence read was rejected. Check the selected scope and filters.',
        definite: true,
      );
    } on FormatException {
      throw const ReceivableFailure(
        'READ_INVALID',
        'The response could not be verified. Refresh its evidence.',
      );
    } catch (_) {
      throw const ReceivableFailure(
        'READ_UNAVAILABLE',
        'Evidence could not be verified. Retry when connected.',
      );
    }
  }

  @override
  Future<CursorPage<ReceivableDocument>> page(
    TenantContext scope,
    ReceivableKind kind, {
    String? cursor,
    String? status,
  }) => _read(() async {
    _scope(scope);
    var query = client
        .schema('api')
        .from(kind.view)
        .select('detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!);
    if (cursor != null) query = query.gt('id', cursor);
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('id').limit(51);
    final docs = rows
        .take(50)
        .map((r) => ReceivableDocument(receivableMap(r['detail'])))
        .toList();
    return CursorPage(
      items: docs,
      limit: 50,
      nextCursor: rows.length > 50 ? docs.last.id : null,
    );
  });

  @override
  Future<ReceivableDocument> find(
    TenantContext scope,
    ReceivableKind kind,
    String id,
  ) => _read(() async {
    _scope(scope);
    final rows = await client
        .schema('api')
        .from(kind.view)
        .select('detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!)
        .eq('id', id)
        .limit(2);
    if (rows.isEmpty) {
      throw const ReceivableFailure(
        'NOT_FOUND',
        'Document is unavailable in this scope.',
        definite: true,
      );
    }
    if (rows.length != 1) {
      throw const FormatException('Document identity is not unique.');
    }
    return ReceivableDocument(receivableMap(rows.single['detail']));
  });

  @override
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> envelope,
  ) async {
    _scope(envelope.context);
    if (!{
      for (final kind in ReceivableKind.values) ...[
        'upsert_${kind.wire}',
        'post_${kind.wire}',
      ],
      'transition_operational_document',
      'decide_operational_approval',
      'allocate_customer_receipt',
      'upsert_receivables_setup',
    }.contains(rpc)) {
      throw const ReceivableFailure(
        'COMMAND_INVALID',
        'Unsupported receivables command.',
        definite: true,
      );
    }
    try {
      final raw = receivableMap(
        await client
            .schema('api')
            .rpc(
              rpc,
              params: {
                'p_tenant_id': envelope.context.tenantId,
                'p_legal_entity_id': envelope.context.legalEntityId,
                'p_branch_id': envelope.context.branchId,
                'p_command_id': envelope.commandId,
                'p_idempotency_key': envelope.idempotencyKey,
                'p_client_timestamp': envelope.clientTimestamp
                    .toIso8601String(),
                'p_expected_entity_version': envelope.expectedEntityVersion,
                'p_payload': envelope.payload,
              },
            ),
      );
      if (raw['request_id'] is! String ||
          raw['command_id'] != envelope.commandId ||
          raw['entity'] is! Map) {
        throw const ReceivableFailure(
          'UNCERTAIN_RESULT',
          'Response could not be verified. Retry the saved command.',
        );
      }
      return raw;
    } on PostgrestException catch (error) {
      // PostgreSQL errors abort the RPC transaction. Gateway/server/transport errors
      // do not establish whether a mutation committed, so retain their envelope.
      final definite = RegExp(
        r'^(22|23|40|42|55|P0)',
      ).hasMatch(error.code ?? '');
      final code = error.code == '40001'
          ? 'VERSION_CONFLICT'
          : error.code == '42501'
          ? 'PERMISSION_DENIED'
          : RegExp(r'^[A-Z_]+$').hasMatch(error.message)
          ? error.message
          : 'COMMAND_REJECTED';
      throw ReceivableFailure(
        code,
        definite
            ? error.message
            : 'Connection interrupted. Retry the saved command.',
        definite: definite,
      );
    }
  }

  @override
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? customerId,
    String? sourceId,
  }) => _read(() async {
    _scope(scope);
    if (!{
      'parties',
      'currencies',
      'exchange_rates',
      'products',
      'units',
      'tax_definitions',
      'sales_order_details',
      'deliveries',
      'sales_invoices',
      'receivable_balances',
      'cash_bank_accounts',
      'lots',
      'serials',
      'open_item_allocations',
      'journal_entries',
      'accounts',
      'posting_mappings',
    }.contains(resource)) {
      throw const ReceivableFailure(
        'REFERENCE_INVALID',
        'Unknown reference.',
        definite: true,
      );
    }
    var q = client.schema('api').from(resource).select();
    if (resource != 'currencies') q = q.eq('tenant_id', scope.tenantId);
    if (!{'parties', 'currencies', 'units'}.contains(resource)) {
      q = q.eq('legal_entity_id', scope.legalEntityId!);
    }
    if ({
      'sales_order_details',
      'deliveries',
      'sales_invoices',
      'receivable_balances',
      'cash_bank_accounts',
      'serials',
      'open_item_allocations',
      'journal_entries',
    }.contains(resource)) {
      q = q.eq('branch_id', scope.branchId!);
    }
    if ({
      'parties',
      'currencies',
      'exchange_rates',
      'products',
      'units',
      'tax_definitions',
    }.contains(resource)) {
      q = q.eq('status', 'active');
    }
    if (resource == 'products') {
      q = q.eq('can_sell', true).inFilter('kind', ['service', 'non_stocked']);
    }
    if (resource == 'parties') q = q.inFilter('kind', ['customer', 'both']);
    if (customerId != null &&
        {
          'sales_order_details',
          'deliveries',
          'sales_invoices',
        }.contains(resource)) {
      q = q.eq('customer_id', customerId);
    }
    if (customerId != null && resource == 'receivable_balances') {
      q = q.eq('party_id', customerId);
    }
    if ({'deliveries', 'sales_invoices'}.contains(resource)) {
      q = q.eq('status', 'posted');
    }
    if (resource == 'sales_order_details') {
      q = q.inFilter('status', [
        'confirmed',
        'partially_reserved',
        'reserved',
        'fulfilled',
      ]);
    }
    if (resource == 'cash_bank_accounts') q = q.eq('detail->>status', 'active');
    if (sourceId != null && resource == 'open_item_allocations') {
      q = q.or(
        'detail->>source_open_item_id.eq.$sourceId,detail->>target_open_item_id.eq.$sourceId',
      );
    }
    if (sourceId != null && resource == 'journal_entries') {
      q = q.eq('detail->>source_id', sourceId);
    }
    if (cursor != null) q = q.gt('id', cursor);
    final rows = await q.order('id').limit(51);
    final items = rows
        .take(50)
        .map((r) => receivableMap(r['detail'] ?? r))
        .toList();
    return CursorPage(
      items: items,
      limit: 50,
      nextCursor: rows.length > 50 ? items.last['id'] as String : null,
    );
  });

  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope,
    String customer,
    String currency,
    String asOf,
    List<int> buckets,
  ) => _read(() async {
    _scope(scope);
    return receivableMap(
      await client
          .schema('api')
          .rpc(
            'customer_statement',
            params: {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              'p_customer_id': customer,
              'p_currency_code': currency,
              'p_as_of': asOf,
              'p_buckets': buckets,
            },
          ),
    );
  });
}
