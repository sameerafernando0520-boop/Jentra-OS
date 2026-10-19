const landedId = '20000000-0000-0000-0000-000000000001';
const landedReceipt = '20000000-0000-0000-0000-000000000002';
const landedProduct = '20000000-0000-0000-0000-000000000003';
const landedAccount = '20000000-0000-0000-0000-000000000004';
const landedWarehouse = '20000000-0000-0000-0000-000000000005';
const landedValuation = '20000000-0000-0000-0000-000000000006';
const landedHash = '0123456789abcdef0123456789abcdef';
Map<String, Object?> landedInput() => {
  'id': landedId,
  'document_date': '2026-09-29',
  'reason': 'Recorded freight allocation',
  'reference': 'FREIGHT-01',
  'total_amount': '9007199254740.123456',
  'basis_mode': 'manual',
  'offset_account_id': landedAccount,
  'variance_account_id': landedAccount,
  'receipts': [
    <String, Object?>{'receipt_line_id': landedReceipt, 'weight': '1.000001'},
  ],
};
Map<String, Object?> landedEvidence() {
  final receipt = <String, Object?>{
    'receipt_line_id': landedReceipt,
    'product_id': landedProduct,
    'inventory_account_id': landedAccount,
    'weight': '1.000001',
    'received_quantity': '3',
    'held_quantity': '2',
    'transit_quantity': '0',
    'consumed_quantity': '1',
    'target_allocation': '9007199254740.123456',
    'previous_allocation': '0',
    'incremental_amount': '9007199254740.123456',
  };
  return {
    'tenant_id': '10000000-0000-0000-0000-000000000001',
    'legal_entity_id': '10000000-0000-0000-0000-000000000002',
    'branch_id': '10000000-0000-0000-0000-000000000003',
    'root_id': landedId,
    'correction_of': null,
    'document_date': '2026-09-29',
    'currency_code': 'LKR',
    'basis_mode': 'manual',
    'offset_account_id': landedAccount,
    'variance_account_id': landedAccount,
    'basis_hash': landedHash,
    'total_amount': '9007199254740.123456',
    'amount': '9007199254740.123456',
    'inventory_amount': '6004799503160.082304',
    'transit_amount': '0',
    'variance_amount': '3002399751580.041152',
    'receipts': [receipt],
    'legs': [
      <String, Object?>{
        ...receipt,
        'kind': 'held',
        'branch_id': '10000000-0000-0000-0000-000000000003',
        'warehouse_id': landedWarehouse,
        'valuation_id': landedValuation,
        'quantity': '2',
        'value': '6004799503160.082304',
      },
      <String, Object?>{
        ...receipt,
        'kind': 'consumed',
        'branch_id': '10000000-0000-0000-0000-000000000003',
        'quantity': '1',
        'value': '3002399751580.041152',
      },
    ],
  };
}
