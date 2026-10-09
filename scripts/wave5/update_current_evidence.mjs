import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const evidence = path.join(root, 'docs/verification/wave5');
const rel = (p) => path.join(root, p);
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
const read = async (p) => readFile(rel(p), 'utf8');
const write = async (p, value) => writeFile(rel(p), `${value.replace(/\r?\n*$/, '')}\n`, 'utf8');
const jsonRead = async (p) => JSON.parse(await read(p));
const jsonWrite = async (p, value) => write(p, JSON.stringify(value, null, 2));
const now = new Date().toISOString();

const strictPath = 'docs/verification/wave5/remaining-candidate-final-result-20261008.json';
const hashesPath = 'docs/verification/wave5/remaining-candidate-20261008.hashes.json';
const livePath = 'docs/verification/wave5/live-refresh-confirmed-20261008.json';
const reviewJsonPath = 'docs/verification/wave5/continuation-review-20261008.json';
const reviewMdPath = 'docs/verification/wave5/continuation-review-20261008.md';
const matrixJsonPath = 'docs/verification/wave5/requirement-matrix-20261008.json';
const matrixMdPath = 'docs/verification/wave5/requirement-matrix-20261008.md';
const summaryPath = 'docs/verification/wave5/continuation-evidence-summary-20261008.json';
const runtimeLabelsPath = 'docs/verification/wave5/designated-runtime-labels-20261008.json';

const strict = await jsonRead(strictPath);
const candidateHashes = await jsonRead(hashesPath);
const live = await jsonRead(livePath);
if (strict.project !== 'xpdoufauvrbdmxgngetv' || strict.assertions !== 116 ||
    strict.passed !== 116 || !strict.strictFinish || !strict.rolledBack ||
    strict.installedMigrationsReplayed || strict.installedBehaviorClaimed ||
    strict.querySha256 !== candidateHashes.querySha256) {
  throw new Error('Strict rollback evidence does not match the prepared candidate composition');
}
if (live.project !== 'xpdoufauvrbdmxgngetv' || live.migrationCount !== 43 ||
    live.apiFunctions !== 107 || live.candidateCashTableInstalled ||
    live.reviewCandidateMigrationsInstalled.length !== 0) {
  throw new Error('Fresh connected Supabase baseline does not match the continuation state');
}

const bundles = {
  shared: [
    'Installed Wave 5 foundation remains intact; exact candidate scope, hashes and rollback permissions were rechecked. New candidate tables are still absent from the live project.',
    'Keep all new candidates uninstalled under the current owner decision. Before any later installation, review the exact source package and its separately owned Wave 3 prerequisites; then collect authenticated source access, revocation, foreign-scope and real MFA evidence.'
  ],
  process: [
    'Installed process provider remains intact; exact domain, gateway, encrypted filters and workspace checks remain evidenced.',
    'Real authenticated process access, native restart, required keyboard/viewports, target-scale latency and owner acceptance remain open. Stage dwell/work/rework remain uncertified.'
  ],
  pipeline: [
    'Historical conversion, open-stage aging/velocity and frozen-cohort realized-result adapters plus the native workspace are implemented as uninstalled candidates. Nonempty invoice/order/credit SQL mapping passes the strict rollback composition.',
    'The candidates remain uninstalled. Real authenticated historical/forecast acceptance is open; revision gaps fail closed, and rollback fixtures do not establish installed behavior.'
  ],
  finance: [
    'Six named exact ratios consume matching immutable Wave 3 statements and an MFA-reviewed account classification; candidate SQL and adapter forms are present.',
    'The Wave 3 statement sources and Wave 5 classifier remain uninstalled candidates. Publish reviewed classifications and verify real nonzero ratio cases against statement drill-through under authenticated native access.'
  ],
  cash: [
    'Uninstalled candidates cover dated bank cash and permission-gated residual AR/AP with allocation and reversal evidence, immutable scenario assumptions/overrides, encrypted uncertain-command recovery, and governed export metadata/reopen paths. Payroll and project-reimbursement cash dates remain unavailable.',
    'Full cash forecasting remains incomplete because payroll and approved project-reimbursement sources do not define authoritative payment due dates; project billing milestones do not establish cash-out dates before invoicing. The cash-screen/gateway edits have no post-edit Flutter analysis, test, render or build evidence. Real authenticated export bytes/download/reopen also remain open.'
  ],
  ai: [
    'Reviewed numeric-only redaction, strict model output/counting and durable trusted-usage adapters are implemented as candidates; installed human-proposal controls are retained.',
    'A separate exact provider/model/policy review, secret provisioning and deployment are still required. No model call occurred. Verify distinct real MFA approval, revocation, stale/changed cohorts, overlapping execution, trusted usage and unknown-outcome reconciliation.'
  ],
  integration: [
    'Candidate sources cover scoped registration, key rotation/revocation, committed-outbox leases, immutable attempts/outcomes, reviewed replay, atomic throttle/quota, named dispatch and scheduling.',
    'Candidate installation, receiver/host/vault/credential provisioning and worker deployment require separate review. Actual signed delivery, receiver idempotency, restart reconciliation, dead letters/replay and independent-session races remain unproved; controlled transports are not delivery evidence.'
  ],
  billing: [
    'Installed synthetic subscription/metering controls remain intact; bounded due-revision scheduling and persistent invocation adapters are candidates.',
    'Choose and review separate synthetic actor labels and any private tenant/plan/role/entitlement bootstrap before provisioning. No entitlement activation or real billing is authorized; prove boundaries, overlapping quota/seat/admission races and trusted settlement later.'
  ],
  operator: [
    'Installed operator isolation remains intact; the candidate health collector uses durable queue/quota projections and preserves unknown missing quotas.',
    'A distinct operator identity and exact expiring selected-tenant grant/deployment review remain open. No operator or grant exists; real probes, owner denial, MFA, expiry and access audit remain unverified.'
  ],
  native: [
    'Seven analytics workspaces are implemented. The dated-cash workspace and gateway changed after the last platform/native test, render, analyzer and Windows build evidence.',
    'Rerun serialized Flutter checks and inspect fresh rendered frames only after SDK approval is available. Real authenticated launch, restart, delayed revocation, export creation/download/reopen, keyboard reachability at prescribed viewports and owner review remain open. The 13 shared dashboard/setup golden failures remain investigated but unresolved.'
  ],
  provider: [
    'Historical CRM, realized results, statement classifications, dated bank/AR/AP cash, scenario/export, persistent integration and trusted-usage adapters are implemented as uninstalled candidates.',
    'Complete dated payroll/project-reimbursement sources and authenticated provider/cache behavior remain open. Unavailable-provider cards and injected policy tests do not count as completed runtime features.'
  ],
  ownership: [
    'The six previously approved migrations remain installed and untouched. The refreshed live ledger has 43 entries and 107 API functions; the candidate cash table and eight review migrations are absent. The eight-file candidate composition has current source hashes.',
    'The owner selected keeping the eight-file package uninstalled for review. Preserve the separately owned Wave 3/4 sources and acceptance stores; never replay the original six connector-mapped migrations.'
  ],
  quality: [
    'The strict candidate composition passes 116 rollback-only SQL assertions. The last domain and worker runs passed 71 and 31 checks. Earlier platform 41/native 90 counts, analyzer, renders and Windows attribution predate the latest cash-screen/gateway edits and are stale for current source.',
    'Run fresh platform/native tests, analyzer, source-attributed Windows build and cash workspace renders when the SDK command can be reviewed. Keep the 13 shared golden failures visible; no golden was regenerated. Real export/model/log privacy scans, authenticated runtime, contention/load and owner signoff remain open.'
  ],
  load: [
    'Bounded source limits and atomic SQL lock/reservation behavior are verified in rollback-only candidates; no independent-session or target-scale run has occurred.',
    'Use distinct authenticated sessions with a barrier and record overlap and before/after effects, quota/seat/throttle limits and duplicates. Publish hardware/workload and p95 at 500 tenants/2,000 sessions; no test identities or timings are inferred.'
  ]
};

const bundleEvidence = {
  pipeline: ['supabase/tests/wave5_realized_mapping_test.sql'],
  cash: ['supabase/tests/wave5_remaining_adapters_test.sql', 'packages/jentra_platform/lib/src/analytics/dated_cash_gateway.dart', 'apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart'],
  native: ['apps/jentra_desktop/lib/src/features/analytics/cash_scenario_screen.dart', 'packages/jentra_platform/lib/src/analytics/dated_cash_gateway.dart'],
  ownership: ['docs/verification/wave5/live-refresh-confirmed-20261008.json'],
  quality: [strictPath, 'docs/verification/wave5/shared-golden-investigation-20261008.md']
};
const commonEvidence = [reviewMdPath, strictPath, 'docs/verification/wave5/continuation-live-final-20261008.json'];
const matrix = await jsonRead(matrixJsonPath);
const oldMatrixMd = await read(matrixMdPath);
const titles = Object.fromEntries([...oldMatrixMd.matchAll(/<a id="evidence-([^"]+)"><\/a>\s*## ([^\n]+)/g)].map((m) => [m[1], m[2].trim()]));
if (matrix.rows.length !== 109 || Object.keys(titles).length !== Object.keys(bundles).length) {
  throw new Error('Requirement identities or evidence-bundle headings changed');
}
for (const row of matrix.rows) {
  if (row.ownerAccepted) throw new Error(`Unexpected owner acceptance on ${row.id}`);
  [row.developmentStatus, row.remaining] = bundles[row.bundle];
  for (const p of [...commonEvidence, ...(bundleEvidence[row.bundle] || [])]) {
    if (!row.evidence.includes(p)) row.evidence.push(p);
  }
}
matrix.updatedAt = now;
matrix.requirementCount = 109;
matrix.ownerAcceptedCriteria = 0;
matrix.wholeWaveComplete = false;
matrix.installationComplete = true;
matrix.continuationResult = reviewMdPath;
matrix.continuationChecks = {
  candidateSql: 116,
  domainLastVerified: 71,
  platformLastVerified: 41,
  nativeLastVerified: 90,
  workerLastVerified: 31,
  platformAndNativeCurrentSource: false,
  analyzerCurrentSource: false,
  windowsBuildCurrentSourceMatch: false
};
matrix.authenticatedNativeAcceptance = false;
matrix.actualWorkerDelivery = false;
matrix.independentSessionContention = false;
matrix.targetScaleLoad = false;
await jsonWrite(matrixJsonPath, matrix);

const matrixLines = [
  '# Wave 5 requirement matrix - October 8, 2026', '',
  'All 109 approved identifiers remain mapped, with zero owner-accepted criteria. A fresh connector read confirms 43 installed migrations and 107 API functions; the eight review migrations and candidate cash table remain absent. The original installation report holds the 126 installed SQL checks. The separate eight-file candidate composition passes 116 strict rollback-only checks; it is not installed. The owner chose to keep it uninstalled for review. [Live refresh](live-refresh-confirmed-20261008.json) and [candidate review](continuation-review-20261008.md).', '',
  'The last domain and worker runs passed 71 and 31 checks. The prior platform 41/native 90 counts, analyzer, rendered frames and source-attributed Windows build predate the latest cash-screen/gateway changes, so they are not current-source evidence. Authenticated native acceptance, actual worker delivery, contention, target-scale load and owner signoff remain open. Full cash coverage is incomplete.', '',
  '| ID | Evidence bundle | Current status |', '|---|---|---|'
];
for (const row of matrix.rows) matrixLines.push(`| ${row.id} | [${titles[row.bundle]}](#evidence-${row.bundle}) | ${row.developmentStatus} |`);
for (const [bundle, title] of Object.entries(titles)) {
  const rows = matrix.rows.filter((r) => r.bundle === bundle);
  const evidence = [...new Set(rows.flatMap((r) => r.evidence))];
  matrixLines.push('', `<a id="evidence-${bundle}"></a>`, `## ${title}`, '', `${bundles[bundle][0]}.`, '',
    `Evidence: ${evidence.map((p) => `[${path.basename(p)}](../../../${p})`).join(', ')}.`, '',
    `Remaining: ${bundles[bundle][1]}`);
}
await write(matrixMdPath, matrixLines.join('\n'));

const review = await jsonRead(reviewJsonPath);
review.preparedAt = now;
review.installationAuthorized = false;
review.additionalMigrationsInstalled = false;
review.originalInstalledSixExcluded = true;
review.ownerDecision = 'keep the eight new candidates uninstalled for review';
review.liveRefresh = live;
review.candidateQuerySha256 = candidateHashes.querySha256;
review.nonemptyRealizedSqlEvidence = true;
review.developmentChecks = {
  ...review.developmentChecks,
  candidateSql: strict.passed,
  analyzerClean: false,
  buildSourceMatches: false,
  platformAndNativeCurrentSource: false,
};
if (review.currentSourceSdkEvidence) review.currentSourceSdkEvidence.currentSource = false;
review.candidateVerification = {
  querySha256: candidateHashes.querySha256,
  assertions: 116,
  passed: 116,
  strictFinish: true,
  rolledBack: true,
  installedMigrationsReplayed: false,
  installedBehaviorClaimed: false
};
for (const candidate of review.candidatesInOrder) {
  const sourceHash = candidateHashes.candidateSources[candidate.path];
  if (!sourceHash) throw new Error(`Missing candidate hash for ${candidate.path}`);
  candidate.bytesSha256 = sourceHash;
  candidate.normalizedSqlSha256 = sourceHash;
  if (candidate.path.endsWith('wave5_dated_cash.sql')) candidate.purpose = 'Immutable dated bank cash and permission-gated residual AR/AP after allocations and reversals; scenario sources; payroll and project reimbursement dates remain incomplete.';
  if (candidate.path.endsWith('wave5_governed_export_adapter.sql')) candidate.purpose = 'Extends the W3 export contract for frozen pipeline and scenario sources, including AP outflows and source-hash checks on reopen.';
}
await jsonWrite(reviewJsonPath, review);

const runtimeLabels = await jsonRead(runtimeLabelsPath);
runtimeLabels.requiredActorLabelsConfirmed = false;
runtimeLabels.roleLabelProposal = {
  status: 'proposal only; no account, session, role or tenant was provisioned',
  labels: {
    proposer: 'w5-proposer',
    mfaApprover: 'w5-approver',
    executor: 'w5-executor',
    billingAdministrator: 'w5-billing-admin',
    operator: 'w5-operator',
    foreignTenantMember: 'w5-foreign-member'
  },
  placement: 'Use distinct accounts in the existing Jentra Acceptance Lab for the first five roles. Place the foreign member only in a separately reviewed synthetic tenant; no such second tenant is selected or created by this proposal.',
  existingLiveSmokeAccount: 'test@test.com'
};
await jsonWrite(runtimeLabelsPath, runtimeLabels);

let reviewMd = (await read(reviewMdPath)).replace(/\r\n/g, '\n');
const replaceExact = (source, from, to, label) => {
  const count = source.split(from).length - 1;
  if (count === 0 && source.includes(to)) return source;
  if (count !== 1) throw new Error(`Expected one ${label} paragraph, found ${count}`);
  return source.replace(from, to);
};
reviewMd = replaceExact(reviewMd,
  '**State:** review package only. No additional migrations have been installed. This review requests installation approval for exactly the eight files below; it does not request or imply bootstrap, grants, entitlements, key provisioning, worker deployment, provider calls, outbound delivery, or production use.',
  '**State:** review package only. No additional migrations have been installed. The owner chose to keep these eight candidates uninstalled for review; this update requests no installation or provisioning. The package does not authorize bootstrap, grants, entitlements, key provisioning, worker deployment, provider calls, outbound delivery, or production use.', 'review state');
reviewMd = reviewMd.replace('129e74d8fed878cc3d812b64092c8b181e26f567945b68a2d283b8e76a58cf51', candidateHashes.querySha256)
  .replace('**All 100 checks passed in that rollback transaction.**', '**All 116 checks passed in that strict rollback transaction.**');
reviewMd = reviewMd.replace(/\| (\d+) \| `([^`]+)` \| `[a-f0-9]{64}` \|/g, (line, order, file) => {
  const hash = candidateHashes.candidateSources[file];
  return hash ? `| ${order} | \`${file}\` | \`${hash}\` |` : line;
});
reviewMd = reviewMd.replace('Immutable dated bank cash and positive AR basis, encrypted-client scenario support endpoints and immutable scenario revisions. Does **not** certify all obligation families.',
  'Immutable dated bank cash and permission-gated AR/AP residuals after allocations and reversals, plus scenario support and immutable revisions. Does **not** certify all obligation families.');
reviewMd = reviewMd.replace(/^The fixture also replays[\s\S]*?synthetic SQL records\.$/m,
  'The fixture composes the installed process-metrics provider and candidate adapters inside one strict rollback, without replaying any installed Wave 5 migration. The 116 assertions cover nonempty immutable invoice/order/credit realization, dated bank and AR/AP residuals, allocation reversals, permission loss, immutable scenario recovery/export metadata, source scope, model/usage and integration contracts, and forced-RLS/client-grant boundaries. A test-only `finance.allocation_reversals` shape shim exists only inside the transaction because the separately owned Wave 3 correction provider is not installed; it is rolled back. No synthetic SQL records persist, and the fixture does not perform native file delivery, model calls or webhook sends.');
reviewMd = reviewMd.replace(/^The read-only refresh at `2026-10-07T23:29:22Z`[\s\S]*?not in the package\.$/m,
  'The [fresh connected Supabase read](live-refresh-confirmed-20261008.json) confirms **43 installed migrations, 107 API functions, zero of the eight review migrations installed, and no candidate cash table**. The earlier installed-catalog comparison recorded 15 Wave 5 tables with forced RLS and 120/120 unchanged API/core fingerprints. Those counts describe the installed baseline, not candidate behavior. The original six remain installed and excluded from the candidate package.');
reviewMd = reviewMd.replace('A fresh read-only refresh on October 8 confirms **43 installed migrations and 107 API functions**; the candidate cash table is absent. The earlier installed-catalog comparison recorded 15 Wave 5 tables with forced RLS and 120/120 unchanged API/core fingerprints. Those counts describe the installed baseline, not candidate behavior. The original six remain installed and excluded from the candidate package.',
  'The [fresh connected Supabase read](live-refresh-confirmed-20261008.json) confirms **43 installed migrations, 107 API functions, zero of the eight review migrations installed, and no candidate cash table**. The earlier installed-catalog comparison recorded 15 Wave 5 tables with forced RLS and 120/120 unchanged API/core fingerprints. Those counts describe the installed baseline, not candidate behavior. The original six remain installed and excluded from the candidate package.');
reviewMd = reviewMd.replace(/^Live tenant evidence identifies[\s\S]*?here\.$/m,
  'Live tenant evidence identifies `Jentra Acceptance Lab` (`jentra-acceptance-lab`) and one active account label, `test@test.com`, with one verified MFA factor. Repository rollback labels `owner`, `reader` and `outsider` are transaction-local fixtures, not separate live accounts; `test@lh.com` is absent from live membership. Proposed distinct labels are `w5-proposer`, `w5-approver`, `w5-executor`, `w5-billing-admin`, `w5-operator` and `w5-foreign-member`, with the foreign member scoped only to a second synthetic tenant. This is a naming proposal only: no accounts, role assignments or sessions were created, and the existing `test@test.com` account remains smoke-test-only. No passwords, tokens or credentials were read or included.');
reviewMd = reviewMd.replace(/^Approval would authorize only installation[\s\S]*?must not be replayed\.$/m,
  'If the owner later reopens installation review, approval would cover only these eight exact files, in the tested order, in development project `xpdoufauvrbdmxgngetv`. It would still not authorize user or tenant bootstrap, grants, entitlement changes, synthetic plan/trial activation, provider secrets, worker deployment, model requests, test-destination provisioning or external delivery. Real billing and production remain excluded. Any future installation requires a fresh ledger/catalog check and strict installed verification; the original six approved source files must not be replayed.');
reviewMd = reviewMd.replace('- Historical SQL currently exercises one immutable opportunity revision and an empty realized invoice cohort. Adapter tests cover signed invoices and credits, but a complete non-empty SQL invoice/order/return fixture remains open. A source revision gap fails closed.',
  '- The strict SQL composition includes nonempty posted invoice and order-linked credit-return mapping for a frozen opportunity cohort, exact signed gross, recorded cutoffs, immutable versions and a line-only return that fails closed. This remains rollback candidate evidence; live authenticated historical/forecast acceptance is still open.');
reviewMd = reviewMd.replace('- Cash currently covers dated bank cash and positive AR only. The corrected AP allocation provider is a separate uninstalled migration. W4 payroll and project obligation rows have posting/effect dates but no authoritative cash due date; this package does not infer one. **Full cash forecasting is incomplete.** A dated provider contract and implementation for all required families is still needed.',
  '- Candidate cash covers dated bank balances and permission-gated AR/AP residuals after immutable allocations and reversals. A test-only reversal-table shape shim is rolled back; no Wave 3 provider was installed. W4 payroll and approved project-reimbursement rows do not define authoritative payment due dates. A project milestone date is future billing evidence, not a cash-out obligation before invoicing. **Full cash forecasting remains incomplete** until those authoritative due-date sources exist and are verified.');
reviewMd = reviewMd.replace('- Native analysis workspaces exist. The last completed font-loaded render batch passed 89 cases before the final integration list selection/scope-clearing interaction was added. The latest 89-case attempt had one widget-test harness exception in scroll-target selection and 88 other cases passed; the selector has since been narrowed to the integration list\'s scrollable, **without a rerun**. The previously successful Windows executable predates that last native change and has no current-source match. Neither is final-source evidence.',
  '- Native workspaces exist, but the latest cash-screen and gateway edits postdate the previous platform/native tests, analyzer, font-loaded frames and Windows build. Those results are historical for the prior source and do not verify this cash change. Current-source Flutter verification and a fresh cash-workspace render are pending; the last Windows executable no longer matches current source.');
reviewMd = reviewMd.replace('- A fresh run of 31 controlled worker tests passed. Earlier domain/platform runs passed 71/71 and 41/41. Analyzer and native tests need a final-source rerun. The 13 shared dashboard/setup golden failures have a separate investigation; approved goldens were not changed.',
  '- The last domain and worker runs passed 71 and 31 checks; domain and worker sources were unchanged by the latest cash edit. The prior 41 platform and 90 native checks, analyzer and source-attributed build predate the edit and are stale for current Dart source. Flutter rechecks were not run after automatic approval review failed due to the usage limit. The 13 shared dashboard/setup golden failures have a separate investigation; no approved golden was changed.');
reviewMd = reviewMd.replace('[100-check rollback result]', '[116-check rollback result]')
  .replace('[live refresh and fingerprint comparison](continuation-live-final-20261008.json)', '[fresh live refresh](live-refresh-confirmed-20261008.json), [earlier catalog/fingerprint comparison](continuation-live-final-20261008.json)');
await write(reviewMdPath, reviewMd);

const statusPath = 'docs/development/wave5-status.md';
const status = `# Wave 5 development status

Updated October 8, 2026. **Wave 5 remains incomplete.** The six owner-approved Wave 5 migrations remain installed and untouched. The [fresh read-only connector refresh](../verification/wave5/live-refresh-confirmed-20261008.json) confirms 43 ledger entries and 107 API functions; the eight review migrations and new dated-cash table are absent. The original installation report records 126 strict installed SQL checks. The owner chose to keep the eight additional candidate files uninstalled for review; no installation, synthetic bootstrap, entitlement activation, secret provisioning, worker deployment or external delivery is authorized.

| Slice | Implemented candidate/source behavior | Remaining evidence or dependency |
|---|---|---|
| W5-01 Process | Installed exact process metrics provider, scoped reads, encrypted filters and native workspace retained | Authenticated synthetic access, restart/keyboard/runtime/load and owner review |
| W5-02 Pipeline | Immutable CRM history, conversion/open-stage aging/velocity and frozen-cohort realized results; nonempty invoice/order/credit SQL mapping passes strict rollback checks | New provider remains uninstalled; live authenticated historical/forecast acceptance |
| W5-03 Ratios and cash | Six named statement ratios; dated bank and permission-gated AR/AP residuals with allocations/reversals; immutable scenario assumptions/overrides, encrypted recovery and governed export source/reopen paths | W3 statement/export dependencies and six W5 candidates remain uninstalled. Payroll and project-reimbursement providers lack authoritative payment due dates, so full cash is incomplete. Real authenticated statement/export and native acceptance remain open |
| W5-04 AI controls | Reviewed numeric-only redaction, strict model response/counting and durable trusted-usage adapters; installed human-proposal controls retained | Exact model/provider policy review, separate secret/deployment review, actual usage, distinct MFA approver, revocation and overlapping execution |
| W5-05 Integrations | Candidate scoped storage, key rotation/revocation, committed-outbox lease/attempt/dead-letter/reviewed replay, atomic throttle/quota, named dispatch and scheduling | Candidate installation, receiver/host/vault/credential provisioning and worker deployment require separate review; actual delivery and contention remain open |
| W5-06 Billing | Installed synthetic subscription/metering authority retained; due-revision scheduler implemented | Separate review of synthetic tenant/actor/role/entitlement setup; actual worker and independent-session billing/quota tests |
| W5-07 Operator | Installed isolated operator control retained; candidate durable health collection | Distinct operator label, expiring grant review, deployment, actual probes and authenticated denial/MFA/expiry audit |
| W5-08 Acceptance | Six-migration installation gate evidenced; 116 strict rollback candidate checks; 109 requirement IDs retained | Post-edit Flutter analysis/tests/render/build, 13 shared golden failures, authenticated MFA/native/restart/revocation/export, actual worker/model, independent-session contention, 500-tenant/2,000-session load and owner signoff |

The current candidate composition is the two separately owned Wave 3 prerequisites followed by six additive Wave 5 migrations. Its ordered source hash and file hashes are recorded in [the review package](../verification/wave5/continuation-review-20261008.md) and [hash manifest](../verification/wave5/remaining-candidate-20261008.hashes.json). The strict \`finish(true)\` fixture passed 116 assertions and ended in \`rollback;\`; it exercised nonempty realized invoice/credit mapping and a test-only allocation-reversal schema shim. No candidate was installed and no Wave 3/4 source was replayed.

The dated-cash adapter now includes permission-gated AP residuals after allocations and reversal evidence. Full cash remains incomplete: current payroll and project-reimbursement contracts lack authoritative payment dates. Project milestone dates are future billing evidence and cannot be treated as cash-out dates before invoicing. The cash UI/gateway changed after the latest Flutter checks. Earlier domain 71 and worker 31 checks remain in scope; platform 41/native 90 counts, analyzer, rendered frames and Windows build are historical for the previous source and must be rerun before current-source claims. The 13 shared dashboard/setup golden failures remain investigated; no goldens were regenerated.

The live tenant evidence identifies Jentra Acceptance Lab and one active MFA-enabled label, \`test@test.com\`. That account remains smoke-test-only. Proposed distinct labels are \`w5-proposer\`, \`w5-approver\`, \`w5-executor\`, \`w5-billing-admin\`, \`w5-operator\` and \`w5-foreign-member\`; this proposal does not create identities or grant roles. Separate authenticated MFA approval, executor, billing administrator, operator and foreign-tenant sessions are unproved. No account secrets or sessions were read. Real billing and production are excluded; no broad staging, commit or push occurred.

See the [109-ID requirement matrix](../verification/wave5/requirement-matrix-20261008.md), [candidate review](../verification/wave5/continuation-review-20261008.md), [strict rollback result](../verification/wave5/remaining-candidate-final-result-20261008.json), [evidence summary](../verification/wave5/continuation-evidence-summary-20261008.json) and [integrated runtime protocol](../verification/wave5/integrated-runtime-protocol-20261006.md). The original [installation report](../verification/wave5/installation-result-20261008.md) maps the six installed filenames to connector-assigned versions. Do not replay those migrations.
`;
await write(statusPath, status);

const summary = {
  updatedAt: now,
  project: 'xpdoufauvrbdmxgngetv',
  wholeWaveComplete: false,
  installedMigrationCount: live.migrationCount,
  installedApiFunctions: live.apiFunctions,
  liveStateCheckedAt: live.checkedAt,
  newCandidatesInstalled: false,
  ownerDecision: 'keep candidates uninstalled for review',
  candidateSqlAssertions: 116,
  nonemptyRealizedSqlMapping: true,
  domainLastVerified: 71,
  platformLastVerified: 41,
  platformEvidenceCurrentSource: false,
  nativeLastVerified: 90,
  nativeEvidenceCurrentSource: false,
  workerLastVerified: 31,
  analyzerCurrentSource: false,
  windowsBuildCurrentSourceMatch: false,
  currentCashRenderAvailable: false,
  authenticatedNative: false,
  actualDelivery: false,
  contention: false,
  load: false,
  ownerAccepted: 0,
  fullCashProviders: false,
  payrollProjectPaymentDueDates: false,
  goldenFailures: 13
};
await jsonWrite(summaryPath, summary);

const matrixText = await read(matrixMdPath);
const reviewText = await read(reviewMdPath);
const statusText = await read(statusPath);
const strictText = await read(strictPath);
const reviewJsonText = await read(reviewJsonPath);
const runtimeLabelsText = await read(runtimeLabelsPath);
const hashManifestText = await read(hashesPath);
summary.evidenceHashes = {
  [path.basename(matrixJsonPath)]: sha256(await read(matrixJsonPath)),
  [path.basename(matrixMdPath)]: sha256(matrixText),
  [path.basename(reviewMdPath)]: sha256(reviewText),
  [path.basename(reviewJsonPath)]: sha256(reviewJsonText),
  [path.basename(strictPath)]: sha256(strictText),
  [path.basename(hashesPath)]: sha256(hashManifestText),
  [path.basename(livePath)]: sha256(await read(livePath)),
  [path.basename(runtimeLabelsPath)]: sha256(runtimeLabelsText),
  [path.basename(statusPath)]: sha256(statusText)
};
await jsonWrite(summaryPath, summary);

const { updateCashUiStatus } = await import('./update_cash_ui_status.mjs');
const cashUiUpdated = await updateCashUiStatus({ allowStale: true });
if (!cashUiUpdated) console.log(JSON.stringify({
  updatedAt: now,
  candidateChecks: strict.passed,
  matrixRows: matrix.rows.length,
  matrixOwnerAccepted: matrix.ownerAcceptedCriteria,
  candidateSources: Object.keys(candidateHashes.candidateSources).length,
  evidenceHashes: summary.evidenceHashes
}));
