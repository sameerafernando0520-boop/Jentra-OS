import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';

FieldSalesJson _rep({
  String userId = 'rep-one',
  String label = 'Asha Perera',
  Object linked = true,
  String total = '100.350000',
}) => {
  'user_id': userId,
  'label': label,
  'linked': linked,
  'active_customer_count': '1',
  'submitted_count': '4',
  'pending_count': '1',
  'approved_count': '2',
  'rejected_count': '1',
  'approved_total': total,
};

void main() {
  const scope = FieldSalesScope('tenant', 'entity', 'branch');

  test(
    'rep list calls the named company read with company local dates',
    () async {
      final calls = <(String, FieldSalesJson)>[];
      final g = SupabaseFieldSalesGateway.withRpc((name, params) async {
        calls.add((name, params));
        return {
          'items': [
            _rep(),
            _rep(
              userId: 'rep-two',
              label: 'Unlinked member ····9f3a',
              linked: false,
              total: '0.000000',
            ),
          ],
          'currency_code': 'LKR',
          'from': '2026-11-01',
          'to': '2026-11-17',
          'as_of': '2026-11-17T10:00:00Z',
        };
      }, currentActor: () => 'manager');
      final list = await g.reps(
        scope,
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 17, 23, 59),
      );
      expect(calls.single.$1, 'field_sales_reps');
      expect(calls.single.$2, {
        'p_tenant_id': 'tenant',
        'p_legal_entity_id': 'entity',
        'p_branch_id': 'branch',
        'p_from': '2026-11-01',
        'p_to': '2026-11-17',
      });
      expect(list.currencyCode, 'LKR');
      expect(list.items.map((r) => r.label), [
        'Asha Perera',
        'Unlinked member ····9f3a',
      ]);
      expect(list.items.first.approvedTotal, '100.350000');
      expect(list.items.first.submittedCount, '4');
      expect(list.items.last.linked, isFalse);
      expect(list.labelFor('rep-two'), 'Unlinked member ····9f3a');
      expect(list.labelFor('someone-else'), 'not listed');
      expect(list.labelFor(null), 'not listed');
    },
  );

  test('a label that could be an e-mail address is a contract fault', () {
    expect(
      () => FieldSalesRep.fromJson(_rep(label: 'rep@company.invalid')),
      throwsA(
        isA<FieldSalesFailure>().having(
          (e) => e.code,
          'code',
          'CONTRACT_INVALID',
        ),
      ),
    );
  });

  test('inexact totals, numeric counts and missing link flags are refused', () {
    for (final row in [
      _rep(total: '100.35'),
      {..._rep(), 'approved_total': 100.35},
      {..._rep(), 'submitted_count': 4},
      _rep(linked: 'yes'),
      {..._rep(), 'label': '  '},
    ]) {
      expect(
        () => FieldSalesRep.fromJson(row),
        throwsA(isA<FieldSalesFailure>()),
        reason: '$row',
      );
    }
    expect(
      () => FieldSalesRepList.fromJson({
        'items': [],
        'from': '2026-11-01',
        'to': '2026-11-17',
      }),
      throwsA(isA<FieldSalesFailure>()),
    );
  });

  test('company local dates are zero padded', () {
    expect(fieldSalesDate(DateTime(987, 3, 4)), '0987-03-04');
  });
}
