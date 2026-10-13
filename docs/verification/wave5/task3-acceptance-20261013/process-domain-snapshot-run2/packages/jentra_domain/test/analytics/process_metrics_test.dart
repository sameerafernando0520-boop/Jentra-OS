import 'dart:convert';

import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:test/test.dart';

const tenant = '10000000-0000-0000-0000-000000000001';
const entity = '20000000-0000-0000-0000-000000000001';
const branch = '30000000-0000-0000-0000-000000000001';
const document = '40000000-0000-0000-0000-000000000001';
const snapshot = '50000000-0000-0000-0000-000000000001';
const start = '2026-09-01T00:00:00Z';
const end = '2026-09-02T00:00:00Z';
const cutoff = '2026-09-03T00:00:00Z';
const generated = '2026-09-03T00:00:01Z';
final scope = ProcessMetricScope(
  tenantId: tenant,
  legalEntityId: entity,
  branchId: branch,
);

String eventId(int value) =>
    '60000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';

Map<String, Object?> observation(
  int id, {
  String enteredAt = start,
  String? completedAt = end,
  String recordedAt = end,
  String activeMinutes = '0',
  String waitMinutes = '0',
}) => {
  'id': eventId(id),
  'tenantId': tenant,
  'legalEntityId': entity,
  'branchId': branch,
  'documentType': 'crm_opportunity',
  'documentId': document,
  'enteredAt': enteredAt,
  'completedAt': completedAt,
  'recordedAt': recordedAt,
  'activeMinutes': activeMinutes,
  'waitMinutes': waitMinutes,
};

/// Tests only: recognizes exact canonical bytes, never computes a real digest.
final class ExpectedBytesHasher implements ProcessMetricHasher {
  ExpectedBytesHasher(this.expected, {String? value}) : value = value ?? digest;
  static final digest = 'a' * 64;
  final List<int> expected;
  final String value;
  @override
  Future<String> sha256(List<int> bytes) async =>
      utf8.decode(bytes) == utf8.decode(expected) ? value : 'b' * 64;
}

final class FailingHasher implements ProcessMetricHasher {
  FailingHasher(this.failure);
  final Object failure;
  @override
  Future<String> sha256(List<int> bytes) async => throw failure;
}

Map<String, Object?> wire(List<Map<String, Object?>> rows) => {
  'source': <String, Object?>{
    'snapshotId': snapshot,
    'sourceManifestHash': ExpectedBytesHasher.digest,
    'sourceEventIds': rows.map((row) => row['id']).toList()..sort(),
    'sourceContractVersion': 'workflow.process_events.v1',
    'tenantId': tenant,
    'legalEntityId': entity,
    'branchId': branch,
    'documentType': 'crm_opportunity',
    'windowStart': start,
    'windowEnd': end,
    'asOf': end,
    'recordedThrough': cutoff,
    'sourceCount': rows.length,
    'complete': true,
  },
  'observations': rows,
};

Map<String, Object?> sourceOf(Map<String, Object?> input) =>
    input['source']! as Map<String, Object?>;

ParsedProcessMetricSnapshot parse(Map<String, Object?> input) =>
    ParsedProcessMetricSnapshot.fromJson(input, expectedScope: scope);

Future<ProcessMetricSnapshot> verify(Map<String, Object?> input) async {
  final parsed = parse(input);
  return parsed.verify(ExpectedBytesHasher(parsed.canonicalBytes));
}

Future<ProcessMetricSummary> summarize(List<Map<String, Object?>> rows) async =>
    (await verify(wire(rows))).summarize(generatedAt: generated);

Matcher errorCode(String code) =>
    isA<DomainError>().having((error) => error.code, 'code', code);

void main() {
  test(
    'AC-558 EC-558 verifier failures preserve domain errors and redact unknown errors',
    () async {
      final parsed = parse(wire([]));
      await expectLater(
        parsed.verify(
          FailingHasher(
            const DomainError(
              code: 'LIMIT_EXCEEDED',
              message: 'Bound exceeded.',
            ),
          ),
        ),
        throwsA(errorCode('LIMIT_EXCEEDED')),
      );
      await expectLater(
        parsed.verify(FailingHasher(StateError('sensitive provider detail'))),
        throwsA(
          isA<DomainError>()
              .having((error) => error.code, 'code', 'PROVIDER_UNAVAILABLE')
              .having(
                (error) => error.message,
                'message',
                isNot(contains('sensitive')),
              )
              .having((error) => error.retryable, 'retryable', true),
        ),
      );
    },
  );

  test('AC-555 forged row/identity counts do not evade input limits', () {
    final input = wire([for (var id = 1; id <= 10000; id++) observation(id)]);
    (input['observations']! as List).add(observation(10001));
    expect(() => parse(input), throwsA(errorCode('LIMIT_EXCEEDED')));
    final identities = wire([]);
    sourceOf(identities)['sourceEventIds'] = [
      for (var id = 1; id <= 10001; id++) eventId(id),
    ];
    expect(() => parse(identities), throwsA(errorCode('LIMIT_EXCEEDED')));
    final duplicates = wire([observation(1), observation(1)]);
    sourceOf(duplicates)['sourceEventIds'] = [eventId(1), eventId(2)];
    expect(() => parse(duplicates), throwsA(errorCode('VALIDATION_ERROR')));
  });

  test(
    'AC-558 malformed container shapes and foreign selection fail safely',
    () {
      for (final value in [
        null,
        'not an object',
        {1: 'value'},
      ]) {
        final input = wire([])..['source'] = value;
        expect(() => parse(input), throwsA(errorCode('VALIDATION_ERROR')));
      }
      final noRows = wire([])..['observations'] = null;
      expect(() => parse(noRows), throwsA(errorCode('VALIDATION_ERROR')));
      final badRows = wire([observation(1)])..['observations'] = ['invalid'];
      expect(() => parse(badRows), throwsA(errorCode('VALIDATION_ERROR')));
      final extraField = wire([])..['unexpected'] = true;
      expect(() => parse(extraField), throwsA(errorCode('VALIDATION_ERROR')));
      final negativeCount = wire([]);
      sourceOf(negativeCount)['sourceCount'] = -1;
      expect(
        () => parse(negativeCount),
        throwsA(errorCode('VALIDATION_ERROR')),
      );
      final incomplete = wire([observation(1)]);
      incomplete['observations'] = <Map<String, Object?>>[];
      expect(
        () => parse(incomplete),
        throwsA(errorCode('INSUFFICIENT_EVIDENCE')),
      );
    },
  );
  test(
    'AC-551 EC-551 half-open entry and inclusive recorded/completion cutoffs',
    () async {
      final result = await summarize([
        observation(1),
        observation(2, enteredAt: end),
        observation(3, recordedAt: cutoff),
        observation(4, recordedAt: '2026-09-03T00:00:00.000001Z'),
        observation(5, completedAt: '2026-09-02T00:00:00.000001Z'),
        observation(6, completedAt: null),
        observation(7, enteredAt: '2026-08-31T23:59:59.999999Z'),
      ]);
      expect(result.source.sourceCount, 7);
      expect(result.cohortCount, 4);
      expect(result.completedCount, 2);
      expect(result.openCount, 2);
      expect(result.invalidCount, 0);
      expect(result.excludedCount, 3);
    },
  );

  test(
    'AC-552 EC-554 exact P50/P90 over every permutation including zero',
    () async {
      final rows = [
        for (final value in [0, 1, 2, 3, 10])
          observation(
            value + 1,
            completedAt:
                '2026-09-01T00:00:00.${value.toString().padLeft(6, '0')}Z',
          ),
      ];
      final original = parse(wire(rows));
      final hasher = ExpectedBytesHasher(original.canonicalBytes);
      for (final permutation in permutations(rows)) {
        final parsed = parse(wire(permutation));
        final result = (await parsed.verify(
          hasher,
        )).summarize(generatedAt: generated);
        expect(result.p50Microseconds, BigInt.from(2));
        expect(result.p90Microseconds, BigInt.from(10));
        expect(parsed.canonicalBytes, original.canonicalBytes);
      }
    },
  );

  test(
    'AC-552 nearest rank is discrete for even, single and tied populations',
    () async {
      for (final durations in [
        [0],
        [7],
        [3, 3],
        [1, 2, 3, 4],
        List.filled(10, 11),
      ]) {
        final rows = [
          for (var index = 0; index < durations.length; index++)
            observation(
              index + 1,
              completedAt:
                  '2026-09-01T00:00:00.${durations[index].toString().padLeft(6, '0')}Z',
            ),
        ];
        final result = await summarize(rows);
        expect(
          result.p50Microseconds,
          BigInt.from(durations[(durations.length - 1) ~/ 2]),
        );
        expect(
          result.p90Microseconds,
          BigInt.from(durations[(9 * durations.length + 9) ~/ 10 - 1]),
        );
      }
    },
  );

  test(
    'AC-553 EC-554 empty, valid zero and open-only samples remain distinct',
    () async {
      final empty = await summarize([]);
      expect(empty.p50Microseconds, isNull);
      expect(empty.emptyDurationReason, 'NO_COMPLETED_OBSERVATIONS');
      expect(empty.completeness, 'complete');
      final zero = await summarize([observation(1, completedAt: start)]);
      expect(zero.p50Microseconds, BigInt.zero);
      expect(zero.emptyDurationReason, isNull);
      final open = await summarize([observation(1, completedAt: null)]);
      expect(open.openCount, 1);
      expect(open.p90Microseconds, isNull);
    },
  );

  test(
    'AC-553 EC-555 invalid duration/minutes conserve counts and mark partial',
    () async {
      final result = await summarize([
        observation(1, completedAt: '2026-08-31T23:59:59Z'),
        observation(2, activeMinutes: '-0.000001'),
        observation(3, waitMinutes: '-1'),
        observation(4),
      ]);
      expect(result.invalidCount, 3);
      expect(result.completedCount, 1);
      expect(result.completeness, 'partial');
      expect(
        result.cohortCount,
        result.completedCount + result.openCount + result.invalidCount,
      );
      expect(
        result.source.sourceCount,
        result.cohortCount + result.excludedCount,
      );
    },
  );

  test(
    'AC-553 default-zero and positive minutes cannot certify other measures',
    () async {
      for (final amount in ['0', '12.25']) {
        final result = await summarize([
          observation(1, activeMinutes: amount, waitMinutes: amount),
        ]);
        expect(
          result.unsupportedMeasures.keys,
          containsAll([
            'stage_dwell',
            'process_throughput',
            'handoff_wait',
            'productive_work_ratio',
            'rework',
          ]),
        );
        expect(result.unsupportedMeasures.values.toSet(), {
          'UNCERTIFIED_PROCESS_SEMANTICS',
        });
      }
    },
  );

  test(
    'AC-558 EC-557 strict UTC rejects normalized invalid calendar values',
    () {
      for (final invalid in [
        '2026-02-30T00:00:00Z',
        '2026-09-01T24:00:00Z',
        '2026-09-01T00:60:00Z',
        '2026-09-01T00:00:60Z',
        '2026-09-01T00:00:00+00:00',
        '2026-09-01',
        '2026-09-01T00:00:00.1234567Z',
        '0000-01-01T00:00:00Z',
      ]) {
        final input = wire([observation(1, enteredAt: invalid)]);
        expect(() => parse(input), throwsA(errorCode('VALIDATION_ERROR')));
      }
      expect(
        parseProcessMetricUtc('2024-02-29T00:00:00.000001Z').microsecond,
        1,
      );
    },
  );

  test(
    'AC-558 manifest instants and generation time require ordered UTC',
    () async {
      for (final change in [
        {'windowEnd': start},
        {'windowStart': end},
        {'asOf': '2026-09-01T23:59:59Z'},
        {'asOf': '2026-09-04T00:00:00Z'},
        {'recordedThrough': '2026-09-01T00:00:00Z'},
      ]) {
        final input = wire([]);
        sourceOf(input).addAll(change);
        expect(() => parse(input), throwsA(errorCode('VALIDATION_ERROR')));
      }
      final checked = await verify(wire([]));
      expect(
        () => checked.summarize(generatedAt: start),
        throwsA(errorCode('VALIDATION_ERROR')),
      );
    },
  );

  test(
    'AC-558 exact minute parser rejects numeric coercion and silent rounding',
    () {
      for (final invalid in [
        1.0,
        '0.0000001',
        '1e2',
        '+1',
        ' 1 ',
        '100000000000000',
        null,
        true,
      ]) {
        final row = observation(1)..['activeMinutes'] = invalid;
        expect(
          () => parse(wire([row])),
          throwsA(errorCode('VALIDATION_ERROR')),
        );
      }
      final parsed = parse(
        wire([
          observation(1, activeMinutes: '00001.25', waitMinutes: '-0.000000'),
        ]),
      );
      expect(
        parsed.observations.single.activeMinutes.toDecimalString(),
        '1.250000',
      );
      expect(
        parsed.observations.single.waitMinutes.toDecimalString(),
        '0.000000',
      );
    },
  );

  test(
    'AC-555 EC-553 duplicate event IDs fail; shared document IDs remain distinct',
    () async {
      expect(
        () => parse(wire([observation(1), observation(1)])),
        throwsA(errorCode('VALIDATION_ERROR')),
      );
      final result = await summarize([observation(1), observation(2)]);
      expect(result.completedCount, 2);
    },
  );

  test('AC-555 incomplete, mismatched and unsorted manifests fail closed', () {
    final mutations = <void Function(Map<String, Object?>)>[
      (source) => source['complete'] = false,
      (source) => source['sourceCount'] = 2,
      (source) => source['sourceCount'] = 1.0,
      (source) => source['sourceEventIds'] = [eventId(2)],
      (source) => source['sourceEventIds'] = [eventId(2), eventId(1)],
      (source) => source['sourceEventIds'] = [eventId(1), eventId(1)],
    ];
    for (final mutate in mutations) {
      final input = wire([observation(1)]);
      mutate(sourceOf(input));
      expect(() => parse(input), throwsA(isA<DomainError>()));
    }
  });

  test(
    'AC-558 EC-556 foreign tenant/entity/branch and null entity are denied',
    () {
      for (final field in ['tenantId', 'legalEntityId', 'branchId']) {
        final row = observation(1)..[field] = document;
        expect(
          () => parse(wire([row])),
          throwsA(errorCode('PERMISSION_DENIED')),
        );
        final input = wire([observation(1)]);
        sourceOf(input)[field] = document;
        expect(() => parse(input), throwsA(errorCode('PERMISSION_DENIED')));
      }
      final row = observation(1)..['legalEntityId'] = null;
      expect(() => parse(wire([row])), throwsA(errorCode('PERMISSION_DENIED')));
    },
  );

  test(
    'AC-558 null branch permits authorized mixed-branch observations only within entity',
    () {
      final input = wire([observation(1), observation(2)..['branchId'] = null]);
      sourceOf(input)['branchId'] = null;
      final allBranches = ProcessMetricScope(
        tenantId: tenant,
        legalEntityId: entity,
      );
      expect(
        () => ParsedProcessMetricSnapshot.fromJson(
          input,
          expectedScope: allBranches,
        ),
        returnsNormally,
      );
    },
  );

  test(
    'AC-558 unsupported source revision or document kind fails before calculation',
    () {
      for (final field in ['sourceContractVersion', 'documentType']) {
        final input = wire([]);
        sourceOf(input)[field] = 'unsupported';
        expect(() => parse(input), throwsA(errorCode('CONTRACT_MISMATCH')));
      }
      final row = observation(1)..['documentType'] = 'sales_invoice';
      expect(() => parse(wire([row])), throwsA(errorCode('CONTRACT_MISMATCH')));
    },
  );

  test(
    'AC-555 EC-557 10000 rows succeed and 10001 fail without partial totals',
    () async {
      final rows = [
        for (var id = 1; id <= 10000; id++) observation(id, completedAt: start),
      ];
      final result = await summarize(rows);
      expect(result.completedCount, 10000);
      expect(result.p90Microseconds, BigInt.zero);
      expect(
        utf8.encode(jsonEncode(result.toJson())).length,
        lessThanOrEqualTo(8 * 1024 * 1024),
      );
      rows.add(observation(10001));
      expect(() => parse(wire(rows)), throwsA(errorCode('LIMIT_EXCEEDED')));
    },
  );

  test(
    'AC-555 EC-557 366-day cohort succeeds; one microsecond excess fails',
    () {
      final input = wire([]);
      sourceOf(
        input,
      ).addAll({'windowStart': '2025-09-01T00:00:00Z', 'windowEnd': end});
      expect(() => parse(input), returnsNormally);
      sourceOf(input)['windowStart'] = '2025-08-31T23:59:59.999999Z';
      expect(() => parse(input), throwsA(errorCode('LIMIT_EXCEEDED')));
    },
  );

  test(
    'AC-552 durations larger than safe JSON integers serialize exactly as strings',
    () async {
      final input = wire([
        observation(
          1,
          enteredAt: '0001-01-01T00:00:00Z',
          completedAt: '9999-01-01T00:00:00Z',
          recordedAt: '9999-01-01T00:00:00Z',
        ),
      ]);
      sourceOf(input).addAll({
        'windowStart': '0001-01-01T00:00:00Z',
        'windowEnd': '0001-01-02T00:00:00Z',
        'asOf': '9999-01-01T00:00:00Z',
        'recordedThrough': '9999-01-01T00:00:00Z',
      });
      final result = (await verify(
        input,
      )).summarize(generatedAt: '9999-01-01T00:00:01Z');
      expect(
        result.p50Microseconds,
        greaterThan(BigInt.parse('9007199254740991')),
      );
      expect(result.toJson()['p50Microseconds'], '315506361600000000');
    },
  );

  test(
    'AC-558 source projection rejects private/unknown fields and missing required fields',
    () {
      for (final field in ['actorId', 'ownerId', 'reason', 'unexpected']) {
        final row = observation(1)..[field] = 'sensitive text';
        expect(
          () => parse(wire([row])),
          throwsA(errorCode('VALIDATION_ERROR')),
        );
      }
      final row = observation(1)..remove('enteredAt');
      expect(() => parse(wire([row])), throwsA(errorCode('VALIDATION_ERROR')));
    },
  );

  test(
    'AC-551 EC-552 canonical captured bytes freeze source values and selection',
    () async {
      final input = wire([observation(1, activeMinutes: '01.25')]);
      final parsed = parse(input);
      final canonical = jsonDecode(utf8.decode(parsed.canonicalBytes)) as Map;
      expect(canonical.keys.toList(), [
        'definitionCode',
        'definitionVersion',
        'sourceContractVersion',
        'tenantId',
        'legalEntityId',
        'branchId',
        'documentType',
        'windowStart',
        'windowEnd',
        'asOf',
        'recordedThrough',
        'observations',
      ]);
      expect(canonical['windowStart'], '2026-09-01T00:00:00.000000Z');
      expect(
        (canonical['observations'] as List).single['activeMinutes'],
        '1.250000',
      );
      final hasher = ExpectedBytesHasher(parsed.canonicalBytes);
      final checked = await parsed.verify(hasher);
      input['observations'] = [observation(2)];
      sourceOf(input)['sourceEventIds'] = [eventId(2)];
      expect(checked.summarize(generatedAt: generated).completedCount, 1);
      expect(
        () => parse(input).verify(hasher),
        throwsA(errorCode('INSUFFICIENT_EVIDENCE')),
      );
    },
  );

  test(
    'AC-558 manifest/hash verification rejects wrong or malformed digest',
    () async {
      final parsed = parse(wire([]));
      expect(
        () => parsed.verify(
          ExpectedBytesHasher(parsed.canonicalBytes, value: 'c' * 64),
        ),
        throwsA(errorCode('INSUFFICIENT_EVIDENCE')),
      );
      expect(
        () => parsed.verify(
          ExpectedBytesHasher(parsed.canonicalBytes, value: 'invalid'),
        ),
        throwsA(errorCode('INSUFFICIENT_EVIDENCE')),
      );
      final malformed = wire([]);
      sourceOf(malformed)['sourceManifestHash'] = 'not-a-digest';
      expect(() => parse(malformed), throwsA(errorCode('VALIDATION_ERROR')));
    },
  );

  test(
    'AC-558 verified observations/manifests/results are immutable',
    () async {
      final parsed = parse(wire([observation(1)]));
      expect(() => parsed.observations.clear(), throwsUnsupportedError);
      expect(
        () => parsed.source.sourceEventIds.clear(),
        throwsUnsupportedError,
      );
      final verified = await parsed.verify(
        ExpectedBytesHasher(parsed.canonicalBytes),
      );
      final result = verified.summarize(generatedAt: generated);
      expect(() => result.unsupportedMeasures.clear(), throwsUnsupportedError);
      final json = result.toJson();
      (json['source']! as Map)['sourceCount'] = 999;
      expect(result.source.sourceCount, 1);
    },
  );

  test(
    'AC-558 identifiers canonicalize case and reject malformed UUIDs safely',
    () {
      expect(
        () => ProcessMetricScope(tenantId: 'invalid', legalEntityId: entity),
        throwsA(errorCode('VALIDATION_ERROR')),
      );
      final input = wire([
        observation(1)..['documentId'] = 'ABCDEF01-0000-0000-0000-000000000001',
      ]);
      expect(
        parse(input).observations.single.documentId,
        'abcdef01-0000-0000-0000-000000000001',
      );
      final error = (() {
        try {
          parse(
            wire([observation(1)..['enteredAt'] = 'private-sensitive-invalid']),
          );
        } on DomainError catch (error) {
          return error;
        }
        throw StateError('Expected rejection.');
      })();
      expect(error.toString(), isNot(contains('private-sensitive-invalid')));
    },
  );
}

Iterable<List<T>> permutations<T>(List<T> input) sync* {
  if (input.isEmpty) {
    yield <T>[];
    return;
  }
  for (var index = 0; index < input.length; index++) {
    final rest = [...input]..removeAt(index);
    for (final tail in permutations(rest)) {
      yield [input[index], ...tail];
    }
  }
}
