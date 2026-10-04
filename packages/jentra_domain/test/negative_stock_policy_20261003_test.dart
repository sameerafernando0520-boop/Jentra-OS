import 'package:jentra_domain/jentra_domain.dart';
import 'package:test/test.dart';

Map<String, Object?> policyJson({String version = '1', bool active = true}) => {
  'tenant_id': 'tenant',
  'legal_entity_id': 'entity',
  'id': version == '0' ? null : 'policy',
  'policy_version': version,
  'active': active,
  'basis': 'last_authoritative_positive_average',
  'cover_order': 'issue_ledger_fifo',
  'tracking_scope': 'untracked',
  'reason': version == '0' ? null : 'approved',
  'created_by': version == '0' ? null : 'actor',
  'created_at': version == '0' ? null : '2026-10-03T00:00:00Z',
};
Map<String, Object?> evidenceJson({String id = '1', bool cover = false}) => {
  'id': id,
  'quantity': '3.000000',
  'provisional_value': '0.000000',
  'posting_date': '2026-10-03',
  'command_id': 'command',
  'created_at': '2026-10-03T00:00:00Z',
  'created_by': 'actor',
  if (cover) ...{
    'deficit_id': '1',
    'movement_line_id': 'receipt',
    'kind': 'receipt',
    'request_id': 'request',
    'actual_value': '6.000001',
    'variance': '6.000001',
    'journal_entry_id': 'journal',
  } else ...{
    'open_quantity': '3.000000',
    'issue_movement_line_id': 'issue',
    'policy_id': 'policy',
    'policy_version': '9007199254740993',
    'basis_id': '1',
    'warehouse_id': 'warehouse',
    'product_id': 'product',
  },
};
void main() {
  test('absent policy is explicitly inactive and exact version zero', () {
    final p = NegativeStockPolicy.fromJson(
      policyJson(version: '0', active: false),
    );
    expect(p.version, BigInt.zero);
    expect(p.active, isFalse);
    expect(p.id, isNull);
    expect(p.tenantId, 'tenant');
    expect(p.legalEntityId, 'entity');
  });
  test(
    'policy version exceeds JavaScript exact integer range without rounding',
    () {
      expect(
        NegativeStockPolicy.fromJson(
          policyJson(version: '9007199254740993'),
        ).version,
        BigInt.parse('9007199254740993'),
      );
    },
  );
  for (final (key, value) in [
    ('tenant_id', null),
    ('legal_entity_id', null),
    ('tenant_id', ''),
    ('legal_entity_id', 3),
    ('policy_version', 1),
    ('policy_version', '-1'),
    ('policy_version', '01'),
    ('basis', 'receipt_cost'),
    ('cover_order', 'latest'),
    ('tracking_scope', 'serial'),
    ('active', 'true'),
    ('id', null),
    ('reason', null),
    ('created_by', null),
    ('created_at', null),
    ('created_at', 'invalid'),
  ]) {
    test('policy rejects malformed $key $value', () {
      expect(
        () => NegativeStockPolicy.fromJson(policyJson()..[key] = value),
        throwsFormatException,
      );
    });
  }
  test('zero policy cannot claim an active or attributed identity', () {
    expect(
      () => NegativeStockPolicy.fromJson(policyJson(version: '0')),
      throwsFormatException,
    );
    expect(
      () => NegativeStockPolicy.fromJson(
        policyJson(version: '0', active: false)..['id'] = 'invented',
      ),
      throwsFormatException,
    );
  });
  test(
    'override reason and positive version are required, exact wire is immutable',
    () {
      final o = NegativeStockOverride(
        policyVersion: BigInt.parse('9007199254740993'),
        reason: '  approved shortage  ',
      );
      expect(o.validate().isValid, isTrue);
      expect(o.toJson(), {
        'policy_version': '9007199254740993',
        'reason': 'approved shortage',
      });
      expect(
        NegativeStockOverride(
          policyVersion: BigInt.zero,
          reason: '',
        ).validate().issues,
        hasLength(2),
      );
      expect(
        NegativeStockOverride(
          policyVersion: BigInt.one,
          reason: 'x' * 1001,
        ).validate().isValid,
        isFalse,
      );
    },
  );
  test(
    'reservation normal wire is unchanged and opt-in override is additive',
    () {
      StockReservationDraft draft([NegativeStockOverride? override]) =>
          StockReservationDraft(
            salesOrderId: 'order',
            expiresAt: DateTime.utc(2099),
            lines: [
              StockReservationLineDraft(
                salesOrderLineId: 'line',
                requestedBaseQuantity: ExactDecimal.parse(
                  '90071992547409.123456',
                  scale: 6,
                ),
              ),
            ],
            negativeStockOverride: override,
          );
      final normal = draft().toJson();
      expect(normal.keys, ['sales_order_id', 'expires_at', 'lines']);
      final changed = draft(
        NegativeStockOverride(policyVersion: BigInt.one, reason: 'approve'),
      ).toJson();
      expect(changed..remove('negative_stock_override'), normal);
      expect(
        draft(
          NegativeStockOverride(policyVersion: BigInt.zero, reason: ''),
        ).validate().isValid,
        isFalse,
      );
    },
  );
  test('known zero cost and exact large ledger id remain valid', () {
    final row = NegativeStockEvidence.fromJson(
      NegativeStockEvidenceKind.deficits,
      evidenceJson(id: '9007199254740993'),
    );
    expect(row.ledgerId, BigInt.parse('9007199254740993'));
    expect(() => row.values['quantity'] = '0', throwsUnsupportedError);
  });
  test('receipt and customer return corrections reconcile all minor units', () {
    for (final kind in ['receipt', 'customer_return']) {
      final row = NegativeStockEvidence.fromJson(
        NegativeStockEvidenceKind.covers,
        evidenceJson(cover: true)..['kind'] = kind,
      );
      expect(row.values['variance'], '6.000001');
    }
  });
  for (final (key, value) in [
    ('quantity', 3),
    ('quantity', '1.0000001'),
    ('quantity', '-1'),
    ('quantity', '0'),
    ('provisional_value', '-1'),
    ('open_quantity', '-1'),
    ('open_quantity', '4'),
    ('policy_version', '0'),
    ('warehouse_id', ''),
    ('command_id', null),
  ]) {
    test('deficit rejects invalid $key $value', () {
      expect(
        () => NegativeStockEvidence.fromJson(
          NegativeStockEvidenceKind.deficits,
          evidenceJson()..[key] = value,
        ),
        throwsFormatException,
      );
    });
  }
  for (final (key, value) in [
    ('kind', 'manual'),
    ('actual_value', '-1'),
    ('variance', '6'),
    ('movement_line_id', null),
  ]) {
    test('cover rejects invalid $key $value', () {
      expect(
        () => NegativeStockEvidence.fromJson(
          NegativeStockEvidenceKind.covers,
          evidenceJson(cover: true)..[key] = value,
        ),
        throwsFormatException,
      );
    });
  }
  test('bounded page advances exact ledger cursor and seals rows', () {
    final p = NegativeStockEvidencePage.fromJson(
      NegativeStockEvidenceKind.deficits,
      {
        'items': [evidenceJson(), evidenceJson(id: '9007199254740993')],
        'next_cursor': '9007199254740993',
      },
    );
    expect(p.nextCursor, BigInt.parse('9007199254740993'));
    expect(() => p.items.clear(), throwsUnsupportedError);
  });
  for (final raw in [
    {'items': null},
    {
      'items': [null],
    },
    {
      'items': [evidenceJson(), evidenceJson()],
    },
    {'items': [], 'next_cursor': '1'},
    {
      'items': [evidenceJson()],
      'next_cursor': '2',
    },
    {'items': List.generate(51, (i) => evidenceJson(id: '${i + 1}'))},
  ]) {
    test(
      'malformed or unbounded evidence page is rejected ${raw['items'] is List ? (raw['items'] as List).length : 'null'} $raw',
      () {
        expect(
          () => NegativeStockEvidencePage.fromJson(
            NegativeStockEvidenceKind.deficits,
            raw,
          ),
          throwsFormatException,
        );
      },
    );
  }
  test('empty final page has no artificial cursor', () {
    final p = NegativeStockEvidencePage.fromJson(
      NegativeStockEvidenceKind.covers,
      {'items': [], 'next_cursor': null},
    );
    expect(p.items, isEmpty);
    expect(p.nextCursor, isNull);
  });
}
