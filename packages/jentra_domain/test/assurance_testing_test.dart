import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

String uid(int n) => '30000000-0000-0000-0000-${n.toString().padLeft(12, '0')}';
final eng = uid(1);

Map<String, Object?> design([Map<String, Object?> patch = const {}]) => {
  'action': 'design_test',
  'engagement_id': eng,
  'procedure_id': uid(2),
  'control_id': uid(3),
  'code': 'TP1',
  'objective': 'Each sampled payment has a matched receipt',
  'population_size': 1000,
  'sample_start': 7,
  ...patch,
};

Map<String, Object?> execute([Map<String, Object?> patch = const {}]) => {
  'action': 'execute_test',
  'engagement_id': eng,
  'run_id': uid(4),
  'procedure_id': uid(2),
  'items_tested': 40,
  'exceptions_found': 2,
  'conclusion': 'ineffective',
  'workpaper_sha256': 'b' * 64,
  ...patch,
};

void main() {
  test('systematic sample matches the server vectors exactly', () {
    // Same vectors asserted by supabase/tests/assurance_testing_test.sql.
    expect(assuranceSystematicSample(100, 25, 7), [
      for (var i = 0; i < 25; i++) ((7 - 1 + i * 100 ~/ 25) % 100) + 1,
    ]);
    final high = assuranceSystematicSample(
      1000,
      assuranceSampleSize(1000, AssuranceSeverity.high),
      7,
    );
    expect(high.length, 40);
    expect(high.take(3), [7, 32, 57]);
    // Large populations stay exact (no floating-point drift).
    final big = assuranceSystematicSample(99999999, 60, 99999999);
    expect(big.toSet().length, 60);
    expect(big.every((p) => p >= 1 && p <= 99999999), isTrue);
  });

  test('test commands mirror server capabilities and MFA', () {
    expect(
      AssuranceTestCommands.capability('review_test'),
      'assurance.test.review',
    );
    expect(AssuranceTestCommands.requiresRecentMfa('carry_forward'), isTrue);
    expect(AssuranceTestCommands.requiresRecentMfa('execute_test'), isFalse);
    expect(
      () => AssuranceTestCommands.capability('delete_run'),
      throwsFormatException,
    );
  });

  test('client cannot choose sample size; start must be in population', () {
    AssuranceTestCommands.validate('design_test', design());
    for (final patch in <Map<String, Object?>>[
      {'sample_size': 5},
      {'sample_start': 1001},
      {'sample_start': 0},
      {'population_size': 0},
      {'population_size': 10.0},
      {'code': 'tp 1'},
    ]) {
      expect(
        () => AssuranceTestCommands.validate('design_test', design(patch)),
        throwsFormatException,
        reason: '$patch',
      );
    }
  });

  test('execution requires the full sample and a consistent conclusion', () {
    AssuranceTestCommands.validate('execute_test', execute(), sampleSize: 40);
    for (final patch in <Map<String, Object?>>[
      {'items_tested': 39},
      {'conclusion': 'effective'},
      {'exceptions_found': 41},
      {'conclusion': 'mostly_effective'},
      {'workpaper_sha256': 'nope'},
    ]) {
      expect(
        () => AssuranceTestCommands.validate(
          'execute_test',
          execute(patch),
          sampleSize: 40,
        ),
        throwsFormatException,
        reason: '$patch',
      );
    }
    AssuranceTestCommands.validate(
      'execute_test',
      execute({'exceptions_found': 0, 'conclusion': 'effective'}),
      sampleSize: 40,
    );
  });

  test('review decisions and carry-forward identities', () {
    AssuranceTestCommands.validate('review_test', {
      'action': 'review_test',
      'engagement_id': eng,
      'procedure_id': uid(2),
      'decision': 'return',
      'reason': 'Attach exception list',
    });
    expect(
      () => AssuranceTestCommands.validate('review_test', {
        'action': 'review_test',
        'engagement_id': eng,
        'procedure_id': uid(2),
        'decision': 'approve',
        'reason': 'Wrong verb',
      }),
      throwsFormatException,
    );
    final carry = {
      'action': 'carry_forward',
      'engagement_id': eng,
      'finding_id': uid(5),
      'source_finding_id': uid(6),
      'exception_id': uid(7),
      'control_id': uid(3),
    };
    AssuranceTestCommands.validate('carry_forward', carry);
    expect(
      () => AssuranceTestCommands.validate('carry_forward', {
        ...carry,
        'severity': 'low',
      }),
      throwsFormatException,
      reason: 'severity and owner are copied from the source by the server',
    );
  });
}
