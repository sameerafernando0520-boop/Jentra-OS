import 'package:jentra_domain/jentra_expense_evidence.dart';
import 'package:test/test.dart';

const id = '20000000-0000-4000-8000-000000000001',
    project = '20000000-0000-4000-8000-000000000002',
    expense = '20000000-0000-4000-8000-000000000003';
Map<String, Object?> proof() => {'id': id, 'version': 1, 'digest': 'a' * 64};
Map<String, Object?> reserve() => {
  'action': 'reserve',
  'id': id,
  'project_id': project,
  'expense_id': expense,
  'mime': 'application/pdf',
  'byte_size': 4,
  'checksum': 'b' * 64,
  'purpose': 'Synthetic receipt',
};
void main() {
  test(
    'policy confirmation requires its minimal entity shape and no document fields',
    () {
      final policy = <String, Object?>{
        'id': id,
        'version': 1,
        'action': 'policy_create',
        'tenant_id': id,
        'legal_entity_id': project,
        'branch_id': expense,
      };
      Map<String, Object?> response(Map<String, Object?> e) => {
        'request_id': id,
        'command_id': project,
        'correlation_id': expense,
        'warnings': <Object?>[],
        'entity': e,
      };
      expect(
        ExpenseEvidenceConfirmation.fromJson(response(policy)).recordVersion,
        1,
      );
      expect(
        () => ExpenseEvidenceConfirmation.fromJson(
          response({...policy, 'expense_id': expense}),
        ),
        throwsFormatException,
      );
    },
  );
  test('proof retains immutable content version independent of lifecycle', () {
    final source = proof(), value = ExpenseEvidenceProof.fromJson(source);
    source['digest'] = 'c' * 64;
    expect(value.toJson(), proof());
    expect(
      () => ExpenseEvidenceProof.fromJson({...proof(), 'version': 2}),
      throwsFormatException,
    );
  });
  test('paths URLs bytes and unknown fields cannot enter financial proof', () {
    for (final field in [
      'object_path',
      'url',
      'bytes',
      'filename',
      'checksum',
    ]) {
      expect(
        () => ExpenseEvidenceProof.fromJson({...proof(), field: 'private'}),
        throwsFormatException,
      );
    }
  });
  test('proof selection is bounded unique and canonical', () {
    expect(
      () => expenseEvidenceProofs([proof(), proof()]),
      throwsFormatException,
    );
    expect(
      () => expenseEvidenceProofs(List.generate(11, (_) => proof())),
      throwsFormatException,
    );
    final second = {...proof(), 'id': expense};
    expect(expenseEvidenceProofs([second, proof()]).map((p) => p.id), [
      id,
      expense,
    ]);
  });
  test('reservation snapshot cannot mutate after command validation', () {
    final p = reserve(), frozen = ExpenseEvidenceCommands.validate(p);
    p['checksum'] = 'c' * 64;
    expect(frozen['checksum'], 'b' * 64);
    expect(
      () => ExpenseEvidenceCommands.validate({
        ...reserve(),
        'bytes': [1],
      }),
      throwsFormatException,
    );
  });
  test(
    'uploads reject unsupported MIME fractional bytes and unbounded metadata',
    () {
      for (final change in [
        {'mime': 'text/html'},
        {'byte_size': 0},
        {'byte_size': 1.5},
        {'byte_size': 10485761},
        {'purpose': 'x' * 161},
        {'checksum': 'B' * 64},
      ]) {
        expect(
          () => ExpenseEvidenceCommands.validate({...reserve(), ...change}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'policy requires explicit bounded interval and has no document scope',
    () {
      final p = {
        'action': 'policy_create',
        'id': id,
        'retention_days': 30,
        'purpose': 'Explicit synthetic choice',
      };
      expect(ExpenseEvidenceCommands.validate(p), p);
      expect(
        () => ExpenseEvidenceCommands.validate({...p, 'retention_days': 0}),
        throwsFormatException,
      );
      expect(
        () => ExpenseEvidenceCommands.validate({...p, 'expense_id': expense}),
        throwsFormatException,
      );
    },
  );
  test('retention and upload have distinct current capabilities', () {
    expect(
      ExpenseEvidenceCommands.capability('complete'),
      expenseEvidenceManage,
    );
    expect(
      ExpenseEvidenceCommands.capability('hold'),
      expenseEvidenceRetention,
    );
    expect(
      () => ExpenseEvidenceCommands.validate({
        'action': 'hold',
        'id': id,
        'project_id': project,
        'expense_id': expense,
        'reason': 'Synthetic',
        'review_date': '2026-02-30',
      }),
      throwsFormatException,
    );
  });
}
