import 'package:jentra_domain/jentra_assets.dart';
import 'package:test/test.dart';

const assetId = '20000000-0000-0000-0000-000000000001';
const bookId = '30000000-0000-0000-0000-000000000001';
Map<String, Object?> assetWire() => {
  'id': assetId,
  'tenant_id': assetId,
  'legal_entity_id': bookId,
  'branch_id': assetId,
  'original_branch_id': assetId,
  'code': 'SYN-1',
  'name': 'Synthetic equipment',
  'ownership': 'Synthetic owned',
  'currency_code': 'LKR',
  'in_service': '2026-01-01',
  'location_id': bookId,
  'custodian_id': null,
  'status': 'active',
  'version': 3,
  'cost': '1000.000000',
  'accumulated': '200.000000',
  'impairment': '300.000000',
  'carrying': '500.000000',
  'cost_account_id': assetId,
  'accumulated_account_id': bookId,
  'impairment_account_id': '40000000-0000-0000-0000-000000000001',
  'book_id': bookId,
  'posted_periods': 1,
  'proposal_id': null,
  'last_effect_id': assetId,
};
Map<String, Object?> bookWire() => {
  'residual': '100.000000',
  'remaining_months': 2,
  'method': 'straight_line',
  'convention': 'in_service_month',
  'rate_numerator': 1,
  'rate_denominator': 1,
  'precision': 2,
  'expense_account_id': assetId,
  'cost': '1000.000000',
  'opening_accumulated': '200.000000',
  'opening_impairment': '300.000000',
  'start_date': '2026-02-01',
  'in_service': '2026-01-01',
  'currency_code': 'LKR',
};
void main() {
  test('asset register proves cost/depreciation/impairment conservation', () {
    final row = AssetRecord.fromJson(assetWire());
    expect(row.carrying.toDecimalString(), '500.000000');
    expect(
      () => AssetRecord.fromJson(assetWire()..['carrying'] = '600'),
      throwsFormatException,
    );
    expect(
      () => AssetRecord.fromJson(assetWire()..['private_profile'] = {}),
      throwsFormatException,
    );
    final copy = row.toJson()..['name'] = 'Changed';
    expect(row.name, 'Synthetic equipment');
    expect(copy['name'], 'Changed');
  });
  test(
    'frozen book rejects unsupported methods and preserves separate reserves',
    () {
      final row = AssetBookDefinition.fromJson(bookWire());
      expect(row.schedule.totalDepreciation.toDecimalString(), '400.000000');
      expect(
        row.schedule.periods.last.accumulatedClosing.toDecimalString(),
        '600.000000',
      );
      expect(
        () => AssetBookDefinition.fromJson(
          bookWire()..['method'] = 'actual_days',
        ),
        throwsFormatException,
      );
      expect(
        () => AssetBookDefinition.fromJson(
          bookWire()..['remaining_months'] = '2',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'commands reject ignored kind fields, unsupported providers and unsafe numbers',
    () {
      final p = <String, Object?>{
        'action': 'propose',
        'id': assetId,
        'proposal_id': bookId,
        'kind': 'impair',
        'amount': '100',
        'loss_account_id': bookId,
        'posting_date': '2026-09-30',
        'reason': 'Synthetic impairment',
      };
      AssetCommands.validate('propose', p);
      expect(
        () => AssetCommands.validate('propose', {...p, 'proceeds': '100'}),
        throwsFormatException,
      );
      expect(
        () => AssetCommands.validate('propose', {...p, 'amount': 100.0}),
        throwsFormatException,
      );
      expect(
        () => AssetCommands.validate('procurement', {
          ...p,
          'action': 'procurement',
        }),
        throwsFormatException,
      );
      expect(
        () => AssetCommands.validate('depreciate', {
          'action': 'depreciate',
          'id': assetId,
          'book_id': bookId,
          'period_index': 1201,
          'reason': 'Synthetic period',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'explicit state transitions reject impossible active and draft books',
    () {
      expect(
        () => AssetRecord.fromJson(assetWire()..['book_id'] = null),
        throwsFormatException,
      );
      expect(
        () => AssetRecord.fromJson(assetWire()..['status'] = 'draft'),
        throwsFormatException,
      );
      expect(
        () => AssetRecord.fromJson(assetWire()..['posted_periods'] = 1201),
        throwsFormatException,
      );
    },
  );
}
