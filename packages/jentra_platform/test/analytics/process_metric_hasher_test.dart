import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_domain/analytics.dart';
import 'package:jentra_domain/jentra_domain.dart' show DomainError;
import 'package:jentra_platform/analytics_platform.dart';

const tenant = '10000000-0000-0000-0000-000000000001';
const entity = '20000000-0000-0000-0000-000000000001';
const branch = '30000000-0000-0000-0000-000000000001';
final scope = ProcessMetricScope(
  tenantId: tenant,
  legalEntityId: entity,
  branchId: branch,
);
// Independent Python hashlib vectors over the documented ordered JSON format.
const emptyManifestDigest =
    '314d0335c8df8976301d59ebf0d7bb4a25d3c54170865a7b9824e7bfd89737eb';

Map<String, Object?> fixture() => {
  'source': <String, Object?>{
    'snapshotId': '50000000-0000-0000-0000-000000000001',
    'sourceManifestHash': emptyManifestDigest,
    'sourceEventIds': <String>[],
    'sourceContractVersion': 'workflow.process_events.v1',
    'tenantId': tenant,
    'legalEntityId': entity,
    'branchId': branch,
    'documentType': 'crm_opportunity',
    'windowStart': '2026-09-01T00:00:00Z',
    'windowEnd': '2026-09-02T00:00:00Z',
    'asOf': '2026-09-02T00:00:00Z',
    'recordedThrough': '2026-09-03T00:00:00Z',
    'sourceCount': 0,
    'complete': true,
  },
  'observations': <Map<String, Object?>>[],
};

void main() {
  final hasher = ProcessMetricSha256Hasher();
  test(
    'AC-558 nonempty canonical projection matches independent Python vector',
    () async {
      final input = fixture();
      final source = input['source']! as Map;
      source['sourceManifestHash'] =
          '628e37a067c186597ba70f819abfda96f9ba3446e03d454f2292dabd5abc7fa5';
      source['sourceCount'] = 1;
      source['sourceEventIds'] = ['60000000-0000-0000-0000-000000000001'];
      input['observations'] = [
        <String, Object?>{
          'id': '60000000-0000-0000-0000-000000000001',
          'tenantId': tenant,
          'legalEntityId': entity,
          'branchId': branch,
          'documentType': 'crm_opportunity',
          'documentId': '40000000-0000-0000-0000-000000000001',
          'enteredAt': '2026-09-01T00:00:00Z',
          'completedAt': '2026-09-01T00:00:00.000001Z',
          'recordedAt': '2026-09-02T00:00:00Z',
          'activeMinutes': '01.25',
          'waitMinutes': '-0.000000',
        },
      ];
      final parsed = ParsedProcessMetricSnapshot.fromJson(
        input,
        expectedScope: scope,
      );
      final verified = await parsed.verify(hasher);
      expect(
        verified.summarize(generatedAt: '2026-09-03T00:00:01Z').p50Microseconds,
        BigInt.one,
      );
      (input['observations']! as List).single['activeMinutes'] = '2';
      await expectLater(
        ParsedProcessMetricSnapshot.fromJson(
          input,
          expectedScope: scope,
        ).verify(hasher),
        throwsA(
          isA<DomainError>().having(
            (error) => error.code,
            'code',
            'INSUFFICIENT_EVIDENCE',
          ),
        ),
      );
    },
  );
  test('AC-558 SHA-256 matches independent empty and ASCII vectors', () async {
    expect(
      await hasher.sha256([]),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      await hasher.sha256(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
  test(
    'AC-558 SHA-256 preserves binary bytes without text conversion',
    () async {
      expect(
        await hasher.sha256([0, 255, 128, 1]),
        '6509423fd9da5c225d2f8619ffae394b40f9f7686fee55a38c54b1424ac65f46',
      );
    },
  );
  test(
    'AC-558 canonical empty snapshot matches independent Python vector',
    () async {
      final parsed = ParsedProcessMetricSnapshot.fromJson(
        fixture(),
        expectedScope: scope,
      );
      expect(await hasher.sha256(parsed.canonicalBytes), emptyManifestDigest);
      final verified = await parsed.verify(hasher);
      expect(
        verified
            .summarize(generatedAt: '2026-09-03T00:00:01Z')
            .emptyDurationReason,
        'NO_COMPLETED_OBSERVATIONS',
      );
    },
  );
  test('AC-551 captured source digest changes when cutoff changes', () async {
    final input = fixture();
    (input['source']! as Map)['recordedThrough'] =
        '2026-09-03T00:00:00.000001Z';
    final parsed = ParsedProcessMetricSnapshot.fromJson(
      input,
      expectedScope: scope,
    );
    await expectLater(
      parsed.verify(hasher),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'INSUFFICIENT_EVIDENCE',
        ),
      ),
    );
  });
  test(
    'AC-558 snapshot identity does not replace the captured value digest',
    () async {
      final input = fixture();
      (input['source']! as Map)['snapshotId'] =
          '50000000-0000-0000-0000-000000000002';
      final parsed = ParsedProcessMetricSnapshot.fromJson(
        input,
        expectedScope: scope,
      );
      expect(await hasher.sha256(parsed.canonicalBytes), emptyManifestDigest);
    },
  );
  test('AC-555 oversized digest payload fails before hashing', () async {
    await expectLater(
      hasher.sha256(List.filled(8 * 1024 * 1024 + 1, 0)),
      throwsA(
        isA<DomainError>().having(
          (error) => error.code,
          'code',
          'LIMIT_EXCEEDED',
        ),
      ),
    );
  });
  test(
    'AC-558 invalid byte values cannot be normalized into evidence',
    () async {
      for (final invalid in [-1, 256]) {
        await expectLater(
          hasher.sha256([invalid]),
          throwsA(
            isA<DomainError>().having(
              (error) => error.code,
              'code',
              'VALIDATION_ERROR',
            ),
          ),
        );
      }
    },
  );
}
