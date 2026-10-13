import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const folder = 'docs/verification/wave5/task3-acceptance-20261013';
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const bind = path => ({path, sha256: sha(fs.readFileSync(path))});
const matrixPath = `${folder}/delegated-technical-acceptance-matrix.json`;
const matrix = JSON.parse(fs.readFileSync(matrixPath, 'utf8'));
const open = matrix.rows.filter(row => !row.accepted);
assert.equal(open.length, 86);

const prerequisites = [
  {id: 'P0', input: 'Current shared source ownership and exact approved target', action: 'Coordinate with the live owning chat before any shared or live change; bind current source, approved migration/function lists and provider revisions.'},
  {id: 'P1', input: 'Genuine independent actors and permission controls', action: 'Privately prepare permitted/forbidden tenant/entity/branch sessions, source capability and entitlement changes, a distinct MFA approver, and the separately authorized MFA operator.'},
  {id: 'P2', input: 'Authoritative historical source snapshots', action: 'Prepare scoped transition history, opportunity revisions, matching financial statements, obligation residuals and retained manifests; record source versions and controlled late commit/backfill cases.'},
  {id: 'P3', input: 'Reviewed private providers and actual external transport', action: 'Use the owning chat for private provider configuration and bounded worker routing repair; verify deployed readback, actual signed receipts, safe destinations and reconciled invocation/usage outcomes.'},
  {id: 'P4', input: 'Exact Connected Windows package and new private profile', action: 'Privately provision the exact approved account/package/profile and complete Connected sign-in/MFA; then execute the native protocol. Secure-store/disk-full cases require a separately reviewed reversible failure harness.'},
  {id: 'P5', input: 'Independent contention and target workload readiness', action: 'Privately prepare the reviewed PostgreSQL transport and genuine sessions, complete no-egress observation and job quiescence; execute every named committed race and the 500-company/2,000-session measured protocol.'},
  {id: 'P6', input: 'Current source quality and complete coverage evidence', action: 'Under the owning chat SDK schedule, bind all current source/provider inputs and complete deterministic fixtures, critical branch coverage, analysis and native variant evidence.'},
];

const groups = [
  {id: 'G0', name: 'Shared ownership and change attribution', prerequisites: ['P0'], rows: 'FR-533 FR-560 AC-516 EC-515', next: 'Bind ownership refresh for every shared integration and preserve the historical first-domain step.'},
  {id: 'G1', name: 'Scope, source permissions and protected data', prerequisites: ['P0', 'P1', 'P4'], rows: 'FR-501 FR-503 FR-504 NFR-501 NFR-507 AC-501 EC-501 FR-557 NFR-553 AC-554 EC-556', next: 'Run the complete allowed/denied/revoked actor matrix and zero-leak field scans; include immediate clearing in the actual native client.'},
  {id: 'G2', name: 'Authoritative analytics history and exact financial basis', prerequisites: ['P0', 'P1', 'P2'], rows: 'FR-505 FR-506 FR-509 FR-510 FR-511 FR-512 FR-513 FR-514 NFR-502 NFR-510 AC-504 AC-505 EC-504 EC-505 FR-552', next: 'Capture genuine complete source manifests, exercise late commit/backfill, reproduce all supported metrics and financial residuals, and retain freeze/readback basis.'},
  {id: 'G3', name: 'Governed exports and notification contracts', prerequisites: ['P1', 'P2', 'P3'], rows: 'FR-515 FR-535 AC-506 EC-506', next: 'Create, download, hash and reopen actual governed exports; test permission changes, retained basis and workflow/outbox integration.'},
  {id: 'G4', name: 'AI retrieval, approvals, execution and usage', prerequisites: ['P0', 'P1', 'P2', 'P3'], rows: 'FR-516 FR-517 FR-518 FR-519 FR-520 AC-507 AC-508 AC-509 EC-507 EC-508', next: 'Use the complete private provider coordinator with malicious retrieval fixtures, distinct MFA approval, stale/expired/revoked denials and settled invocation retries.'},
  {id: 'G5', name: 'Actual worker delivery and external commands', prerequisites: ['P0', 'P1', 'P3'], rows: 'FR-521 FR-522 FR-523 AC-510 AC-511 EC-509 EC-510', next: 'After the bounded routing repair, capture real signed attempts, receipt/retry/dead-letter/replay and credential/schema/idempotency/unsafe-destination denials.'},
  {id: 'G6', name: 'Entitlements, trusted metering, quotas and seats', prerequisites: ['P0', 'P1', 'P5'], rows: 'FR-524 FR-525 FR-526 AC-512 AC-513 EC-511', next: 'Run audited effective-time transitions, deduplicated corrections and independently overlapping seat/quota reservations without billing effects.'},
  {id: 'G7', name: 'Authorized operator access and measured health', prerequisites: ['P1', 'P3'], rows: 'FR-527 FR-528 FR-529 AC-514 EC-512', next: 'Use the separate MFA operator and reasoned expiring grant; verify owner/cross-tenant denial, immutable audit and stopped-probe unknown health.'},
  {id: 'G8', name: 'Authenticated native workflows, keyboard and recovery', prerequisites: ['P0', 'P1', 'P2', 'P3', 'P4'], rows: 'FR-530 FR-531 NFR-508 AC-515 EC-513 FR-558 FR-559 AC-556 EC-558', next: 'Execute actual Connected workflows, keyboard/focus variants, encrypted restart/context/revocation/offline recovery and safe isolated failure cases.'},
  {id: 'G9', name: 'Limits, resumable jobs, concurrency and measured load', prerequisites: ['P0', 'P1', 'P2', 'P3', 'P5'], rows: 'FR-502 FR-508 NFR-503 NFR-504 NFR-505 NFR-506 AC-503 EC-514 NFR-552 AC-555 EC-557', next: 'Exercise complete installed page/group/output limits and cancellation/crash boundaries; record every genuine committed race and target workload P95.'},
  {id: 'G10', name: 'Complete provider readiness and current quality', prerequisites: ['P0', 'P1', 'P2', 'P3', 'P4', 'P5', 'P6'], rows: 'FR-532 NFR-509 NFR-554 AC-558', next: 'Close readiness/version drift, deterministic per-requirement fixtures and critical coverage only after each provider and native evidence set is complete.'},
].map((group, index) => ({...group, suggestedOrder: index + 1, rowIds: group.rows.split(' ')}));

const assignments = new Map();
for (const group of groups) {
  for (const id of group.rowIds) {
    assert.ok(!assignments.has(id), `Duplicate group assignment ${id}`);
    assert.ok(open.some(row => row.id === id), `Assigned row is not open: ${id}`);
    assignments.set(id, group);
  }
  delete group.rows;
  group.rowCount = group.rowIds.length;
}
assert.equal(assignments.size, 86);
assert.ok(open.every(row => assignments.has(row.id)));
const validPrerequisites = new Set(prerequisites.map(item => item.id));
for (const group of groups) assert.ok(group.prerequisites.every(id => validPrerequisites.has(id)));
const rowMap = open.map(row => {
  const group = assignments.get(row.id);
  return {id: row.id, statementSha256: row.statementSha256, decision: row.decision, accepted: false, primaryGroup: group.id, prerequisites: group.prerequisites, exactRemainingEvidence: row.nextEvidence};
});
const evidencePaths = [
  'docs/verification/wave5/task3-windows-20261013/native-acceptance-protocol.md',
  'docs/verification/wave5/task3-windows-20261013/native-prerequisites-20261013T182346876Z.json',
  'docs/verification/wave5/task3-load-release-20261013/release-audit.md',
  'docs/verification/wave5/task3-load-release-20261013/README.md',
  'docs/verification/wave5/task3-completion-20261013/owner-delegation.json',
];
const report = {
  kind: 'wave5-open-requirement-prerequisite-map', recordedAt: new Date().toISOString(),
  decisionMatrix: bind(matrixPath), openCount: 86, groupedRowCount: assignments.size,
  originalHumanAccepted: 3, delegatedTechnicalAccepted: 20, totalAccepted: 23,
  acceptanceDecisionsAdded: 0, liveActionsPerformed: 0, SDKExecuted: false,
  guidance: 'The sequence shows practical prerequisites; independent preparation can run in parallel. Group membership is a planning aid, not evidence. Every row remains open until its complete statement and exact gap are satisfied.',
  authorityBoundary: 'Technical delegation permits evidence-based review. The live owning chat retains coordinated private/live actions; passwords, MFA, security prompts and production actions are not simulated or treated as completed.',
  productionRelease: 'Production release is a separate Wave 6 gate: authorized separate staging/production, migration rehearsal, isolated restore, monitoring/alert receipt, performance/accessibility certification, signed MSIX and controlled pilot evidence remain required.',
  prerequisites, groups, rows: rowMap, inputBindings: evidencePaths.map(bind),
};
const jsonPath = `${folder}/open-requirement-prerequisites.json`;
const mdPath = `${folder}/open-requirement-prerequisites.md`;
fs.writeFileSync(jsonPath, JSON.stringify(report, null, 2) + '\n');
const md = [
  '# Wave 5 remaining requirement prerequisites', '',
  '**86 requirements remain open.** This map assigns each to one primary work group and records its prerequisite inputs. The final acceptance count remains 23 of 109: 3 original human decisions and 20 delegated technical decisions.', '',
  '| Input | Required preparation |', '|---|---|',
  ...prerequisites.map(item => `| ${item.id}: ${item.input} | ${item.action} |`), '',
  '| Suggested order | Work group | Rows | Prerequisites | Next evidence |', '|---|---|---|---|---|',
  ...groups.map(group => `| ${group.suggestedOrder} | ${group.name} | ${group.rowCount}: ${group.rowIds.join(', ')} | ${group.prerequisites.join(', ')} | ${group.next} |`), '',
  'Prepare independent inputs in parallel. Follow each exact row gap in the [decision matrix](delegated-technical-acceptance-matrix.md); primary grouping does not waive secondary requirements or imply acceptance.', '',
  '[Exact row-to-prerequisite map and input hashes](open-requirement-prerequisites.json). Actual native execution uses the Windows agent protocol; measured concurrency/load uses the separately reviewed private runtime protocol under the live owning chat.', '',
  report.productionRelease, '',
].join('\n');
fs.writeFileSync(mdPath, md);
const checked = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
assert.equal(checked.rows.length, open.length);
assert.equal(new Set(checked.rows.map(row => row.id)).size, 86);
assert.equal(checked.groups.reduce((sum, group) => sum + group.rowCount, 0), 86);
assert.equal(checked.acceptanceDecisionsAdded, 0);
assert.equal(checked.decisionMatrix.sha256, bind(matrixPath).sha256);
for (const row of checked.rows) {
  const source = open.find(item => item.id === row.id);
  assert.equal(row.statementSha256, source.statementSha256);
  assert.equal(row.exactRemainingEvidence, source.nextEvidence);
  assert.equal(row.accepted, false);
}
for (const input of checked.inputBindings) assert.equal(bind(input.path).sha256, input.sha256);
const validation = {kind: 'open-requirement-prerequisite-map-validation', validatedAt: new Date().toISOString(), passed: true, exactOpenRows: 86, uniquePrimaryAssignments: 86, groupCount: 11, acceptanceDecisionsAdded: 0, json: bind(jsonPath), markdown: bind(mdPath), matrixUnchanged: bind(matrixPath)};
fs.writeFileSync(`${folder}/open-requirement-prerequisites-validation.json`, JSON.stringify(validation, null, 2) + '\n');
console.log(JSON.stringify(validation, null, 2));
