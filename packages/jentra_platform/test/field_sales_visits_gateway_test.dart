import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/jentra_field_sales.dart';
import 'package:jentra_platform/jentra_field_sales_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _scope = FieldSalesScope('tenant', 'entity', 'branch');

FieldSalesVisitCommand _command({
  String action = 'check_in',
  int? version = 1,
  FieldSalesJson payload = const {'id': 'visit'},
}) => FieldSalesVisitCommand(
  actorId: 'rep',
  scope: _scope,
  commandId: 'command',
  key: 'key',
  at: '2026-11-17T09:00:00.000Z',
  action: action,
  expectedVersion: version,
  payload: payload,
);

FieldSalesJson _receipt({
  String state = 'checked_in',
  String version = '2',
  String rep = 'rep',
}) => {
  'command_id': 'command',
  'entity': {
    'id': 'visit',
    'tenant_id': 'tenant',
    'legal_entity_id': 'entity',
    'branch_id': 'branch',
    'rep_id': rep,
    'state': state,
    'version': version,
  },
};

void main() {
  test(
    'visit commands carry their exact identity, action and version',
    () async {
      final calls = <(String, FieldSalesJson)>[];
      final g = SupabaseFieldSalesGateway.withRpc((name, params) async {
        calls.add((name, params));
        return _receipt();
      }, currentActor: () => 'rep');
      final command = _command(
        payload: {
          'id': 'visit',
          ...const FieldSalesLocation('6.927079', '-79.861244').payload,
        },
      );
      await g.visitCommand(command);
      expect(calls.single.$1, 'field_sales_visit_command');
      expect(calls.single.$2, {
        'p_tenant_id': 'tenant',
        'p_legal_entity_id': 'entity',
        'p_branch_id': 'branch',
        'p_command_id': 'command',
        'p_idempotency_key': 'key',
        'p_client_timestamp': '2026-11-17T09:00:00.000Z',
        'p_action': 'check_in',
        'p_payload': {
          'id': 'visit',
          'latitude': '6.927079',
          'longitude': '-79.861244',
        },
        'p_expected_entity_version': 1,
      });
    },
  );

  test('visit reads use the named pages and the receipt facade', () async {
    final calls = <(String, FieldSalesJson)>[];
    final g = SupabaseFieldSalesGateway.withRpc((name, params) async {
      calls.add((name, params));
      return name == 'field_sales_visit_receipt'
          ? {'state': 'not_found'}
          : {
              'items': [
                {'id': 'visit'},
              ],
              'next_cursor': null,
            };
    }, currentActor: () => 'rep');
    expect((await g.visits(_scope)).single['id'], 'visit');
    expect((await g.visitReceipt(_scope, 'key'))['state'], 'not_found');
    await g.companyVisits(
      _scope,
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 17),
    );
    expect(calls.map((c) => c.$1), [
      'field_sales_visits',
      'field_sales_visit_receipt',
      'field_sales_company_visits',
    ]);
    expect(calls[1].$2['p_idempotency_key'], 'key');
    expect(calls[2].$2['p_from'], '2026-11-01');
    expect(calls[2].$2['p_to'], '2026-11-17');
    expect(calls[2].$2['p_limit'], 50);
  });

  test('visit refusals get their own wording and keep their code', () async {
    final g = SupabaseFieldSalesGateway.withRpc(
      (_, _) async => throw const PostgrestException(
        message: 'VISIT_STATE_INVALID',
        code: '55000',
      ),
      currentActor: () => 'rep',
    );
    await expectLater(
      g.visitCommand(_command()),
      throwsA(
        isA<FieldSalesFailure>()
            .having((e) => e.code, 'code', '55000')
            .having((e) => e.message, 'message', contains('already moved on')),
      ),
    );
  });

  test('a visit command round-trips through protected storage', () {
    final command = _command(
      action: 'complete',
      version: 2,
      payload: {'id': 'visit', 'outcome': 'Met the buyer'},
    );
    final copy = FieldSalesVisitCommand.fromJson(command.toJson());
    expect(copy.params, command.params);
    expect(copy.visitId, 'visit');
  });

  test('receipts must match the command, the rep and the next state', () {
    final command = _command();
    expect(command.validateReceipt(_receipt())['state'], 'checked_in');
    for (final bad in [
      _receipt(state: 'planned'),
      _receipt(version: '3'),
      _receipt(rep: 'someone-else'),
      {..._receipt(), 'command_id': 'other'},
    ]) {
      expect(
        () => command.validateReceipt(bad),
        throwsA(isA<FieldSalesFailure>()),
      );
    }
    expect(
      _command(
        action: 'plan',
        version: null,
      ).validateReceipt(_receipt(state: 'planned', version: '1'))['id'],
      'visit',
    );
  });

  test('plan has no version and every later action needs one', () {
    expect(
      () => _command(action: 'plan', version: 1),
      throwsA(isA<FieldSalesFailure>()),
    );
    expect(
      () => _command(action: 'cancel', version: null),
      throwsA(isA<FieldSalesFailure>()),
    );
    expect(() => _command(action: 'track'), throwsA(isA<FieldSalesFailure>()));
  });

  test('locations are six-place decimal strings within range', () {
    final location = FieldSalesLocation.fromDegrees(6.9270786, 79.8612430);
    expect(location.payload, {
      'latitude': '6.927079',
      'longitude': '79.861243',
    });
    expect(
      () => FieldSalesLocation.fromDegrees(91, 0),
      throwsA(isA<FieldSalesFailure>()),
    );
    expect(
      () => FieldSalesLocation.fromDegrees(double.nan, 0),
      throwsA(isA<FieldSalesFailure>()),
    );
  });
}
