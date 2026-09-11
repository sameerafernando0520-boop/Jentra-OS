import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class SupabaseStockOpeningGateway implements StockOpeningRepository {
  SupabaseStockOpeningGateway(this.client);
  final SupabaseClient client;
  void _scope(TenantContext scope) {
    if (!scope.hasOperationalScope) {
      throw const StockOpeningFailure(
        'BRANCH_REQUIRED',
        'Choose a legal entity and branch.',
        definite: true,
      );
    }
  }

  @override
  Future<CursorPage<StockOpeningDocument>> page(
    TenantContext scope, {
    String? cursor,
    String? status,
  }) async {
    _scope(scope);
    var query = client
        .schema('api')
        .from('stock_openings')
        .select('detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!);
    if (cursor != null) query = query.gt('id', cursor);
    if (status != null) query = query.eq('status', status);
    final rows = await query.order('id').limit(51);
    final docs = rows
        .take(50)
        .map((r) => StockOpeningDocument(openingMap(r['detail'])))
        .toList();
    return CursorPage(
      items: docs,
      limit: 50,
      nextCursor: rows.length > 50 ? docs.last.id : null,
    );
  }

  @override
  Future<StockOpeningDocument> find(TenantContext scope, String id) async {
    _scope(scope);
    final row = await client
        .schema('api')
        .from('stock_openings')
        .select('detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!)
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const StockOpeningFailure(
        'NOT_FOUND',
        'Document is unavailable in this scope.',
        definite: true,
      );
    }
    return StockOpeningDocument(openingMap(row['detail']));
  }

  @override
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> envelope,
  ) async {
    _scope(envelope.context);
    if (!{
      'upsert_stock_opening',
      'transition_stock_opening',
      'post_stock_opening',
    }.contains(rpc)) {
      throw const StockOpeningFailure(
        'COMMAND_INVALID',
        'Unsupported opening command.',
        definite: true,
      );
    }
    try {
      final raw = openingMap(
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
        throw const StockOpeningFailure(
          'UNCERTAIN_RESULT',
          'Response could not be verified. Retry the saved command.',
        );
      }
      final doc = StockOpeningDocument(openingMap(raw['entity']));
      final expectedId =
          envelope.payload['id'] ?? envelope.payload['document_id'];
      if (doc.id != expectedId ||
          doc.data['tenant_id'] != envelope.context.tenantId ||
          doc.data['legal_entity_id'] != envelope.context.legalEntityId ||
          doc.data['branch_id'] != envelope.context.branchId) {
        throw const StockOpeningFailure(
          'UNCERTAIN_RESULT',
          'Response identity did not match. Retry the saved command.',
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
      throw StockOpeningFailure(
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
    String? id,
  }) async {
    _scope(scope);
    if (!{
      'warehouses',
      'products',
      'accounts',
      'units',
      'legal_entities',
    }.contains(resource)) {
      throw const StockOpeningFailure(
        'REFERENCE_INVALID',
        'Unknown reference.',
        definite: true,
      );
    }
    var q = client
        .schema('api')
        .from(resource)
        .select()
        .eq('tenant_id', scope.tenantId)
        .eq('status', 'active');
    if (resource == 'legal_entities') {
      q = q.eq('id', scope.legalEntityId!);
    } else if (resource != 'units') {
      q = q.eq('legal_entity_id', scope.legalEntityId!);
    }
    if (resource == 'warehouses') q = q.eq('branch_id', scope.branchId!);
    if (resource == 'products') q = q.eq('kind', 'stocked');
    if (resource == 'accounts') {
      q = q.eq('account_type', 'equity').eq('is_posting', true);
    }
    if (id != null) q = q.eq('id', id);
    if (cursor != null) q = q.gt('id', cursor);
    final rows = await q.order('id').limit(51);
    return CursorPage(
      items: rows.take(50).map(openingMap).toList(),
      limit: 50,
      nextCursor: rows.length > 50 ? rows[49]['id'] as String : null,
    );
  }
}
