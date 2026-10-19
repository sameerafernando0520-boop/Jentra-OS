import 'dart:async';

import 'package:jentra_domain/jentra_stock_opening.dart';
import 'package:jentra_platform/jentra_platform.dart';

const openingScope = TenantContext(
  tenantId: 'tenant',
  actorId: 'actor',
  legalEntityId: 'entity',
  branchId: 'branch',
);
const openingPermissions = {
  'inventory.cost.view',
  'inventory.adjustments.post',
  'workflow.approvals.decide',
};

class OpeningMemoryKeys implements SecretKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

Map<String, Object?> openingSnapshot({String status = 'draft'}) => {
  'id': '00000000-0000-4000-8000-000000000001',
  'document_type': 'stock_opening',
  'tenant_id': 'tenant',
  'legal_entity_id': 'entity',
  'branch_id': 'branch',
  'warehouse_id': 'warehouse',
  'offset_account_id': 'equity',
  'document_number': 'OPEN-00001',
  'document_date': '2026-09-11',
  'currency_code': 'LKR',
  'grand_total': '248500.000000',
  'reason': 'Verified physical count at the Colombo warehouse.',
  'status': status,
  'version': 3,
  'created_by': 'preparer',
  'prepared_by': 'preparer',
  'submitted_by': 'preparer',
  'stock_movement_id': status == 'posted' ? 'movement-001' : null,
  'journal_entry_id': status == 'posted' ? 'journal-001' : null,
  'workflow_snapshot': {
    'lifecycle': {
      'transitions': [
        ['draft', 'submitted'],
        ['submitted', 'approved'],
        ['submitted', 'rejected'],
        ['draft', 'cancelled'],
        ['submitted', 'cancelled'],
      ],
      'posting_transitions': [
        ['submitted', 'draft'],
        ['approved', 'draft'],
        ['rejected', 'draft'],
      ],
    },
  },
  'lines': [
    {
      'line_id': 'line1',
      'product_id': 'product',
      'product_name': 'Office paper · A4 80 gsm',
      'sku': 'PAP-A4-80',
      'tracking_mode': 'none',
      'base_unit_id': 'unit',
      '_unit_label': 'Ream (rm)',
      'base_quantity': '250',
      'base_value': '187500',
      'serial_codes': <String>[],
    },
    {
      'line_id': 'line2',
      'product_id': 'toner',
      'product_name': 'Black toner cartridge',
      'sku': 'TON-BLK-410',
      'tracking_mode': 'lot',
      'base_unit_id': 'unit',
      '_unit_label': 'Each (ea)',
      'base_quantity': '10',
      'base_value': '61000',
      'lot_code': 'LOT-2026-09',
      'expiry_date': '2028-09-01',
      'serial_codes': <String>[],
    },
  ],
};

class FakeStockOpeningRepository implements StockOpeningRepository {
  StockOpeningDocument doc = StockOpeningDocument(openingSnapshot());
  Object? failure;
  Completer<void>? gate;
  final commands = <CommandEnvelope<Map<String, Object?>>>[];
  final rpcs = <String>[];
  @override
  Future<CursorPage<StockOpeningDocument>> page(
    TenantContext scope, {
    String? cursor,
    String? status,
  }) async => CursorPage(
    items: status == null || status == doc.status ? [doc] : [],
    limit: 50,
  );
  @override
  Future<StockOpeningDocument> find(TenantContext scope, String id) async =>
      doc;
  @override
  Future<Map<String, Object?>> command(
    String rpc,
    CommandEnvelope<Map<String, Object?>> e,
  ) async {
    commands.add(e);
    rpcs.add(rpc);
    await gate?.future;
    if (failure != null) throw failure!;
    final next = {...doc.data};
    if (rpc == 'upsert_stock_opening') {
      next.addAll({
        ...e.payload,
        'grand_total': StockOpeningDraft(e.payload).total.toDecimalString(),
      });
    }
    if (rpc == 'post_stock_opening') {
      next.addAll({
        'status': 'posted',
        'stock_movement_id': 'movement-001',
        'journal_entry_id': 'journal-001',
      });
    }
    if (rpc == 'transition_stock_opening') {
      next['status'] =
          e.payload['decision'] ??
          (e.payload['action'] == 'submit'
              ? 'pending_approval'
              : e.payload['action'] == 'recall'
              ? 'draft'
              : 'cancelled');
    }
    next['version'] = doc.version + 1;
    doc = StockOpeningDocument(next);
    return {
      'request_id': 'reference-001',
      'command_id': e.commandId,
      'entity': doc.data,
    };
  }

  @override
  Future<CursorPage<Map<String, Object?>>> references(
    TenantContext scope,
    String resource, {
    String? cursor,
    String? id,
  }) async => CursorPage(
    items: switch (resource) {
      'warehouses' => [
        {
          'id': 'warehouse',
          'code': 'CMB-01',
          'name': 'Colombo warehouse',
          'status': 'active',
        },
      ],
      'accounts' => [
        {
          'id': 'equity',
          'code': '3100',
          'name': 'Opening balances',
          'status': 'active',
        },
      ],
      'legal_entities' => [
        {'id': 'entity', 'currency_code': 'LKR'},
      ],
      'units' => [
        {'id': 'unit', 'name': 'Each', 'symbol': 'ea', 'precision': 0},
      ],
      'products' => [
        {
          'id': 'serial-product',
          'sku': 'PRN-LSR-01',
          'name': 'Laser printer',
          'tracking_mode': 'serial',
          'base_unit_id': 'unit',
        },
      ],
      _ => [],
    },
    limit: 50,
  );
}
