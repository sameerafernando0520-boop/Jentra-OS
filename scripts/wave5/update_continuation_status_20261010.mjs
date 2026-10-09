// Update living status documents only after final evidence and review are ready.
// This performs no installation, provisioning, deployment, authentication or send.
// Default is read-only preview. Pass --write only after the root evidence freeze.
import { access, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { parseTestLog } from './record_continuation_windows.mjs';

const revision = process.argv[2];
if (!/^r[1-9][0-9]*$/.test(revision ?? '')) throw Error('FINAL_REVISION_REQUIRED');
const write = process.argv.includes('--write');
const base = 'docs/verification/wave5/';
const nativePath = base + `windows-test-verification-20261009-${revision}.json`;
const reviewPath = base + `complete-app-runtime-review-20261009-${revision}.json`;
const livePath = base + 'continuation-live-summary-20261010.json';
const liveRawPath = base + 'continuation-live-refresh-20261010.json';
const loginPath = base + 'desktop-test-login-signin-20261009.json';
const createdPath = base + 'desktop-test-login-result-20261009.json';
const goldenPath = base + 'continuation-goldens-native-20261009.json';
const publicAuthPath = base + 'public-auth-settings-20261010.json';
const matrixPath = base + 'requirement-matrix-20261008.json';
const matrixMdPath = base + 'requirement-matrix-20261008.md';
const statusPath = 'docs/development/wave5-status.md';
const handoffPath = 'docs/development/wave5-next-session-20261010.md';
const resultPath = base + `continuation-status-20261010-${revision}.json`;
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const parseJsonBytes = bytes => JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
const json = async p => parseJsonBytes(await readFile(p));
const [native, review, live, login, created, goldens, originalMatrixBytes,
  originalMatrixMdBytes, publicAuth, originalStatusBytes] = await Promise.all([
  json(nativePath), json(reviewPath), json(livePath), json(loginPath), json(createdPath),
  json(goldenPath), readFile(matrixPath), readFile(matrixMdPath), json(publicAuthPath),
  readFile(statusPath),
]);
const matrix = parseJsonBytes(originalMatrixBytes);
const originalLivingHashes = new Map([
  [matrixPath, sha(originalMatrixBytes)], [matrixMdPath, sha(originalMatrixMdBytes)],
  [statusPath, sha(originalStatusBytes)],
]);
async function assertLivingDocumentUnchanged(file) {
  if (sha(await readFile(file)) !== originalLivingHashes.get(file)) {
    throw Error('CONCURRENT_LIVING_DOCUMENT_CHANGE:' + file);
  }
}
async function verifyCurrentNativeSources() {
  if (native.builds?.length !== 2 ||
      !Number.isSafeInteger(native.sourceFilesPerApp) || native.sourceFilesPerApp < 1) {
    throw Error('CURRENT_NATIVE_SOURCE_MANIFESTS_REQUIRED');
  }
  const workspaceRoot = path.resolve('.');
  let reference;
  for (const mode of ['preview', 'connected']) {
    const build = native.builds.find(item => item.mode === mode);
    const expectedPath = base + `windows-test-${mode}-source-20261009-${revision}.json`;
    if (!build || build.sourceManifest !== expectedPath) throw Error('NATIVE_SOURCE_MANIFEST_IDENTITY_CHANGED');
    const bytes = await readFile(expectedPath);
    if (sha(bytes) !== build.sourceManifestSha256) throw Error('NATIVE_SOURCE_MANIFEST_DRIFT:' + mode);
    const source = parseJsonBytes(bytes);
    const entries = Object.entries(source.baseSourceHashes ?? {}).sort(([a], [b]) => a.localeCompare(b));
    if (source.revision !== revision || String(source.mode).toLowerCase() !== mode ||
        entries.length !== native.sourceFilesPerApp || build.sourceFileCount !== entries.length) {
      throw Error('NATIVE_SOURCE_MANIFEST_SCOPE_CHANGED:' + mode);
    }
    if (reference && JSON.stringify(entries) !== JSON.stringify(reference)) {
      throw Error('NATIVE_SOURCE_MANIFESTS_DISAGREE');
    }
    reference ??= entries;
  }
  // Hash the current checkout files, not the copied build inputs. Both ordinary
  // source manifests must bind the same current base source without overlays.
  for (const [file, expected] of reference) {
    const resolved = path.resolve(file);
    const relative = path.relative(workspaceRoot, resolved);
    if (path.isAbsolute(file) || relative.startsWith('..' + path.sep) ||
        relative === '..' || path.isAbsolute(relative) || !/^[a-f0-9]{64}$/.test(expected)) {
      throw Error('NATIVE_SOURCE_PATH_OR_HASH_INVALID:' + file);
    }
    if (sha(await readFile(resolved)) !== expected) throw Error('CURRENT_NATIVE_SOURCE_DRIFT:' + file);
  }
  return { checkedAt: new Date().toISOString(), checkedFiles: reference.length,
    modes: ['preview', 'connected'], sourceMatches: true };
}
if (publicAuth.projectId !== 'xpdoufauvrbdmxgngetv' ||
    publicAuth.googleEnabled !== false || publicAuth.emailEnabled !== true ||
    publicAuth.signupDisabled !== false || publicAuth.emailAutoconfirm !== false ||
    publicAuth.privateConfigurationRead !== false || publicAuth.accountCreatedByThisRead !== false) {
  throw Error('PUBLIC_AUTH_OBSERVATION_CHANGED');
}
const { bundleSha256, ...reviewBody } = review;
if (sha(JSON.stringify(reviewBody)) !== bundleSha256 || review.ownerApproved !== false ||
    review.approvalReady !== true || review.migrations.length !== 71 ||
    review.evidence?.nativeReport !== nativePath || review.evidence?.freshLiveSummary !== livePath) {
  throw Error('FINAL_EXACT_REVIEW_REQUIRED');
}
if (native.revision !== revision || native.currentSourceMatch !== true ||
    native.previewBuilt !== true || native.connectedBuilt !== true ||
    native.authenticatedNativeAcceptance !== false || native.realMfa !== false ||
    native.ownerAccepted !== false || native.actualModelUsage !== false ||
    native.actualWorkerDelivery !== false || native.nativeKeyboardVerified !== false ||
    native.independentSessionContention !== false || native.targetScaleLoad !== false) {
  throw Error('NATIVE_EVIDENCE_BOUNDARY_CHANGED');
}
if (live.migrationCount !== 43 || live.apiFunctions !== 107 ||
    live.rolePermissions !== 87 || live.roleAssignments !== 1 ||
    live.entitlements !== 28 || live.memberships !== 1 ||
    live.proposedRuntimeAccounts !== 0 || live.changedProviders?.length ||
    live.edgeAuthorities || live.cronJobs || live.netQueue ||
    live.checkedProviders !== 120 || live.unchangedProviders !== 120 ||
    live.readOnly !== true || live.rawEvidence !== liveRawPath ||
    live.wave5Tables?.length !== 15 ||
    live.wave5Tables.some(t => t.rlsEnabled !== true || t.rlsForced !== true)) {
  throw Error('LIVE_SCOPE_CHANGED');
}
const existingPeopleEdges = [
  ['people-private-documents', 1, '013bc0f0544765f1f55534b300eb9ff9db1287baa8fd3aaa51a56de44d6f90a8'],
  ['people-private-purge', 1, '11090fac763e7a81a1fc0a7e607edc6389b2888230e82c2c307d533e89119010'],
];
if (JSON.stringify(live.edgeFunctions?.map(f => [f.name, f.version, f.sourceSha256]).sort()) !==
    JSON.stringify(existingPeopleEdges)) throw Error('DEPLOYED_EDGE_SCOPE_CHANGED');
if (matrix.rows.length !== 109 || matrix.requirementCount !== 109 ||
    matrix.ownerAcceptedCriteria !== 0 || matrix.rows.some(r => r.ownerAccepted !== false) ||
    matrix.wholeWaveComplete !== false) throw Error('OWNER_ACCEPTANCE_BOUNDARY_CHANGED');
const originals = matrix.rows.map(r => ({
  id: r.id, bundle: r.bundle, specification: r.specification,
  specificationLine: r.specificationLine, statement: r.statement,
}));
const ids = matrix.rows.map(r => r.id);
if (new Set(ids).size !== 109) throw Error('REQUIREMENT_IDENTITIES_CHANGED');
const forbiddenWrites = new Set([matrixPath, matrixMdPath, statusPath, handoffPath, resultPath]);
const originalInstalledSources = new Set([
  '20261006140000_wave5_process_metrics.sql',
  '20261006143000_wave5_pipeline_forecasts.sql',
  '20261006150000_wave5_trusted_metering.sql',
  '20261006153000_wave5_operator_isolation.sql',
  '20261006160000_wave5_human_proposals.sql',
  '20261006170000_wave5_synthetic_subscriptions.sql',
]);
if (new Set(review.migrations.map(m => m.path)).size !== 71) throw Error('MIGRATION_IDENTITIES_CHANGED');
for (const migration of review.migrations) {
  if (originalInstalledSources.has(path.posix.basename(migration.path))) {
    throw Error('ORIGINAL_SIX_MUST_REMAIN_EXCLUDED:' + migration.path);
  }
  if (sha(await readFile(migration.path)) !== migration.sha256) {
    throw Error('REVIEW_MIGRATION_DRIFT:' + migration.path);
  }
}
for (const artifact of review.artifacts) {
  if (forbiddenWrites.has(artifact.path)) throw Error('LIVING_DOCUMENT_IS_REVIEW_ARTIFACT:' + artifact.path);
  if (sha(await readFile(artifact.path)) !== artifact.sha256) throw Error('REVIEW_ARTIFACT_DRIFT:' + artifact.path);
}
for (const stage of native.stages ?? []) {
  const bytes = await readFile(stage.log);
  if (stage.logSha256 && sha(bytes) !== stage.logSha256) {
    throw Error('CURRENT_STAGE_LOG_DRIFT:' + stage.stage);
  }
  if (stage.stage === 'desktopAll') {
    const summary = parseTestLog(bytes.toString('utf8'));
    const expected = goldens.cases.map(c => c.golden).sort();
    const actual = summary?.failures.map(f => f.golden).sort();
    if (stage.exitCode !== 1 || !summary || summary.failedTests !== 83 ||
        summary.failures.length !== 83 || summary.failures.some(f => f.kind !== 'golden-comparison') ||
        JSON.stringify(actual) !== JSON.stringify(expected) ||
        summary.passedTests !== stage.passedTests || stage.failedTests !== 83) {
      throw Error('UNEXPECTED_DESKTOP_FAILURES');
    }
  } else if (stage.stage === 'cashEpochRed') {
    const summary = parseTestLog(bytes.toString('utf8'));
    const redPath = base + `cash-epoch-red-20261009-${revision}.json`;
    const red = await json(redPath);
    if (stage.exitCode !== 1 || !summary || summary.passedTests !== 0 || summary.failedTests !== 12 ||
        red.redObserved !== true || red.sourceRestored !== true || red.workspaceSourceChanged !== false ||
        red.originalControlRevision !== 'r10' || red.log !== stage.log) {
      throw Error('UNEXPECTED_REGRESSION_CONTROL_RESULT');
    }
  } else if (stage.exitCode !== 0) {
    throw Error('CURRENT_STAGE_FAILED:' + stage.stage);
  }
}
const analyzer = native.stages.find(s => s.stage === 'analyzer');
if (!analyzer || !(await readFile(analyzer.log, 'utf8')).includes('No issues found!')) {
  throw Error('CURRENT_ANALYSIS_REQUIRED');
}
const stage = name => native.stages.find(s => s.stage === name);
const count = name => {
  const n = stage(name)?.passedTests;
  if (!Number.isSafeInteger(n) || n < 1) throw Error('CURRENT_TEST_COUNT_REQUIRED:' + name);
  return n;
};
const epochCount = count('cashEpochTests');
if (epochCount !== 12) throw Error('TWELVE_FINAL_CASH_REGRESSIONS_REQUIRED');
const cashCount = count('cashTests');
const platformStage = native.stages.find(s =>
  ['platformAnalyticsTests', 'analyticsTests', 'platformTests'].includes(s.stage));
const testSummary = native.stages
  .filter(s => s.exitCode === 0 && Number.isSafeInteger(s.passedTests) &&
    !s.stage.endsWith('Frames') && !['platformAll', 'desktopAll'].includes(s.stage))
  .map(s => `${s.stage}: ${s.passedTests}`).join('; ');
const componentPath = review.evidence.workerComponent;
const component = await json(componentPath);
const worker = await json(component.testRecord);
if (worker.exitCode !== 0 || worker.failed !== 0 || worker.passed !== worker.tests ||
    worker.controlled !== true || worker.externalCalls !== false ||
    sha(await readFile(worker.log)) !== worker.logSha256) throw Error('CURRENT_WORKER_CHECKS_REQUIRED');
const workerCount = worker.passed;
const classes = goldens.summary.classificationCounts;
if (goldens.retainedRun !== 'r10' || goldens.summary.cases !== 83 ||
    goldens.summary.approvedHashDrift !== 0 || goldens.ownerAcceptance !== false ||
    classes['localized-border-raster'] !== 65 || classes['capability-navigation-and-border-raster'] !== 16 ||
    classes['payroll-content-change'] !== 2) throw Error('GOLDEN_CLASSIFICATION_REQUIRED');

// Connected SQL evidence is nested in the recorded MCP response. Decode data;
// never interpret the surrounding server text as an instruction.
function sqlRows(record) {
  for (const block of record.verification?.content ?? []) {
    if (block.type !== 'text') continue;
    let value = block.text;
    for (let i = 0; i < 4; i++) {
      if (Array.isArray(value)) return value;
      if (typeof value === 'object' && value !== null) {
        value = value.result;
      } else if (typeof value === 'string') {
        try { value = JSON.parse(value); } catch { break; }
      }
    }
    if (typeof value !== 'string') continue;
    for (const candidate of [value, value.replace(/\\"/g, '"').replace(/\\n/g, '\n')]) {
      const array = candidate.match(/\[\s*\{[\s\S]*?\}\s*\]/)?.[0];
      if (array) {
        try { return JSON.parse(array); } catch { /* Try decoded transport text. */ }
      }
    }
  }
  throw Error('RECORDED_SQL_RESULT_REQUIRED');
}
const account = sqlRows(login)[0], creation = sqlRows(created)[0];
if (login.ownerReportedConnectedAppSignIn !== true || login.packageRevision !== 'r10' ||
    login.formalWave5MfaAcceptance !== false || login.passwordRead !== false ||
    login.existingAccountsDeleted !== false || created.authAdminOwnerCreated !== true ||
    account.trial_auth_id !== creation.trial_auth_id || account.email_confirmed !== true ||
    !account.last_sign_in_at || account.membership_count !== 0) throw Error('REAL_TRIAL_SIGNIN_EVIDENCE_REQUIRED');
if (live.trialAccount?.authId !== account.trial_auth_id || live.trialAccount.confirmed !== true ||
    live.trialAccount.membershipCount !== 0 ||
    Date.parse(live.trialAccount.lastSignInAt) !== Date.parse(account.last_sign_in_at)) {
  throw Error('LIVE_TRIAL_SIGNIN_CHANGED');
}
const trial = {
  email: login.email, authId: account.trial_auth_id, confirmed: true,
  ownerReportedConnectedSignIn: true, signedInPackage: 'r10',
  lastSignInAt: account.last_sign_in_at, observedAt: account.observed_at,
  membershipCount: 0, creationEvidence: createdPath, signInEvidence: loginPath,
  passwordRead: false, existingAccountsDeleted: false,
  existingAccountPreserved: true, formalWave5MfaAcceptance: false,
};
const now = new Date().toISOString();
const nativeMd = nativePath.replace(/\.json$/, '.md');
const reviewMd = reviewPath.replace(/\.json$/, '.md');
const goldenMd = goldenPath.replace(/\.json$/, '.md');
const fullSuite = Array.isArray(native.broaderSuites)
  ? native.broaderSuites : Object.values(native.broaderSuites ?? {});
const broaderCurrent = fullSuite.length
  ? fullSuite.map(s => `${s.stage}: ${s.passedTests} passed / ${s.failedTests} failed (exit ${s.exitCode})`).join('; ')
  : 'Full platform/desktop suite counts are historical r10 evidence: 1127/0 and 1909/83. These full suites were not rerun on this revision.';
const cashFrames = native.cashFrames?.length ?? 0;
const nativeDescription = `Fresh ${revision} scoped analysis is clean; ${testSummary}. Ordinary Preview/Connected builds bind ${native.sourceFilesPerApp} selected source inputs per app and ${native.releaseEntriesVerified} release hashes. ${cashFrames} cash frames were captured; ${native.cashFramesInspected ?? 0} inspected. Native launch on this revision: ${native.nativeLaunched === true}.`;
const freshDesktop = fullSuite.find(s => s.stage === 'desktopAll');
const freshGoldenDescription = freshDesktop
  ? `Fresh ${revision} desktop suite still fails the same 83 approved golden comparisons; ${native.goldenCurrentImagesIdenticalToR10 ?? 0} current failure images exactly match retained r10 bytes. ` : '';
const visualDescription = freshGoldenDescription + 'All 83 retained r10 golden failures are investigated: 65 localized border-raster, 16 capability/navigation plus border-raster (including the 13 shared dashboard/setup cases), two payroll content changes. Approved PNGs are preserved and all strict golden/owner visual gates remain open.';
const accountDescription = `The separate confirmed trial identity ${trial.email} (${trial.authId}) was created privately by the owner. Owner-reported Connected r10 sign-in is corroborated by server last_sign_in_at ${trial.lastSignInAt}; membership count is zero. Existing accounts are preserved. This is separate from genuine Wave 5 MFA/native acceptance and the six uncreated runtime actors.`;
const publicAuthDescription = `The public Auth settings read at ${publicAuth.observedAt} reports Google disabled, email enabled, sign-up enabled and email confirmation required. No private configuration was read and no setting changed. Real Google sign-in and email confirmation delivery remain unverified.`;
const providerRemaining = 'Approve the refreshed exact runtime bundle before installing/provisioning. Then prove nonempty authoritative sources and publications through real permitted/denied sessions, genuine distinct MFA, current permissions/revocation and owner acceptance.';
const titles = {
  shared: 'Scope, permission and complete bounded evidence', process: 'W5-01 process metrics',
  pipeline: 'W5-02 historical and current pipeline', finance: 'W5-03 authoritative statements and ratios',
  cash: 'W5-03 cash dates, scenarios and governed export', ai: 'W5-04 reviewed model and human proposal controls',
  integration: 'W5-05 persistent integrations and hosted workers', billing: 'W5-06 synthetic subscriptions and trusted usage',
  operator: 'W5-07 separate operator authority and health', native: 'Native workspaces and encrypted recovery',
  provider: 'Authoritative provider completion', ownership: 'Concurrent source and acceptance-store preservation',
  quality: 'Evidence and quality gates', load: 'Real contention and target-scale performance',
};
const statuses = {
  shared: 'The original six installed Wave 5 migrations remain intact. Fresh live state is 43 migrations/107 API functions with unchanged scoped access and provider fingerprints. The 71 additional migrations and runtime bootstrap remain unapproved and uninstalled; 105/25 strict rollback checks are historical candidate evidence.',
  process: 'Installed exact process provider, scoped gateway, encrypted filters and native workspace are retained. Current controlled workspace tests are source evidence; real duration/source certification remains open.',
  pipeline: 'Immutable historical CRM conversion/aging/velocity and frozen forecast realized mappings are implemented as uninstalled candidates. No new nonempty authenticated provider acceptance occurred.',
  finance: 'Matching immutable Wave 3 statements, independent MFA-reviewed classifications and six named exact ratios are implemented as uninstalled candidates. Real statement publication/review/drill-through remain open.',
  cash: `Five-family cash/date/scenario/export candidates are retained. Epoch guards stop invalidated operations before further reads/dispatch; current-operation predicates after final store authorization prevent recovery-row deletion after invalidation. Actor/offline input clearing and 200% field spacing are implemented. ${epochCount} focused cancellation/privacy regressions and ${cashCount} cash/workspace tests pass on ${revision}; actual source-date/scenario/export acceptance remains open.`,
  ai: 'Numeric redaction, strict model output/trusted metering, encrypted original invocation/usage recovery and distinct human proposal/approval/execution candidates are retained. No actual trusted model usage or genuine MFA execution occurred.',
  integration: `Persistent credentials/rotation/revocation, committed outbox/attempts/dead letters/replay, throttle/quota and named scheduling candidates are retained. Current worker source changes and request/caller/downstream deadline controls are bound in the refreshed component. ${workerCount} fresh controlled worker tests and current Deno entrypoint checks pass; no deployment or actual delivery occurred.`,
  billing: 'Installed synthetic billing authority is retained. Exact reviewed synthetic plans/scopes/quotas/seats and expiring scheduling remain unprovisioned; trusted usage and independent races are unverified.',
  operator: 'Installed isolation is retained. The separate returned-ID-bound operator, zero membership and bounded MFA authority/grant remain reviewed but unprovisioned. No genuine grant/health acceptance occurred.',
  native: `${nativeDescription} ${accountDescription} ${visualDescription}`,
  provider: 'Historical/realized, statement/classification, five-family cash/date, scenario/export, persistent integration and trusted model adapters are implemented as candidates. Missing/denied/incompatible providers remain unavailable. The 71 additional dependencies remain uninstalled.',
  ownership: 'Concurrent W3/W4/Employee sources, existing accounts and acceptance stores/sessions are preserved. No reset/clean/stage/commit/push occurred. The original review/r10 reports are retained; refreshed native and worker source bindings require their own exact approval.',
  quality: `${nativeDescription} ${workerCount} controlled worker tests and current Deno entrypoint checks pass. Unchanged 105/25 rollback probes and 126 installed checks remain historical. ${broaderCurrent} ${visualDescription}`,
  load: 'The reviewed protocol requires committed independent-session contention and 500 tenants/2000 genuine sessions with actual distributions/errors/p95. No contention or target-scale run occurred; sequential/injected probes do not satisfy this gate.',
};
const remaining = {
  shared: providerRemaining,
  process: 'Genuine source/duration certification, authenticated native keyboard/restart/revocation, target-scale latency and owner acceptance remain open.',
  pipeline: 'Install reviewed dependencies and prove nonempty historical/realized cohorts, conversion/aging/velocity/accuracy with real authorized and denied sessions.',
  finance: 'Install exact dependencies; publish nonempty statements and independently review classifications through genuine MFA; verify all six ratios/drill-through and revocation.',
  cash: 'Install and verify exact providers. Prove genuine distinct-MFA payment-date proposal/approval/revision, authoritative settlements/reversals, immutable scenario recovery, actual CSV/XLSX creation/download/hash/reopen, native restart/revocation and owner acceptance.',
  ai: 'Approve exact provisioning/deployment, privately configure the model and prove actual trusted token settlement/unknown reconciliation, distinct genuine MFA approval/execution, stale-source rejection and revocation.',
  integration: 'Approve exact setup/deployments; privately configure only reviewed values. Prove actual signed receipt-before-ACK delivery, rotation/revocation, timeout/unknown reconciliation, dead letters/reviewed replay, persistent restart and independent races.',
  billing: 'Approve reviewed synthetic setup; prove trusted activation/usage/scheduling and actual independent seat/quota/admission/activation contention. Real billing stays excluded.',
  operator: 'After approval privately create/bind the separate operator, issue a genuine MFA grant and prove scope/reason/expiry/owner denial, health and immutable audit.',
  native: 'The trial sign-in is corroborated and existing accounts are preserved. Genuine Wave 5 MFA/keyboard/actor switch/restart/revocation/export checks, the formal isolated profile, all 83 strict golden decisions and owner acceptance remain open. Google remains disabled in the latest public settings observation; private configuration, real Google sign-in and email delivery remain unverified.',
  provider: providerRemaining,
  ownership: 'Refresh live/source/release bindings before approved operations; preserve all concurrent ownership and acceptance stores. Do not reinstall the six connector-mapped migrations or infer approval from hosting/account choices.',
  quality: 'Keep source implementation, installed SQL, authenticated native/MFA, actual model/worker/export delivery, independent contention/load and owner acceptance separate. The app is incomplete; zero of 109 IDs are owner-accepted.',
  load: 'After approval run genuine independent sessions/barriers and committed races, then the bounded 500-tenant/2000-session target load. Record actual host/tier/row populations/errors/latencies; unsupported limits remain unmet.',
};
const common = [nativePath, nativeMd, reviewPath, reviewMd, livePath, componentPath, goldenPath, goldenMd];
for (const row of matrix.rows) {
  if (!statuses[row.bundle] || !titles[row.bundle]) throw Error('UNMAPPED_BUNDLE:' + row.bundle);
  row.developmentStatus = statuses[row.bundle];
  row.remaining = remaining[row.bundle];
  row.ownerAccepted = false;
  row.evidence = [...new Set([...row.evidence, ...common,
    ...(['native', 'quality', 'shared'].includes(row.bundle) ? [createdPath, loginPath] : []),
    ...(['cash', 'native', 'quality'].includes(row.bundle) ? [
      'apps/jentra_desktop/test/wave5_cash_epoch_test.dart',
      base + 'continuation-providers-cash-20261009.md',
    ] : []),
    ...(['integration', 'ai', 'billing', 'quality'].includes(row.bundle) ? [component.testRecord, component.denoRecord] : []),
  ])];
}
if (JSON.stringify(originals) !== JSON.stringify(matrix.rows.map(r => ({
  id: r.id, bundle: r.bundle, specification: r.specification,
  specificationLine: r.specificationLine, statement: r.statement,
})))) throw Error('SPECIFICATION_MAPPING_CHANGED');
matrix.historicalContinuationChecks ??= structuredClone(matrix.continuationChecks);
matrix.updatedAt = now;
matrix.ownerAcceptedCriteria = 0;
matrix.wholeWaveComplete = false;
matrix.originalSixInstallationComplete = true;
matrix.newRuntimeInstallationComplete = false;
matrix.runtimeReview = {
  path: reviewMd, manifest: reviewPath, bundleSha256, ownerApproved: false,
  migrations: 71, hosting: 'existing owner-selected Supabase project xpdoufauvrbdmxgngetv',
  originalSixExcluded: true, originalReviewPreserved: review.supersedes,
  liveAfter: livePath, nativeTarget: 'new standard Windows profile jentra-w5-runtime',
  nativeProvisioned: false, strictCandidateAssertions: 105, strictMappingAssertions: 25,
  candidateChecksRerun: false, bootstrapChecksRerun: false, permissionShim: false,
  controlledWorkerTests: workerCount, newInstalled: false,
};
matrix.continuationChecks = {
  sourceRevision: revision, sourceFileCount: native.sourceFilesPerApp,
  sourceVerifiedAt: native.observedAt, currentSourceScope: native.sourceScope,
  wholeWorkspaceSourceMatch: false, analyzerCurrentSource: true, analyzerScope: analyzer.command,
  windowsBuildCurrentSourceMatch: true, currentCashRenderAvailable: cashFrames > 0,
  currentSdkStages: native.stages, testScope: testSummary,
  cashEpochCurrent: epochCount, cashWorkspaceCurrent: cashCount,
  platformAnalyticsCurrent: platformStage?.passedTests ?? null,
  platformAnalyticsScope: platformStage?.command ?? null,
  domainEvidenceCurrent: false, domainEvidenceScope: 'Historical 72-test analytics domain run; no current domain rerun claimed.',
  broadPlatformAndDesktopCurrent: fullSuite.length > 0, broaderSuites: fullSuite,
  historicalFullSuiteVerification: base + 'windows-test-verification-20261009-r10.json',
  historicalPlatformFullSuite: { passed: 1127, failed: 0 },
  historicalDesktopFullSuite: { passed: 1909, failed: 83 },
  cashUiVerification: nativePath, currentCashFrames: cashFrames,
  cashFramesInspected: native.cashFramesInspected ?? 0,
  currentModelFrames: native.modelFrames?.length ?? 0, modelFramesInspected: native.modelFramesInspected ?? 0,
  workerLastVerified: workerCount, workerEvidence: component.testRecord,
  runtimeCandidateSql: 105, bootstrapMappingSql: 25, candidateChecksRerun: false,
  candidateSqlScope: 'Historical complete candidate/setup/stop and exact-bootstrap rollback probes; test-only Auth shapes, no HTTP.',
  originalInstalledAssertions: 126, installedChecksRerun: false,
  sharedGoldensRerun: native.sharedGoldensRerun === true,
  sharedGoldenFailures: 13, historicalDesktopGoldenFailures: 83,
  goldenInvestigation: goldenPath, goldenClassificationCounts: classes,
  approvedGoldensRegenerated: false,
};
matrix.evidenceGates = {
  implementation: 'Source candidates with current scoped automated evidence; full app development remains incomplete.',
  installedSql: 'Original six installed migrations retained; 71 additional migrations unapproved and uninstalled.',
  authenticatedNative: false, realMfa: false, nativeKeyboard: false,
  trialAuthentication: 'Separate owner-assisted r10 account sign-in corroborated; membership zero.',
  actualGovernedExportDelivery: false, actualWorkerDelivery: false, actualTrustedModelUsage: false,
  independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false,
};
matrix.desktopTrialIdentity = trial;
matrix.windowsUserTestPackage = {
  verification: nativePath, report: nativeMd, delivery: native.delivery ?? null,
  zip: native.zip ?? null, zipSha256: native.zipSha256 ?? null,
  ordinaryEntrypoint: true, previewAndConnected: true,
  nativeLaunched: native.nativeLaunched === true,
  sourceFilesPerApp: native.sourceFilesPerApp, packagedReleaseEntriesVerified: native.releaseEntriesVerified,
  authenticatedAcceptance: false, formalRuntimeProfileProvisioned: false, ownerAccepted: false,
};
matrix.accountAuthentication = {
  ...matrix.accountAuthentication, sourceRevision: revision,
  emailAccountAndWindowsGoogleReturnImplemented: true,
  realGoogleSignIn: false, emailConfirmationDeliveryVerified: false,
  trialSignInCorroborated: true, trialEvidence: loginPath, trialPackageRevision: 'r10',
  businessMembershipAutomatic: false,
  publicSettingsEvidence: publicAuthPath, publicSettingsObservedAt: publicAuth.observedAt,
  googleEnabledObserved: false, emailEnabledObserved: true,
  signupEnabledObserved: true, emailConfirmationRequiredObserved: true,
  privateConfigurationRead: false,
};
for (const key of ['actualModelUsage', 'realMfa', 'actualWorkerDelivery',
  'authenticatedNativeAcceptance', 'independentSessionContention', 'targetScaleLoad',
  'nativeKeyboardVerified', 'ownerSignoff']) matrix[key] = false;

const relative = p => path.posix.relative(base.slice(0, -1), p);
const matrixLines = [
  '# Wave 5 requirement matrix — updated October 10, 2026', '',
  'All 109 approved requirement identifiers and specification mappings are preserved. Zero IDs are owner-accepted; Jentra OS and Wave 5 remain incomplete.', '',
  `[Current native evidence](${path.posix.basename(nativeMd)}) and [refreshed unapproved runtime review](${path.posix.basename(reviewMd)}), bundle \`${bundleSha256}\`, bind the current source. The old review/r10 evidence remain preserved. Hosting stays the existing Supabase project.`, '',
  `Fresh live read ${live.observedAt}: ${live.migrationCount} migrations / ${live.apiFunctions} API functions; ${live.unchangedProviders}/${live.checkedProviders} fingerprints unchanged. The original six installed migrations are excluded; the 71 additional migrations and runtime provisioning remain pending.`, '',
  accountDescription, '', nativeDescription, '', broaderCurrent, '', visualDescription, '',
  'Implementation, installed SQL, authenticated native/MFA, actual delivery/model usage, independent contention/load and owner acceptance remain separate gates.', '',
  '| ID | Evidence bundle | Current status |', '|---|---|---|',
];
for (const row of matrix.rows) matrixLines.push(`| ${row.id} | [${titles[row.bundle]}](#evidence-${row.bundle}) | ${row.developmentStatus.replace(/\|/g, '\\|')} |`);
for (const [bundle, title] of Object.entries(titles)) {
  const rows = matrix.rows.filter(r => r.bundle === bundle);
  matrixLines.push('', `<a id="evidence-${bundle}"></a>`, `## ${title}`, '', statuses[bundle], '',
    `Remaining: ${remaining[bundle]}`, '', 'Evidence:', '');
  for (const file of [...new Set(rows.flatMap(r => r.evidence))]) matrixLines.push(`- [${file}](${relative(file)})`);
}
const status = `# Wave 5 development status

Updated October 10, 2026. **Jentra OS and Wave 5 remain incomplete.** The current [${revision} ordinary Windows evidence](../verification/wave5/${path.posix.basename(nativeMd)}) binds fresh source/build/render checks; the original r10 package and reports remain preserved. ${nativeDescription}

${accountDescription} [Private creation record](../verification/wave5/${path.posix.basename(createdPath)}) and [sign-in corroboration](../verification/wave5/${path.posix.basename(loginPath)}). The existing account is preserved; no deletion request remains pending. ${publicAuthDescription} [Public settings evidence](../verification/wave5/${path.posix.basename(publicAuthPath)}).

The [fresh live read](../verification/wave5/${path.posix.basename(livePath)}), ${live.observedAt}, records **43 migrations / 107 API functions**; ${live.unchangedProviders}/${live.checkedProviders} checked provider fingerprints are unchanged. Role permissions/assignments/entitlements/memberships remain 87/1/28/1 and all 15 original Wave 5 tables retain enabled and forced RLS. The six runtime actors, new runtime authority, expiring jobs and net queue remain absent; only the two existing People Edge functions are deployed. The original six installed migrations retain their connector mapping and must not be reinstalled.

The [refreshed operation review](../verification/wave5/${path.posix.basename(reviewMd)}) binds **71 additional migrations** and current worker/native artifacts. Its exact SHA-256 is **\`${bundleSha256}\`**. Operation approval is absent. Hosting is already the existing Supabase project; account labels and the standard Windows target are selected. This review retains the scoped 500-tenant/four-plan setup, separate operator, private configuration, two Edge functions and bounded genuine MFA/delivery/export/contention/load protocol. The original review hash cannot approve changed source. Production and real billing remain excluded.

| Slice | Implemented source / recorded evidence | Completion evidence still required |
|---|---|---|
| Process / pipeline | Scoped exact metrics and immutable historical/realized candidates retained | Installed dependencies, nonempty authenticated source evidence, duration/accuracy certification and owner acceptance |
| Finance / cash | Statements/classifications/six ratios; five families and independent source dates; immutable scenarios/recovery/governed exports; ${epochCount} fresh epoch/privacy regressions and ${cashCount} workspace tests | Genuine MFA publications/dates, settlements/reversals, native recovery and actual export create/download/hash/reopen |
| Model / proposals | Numeric redaction, strict output, encrypted invocation recovery, distinct human controls retained | Private provider and actual trusted usage; genuine separate MFA approval/execution |
| Integrations / workers | Persistent delivery/rotation/replay/throttle/quota; request/caller/downstream deadlines; ${workerCount} fresh controlled worker tests and Deno entrypoint checks | Approved deployment, actual signed delivery/reconciliation/revocation/replay/restart and independent races |
| Billing / operator | Exact synthetic plans/seat/quota and bounded separate operator candidates retained | Approved setup, trusted usage/activation, genuine operator MFA grant and denial/expiry checks |
| Native / quality | Fresh scoped ${revision} source/build/render evidence; trial r10 sign-in corroborated; all 83 retained goldens classified | Native keyboard/MFA/actor switch/restart/revocation, strict golden/visual decisions, contention/load and all 109 owner decisions |

${visualDescription} The payroll cases require the separately owned Wave 4 visual decision; the 16 navigation cases require intended fixture/capability policy reconciliation. Current cash spacing has new widget geometry/render evidence recorded by the native report; this does not accept any approved golden or establish full native keyboard behavior.

${broaderCurrent} Unchanged 105 full-schema/setup and 25 exact-bootstrap rollback assertions remain historical; no candidate SQL was rerun by this source continuation. Original 126 installed SQL assertions are historical installed evidence. Captures overlap focused tests and are not additional independent feature coverage.

Existing accounts, concurrent W3/W4/Employee changes and acceptance stores/sessions are preserved. No reset/clean/stage/commit/push, fake Auth rows, new runtime installation/provisioning or actual model/worker delivery occurred. [Requirement matrix](../verification/wave5/requirement-matrix-20261008.md) and [October 10 handoff](wave5-next-session-20261010.md) name the remaining gates separately.
`;
const handoff = `# Jentra OS continuation handoff — October 10, 2026

Jentra OS and Wave 5 remain incomplete. Continue from the source-attributed ${revision} checks; do not inherit native acceptance from an older build. ${nativeDescription}

${accountDescription} Preserve the existing account. Do not request deletion clarification again. The trial account grants no business membership or Wave 5 entitlement and does not replace the six runtime actors. Passwords remain private. ${publicAuthDescription}

Read the current status and 109-ID matrix, [${revision} native report](../verification/wave5/${path.posix.basename(nativeMd)}), [fresh live read](../verification/wave5/${path.posix.basename(livePath)}), [refreshed runtime review](../verification/wave5/${path.posix.basename(reviewMd)}) and its JSON, [worker component](../verification/wave5/${path.posix.basename(componentPath)}), [83-case golden investigation](../verification/wave5/${path.posix.basename(goldenMd)}), source slice reports and detailed Wave 5 contracts. Keep the original six-file installation mapping and original review/r10 records.

Latest recorded live state: ${live.observedAt}, 43 migrations/107 API functions, 87/1/28/1 access counts, ${live.unchangedProviders}/${live.checkedProviders} unchanged provider fingerprints, 15 tables with enabled and forced RLS and only the two existing People Edge functions. The refreshed read reconfirms the separate trial identity's confirmed sign-in and zero memberships. Refresh this state and all review/source/release hashes before dependent actions. Never reinstall the original six migrations.

The refreshed runtime bundle is unapproved: **\`${bundleSha256}\`**. Hosting, six account labels and the standard Windows target are selected. Obtain explicit operation approval for this exact review before the 71 additional migrations, scoped runtime bootstrap/private configuration/OS target/Edge deployments/schedules and real bounded test run. The old \`13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e\` review remains preserved and cannot approve changed artifacts. Do not fabricate Auth users/claims, expose credentials or use other chats' sessions.

Continue every unblocked implementation/investigation with agents while serializing heavy Flutter jobs. After required approval/private owner context, privately create/bind six distinct real runtime identities and genuine MFA sessions; install/verify exact provider dependencies; publish nonempty historical CRM/realized/statements/classifications/ratios and authoritative payroll/correction/reimbursement dates; test settlements/reversals, immutable scenario recovery and actual governed CSV/XLSX download/hash/reopen. Deploy only reviewed runtime/receiver/configuration, prove actual signed delivery/rotation/revocation/unknown reconciliation/dead letters/reviewed replay/restart/throttle/quota and actual trusted model usage with distinct human approval/execution.

Native keyboard, genuine MFA/native actor switch/restart/revocation, actual export/delivery/model usage, committed independent-session contention, 500-tenant/2000-real-session load and owner acceptance remain open. ${visualDescription} Preserve approved images pending the appropriate explicit visual decision. ${broaderCurrent}

Preserve concurrent W3/W4/Employee changes, existing accounts and acceptance stores/sessions. Do not reset, clean, broadly overwrite/stage, commit, push or copy acceptance stores. Source edits require a new frozen revision and fresh appropriate analysis/tests/build/render attribution. Implementation, installed SQL, authenticated native/MFA, actual delivery, contention/load and owner acceptance remain separate. All 109 IDs have ownerAccepted=false. Production and real billing remain excluded.
`;
const directReadInventory = [
  'docs/development/wave5-next-session-20261009.md', statusPath,
  base + 'installation-result-20261008.md', base + 'installation-result-20261008.json',
  matrixMdPath, matrixPath, base + 'complete-app-remaining-work-20261009.md',
  base + 'complete-app-runtime-review-20261009.md', base + 'complete-app-runtime-review-20261009.json',
  base + 'windows-test-verification-20261009-r10.md', base + 'windows-test-verification-20261009-r10.json',
  base + 'full-desktop-golden-investigation-20261009-r10.md', base + 'full-desktop-golden-investigation-20261009-r10.json',
  base + 'desktop-test-login-20261009.md', base + 'windows-account-google-setup-20261009.md',
  base + 'integrated-runtime-protocol-20261006.md',
  'docs/blueprint/wave5/WAVE5_INTELLIGENCE_AND_CONTROL_SPEC.md',
  'docs/blueprint/wave5/W5_01_PROCESS_METRICS_CONTRACT.md',
  'docs/blueprint/wave5/W5_02_03_FORECAST_AND_RATIO_CONTRACT.md',
  'docs/blueprint/wave5/W5_04_07_CONTROL_CONTRACT.md',
  'docs/blueprint/wave5/W5_CASH_PAYMENT_DATES_CONTRACT.md',
  'docs/blueprint/wave5/W5_REVIEWED_MODEL_NATIVE_CONTRACT.md',
];
const inventoryHashes = [];
for (const file of directReadInventory) inventoryHashes.push({ path: file, sha256BeforeStatusUpdate: sha(await readFile(file)) });
const sliceInventory = [
  base + 'continuation-providers-cash-20261009.md', goldenMd, componentPath,
  nativeMd, reviewMd, createdPath, loginPath, livePath, liveRawPath, publicAuthPath,
];
for (const file of sliceInventory) await access(file);
const handoffReadInventory = '\n## Read inventory\n\n' +
  'The root continuation and delegated slices reviewed the direct October 9 handoff inputs and six Wave 5 specifications/contracts below. Detailed slice follow-ups and evidence limits are recorded in the separate provider/cash, golden/native and worker component records; this list does not assert that every transitive hyperlink was read.\n\n' +
  directReadInventory.map(file => `- [${file}](${path.posix.relative('docs/development', file)})`).join('\n') +
  '\n\nCurrent continuation evidence and slice records:\n\n' +
  sliceInventory.map(file => `- [${file}](${path.posix.relative('docs/development', file)})`).join('\n') + '\n';
const record = {
  updatedAt: now, revision, requirementCount: 109, ownerAcceptedCriteria: 0,
  wholeWaveComplete: false, reviewPath, bundleSha256, nativePath, livePath,
  liveRawEvidence: { path: liveRawPath, sha256: sha(await readFile(liveRawPath)) },
  workerComponent: componentPath, workerTests: workerCount, cashEpochTests: epochCount,
  publicAuthSettings: { path: publicAuthPath, sha256: sha(await readFile(publicAuthPath)), ...publicAuth },
  cashWorkspaceTests: cashCount, trialIdentity: trial, goldenInvestigation: goldenPath,
  goldenClassification: classes, originalSixReinstalled: false, newRuntimeInstalled: false,
  authenticatedNativeAcceptance: false, realMfa: false, nativeKeyboardVerified: false,
  actualWorkerDelivery: false, actualModelUsage: false, independentContention: false,
  targetScaleLoad: false, ownerSignoff: false,
  documentsUpdated: [matrixPath, matrixMdPath, statusPath, handoffPath],
  readInventory: inventoryHashes,
  previousMatrixSha256: originalLivingHashes.get(matrixPath),
  previousMatrixMarkdownSha256: originalLivingHashes.get(matrixMdPath),
  previousStatusSha256: originalLivingHashes.get(statusPath),
};
if (write) {
  // Prepare every output and validate its provenance before changing any living document.
  for (const file of [resultPath, handoffPath]) {
    try { await access(file); throw Error('OUTPUT_EXISTS_PRESERVE:' + file); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}
record.currentNativeSourceRecheck = await verifyCurrentNativeSources();
// Check all three exact starting byte hashes immediately before the first
// write, then check each living target again immediately before replacing it.
for (const file of originalLivingHashes.keys()) await assertLivingDocumentUnchanged(file);
if (write) {
  await writeFile(resultPath, JSON.stringify(record, null, 2) + '\n', { flag: 'wx' });
  await assertLivingDocumentUnchanged(matrixPath);
  await writeFile(matrixPath, JSON.stringify(matrix, null, 2) + '\n');
  await assertLivingDocumentUnchanged(matrixMdPath);
  await writeFile(matrixMdPath, matrixLines.join('\n') + '\n');
  await assertLivingDocumentUnchanged(statusPath);
  await writeFile(statusPath, status);
  await writeFile(handoffPath, handoff + handoffReadInventory, { flag: 'wx' });
}
console.log(JSON.stringify({ write, ...record }, null, 2));
