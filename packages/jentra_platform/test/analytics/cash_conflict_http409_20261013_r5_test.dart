import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_platform/analytics_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Local transport fixtures only. No Supabase connection, account or store.
String fixtureId(int index) =>
    '10000000-0000-0000-0000-${index.toString().padLeft(12, '0')}';

void main() {
  final scope = ProcessMetricScope(
    tenantId: fixtureId(1),
    legalEntityId: fixtureId(2),
    branchId: fixtureId(3),
  );
  for (final sqlstate in ['40001', 'PT409']) {
    for (final conflict in [
      ('prepare', 'CASH_DATE_VERSION_CONFLICT'),
      ('prepare', 'CASH_DATE_SOURCE_CHANGED'),
      ('approve', 'CASH_DATE_PROPOSAL_CHANGED'),
      ('approve', 'CASH_DATE_SOURCE_CHANGED'),
    ]) {
      test(
        '$sqlstate ${conflict.$1} ${conflict.$2} is denied without resend',
        () async {
          final payload = conflict.$1 == 'prepare'
              ? <String, Object?>{
                  'id': fixtureId(4),
                  'sourceKind': 'payroll_obligation',
                  'sourceId': fixtureId(5),
                  'sourceHash': 'a' * 64,
                  'dueDate': '2026-10-14',
                  'reasonCode': 'payment_terms',
                  'expectedVersion': '1',
                }
              : <String, Object?>{'id': fixtureId(4), 'proposalHash': 'b' * 64};
          final envelope = <String, Object?>{
            'commandId': fixtureId(6),
            'idempotencyKey': fixtureId(7),
            'clientTimestamp': '2026-10-13T00:00:00Z',
            'action': conflict.$1,
            'payload': payload,
          };
          final failure = PostgrestException(
            message: conflict.$2,
            code: sqlstate,
          );
          var calls = 0;
          final gateway = CashPaymentDatesGateway((name, parameters) async {
            calls++;
            expect(name, 'wave5_cash_date_command');
            expect(parameters, {
              'p_tenant_id': scope.tenantId,
              'p_legal_entity_id': scope.legalEntityId,
              'p_branch_id': scope.branchId,
              'p_command_id': envelope['commandId'],
              'p_idempotency_key': envelope['idempotencyKey'],
              'p_issued_at': envelope['clientTimestamp'],
              'p_action': conflict.$1,
              'p_payload': payload,
            });
            throw failure;
          });
          await expectLater(
            gateway.command(scope, envelope),
            throwsA(same(failure)),
          );
          expect(calls, 1);
          expect(envelope['idempotencyKey'], fixtureId(7));
          expect(envelope['payload'], same(payload));
        },
      );
    }
    test('$sqlstate stale scenario basis is denied without resend', () async {
      final revision = CashScenarioRevision(
        id: fixtureId(8),
        scope: scope,
        sourceHash: 'c' * 64,
        horizonStart: '2026-10-13',
        horizonEnd: '2026-10-15',
        recordedThrough: '2026-10-13T00:00:00Z',
        overrides: const {},
      );
      final failure = PostgrestException(
        message: 'SOURCE_BASIS_CHANGED',
        code: sqlstate,
      );
      var calls = 0;
      final gateway = DatedCashGateway((name, parameters) async {
        calls++;
        expect(name, 'wave5_cash_save');
        expect(parameters['p_id'], revision.id);
        expect(parameters['p_source_hash'], revision.sourceHash);
        expect(parameters['p_parameters'], {
          'horizonStart': revision.horizonStart,
          'horizonEnd': revision.horizonEnd,
          'recordedThrough': revision.recordedThrough,
          'overrides': revision.overrides,
        });
        throw failure;
      });
      await expectLater(gateway.save(revision), throwsA(same(failure)));
      expect(calls, 1);
      expect(revision.sourceHash, 'c' * 64);
      expect(revision.overrides, isEmpty);
    });
  }
}
