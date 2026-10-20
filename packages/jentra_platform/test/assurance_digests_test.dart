import 'package:flutter_test/flutter_test.dart';
import 'package:jentra_platform/jentra_assurance_platform.dart';

// Digests produced by the server's SQL for the same literal inputs
// (development project, read-only, 20 October 2026); the texts are checked in
// jentra_domain/test/assurance_digest_test.dart.
void main() {
  test('the freeze digest equals the server cutoff digest', () async {
    expect(
      await assuranceFreezeDigest([
        (
          id: 'ffffffff-0000-4000-8000-000000000001',
          sha256: 'c' * 64,
          byteSize: 1,
        ),
        (
          id: '00000000-0000-4000-8000-000000000002',
          sha256: 'a' * 64,
          byteSize: 21,
        ),
        (
          id: '00000000-0000-4000-8000-00000000000a',
          sha256: 'b' * 64,
          byteSize: 1048576,
        ),
      ]),
      'c8d6239fd88c2a43e10923c17c4e90b38cbb6b0641861d670852dd9b1ed75731',
    );
  });

  test('the report digest equals the server report digest', () async {
    expect(
      await assuranceReportDigest(
        engagementId: '40000000-0000-4000-8000-000000000001',
        reportVersion: 2,
        cutoff: 'd' * 64,
        periodStart: '2026-04-01',
        periodEnd: '2027-03-31',
        findings: [
          (
            id: '20000000-0000-4000-8000-000000000002',
            title: 'Payments released by one "signatory"\nand café · ✓',
            severity: 'high',
            status: 'issued',
            ownerId: '30000000-0000-4000-8000-000000000001',
          ),
          (
            id: '10000000-0000-4000-8000-000000000001',
            title: 'Back\\slash\ttab and \u0001 control',
            severity: 'low',
            status: 'closed',
            ownerId: '30000000-0000-4000-8000-000000000002',
          ),
        ],
        summary: 'Two findings.\nOne closed — résumé.',
      ),
      'afa410adb0485cd6d31281827d1c9ed75e00e99b6c5de2980e264ab88e404145',
    );
    expect(
      await assuranceReportDigest(
        engagementId: '40000000-0000-4000-8000-000000000001',
        reportVersion: 1,
        cutoff: null,
        periodStart: '2026-04-01',
        periodEnd: '2027-03-31',
        findings: const [],
        summary: 'No findings',
      ),
      'ef189204184960ffcb4f7d7cb2eea548aeed5423af43bf0161ecda0db53841e6',
    );
  });
}
