import 'package:jentra_domain/jentra_procurement.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bounded current material fields for an explicit local conflict comparison.
abstract interface class ProcurementConflictGateway {
  Future<Map<String, Object?>> conflictDocument(
    TenantContext scope,
    String kind,
    String id,
  );
}

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

abstract interface class SupplierPaymentGateway {
  Future<Map<String, Object?>> allocationRates(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  });
  Future<Map<String, Object?>> itemDetail(
    TenantContext scope,
    String itemId, {
    String? after,
  });
  Future<Map<String, Object?>> allocationTargets(
    TenantContext scope,
    String sourceId, {
    String? after,
  });
  Future<Map<String, Object?>> correctAllocation(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> statement(
    TenantContext scope, {
    required String supplierId,
    required String currency,
    required String asOf,
    required List<int> buckets,
  });
  Future<Map<String, Object?>> payableItems(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  });
  Future<CursorPage<Map<String, Object?>>> proposals(
    TenantContext scope, {
    String? after,
  });
  Future<CursorPage<Map<String, Object?>>> payments(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> saveProposal(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> transitionProposal(
    CommandEnvelope<Map<String, Object?>> command,
  );
  Future<Map<String, Object?>> postPayment(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

abstract interface class PurchaseReturnGateway {
  Future<CursorPage<Map<String, Object?>>> returns(
    TenantContext scope, {
    String? after,
  });
  Future<Map<String, Object?>> returnSources(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
  });
  Future<Map<String, Object?>> returnSource(
    TenantContext scope,
    String kind,
    String sourceId,
  );
  Future<Map<String, Object?>> postReturn(
    CommandEnvelope<Map<String, Object?>> command,
  );
}

final class SupabaseProcurementGateway
    implements
        ProcurementConflictGateway,
        ProcurementGateway,
        PurchaseOrderGateway,
        ProductUnitGateway,
        GoodsReceiptGateway,
        ReceiptAllowanceGateway,
        SupplierBillGateway,
        SupplierPaymentGateway,
        PurchaseReturnGateway {
  SupabaseProcurementGateway(this.client);
  final SupabaseClient client;

  @override
  Future<Map<String, Object?>> conflictDocument(
    TenantContext scope,
    String kind,
    String id,
  ) => _read(() async {
    _scope(scope);
    final view = switch (kind) {
      'purchase_requisition' => 'purchase_requisitions',
      'purchase_order' => 'purchase_orders',
      'supplier_bill' => 'supplier_bills',
      _ => throw const FormatException('Unsupported conflict document.'),
    };
    if (!RegExp(
      r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('Invalid conflict document identity.');
    }
    final rows = await client
        .schema('api')
        .from(view)
        .select('tenant_id,legal_entity_id,branch_id,id,detail')
        .eq('tenant_id', scope.tenantId)
        .eq('legal_entity_id', scope.legalEntityId!)
        .eq('branch_id', scope.branchId!)
        .eq('id', id)
        .limit(1);
    if (rows.isEmpty) {
      throw const DomainError(
        code: 'READ_REJECTED',
        message:
            'The current document is unavailable. Recheck its scope and access.',
      );
    }
    final row = rows.single;
    if (row['tenant_id'] != scope.tenantId ||
        row['legal_entity_id'] != scope.legalEntityId ||
        row['branch_id'] != scope.branchId ||
        row['id'] != id ||
        row['detail'] is! Map) {
      throw const FormatException('Conflict document scope mismatch.');
    }
    final detail = (row['detail'] as Map).cast<String, Object?>();
    if (detail['id'] != id ||
        detail['version'] is! int ||
        (detail['lines'] != null &&
            (detail['lines'] is! List ||
                (detail['lines'] as List).length > 500))) {
      throw const FormatException('Invalid current document.');
    }
    void exact(Object? value, [String? key]) {
      if (value is Map) {
        for (final entry in value.entries) {
          exact(entry.value, entry.key.toString());
        }
      } else if (value is List) {
        for (final item in value) {
          exact(item);
        }
      } else if (value != null &&
          key != null &&
          RegExp(
            r'(?:^|_)(?:amount|total|price|rate|quantity)$',
          ).hasMatch(key) &&
          (value is! String || !RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value))) {
        throw const FormatException(
          'Current financial fields require exact strings.',
        );
      }
    }

    exact(detail);
    return detail;
  });
  Future<T> _read<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DomainError {
      rethrow;
    } on PostgrestException catch (error) {
      const denied = {
        'PERMISSION_DENIED',
        'ACCESS_DENIED',
        'MFA_REQUIRED',
        'AUTHENTICATION_REQUIRED',
      };
      final code = denied.contains(error.message)
          ? error.message
          : error.code == '42501'
          ? 'PERMISSION_DENIED'
          : const {'PGRST301', 'PGRST302', 'PGRST303'}.contains(error.code)
          ? 'AUTHENTICATION_REQUIRED'
          : 'READ_REJECTED';
      throw DomainError(
        code: code,
        message: denied.contains(code)
            ? 'Evidence is unavailable with your current access. Recheck your role and scope.'
            : 'The evidence read was rejected. Check the selected scope and filters.',
      );
    } on FormatException {
      throw const DomainError(
        code: 'READ_INVALID',
        message: 'The response could not be verified. Refresh its evidence.',
      );
    } on TypeError {
      throw const DomainError(
        code: 'READ_INVALID',
        message: 'The response could not be verified. Refresh its evidence.',
      );
    } catch (_) {
      throw const DomainError(
        code: 'READ_UNAVAILABLE',
        message: 'Evidence could not be verified. Retry when connected.',
        retryable: true,
      );
    }
  }

  @override
  Future<CursorPage<Map<String, Object?>>> returns(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'purchase_returns', after: after);
  @override
  Future<Map<String, Object?>> postReturn(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('post_purchase_return', command);
  @override
  Future<Map<String, Object?>> returnSources(
    TenantContext scope,
    String kind, {
    String? after,
    String search = '',
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'purchase_return_sources',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_kind': kind,
            'p_after': after,
            'p_search': search,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> returnSource(
    TenantContext scope,
    String kind,
    String sourceId,
  ) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'purchase_return_source',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_kind': kind,
            'p_source_id': sourceId,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> allocationRates(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'payable_allocation_rates',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_source_currency': filter['_currency'],
            'p_target_currency': filter['_target_currency'],
            'p_date': filter['posting_date'],
            'p_after': after,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> itemDetail(
    TenantContext scope,
    String itemId, {
    String? after,
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'payable_item_detail',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_item_id': itemId,
            'p_after': after,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> allocationTargets(
    TenantContext scope,
    String sourceId, {
    String? after,
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'payable_allocation_targets',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_source_id': sourceId,
            'p_after': after,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> correctAllocation(
    String action,
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command(switch (action) {
    'allocate' => 'allocate_supplier_credit',
    'reverse' => 'reverse_supplier_allocation',
    _ => throw const DomainError(
      code: 'VALIDATION_ERROR',
      message: 'Unknown allocation correction.',
    ),
  }, command);
  @override
  Future<Map<String, Object?>> statement(
    TenantContext scope, {
    required String supplierId,
    required String currency,
    required String asOf,
    required List<int> buckets,
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'supplier_statement',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_supplier_id': supplierId,
            'p_currency_code': currency,
            'p_as_of': asOf,
            'p_buckets': buckets,
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<Map<String, Object?>> payableItems(
    TenantContext scope,
    Map<String, Object?> filter, {
    String? after,
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          'supplier_payment_reference_options',
          params: {
            'p_tenant_id': scope.tenantId,
            'p_legal_entity_id': scope.legalEntityId,
            'p_branch_id': scope.branchId,
            'p_resource': 'payment_items',
            'p_after': after,
            'p_supplier_id': filter['supplier_id'],
            'p_cash_bank_account_id': filter['cash_bank_account_id'],
            'p_date': filter['document_date'],
            'p_proposal_id': filter['id'],
          },
        );
    return (result as Map).cast<String, Object?>();
  });

  @override
  Future<CursorPage<Map<String, Object?>>> proposals(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'payment_proposals', after: after);
  @override
  Future<CursorPage<Map<String, Object?>>> payments(
    TenantContext scope, {
    String? after,
  }) => _page(scope, 'supplier_payments', after: after);
  @override
  Future<Map<String, Object?>> saveProposal(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('upsert_payment_proposal', command);
  @override
  Future<Map<String, Object?>> transitionProposal(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('transition_payment_proposal', command);
  @override
  Future<Map<String, Object?>> postPayment(
    CommandEnvelope<Map<String, Object?>> command,
  ) => _command('post_supplier_payment', command);
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
  }) => _read(() async {
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
  });

  @override
  Future<List<Map<String, Object?>>> units(TenantContext scope) =>
      _read(() async {
        final result = await references(scope, 'units');
        return (result['items'] as List)
            .map((r) => (r as Map).cast<String, Object?>())
            .toList();
      });

  @override
  Future<Map<String, Object?>> references(
    TenantContext scope,
    String resource, {
    String? after,
    String search = '',
  }) => _read(() async {
    _scope(scope);
    final result = await client
        .schema('api')
        .rpc(
          resource.startsWith('payment_')
              ? 'supplier_payment_reference_options'
              : resource.startsWith('bill_')
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
  });

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
