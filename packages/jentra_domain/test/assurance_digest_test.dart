import 'package:jentra_domain/jentra_assurance.dart';
import 'package:test/test.dart';

// Expected texts were produced by the SQL in api.assurance_command
// (freeze_evidence, issue_report) on the development project with literal
// inputs, read-only, 20 October 2026. Digests are checked in jentra_platform.
const freezeText =
    '00000000-0000-4000-8000-000000000002:'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:21,'
    '00000000-0000-4000-8000-00000000000a:'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:1048576,'
    'ffffffff-0000-4000-8000-000000000001:'
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc:1';

const reportText =
    r'{"cutoff": "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd", '
    r'"period": ["2026-04-01", "2027-03-31"], '
    r'"summary": "Two findings.\nOne closed — résumé.", '
    r'"findings": [{"id": "10000000-0000-4000-8000-000000000001", '
    r'"title": "Back\\slash\ttab and \u0001 control", "status": "closed", '
    r'"owner_id": "30000000-0000-4000-8000-000000000002", "severity": "low"}, '
    r'{"id": "20000000-0000-4000-8000-000000000002", '
    r'"title": "Payments released by one \"signatory\"\nand café · ✓", '
    r'"status": "issued", "owner_id": "30000000-0000-4000-8000-000000000001", '
    r'"severity": "high"}], '
    r'"engagement_id": "40000000-0000-4000-8000-000000000001", '
    r'"report_version": 2}';

const emptyReportText =
    '{"cutoff": null, "period": ["2026-04-01", "2027-03-31"], '
    '"summary": "No findings", "findings": [], '
    '"engagement_id": "40000000-0000-4000-8000-000000000001", '
    '"report_version": 1}';

final evidence = [
  (
    id: '00000000-0000-4000-8000-00000000000a',
    sha256: 'b' * 64,
    byteSize: 1048576,
  ),
  (id: 'ffffffff-0000-4000-8000-000000000001', sha256: 'c' * 64, byteSize: 1),
  (id: '00000000-0000-4000-8000-000000000002', sha256: 'a' * 64, byteSize: 21),
];

final findings = [
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
];

void main() {
  test('the freeze text orders accepted evidence by id', () {
    expect(assuranceFreezeDigestText(evidence), freezeText);
    expect(assuranceFreezeDigestText(evidence.reversed), freezeText);
  });

  test('a freeze needs accepted evidence with valid digests', () {
    expect(() => assuranceFreezeDigestText(const []), throwsFormatException);
    expect(
      () => assuranceFreezeDigestText([
        (id: evidence.first.id, sha256: 'B' * 64, byteSize: 1),
      ]),
      throwsFormatException,
    );
    expect(
      () => assuranceFreezeDigestText([
        (id: evidence.first.id, sha256: 'b' * 64, byteSize: 0),
      ]),
      throwsFormatException,
    );
  });

  test('the report text matches jsonb text, escapes included', () {
    expect(
      assuranceReportDigestText(
        engagementId: '40000000-0000-4000-8000-000000000001',
        reportVersion: 2,
        cutoff: 'd' * 64,
        periodStart: '2026-04-01',
        periodEnd: '2027-03-31',
        findings: findings,
        summary: 'Two findings.\nOne closed — résumé.',
      ),
      reportText,
    );
  });

  test('a report without findings or cutoff still has a stable text', () {
    expect(
      assuranceReportDigestText(
        engagementId: '40000000-0000-4000-8000-000000000001',
        reportVersion: 1,
        cutoff: null,
        periodStart: '2026-04-01',
        periodEnd: '2027-03-31',
        findings: const [],
        summary: 'No findings',
      ),
      emptyReportText,
    );
  });
}
