import fs from 'node:fs';
import crypto from 'node:crypto';

const root = 'docs/verification/remaining-wave3/';
const prior = JSON.parse(fs.readFileSync(root + 'requirement-matrix-20260928.json', 'utf8'));
const spec = fs.readFileSync(prior.spec, 'utf8');
const specHash = crypto.createHash('sha256').update(spec).digest('hex');
if (specHash !== prior.spec_sha256 || prior.requirements.length !== 181) {
  throw new Error('Approved Wave 3 specification or extraction changed; review IDs before regenerating.');
}

const gaps = {
  'FR-318': 'Pipeline metrics are not integrated into the capability-aware command centre.',
  'FR-325': 'Reservation expiry and retirement need complete lifecycle integration beyond the bounded maintenance command.',
  'FR-354': 'Permitted expired-lot disposition command is absent.',
  'FR-355': 'Disposal and full serial disposition history are not implemented.',
  'FR-358': 'Counts over 500 tracked identities are rejected; partitioned count documents are absent.',
  'FR-359': 'Multi-receipt explicit allocation, held/transit split and later-consumption correction are absent.',
  'FR-361': 'Expiry/retirement maintenance is candidate-tested; all event-triggered releases are not verified.',
  'FR-364': 'The approved disposition posting source remains absent.',
  'FR-390': 'Dashboard has current document queues; aging, cash, close, budget and exception states are absent.',
  'FR-393': 'Broader contextual links and command-palette deep-link restoration remain incomplete.',
  'AC-314': 'Disposition path is missing.',
  'AC-315': 'Landed allocation/correction, oversized count partitioning and lifecycle coverage are incomplete.',
  'AC-316': 'Disposition journal source is absent.',
  'AC-323': 'Role dashboard breadth is incomplete.',
  'AC-324': 'Notification breadth and deep-link restoration remain incomplete.',
  'AC-326': 'Approved implementation and full release gate remain open.',
  'EC-324': 'Disposition-side serial uniqueness/reuse path is absent.',
  'EC-326': 'Count cutoff is tested, but oversized partition path is absent.',
  'EC-327': 'Multi-line allocation basis and line-specific failure cases remain absent.',
};
const nfrGaps = {
  307: 'Target-scale indexed read p95 was not measured.',
  308: 'Target-scale command and posting p95 was not measured.',
  309: 'The specified 500-tenant, 10-entity, 25-warehouse, 100k-product, 10m-movement and 20m-journal fixture was not run.',
  310: 'Representative target-scale query plans are missing; three synthetic control reads are only diagnostics.',
  312: 'Independent authenticated concurrent sessions were not exercised.',
  314: 'Full keyboard, screen-reader and reduced-motion review is missing.',
  315: 'Current operational detail has all four sizes at 200%; all Wave 3 screens and mode combinations are not verified.',
  316: 'Observability coverage for every listed signal is not audited.',
  317: 'Branch coverage targets and critical property-test coverage are not measured across the whole change.',
  318: 'Full security, rollback and genuine concurrency matrix is incomplete.',
  319: 'Authorized cold-launch and native visual/keyboard acceptance are outside this prompt.',
  320: 'Target-scale report p95 and progress/cancellation behavior are not verified.',
};
const verificationOverrides = {
  'FR-312': 'Configured file/notification fan-out needs item-by-item source and security review.',
  'FR-334': 'Full source/allocation/credit drill-through and native dated-report proof are missing.',
  'FR-349': 'Full bill/credit/allocation/payment drill-through and native dated-report proof are missing.',
  'FR-360': 'Broader lot/transit value history and target-scale reconciliation remain unproven.',
  'FR-382': 'Metadata and lineage have not been audited item by item for every report.',
  'FR-383': 'Every workspace and command-palette destination has not been audited for scoped routing.',
  'FR-384': 'Timeline, approval and audit context is not verified on every detail screen.',
  'FR-385': 'Keyboard traversal, unsaved changes and preview behavior are not verified on every form.',
  'FR-392': 'Configured recipient notification records are not verified across every listed lifecycle event.',
  'FR-395': 'Cross-module failure-state and encrypted recovery audit is incomplete.',
  'AC-301': 'Notification and cross-module command security coverage is incomplete.',
  'AC-320': 'Report lineage and bank/party native review are incomplete.',
  'AC-321': 'Complete workspace/form keyboard and visual audit is open.',
  'AC-322': 'Cross-module encrypted recovery and access audit is open.',
  'AC-325': 'Target-scale, real contention and observability verification are missing.',
  'EC-334': 'Genuine independent-session match race is not verified.',
  'EC-338': 'All report kinds and unsupported cutoff boundaries are not audited.',
  'EC-339': 'All synchronous report bounds and cancellation paths are not audited.',
  'EC-340': 'Full encrypted-store exhaustion/restart behavior is not verified.',
};
for (const [id, gap] of Object.entries(nfrGaps)) {
  verificationOverrides[`NFR-${id}`] = gap;
}

const proc = root + 'final-procurement-20260929.json';
const ar = root + 'inventory-receivables-20260929.json';
const stock = root + 'inventory-suite-20260929.json';
const desktop = 'build/remaining-wave3/desktop-full-20260929.log';
const platform = 'packages/jentra_platform/test/operational_gateway_test.dart';
const visual = 'apps/jentra_desktop/test/operational_detail_visual_test.dart';
const external = 'Uninstalled development candidates; authenticated native acceptance and owner signoff pending.';
function suiteFor(id) {
  const kind = id.split('-')[0], n = Number(id.split('-')[1]);
  if (kind === 'FR') {
    if (n >= 383) return [desktop, platform, visual];
    if (n >= 350 && n <= 361) return [stock, proc, ar];
    if (n >= 326 && n <= 334) return [ar, proc];
    return [proc, ar];
  }
  if (kind === 'NFR') return n >= 307 ? [proc, ar, stock, visual] : [proc, ar, stock];
  if (kind === 'AC' && n >= 321 && n <= 324) return [desktop, platform, visual];
  if (kind === 'AC' && [313, 314, 315].includes(n)) return [stock, proc, ar];
  return [proc, ar, stock];
}
const rows = prior.requirements.map(r => {
  const missing = gaps[r.id] ?? null;
  const feature = r.source_evidence.startsWith('supabase/tests/') && fs.existsSync(r.source_evidence)
    ? r.source_evidence : null;
  const evidence = [feature, ...suiteFor(r.id)].filter(Boolean);
  let missingVerification = 'Requirement-specific source/security review and installed authenticated native acceptance remain open.';
  if (verificationOverrides[r.id]) {
    missingVerification = verificationOverrides[r.id];
  } else if (missing) {
    missingVerification = 'Candidate-level tests cover adjacent behavior; the named implementation gap has no end-to-end proof.';
  } else if (r.id.startsWith('FR-') && Number(r.id.slice(3)) >= 383) {
    missingVerification = 'Focused client checks exist; full desktop suite and native acceptance are not clean.';
  } else {
    missingVerification = 'Synthetic strict-rollback regression passed; installed, target-scale and native proof remain open.';
  }
  return {
    id: r.id,
    approved_behavior: r.statement,
    implementation: missing ? 'partial' : 'candidate_present',
    missing_implementation: missing,
    evidence,
    missing_verification: missingVerification,
    external_acceptance: external,
  };
});
const out = {
  generated_on: '2026-09-29',
  spec: prior.spec,
  spec_sha256: specHash,
  boundary: 'Evidence references prove only their specific candidate checks. A candidate-present row is not a native or owner acceptance claim.',
  counts: Object.fromEntries(['FR', 'AC', 'EC', 'NFR'].map(k => [k, rows.filter(r => r.id.startsWith(k + '-')).length])),
  requirements: rows,
};
const md = [
  '# Wave 3 approved requirement-to-evidence matrix',
  '',
  'All 181 approved FR, AC, EC and NFR IDs are included. Candidate evidence is synthetic and rolled back. A `candidate_present` status means no code gap was confirmed in this review; it is not installed or signed-in proof. The source/test links are review evidence, not a substitute for the approved behavior.',
  '',
  '| ID | Approved behavior | Candidate state | Evidence | Missing implementation | Missing verification | External acceptance |',
  '|---|---|---|---|---|---|---|',
  ...rows.map(r => `| ${r.id} | ${r.approved_behavior.split('**Covers:**')[0].replaceAll('|', '/')} | ${r.implementation} | ${r.evidence.map(p => `[${p.split('/').at(-1)}](../../../${p})`).join(', ')} | ${(r.missing_implementation ?? 'No specific gap confirmed').replaceAll('|', '/')} | ${r.missing_verification.replaceAll('|', '/')} | ${r.external_acceptance} |`),
  '',
  'The JSON companion preserves the full approved wording and specification hash for each row.',
];
fs.writeFileSync(root + 'requirement-matrix-20260929.json', JSON.stringify(out, null, 2) + '\n');
fs.writeFileSync(root + 'requirement-matrix-20260929.md', md.join('\n') + '\n');
console.log(JSON.stringify({total: rows.length, counts: out.counts, partial: rows.filter(r => r.implementation === 'partial').length, spec_sha256: specHash}));
