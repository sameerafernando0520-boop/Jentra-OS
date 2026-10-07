import 'package:test/test.dart';
import 'package:jentra_domain/jentra_domain.dart';
import 'package:jentra_domain/jentra_milestones.dart';

String uid(int n) => '10000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
Map<String, Object?> input() => {
  'action': 'create',
  'id': uid(1),
  'project_id': uid(2),
  'plan_id': uid(3),
  'task_id': uid(4),
  'owner_id': uid(5),
  'name': 'Customer accepted delivery',
  'due_date': '2026-10-05',
  'amount': '125.25',
  'commercial_terms': 'Whole accepted deliverable',
  'payment_terms': 'Payment within30 days',
  'payment_due_days': 30,
  'evidence_reference': 'ACCEPTANCE-01',
  'reason': 'Original commercial terms',
};
void main() {
  test('commercial amount stays exact beyond double precision', () {
    final m = milestoneAmount('99999999999999.999999', 'LKR', 6);
    expect(m.minorUnits, BigInt.parse('99999999999999999999'));
    expect(() => milestoneAmount('125.255', 'LKR', 2), throwsFormatException);
    expect(() => milestoneAmount(125.25, 'LKR', 2), throwsFormatException);
  });
  test(
    'commercial request requires dated named sources and bounded explicit payment duration',
    () {
      MilestoneCommands.validate('create', input());
      for (final patch in [
        {'due_date': '2026-02-30'},
        {'payment_due_days': 366},
        {'payment_due_days': 30.0},
        {'owner_id': 'Employee One'},
        {'amount': 125.25},
        {'internal_cost': '1'},
      ]) {
        expect(
          () => MilestoneCommands.validate('create', {...input(), ...patch}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'decision binds immutable digest rather than editable commercial terms',
    () {
      final d = {
        'action': 'approve',
        'id': uid(1),
        'project_id': uid(2),
        'digest': 'a' * 64,
        'reason': 'Independent delivery review',
      };
      MilestoneCommands.validate('approve', d);
      expect(MilestoneCommands.capability('approve'), 'projects.approve');
      expect(
        () => MilestoneCommands.validate('approve', {...d, 'amount': '1'}),
        throwsFormatException,
      );
    },
  );
  test(
    'known receipt must match original actor scope project identity and version',
    () {
      final scope = TenantContext(
            tenantId: uid(10),
            actorId: uid(11),
            legalEntityId: uid(12),
            branchId: uid(13),
          ),
          c = CommandEnvelope<Map<String, Object?>>(
            commandId: uid(14),
            idempotencyKey: uid(15),
            context: scope,
            payload: input(),
            expectedEntityVersion: 0,
          );
      final e = {
        'id': uid(1),
        'project_id': uid(2),
        'tenant_id': scope.tenantId,
        'legal_entity_id': scope.legalEntityId,
        'branch_id': scope.branchId,
        'version': 1,
        'status': 'draft',
        'revision_id': uid(16),
      };
      final r = {
        'request_id': uid(14),
        'command_id': uid(14),
        'correlation_id': uid(14),
        'warnings': [],
        'entity': e,
      };
      milestoneReceipt(r, scope, uid(2), request: c);
      for (final patch in [
        {'project_id': uid(99)},
        {'branch_id': uid(99)},
        {'version': 2},
        {'id': uid(99)},
        {'internal_cost': '1'},
      ]) {
        expect(
          () => milestoneReceipt(
            {
              ...r,
              'entity': {...e, ...patch},
            },
            scope,
            uid(2),
            request: c,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
