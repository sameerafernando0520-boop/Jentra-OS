import 'package:jentra_domain/jentra_procurement.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ProcurementGateway {
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<List<Map<String, Object?>>> units(TenantContext scope);
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  });
  Future<Map<String, Object?>> transition(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> source(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class PurchaseOrderGateway {
  Future<CursorPage<Map<String, Object?>>> orders(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> saveOrder(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> transitionOrder(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class ProductUnitGateway {
  Future<Map<String, Object?>> saveProductUnit(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class GoodsReceiptGateway {
  Future<CursorPage<Map<String, Object?>>> receipts(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> postReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> reverseReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> saveReceiptControls(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class ReceiptAllowanceGateway {
  Future<Map<String, Object?>> approveReceiptAllowance(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class SupplierBillGateway {
  Future<CursorPage<Map<String, Object?>>> bills(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> saveBill(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> billAction(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> saveBillControls(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseProcurementGateway
    implements
        ProcurementGateway,
        PurchaseOrderGateway,
        ProductUnitGateway,
        GoodsReceiptGateway,
        ReceiptAllowanceGateway,
        SupplierBillGateway {
  SupabaseProcurementGateway(this.client);
  final SupabaseClient client;
  @override
  Future<CursorPage<Map<String, Object?>>> bills(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'supplier_bills', after: after);
  @override
  Future<Map<String, Object?>> saveBill(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_supplier_bill', command);
  @override
  Future<Map<String, Object?>> saveBillControls(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_supplier_bill_controls', command);
  @override
  Future<Map<String, Object?>> billAction(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command(switch (action) {
    'post' => 'post_supplier_bill',
    'approve' => 'approve_supplier_bill_match',
    'cancel' => 'cancel_supplier_bill',
    _ => throw const DomainError(
      code: 'VALIDATION_ERROR',
      message: 'Unknown supplier bill action.',
    ),
  }, command);
  @override
  Future<Map<String, Object?>> approveReceiptAllowance(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('approve_receipt_allowance', command);
  @override
  Future<CursorPage<Map<String, Object?>>> receipts(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'goods_receipts', after: after);
  @override
  Future<Map<String, Object?>> postReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('post_goods_receipt', command);
  @override
  Future<Map<String, Object?>> reverseReceipt(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('reverse_goods_receipt', command);
  @override
  Future<Map<String, Object?>> saveReceiptControls(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_receipt_controls', command);
  @override
  Future<Map<String, Object?>> saveProductUnit(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_product_unit_conversion', command);
  @override
  Future<CursorPage<Map<String, Object?>>> orders(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'purchase_orders', after: after);
  @override
  Future<Map<String, Object?>> saveOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_purchase_order', command);
  @override
  Future<Map<String, Object?>> transitionOrder(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('transition_purchase_order', command);

  void _scope(TenantContext scope) {
    if (!scope.hasOperationalScope ||
        client.auth.currentUser?.id != scope.actorId) {
      throw const DomainError(
        code: 'PERMISSION_DENIED',
        message: 'Choose an authenticated business scope.',
      );
    }
  }

  @override
  Future<CursorPage<Map<String, Object?>>> page(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'purchase_requisitions', after: after);
  @override
  Future<CursorPage<Map<String, Object?>>> rfqs(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'request_for_quotes', after: after);
  Future<CursorPage<Map<String, Object?>>> _page(
    TenantContext scope,
    String view, {
    String? after,
  }) async {
    _scope(scope);
    var query = client
        .schema('api')
        .from(view)
        .select('detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!);
    if (after != null) query = query.gt('id', after);
    final rows = await query.order('id').limit(51);
    final items = rows
        .take(50)
        .map((r) => (r['detail'] as Map).cast<String, Object?>())
        .toList();
    return CursorPage(
      items: items,
      limit: 50,
      nextCursor: rows.length > 50 ? items.last['id'] as String : null,
    );
  }

  @override
  Future<List<Map<String, Object?>>> units(TenantContext scope) async {
    final result = await references(scope, 'units');
    return (result['items'] as List)
        .map((r) => (r as Map).cast<String, Object?>())
        .toList();
  }

  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          resource.startsWith('bill_')
              ? 'supplier_bill_reference_options'
              : resource.startsWith('receipt_')
              ? 'goods_receipt_reference_options'
              : 'procurement_reference_options',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_resource': resource,
            'p_after': after,
            'p_search': search,
          },
        );
    return (result as Map).cast<String, Object?>();
  }

  @override
  Future<Map<String, Object?>> save(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_purchase_requisition', command);

  @override
  Future<Map<String, Object?>> transition(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('transition_purchase_requisition', command);
  @override
  Future<Map<String, Object?>> source(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_request_for_quote', command);

  Future<Map<String, Object?>> _command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> command,
  ) async {
    _scope(command.context);
    try {
      final raw = await client
          .schema('api')
          .rpc(
            rpc,
            params: {
              'p_tenant_id': command.context.tenantId,
              'p_legal_entity_id': command.context.legalEntityId,
              'p_branch_id': command.context.branchId,
              'p_command_id': command.commandId,
              'p_idempotency_key': command.idempotencyKey,
              'p_client_timestamp': command.clientTimestamp.toIso8601String(),
              'p_expected_entity_version': command.expectedEntityVersion,
              'p_payload': command.payload,
            },
          );
      if (raw is! Map ||
          raw['command_id'] != command.commandId ||
          raw['request_id'] is! String ||
          raw['entity'] is! Map ||
          (raw['entity'] as Map)['id'] !=
              (command.payload['id'] ?? command.payload['document_id'])) {
        throw const DomainError(
          code: 'UNCERTAIN_RESULT',
          message:
              'The response could not be verified. Retry the saved command.',
        );
      }
      return (raw['entity'] as Map).cast<String, Object?>();
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
        message: switch (code) {
          'VERSION_CONFLICT' =>
            'The server document changed. Reload it before editing.',
          'PERMISSION_DENIED' =>
            'Your current access does not permit this command.',
          'VALIDATION_ERROR' =>
            'Check the date, active units, exact amounts and document state.',
          _ => 'Connection interrupted. Retry the saved command.',
        },
      );
    }
  }
}
