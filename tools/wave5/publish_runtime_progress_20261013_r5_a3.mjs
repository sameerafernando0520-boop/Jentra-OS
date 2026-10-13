import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT, BUNDLE, loadApprovedInputs, decodePublicResult } from './approved_management_installer.mjs';
import { hashBytes } from './runtime_contract.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const base = 'docs/verification/wave5/';
const must = (ok, code) => { if (!ok) throw Error(code); };
const evidence = {};
async function read(file, sha256) {
  const bytes = await fs.readFile(path.join(root, file));
  if (sha256) must(hashBytes(bytes) === sha256, 'EXACT_PUBLICATION_INPUT_REQUIRED');
  evidence[file] = { path: file, sha256: hashBytes(bytes), bytes: bytes.length };
  return JSON.parse(bytes);
}
await loadApprovedInputs();
const prior = await read(base + 'approved-runtime-progress-checkpoint-20261013-r5-a2.json', 'ec4e54dd5a65297fa187f9573f7b4da30dece39a1694749b8d07e5eb6e55d793');
for (const [kind, binding] of Object.entries(prior.evidence)) {
  const bytes = await fs.readFile(path.join(root, binding.path));
  must(hashBytes(bytes) === binding.sha256, 'PRIOR_FOUNDATION_EVIDENCE_CHANGED');
  evidence['historical_' + kind] = binding;
}
const preparation = await read(base + 'requirement-status-preparation-20261013-r5.json', '926922d274ecc669bc0cc6d65ec772ce1266f06829b212f7174b51d7f7428fe8');
const historical = preparation.preservedRows;
const canonicalSha256 = '298f767d74ff1e1913e19fce5fc9b79f76dc57da05666b5418355af0ab48b887';
must(historical.length === 109 && hashBytes(JSON.stringify(historical)) === canonicalSha256, 'EXACT_109_HISTORICAL_ROWS_REQUIRED');
const accepted = historical.filter(row => row.ownerAccepted).map(row => row.id).sort();
must(JSON.stringify(accepted) === JSON.stringify(['AC-551', 'AC-552', 'AC-553']), 'EXPLICIT_OWNER_ACCEPTANCE_CHANGED');
const current = await read(base + 'runtime-global-readonly-snapshot-20261013-r5-a4.json');
const live = decodePublicResult(current.result)[0].snapshot;
const age = Date.now() - Date.parse(live.observedAt);
must(age >= -10000 && age < 3600000 && live.migrationCount === 114 && live.apiFunctionCount === 363,
  'FRESH_LIVE_INSTALLATION_STATE_REQUIRED');
must(live.ownJobs.length === 3 && live.ownJobs.every(job => !job.active) && live.netResponseCount === 24 && live.allKnownHandler404,
  'EXACT_PAUSED_FAILED_DELIVERY_STATE_REQUIRED');
must(['ticks', 'deliveryOutcomes', 'receiverReceipts', 'quotaPeriods'].every(key => live[key] === 0), 'UNVERIFIED_DELIVERY_EFFECTS_CHANGED');
must(live.finance.journals === 9 && live.finance.lines === 18 && live.finance.publications === 3 && live.finance.classifications === 1,
  'EXACT_COMMITTED_FINANCE_SOURCE_REQUIRED');
const routingOwner = await read(base + 'worker-routing-owner-decision-20261013-r5.json', 'defc5322c1b73b56630d1834c6fb03d9cb64566f385bdf8e2070fa6d77425c95');
const routingInstalled = await read(base + 'worker-routing-deployment-source-verification-20261013-r5.json', 'a3032f6c0e137bbc05723b63d32ba6f3f4d014404ff1510c3a2b532f54fc2c0f');
must(routingOwner.decision === 'approve' && routingOwner.candidateBundleSha256 === routingInstalled.candidateBundleSha256
  && routingInstalled.ownerDecisionVerified && routingInstalled.functions.every(fn => fn.version === 2 && fn.allReturnedSourceHashesMatch)
  && routingInstalled.independentlyReturnedSourceModules === 22 && routingInstalled.existingPeopleFunctionsUnchanged,
  'EXACT_APPROVED_INSTALLED_ROUTING_V2_REQUIRED');
const providerPeer = await read(base + 'supabase-provider-independent-peer-review-20261013-r5-a1.json', 'e601409928202c60d88900c6173b455e317bbc444491336fd95f35c2ac3e44f0');
const actualAudit = await read(base + 'runtime-evidence-independent-review-20261013-r5-a4.json', '8163c3a31a63083e8b11008c421ffe03d0f84f82da5f5defb24d3e8d786aaa8a');
must(providerPeer.localTestsPassed && providerPeer.localSourceReviewPassed && actualAudit.passed, 'INDEPENDENT_PUBLIC_SOURCE_REVIEW_REQUIRED');
const fixturePeer = await read(base + 'finance-cash-fixture-independent-peer-review-20261013-r5-a1.json', '7f58386dc871755534dd304e1353b7572b5552c492e51f2b1360914ea5d71710');
await read(base + 'finance-cash-fixture-commit-intent-20261013-r5.json');
await read(base + 'finance-cash-fixture-commit-result-20261013-r5.json');
await read(base + 'finance-cash-fixture-after-commit-read-20261013-r5.json');
await read(base + 'genuine-finance-finance-20261013-r5-1791894738890/99-stop.json');
await read(base + 'genuine-finance-finance-20261013-r5-1791894738890/ratios-and-classification.json');
await read(base + 'genuine-finance-finance-20261013-r5-1791894738890/date-payroll_obligation.json');
await read(base + 'finance-stale-command-read-only-resolution-20261013-r5-a1.json');
const sourceReconciliation = await read(base + 'finance-remaining-readonly-reconciliation-20261013-r5-a2.json', '57e51d82616158e1eb3b97ab1f574a2091c9bd0f022c0079d287842724d60f67');
const prerequisites = await read(base + 'private-prerequisites-readonly-refresh-20261013-r5-a3.json');
const ready = await read(base + 'private-owner-input-ready-20261013-r5-a4.json', '67c156db4b4e7050afb324f65808cd15687c55719ae04a7932d2aff4a2b1c946');
const args = process.argv.slice(2);
must(args.length === 0 || (args.length === 2 && args[0] === '--remaining-result'
  && /^docs\/verification\/wave5\/genuine-finance-remaining-20261013-r5-[0-9]+\/99-result[.]json$/.test(args[1])), 'EXACT_REMAINING_RESULT_PATH_REQUIRED');
let remaining = null;
if (args.length) {
  remaining = await read(args[1]);
  must(remaining.passed === true && remaining.projectId === PROJECT && remaining.fullFinanceAndCashGatesComplete === false,
    'BOUNDED_GENUINE_REMAINING_FINANCE_RESULT_REQUIRED');
}
const financeDatesCompleted = live.finance.dateProposals === 3 && live.finance.dateDecisions === 3;
const exportsCompleted = live.finance.exports === 2;
must(!financeDatesCompleted || remaining !== null, 'ACTUAL_REMAINING_RESULT_REQUIRED_FOR_DATE_CLAIM');
must(!exportsCompleted || remaining !== null, 'ACTUAL_REMAINING_RESULT_REQUIRED_FOR_EXPORT_CLAIM');
const publishedAt = new Date().toISOString();
const gates = { ...prior.gates,
  genuineStatementPublicationAndRatios: true,
  genuinePayrollPaymentDateApproval: true,
  genuineAllThreePaymentDateApprovals: financeDatesCompleted,
  genuineStatementAndPipelineCsvExports: exportsCompleted,
  actualAccountingPosting: false,
  authoritativeCashDateWorkflows: false,
  scenarioRecovery: false,
  actualGovernedExports: false,
  reviewedWorkerV2Deployed: true,
  actualWorkerDelivery: false,
  actualTrustedModelUsage: false,
  staleCashVersionDenialObserved: false,
  privateProviderCoordinatorPassed: false,
  authenticatedNative: false,
  nativeKeyboard: false,
  targetScale2000SessionLoad: false,
  all109OwnerCriteriaAccepted: false,
  wholeSystemAccepted: false
};
const next = {
  shared: 'Complete all scoped user workflows and denied/revoked/recovery cases; installed SQL and local evidence are separate gates.',
  process: 'Preserve AC-551, AC-552 and AC-553 acceptance. Extend the genuine reads across 500 scopes to the remaining provider and native cases.',
  pipeline: 'Genuine 500-scope forecasts passed. Complete historical/realized boundaries, governed export coverage and native review.',
  finance: 'Three genuine statements and six exact ratios passed. Finish remaining date/export evidence, posting authorization and native workflows; administrative balanced fixtures are not user posting.',
  cash: 'Preserve the successful payroll-date approval; finish correction/reimbursement dates, stale conflict handling, all five cash families, scenarios and encrypted recovery after the real cutoff or separately reviewed contract correction.',
  ai: 'Private model key remains pending. Execute at most four reviewed actual calls with authoritative source, exact numeric and human approval checks.',
  integration: 'Approved routing v2 is deployed with 22 matching returned modules. All 24 scheduled HTTP responses are NOT_FOUND; jobs 4, 5 and 6 remain paused. Review the separate platform-origin candidate before deployment and prove actual delivery.',
  billing: 'Synthetic activation and one lease case passed. Complete admission/quota/seat contention preserving original membership/history and caps.',
  operator: 'Complete genuine MFA health/revocation under the exact short-lived authority.',
  native: 'Human UAC/private password step and isolated profile/package remain pending; authenticated Connected workflows, keyboard, switch/restart/revoke checks are open.',
  provider: 'The independent review passed 164 local checks and audited saved evidence. Verified private PostgreSQL, the complete coordinator, external observer and all contention cases remain open.',
  ownership: 'Only AC-551, AC-552 and AC-553 are accepted. Obtain explicit decisions against complete statements and tested evidence for the remaining 106 criteria.',
  quality: 'The original 83 and eight later approved golden decisions remain resolved in historical evidence: 2010 passed, 0 failed, 0 skipped. Collect fresh analysis, tests, builds and renders after application source edits.',
  load: 'Reads across 500 companies with two genuine sessions are narrow workflow evidence. Execute the reviewed load protocol with 2000 distinct genuine sessions and all contention cases.'
};
const currentRows = historical.map(row => ({ id: row.id, bundle: row.bundle, ownerAccepted: row.ownerAccepted,
  currentDisposition: row.ownerAccepted ? 'Explicit owner acceptance preserved.' : 'Owner acceptance remains open.',
  currentFoundation: '114 migrations / 363 API functions; six genuine actors with MFA, 500 companies and scoped pipeline/process workflows, three statements and six ratios. Workers v2 are installed; delivery failed.',
  userWorkflowAcceptance: row.ownerAccepted, nextEvidence: next[row.bundle] }));
must(currentRows.every(row => typeof row.nextEvidence === 'string'), 'COMPLETE_CURRENT_REQUIREMENT_MAPPING_REQUIRED');
const checkpoint = { ...prior, kind: 'current-actual-runtime-successor', publishedAt, liveObservedAt: live.observedAt,
  supersedes: evidence[base + 'approved-runtime-progress-checkpoint-20261013-r5-a2.json'],
  historicalCheckpointProseWarning: 'The predecessor remains unchanged; this successor carries later owner approval, deployment, failures and finance evidence.',
  genuineSourceWorkflowEvidence: { ...prior.genuineSourceWorkflowEvidence, independentPriorCommandPreservationAudit: 'Passed with preserved label/schema findings; see the independent saved-evidence report.' },
  localVerification: { ...prior.localVerification, independentProviderTests: 164, independentSourceEvidenceAuditPassed: true },
  persistentRuntime: { ...prior.persistentRuntime, version: 2, returnedModulesMatched: 22, scheduledHttpResponses: 24,
    jobs: live.ownJobs, candidateApproved: true, candidateDeployed: true, independentReviewPending: false,
    nextPlatformOriginCandidateApproved: false, nextPlatformOriginCandidateDeployed: false },
  finance: { ...live.finance, administrativeFixtureBalanced: true, statementTypes: ['profit_loss', 'balance_sheet', 'trial_balance'],
    ratiosVerified: 6, payrollDateDistinctApproval: true, allThreeDatesCompleted: financeDatesCompleted,
    statementAndPipelineCsvExportsCompleted: exportsCompleted, staleVersionRequestTimedOut: true,
    staleVersionErrorResponseObserved: false, originalStaleCommandReplayed: false,
    expectedStatementProcessAppends: 3, baselineSourceHashReconstructed: sourceReconciliation.originalSourceSha256,
    rawSourceHashAtHistoricalReconciliation: sourceReconciliation.currentWholeSourceSha256,
    wholeFinanceAndCashAccepted: false },
  native: { ...prior.native, currentPrerequisites: prerequisites, provisioningConfirmed: false },
  privateOwnerReady: { expiresAt: ready.expiresAt, secretValuesPublished: false },
  remainingFinanceResult: remaining, ownerAcceptedCriteria: 3, remainingUnacceptedCriteria: 106,
  privateDatabaseAndModelInputReady: prerequisites.privateDatabaseAndModelInputReadyFileExists,
  gates, evidence, wholeSystemComplete: false };
const matrix = { kind: 'current-requirement-readiness-successor', publishedAt, projectId: PROJECT,
  approvedSetupBundleSha256: BUNDLE, requirementCount: 109, ownerAcceptedCriteria: 3, remainingUnacceptedCriteria: 106,
  acceptedCriterionIds: accepted, canonicalHistoricalRowsSha256: canonicalSha256, preservedRowsAreHistorical: true,
  historicalRowWarning: 'Original developmentStatus prose predates installation. CurrentRows and this checkpoint carry current evidence, without additional acceptance.',
  preservedRows: historical, currentRows, gates, evidence, production: false, realBilling: false, wholeWaveComplete: false };
async function save(file, value) {
  const bytes = typeof value === 'string' ? value : JSON.stringify(value, null, 2) + '\n';
  const handle = await fs.open(path.join(root, file), 'wx');
  try { await handle.writeFile(bytes); await handle.sync(); } finally { await handle.close(); }
  return { path: file, sha256: hashBytes(bytes) };
}
const outputs = [];
outputs.push(await save(base + 'approved-runtime-progress-checkpoint-20261013-r5-a3.json', checkpoint));
outputs.push(await save(base + 'requirement-readiness-matrix-20261013-r5-a3.json', matrix));
outputs.push(await save(base + 'requirement-readiness-matrix-20261013-r5-a3.md',
  `Live refresh ${live.observedAt}. Owner acceptance remains **3/109**: AC-551, AC-552 and AC-553. The other 106 criteria remain open.\n\n` +
  '| Requirement | Bundle | Accepted | Current gate / next evidence |\n|---|---|---|---|\n' +
  currentRows.map(row => `| ${row.id} | ${row.bundle} | ${row.ownerAccepted ? 'Yes' : 'No'} | ${row.nextEvidence} |`).join('\n') + '\n'));
outputs.push(await save('docs/development/wave5-status-20261013-r5-a3.md',
  `Jentra OS remains incomplete. Live refresh ${live.observedAt}: **114 migrations / 363 API functions**. All 71 additional approved migrations are installed; the original six Wave 5 migrations and 43 ledger entries are preserved.\n\n` +
  'Six genuine Auth Admin actors passed real MFA/AAL2. The exact 500-company setup and pipeline/process workflows across 500 scopes passed. The independent provider review passed 164 local checks and audited saved evidence, with label/schema findings preserved. The full private provider and 2000-session load protocol remain open.\n\n' +
  `The bounded administrative finance fixture contains 10 accounts, nine balanced journals and 18 lines. Genuine actors then published profit/loss, balance sheet and trial balance statements, verified six exact ratios and completed a payroll-date approval with a distinct approver. Current approved date pairs: ${live.finance.dateDecisions}/3; governed CSV export registrations: ${live.finance.exports}/2. User journal posting remains unproved. The stale-version negative request timed out; no error response was observed or original command replayed. Three expected statement process events explain the raw source hash change; excluding exactly those command IDs reproduces the original baseline.\n\n` +
  'The cash horizon starts October 14 UTC while the live clock remains October 13; the installed guard rejects a future horizon with the current cutoff. Preserve actual mapping/audit times and clock. All five cash families, scenario recovery and complete export coverage remain open.\n\n' +
  'Owner-approved routing v2 was deployed; all 22 returned source modules match and the People functions are preserved. All 24 scheduled HTTP responses returned NOT_FOUND, with zero worker ticks, outcomes, receiver receipts and quota periods. Exact jobs 4, 5 and 6 remain paused. The separate candidate for the fixed Supabase platform origin requires concrete review and a new source decision. The actual internal Request URL diagnosis remains an inference.\n\n' +
  'Fresh read-only checks show the isolated Windows account/package and private database/model input readiness remain pending. The user must handle UAC and hidden password entry. Authenticated native workflows, keyboard, actual delivery/model usage, all contention/load cases and 106 owner criteria remain open.\n\n' +
  'Owner acceptance remains **3/109**. The original 83 and eight later golden decisions remain resolved in preserved evidence: 2010 passed, 0 failed, 0 skipped. No application source edit or Flutter job occurred during these helper/candidate changes. All 5539 original approval inputs and 109 historical rows are preserved. No reset, clean, broad staging, commit or push occurred. Production and real billing remain excluded.\n\n' +
  'See the [current checkpoint](../verification/wave5/approved-runtime-progress-checkpoint-20261013-r5-a3.json), [requirement matrix](../verification/wave5/requirement-readiness-matrix-20261013-r5-a3.md) and [next session](wave5-next-session-20261013-r5-a3.md).\n'));
outputs.push(await save('docs/development/wave5-next-session-20261013-r5-a3.md',
  `Continue JentraOS at C:\\Users\\sheha\\Desktop\\Jentra OS,project${PROJECT}. Readwave5-status-20261013-r5-a3.md,currentcheckpoint/matrix and their exactbindings. Live114migrations/API363; do not replay71additional ororiginal6, Authusers/factors/bootstrap/consumed onceintents.\n\n` +
  'Exactsetup approvaldb525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b remainsvalid. Existing encryptedownertoken reuse wasexplicitlyauthorized; no secretoutput/replacementrequest. ReadyA4expires16:56:06.346UTC October13; fresh sameproject/org renewal needed afterexpiry. PrivatePg/modelinput andhumanUAC/privateWindowspassword remainpending.\n\n' +
  'Routingv2 exactbce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552 wasapprovedanddeployed,22modulesmatch. Actual24scheduledHTTP404NOT_FOUND,0effects,jobs4/5/6paused. Preserveoriginalexpiry/caps andPeoplefunctions. Review separatev3candidate andobtain exactnewsourceapproval beforedeployment.\n\n' +
  `Finance fixturecommitted,3statements/6ratios/1initialpayroll-dateapproval passed. Current${live.finance.dateDecisions}datepairs/${live.finance.exports}exports. Originalstale command92e523de-6d82-d54a-0bfe-e81a78593a96 timedout; nevercallits denialverified orreplayblindly. Remaininghelper must verify fresh stale0/activity0, allowed process appends andunchangedoriginalbaselineff90ee8cb1e1a33982eedfc1d05a8b8118a463d8e2bd9a36ac9f1469eb40be38. CashhorizonOct14 requiresrealclock/cutoff; nofakebackdating.\n\n` +
  'Allthree agents resumed:runtime_provider preparesremainingdates/CSV,exports;provider_review checks actualfinance/correctsource/routing;native_matrix preparesfixed-platform-origin candidate plusseparate40001error investigation. Rootserializes privatewrites/heavyFlutter andpublishesdatedsuccessors.\n\n' +
  'Continueallunblocked approvedwork. Nojournalgrantinvention. Distinguish installedSQL,genuineMFA/native, actualdelivery/model, fullcontention/load andowneracceptance. OwneracceptanceONLYAC551/552/553=3/109;106open. Preservegoldens83plus8/2010historicalpasses, sharedW3/W4/Employee/acceptance/sessionstores andall5539approvedinputs. Noreset/clean/stash/broadstage/commit/push. Production/realbillingexcluded.\n'));
await loadApprovedInputs();
must(hashBytes(JSON.stringify(matrix.preservedRows)) === canonicalSha256, 'HISTORICAL_ROWS_CHANGED');
process.stdout.write(JSON.stringify({ published: true, liveObservedAt: live.observedAt, ownerAcceptedCriteria: 3,
  additionalCriteriaAccepted: 0, actualDelivery: false, wholeSystemComplete: false, outputs }) + '\n');
