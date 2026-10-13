import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT_ID, hashBytes, hashJson } from './runtime_contract.mjs';

// Source/local peer report only. This generator cannot issue an executable
// private-factory attestation and never reads a private credential/facility.
const root = fileURLToPath(new URL('../../', import.meta.url));
const [attempt, localAttempt, journalAttempt, caseAttempt, providerPlanAttempt, membershipAttempt] = process.argv.slice(2);
if (![attempt, localAttempt, journalAttempt, caseAttempt, providerPlanAttempt, membershipAttempt].every(value => /^a[1-9][0-9]*$/.test(value ?? '')))
  throw new Error('EXPLICIT_NEW_REVIEW_AND_EVIDENCE_ATTEMPTS_REQUIRED');
const folder = 'docs/verification/wave5';
const prefix = `${folder}/supabase-provider-independent-peer-review-20261013-r5-${attempt}`;
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { path: relative, sha256: hashBytes(bytes), bytes: bytes.length }; };
const read = async relative => ({ binding: await bind(relative), value: JSON.parse(await fs.readFile(path.join(root, relative), 'utf8')) });
const local = await read(`${folder}/independent-provider-local-verification-20261013-r5-${localAttempt}.json`);
const journal = await read(`${folder}/preparation-journal-independent-verification-20261013-r5-${journalAttempt}.json`);
const membership = await read(`${folder}/membership-preparation-independent-verification-20261013-r5-${membershipAttempt}.json`);
const caseProbe = await read(`${folder}/preparation-journal-peer-probe-20261013-r5-${caseAttempt}.json`);
const installed = await read(`${folder}/installed-verification-plan-peer-audit-20261013-r5.json`);
const plan = await read(`${folder}/supabase-provider-preparation-plan-20261013-r5-${providerPlanAttempt}.json`);
const oldLocal = await read(`${folder}/supabase-provider-local-verification-20261012-r5-a8.json`);
const wrongOracle = await read(`${folder}/supabase-provider-local-verification-20261013-r5-a3.json`);
const oldFilesystem = await read(`${folder}/supabase-provider-local-verification-20261013-r5-a14.json`);
const oldCombined = await read(`${folder}/independent-provider-local-verification-20261013-r5-a3.json`);
const oldCapacity = await read(`${folder}/supabase-provider-local-verification-20261013-r5-a19.json`);
const oldCallbackFixture = await read(`${folder}/independent-provider-local-verification-20261013-r5-a5.json`);
const oldCoordinator = await read(`${folder}/supabase-provider-local-verification-20261013-r5-a17.json`);
const actualPublicEvidence = await read(`${folder}/runtime-evidence-independent-review-20261013-r5-a4.json`);
const oldCase = await read(`${folder}/preparation-journal-peer-probe-20261013-r5-a1.json`);
const oldJournal = await read(`${folder}/preparation-journal-independent-verification-20261013-r5-a1.json`);
const oldMembership = await read(`${folder}/membership-preparation-independent-verification-20261013-r5-a1.json`);
const runtime = await read(`${folder}/complete-app-runtime-review-20261010-r5.json`);
const owner = await read(`${folder}/runtime-owner-decision-20261012-r5.json`);
const rootLog = await bind(`${folder}/runtime-node-tests-20261013-r5-a4.log`);
const rootLogText = await fs.readFile(path.join(root, rootLog.path), 'utf8');
const rootLogCount = name => Number(rootLogText.match(new RegExp(`^# ${name} (\\d+)$`, 'm'))?.[1]);
const rootLogSummary = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name => [name, rootLogCount(name)]));
if (rootLogSummary.tests !== 148 || rootLogSummary.pass !== 148
  || ['fail', 'cancelled', 'skipped', 'todo'].some(name => rootLogSummary[name] !== 0)) throw Error('ACTUAL_ROOT_148_LOG_MISMATCH');
const currentBindings = await Promise.all(local.value.filesAfter.map(value => bind(value.path)));
const currentPlanSources = await Promise.all(plan.value.sources.map(value => bind(value.path)));
if (local.value.passed !== true || local.value.selectedSourcesUnchanged !== true
  || hashJson(local.value.filesAfter) !== hashJson(currentBindings) || journal.value.passed !== true
  || journal.value.selectedSourcesUnchanged !== true || membership.value.passed !== true
  || membership.value.selectedSourcesUnchanged !== true || typeof caseProbe.value.passed !== 'boolean'
  || caseProbe.value.selectedSourcesUnchanged !== true
  || installed.value.passed !== true || oldLocal.value.passed !== false || wrongOracle.value.passed !== false
  || oldCase.value.passed !== false || oldJournal.value.passed !== false || oldMembership.value.passed !== false
  || oldFilesystem.value.passed !== false || oldCombined.value.passed !== false
  || oldCapacity.value.passed !== false || oldCoordinator.value.passed !== false || oldCallbackFixture.value.passed !== false
  || actualPublicEvidence.value.passed !== true)
  throw new Error('CURRENT_PASSING_SOURCE_BOUND_EVIDENCE_AND_PRESERVED_FAILURES_REQUIRED');
if (plan.value.actualExecutionReady !== false || plan.value.privateFactoryConfigured !== false
  || plan.value.runtimeReview.sha256 !== runtime.binding.sha256 || plan.value.ownerDecision.sha256 !== owner.binding.sha256
  || plan.value.sources.some((value, index) => value.sha256 !== currentPlanSources[index].sha256 || value.bytes !== currentPlanSources[index].bytes))
  throw new Error('CURRENT_PUBLIC_PREPARATION_PLAN_REQUIRED_WITH_PRIVATE_GATES_OPEN');
for (const evidence of [local, journal, membership]) {
  if (hashJson(await bind(evidence.value.log.path)) !== hashJson(evidence.value.log)) throw new Error('TEST_LOG_BINDING_MISMATCH');
}
if (owner.value.runtimeBundleSha256 !== runtime.value.bundleSha256 || owner.value.runtimeFileSha256 !== runtime.binding.sha256
  || owner.value.decision !== 'approve' || runtime.value.projectId !== PROJECT_ID)
  throw new Error('FROZEN_RUNTIME_APPROVAL_BINDING_MISMATCH');
const coordinatorIntentVerified = caseProbe.value.passed === true && caseProbe.value.observedOriginalCaseIdInJournal === true;
const report = {
  kind: 'independent-wave5-supabase-provider-source-peer-review', projectId: PROJECT_ID,
  observedAt: new Date().toISOString(), reviewer: '/root/provider_review_20261013',
  result: coordinatorIntentVerified ? 'source-local-review-passed-with-runtime-gates-open' : 'changes-requested-source-local-only',
  localTestsPassed: true, localSourceReviewPassed: coordinatorIntentVerified,
  scope: 'Public source, controlled in-memory probes, temporary encrypted file persistence and a separately linked offline review of saved public live evidence. No configured private factory/sink, private credential, live SQL/Auth/MFA/SDK or native operation was invoked by this peer.',
  runtime: runtime.binding, runtimeBundleSha256: runtime.value.bundleSha256, ownerDecision: owner.binding,
  operationScopeSha256: runtime.value.sourceContinuation.unchangedRuntimeOperationScopeSha256,
  sourceBindingsVerified: true, currentBindings, sourceBindingsSha256: hashJson(currentBindings),
  generator: await bind('tools/wave5/write_provider_peer_review_20261013.mjs'),
  localVerification: { ...local.binding, command: local.value.command, actualStartedAt: local.value.actualStartedAt,
    actualFinishedAt: local.value.actualFinishedAt, summary: local.value.summary, childExitCode: local.value.childExitCode,
    selectedSourcesUnchanged: true, log: local.value.log },
  preparationVerification: { ...journal.binding, summary: journal.value.summary, log: journal.value.log },
  membershipCancellationVerification: { ...membership.binding, summary: membership.value.summary, log: membership.value.log },
  coordinatorPreparationProbe: { ...caseProbe.binding, entriesBeforePreparation: caseProbe.value.entriesBeforePreparation,
    entryTypes: caseProbe.value.entryTypes, observedOriginalCaseIdInJournal: caseProbe.value.observedOriginalCaseIdInJournal,
    passed: caseProbe.value.passed, failureCode: caseProbe.value.failureCode },
  installedPlanFileAudit: { ...installed.binding, counts: installed.value.counts,
    migrationInputsMatched: installed.value.migrationInputsMatched, queryBindings: installed.value.queryBindings,
    originalPlan: installed.value.originalPlan, successorPlan: installed.value.successorPlan, actualInstalledQueriesExecutedByReviewer: false },
  currentPreparationPlan: plan.binding,
  rootSerialTestLog: { ...rootLog, summary: rootLogSummary,
    sourceHashesEmbeddedInLog: false, limitation: 'Actual root-provided 148-test TAP log independently read; the fresh peer run separately binds current source hashes.' },
  savedPublicRuntimeEvidenceReview: { ...actualPublicEvidence.binding,
    scopesRevalidated: actualPublicEvidence.value.sourceWorkflows.scopesRevalidated,
    evidenceLabelAndSchemaFindings: actualPublicEvidence.value.actionableFindings,
    reviewerLiveOperations: 0, fullProviderCoordinatorPassed: false, targetScaleLoadPassed: false },
  findings: [
    { id: 'P-01', status: 'fixed-in-reviewed-public-source', title: 'Mutable database and TLS configuration',
      evidence: 'Independent driver probes preserve exact project host, TLS verification and copied CA bytes across caller mutation and an earlier driver mutation. An in-memory recreation of the old mutable configuration is detected without rewriting source.' },
    { id: 'P-02', status: 'fixed-in-reviewed-public-source', title: 'Quota timestamp precision',
      evidence: 'Subscription periods are read as PostgreSQL text and sent without JavaScript Date round trips. Independent exact microsecond comparisons detect an in-memory recreation of the previous truncation.' },
    { id: 'P-03', status: 'fixed-in-reviewed-public-source', title: 'Scope-specific synthetic billing target',
      evidence: 'All 500 reviewed scopes are checked. Only runtime and load-001 require syntheticTarget=true; other scopes require false. Foreign tenants and inverted flags fail, and the previous always-true assumption is detected in memory.' },
    { id: 'P-04', status: coordinatorIntentVerified ? 'fixed-in-reviewed-public-source' : 'provider-fixed-coordinator-change-required',
      title: 'Unjournaled preparation mutations',
      evidence: 'The bound provider preparation guard persists the original membership baseline and each SQL/RPC intent before mutation, then acknowledges a confirmed or uncertain outcome. Failed persistence stops later dispatch. '
        + (coordinatorIntentVerified ? 'The public coordinator case intent now precedes preparation.' : 'The public coordinator still calls prepareRace before its first case journal entry; the fresh ordering probe has zero prior entries and requires a coordinator change.') },
    { id: 'P-05', status: 'fixed-in-reviewed-public-source', title: 'Caller overwrite of reserved journal bindings',
      evidence: 'An independent entry with competing project, runtime, plan, sink, sequence, record ID and time fields cannot overwrite the journal envelope. The original failing controlled test remains saved.' },
    { id: 'P-06', status: 'fixed-in-reviewed-public-source', title: 'Dispatch after uncertainty while waiting for persistence',
      evidence: 'An independent delayed intent receipt cannot resume a mutation after an acknowledged sibling becomes uncertain. The original failing controlled test remains saved.' },
    { id: 'P-07', status: 'fixed-in-reviewed-public-source', title: 'Membership COMMIT after cancellation while waiting for persistence',
      evidence: 'An independent delayed COMMIT-intent receipt followed by cancellation cannot begin COMMIT; the controlled fixture rolls back its unchanged original rows. The original failing controlled test remains saved.' },
    { id: 'P-08', status: 'fixed-in-reviewed-public-source', title: 'Rejection test depended on a 50 ms host scheduling window',
      evidence: 'The rejection-path test uses a deterministic clock and requires an actual rejected dispatch rather than assuming a request runs within 50 ms of host time. Actual host load thresholds remain unchanged. The actual previous combined 113/114 failure remains saved.' },
    { id: 'P-09', status: 'fixed-in-reviewed-public-source', title: 'Capacity test depended on a 40 ms host scheduling window',
      evidence: 'The capacity-path test uses deterministic time and holds the first actual transport, requiring a nonzero dispatch before retaining an unsupported inflight result. The previous 100/101 a19 failure remains saved. Actual host load limits are unchanged.' },
    { id: 'P-10', status: 'fixed-in-reviewed-public-source', title: 'Private configuration references remained caller mutable after binding',
      evidence: 'The high-level factory snapshots the documented callbacks and scalars after canonical binding and before asynchronous work. The independent preflight callback replacement probe passes and detects an in-memory removal of the snapshot, without rewriting source or calling a database. Nested DB/TLS/Auth/calendar copying remains intact; private callback closure internals and concrete facility readiness remain unverified.' },
    { id: 'P-11', status: 'fixed-in-reviewed-public-source', title: 'Forecast response mistook server request ID for caller command ID',
      evidence: 'Actual saved forecast responses distinguish command_id from server-generated request_id and correlation_id. The outcome mapper requires the original command_id and valid separate IDs; a response substituting request_id as command_id is rejected. Activation retains its different fixed contract.' },
    { id: 'P-12', status: 'fixed-in-reviewed-public-source', title: 'Actual installed compound permission denial was treated as uncertain',
      evidence: 'The exact installed message Permission denied or multi-factor authentication required. is a denial only with SQLSTATE 42501 and HTTP 403. Wrong status, state or text stays uncertain. The regression uses the retained genuine response without constructing Auth claims or making new calls.' },
  ],
  reviewedAreas: [
    { area: 'Transport and overlap', conclusion: 'Verified TLS precedes body dispatch; aborted, expired or failed queued requests cannot send later. Each genuine session requires a distinct connection. Client HTTP interval overlap is measured; backend server execution overlap is not inferred.' },
    { area: 'Auth and MFA', conclusion: 'Source requires online Auth identity and matching committed server session/factor evidence, with 2,000 distinct session identities for the reviewed load population. Controlled tests are not genuine sign-in or MFA evidence.' },
    { area: 'Secrets and public evidence', conclusion: 'Public outcomes whitelist identity, counters, safe codes and hashes. Raw API errors, private session values and invitation tokens stay outside the public case journal. Recovery tokens may only enter the separately reviewed private preparation sink.' },
    { area: 'Fixture restoration', conclusion: 'Exact newly reviewed memberships, original roles and assignments are retained. The seat cap is raised before reactivation; versions and immutable history are not rewound or deleted. Unknown outcomes stop automatic restoration. Restart reconciliation still requires the actual private journal/factory review.' },
    { area: 'Encrypted recovery persistence', conclusion: 'Public sink source uses AES-256-GCM with the bound envelope as authenticated data, copied private keys, exclusive new files, actual file-content sync and bounded read-only recovery. Recovery is an incomplete available prefix unless its copied expected head matches the separately retained count and final storage hash; even a complete read never permits automatic replay. An independent real temporary-file tail-loss test verifies this behavior and preserves the surviving bytes. The configured private key, directory ACLs, trusted head and Windows directory-entry/power-loss durability remain unverified.' },
    { area: 'Reviewed caps and unsupported boundaries', conclusion: 'The immutable reviewed caps remain unchanged. 10001Rows and 8MiBPlus1Byte are unavailable under those caps; 101Groups needs reviewed reference evidence. The separately linked saved runtime evidence has an actual 367-day LIMIT_EXCEEDED response; this source review executes no new runtime boundary call.' },
    { area: 'Management API bridge', conclusion: 'The fixed project endpoint accepts only scoped, typed SELECT recipes, verifies TLS and actual read-only/isolation metadata, and explicitly reports committedTransactionProof=false and repeatableReadProof=false. It cannot replace the PostgreSQL provider needed for committed contention evidence.' },
    { area: 'Persistent workers and model usage', conclusion: 'No complete remote outbound observer is implemented or independently verified. Ingress logs and database attempt rows cannot establish actual delivery/model sends or complete timed-window coverage. Zero sends are not fabricated from empty rows.' },
  ],
  preservedFailures: [
    { ...oldLocal.binding, summary: oldLocal.value.summary, description: 'Oct12 a8 actual 73/74 failed TLS deadline expectation; not rewritten.' },
    { ...wrongOracle.binding, summary: wrongOracle.value.summary, description: 'Oct13 a3 actual 81/82 failed an analytics.process_events test oracle; frozen recipe correctly uses workflow.process_events. Test correction does not alter approved SQL.' },
    { ...oldFilesystem.binding, summary: oldFilesystem.value.summary, description: 'Oct13 a14 actual 98/99 encountered sandbox EPERM while creating a controlled temporary junction. A later auto-reviewed local file run and this fresh independent suite executed the junction assertion successfully without a skip.' },
    { ...oldCombined.binding, summary: oldCombined.value.summary, description: 'Independent combined a3 actual 113/114 failed the real-clock 50 ms rejection test: failureCode=null versus LOAD_REQUEST_REJECTED. A denied callback cannot be assumed to execute during such a short host scheduling window.' },
    { ...oldCapacity.binding, summary: oldCapacity.value.summary, description: 'Provider a19 actual 100/101 failed the real-clock 40 ms capacity test after zero dispatched requests. It remains preserved before deterministic correction.' },
    { ...oldCoordinator.binding, summary: oldCoordinator.value.summary, description: 'Provider a17 actual 99/101 retained the first red coordinator intent and timing-oracle checks; it was not overwritten by a later pass.' },
    { ...oldCallbackFixture.binding, summary: oldCallbackFixture.value.summary, description: 'Independent a5 actual 153/155 retained an incomplete controlled calendar in the two new callback probes. The calendar guard stopped before callback selection; only the peer fixture was corrected, with no provider source change.' },
    { ...oldCase.binding, description: 'Coordinator failed probe: zero case journal entries existed before preparation.' },
    { ...oldJournal.binding, summary: oldJournal.value.summary, description: 'Two independent journal assertions failed: reserved envelope and delayed dispatch after uncertainty.' },
    { ...oldMembership.binding, summary: oldMembership.value.summary, description: 'Membership fixture resolved and began COMMIT after cancellation during its delayed intent receipt.' },
  ],
  nextRequiredTechnicalReview: [
    ...(coordinatorIntentVerified ? [] : ['Append a source-bound public case-preparation intent before provider.prepareRace; preserve its exact original case/scope/fixture/restoration identities and verify a failed public journal write prevents preparation. Then rerun the case ordering probe, combined tests and source-bound preparation successor.']),
    'Independently inspect the actual private factory, driver source, private append-only sink durability/recovery and source bindings before executable preparation attestation.',
    'Verify actual private online preflight, restored owner connection and dedicated company/account/session identities without exposing credentials.',
    'Provide a source-reviewed complete observer for local and remote delivery/model outbound calls across the exact workload window.',
    'Run root-owned installed queries and genuine MFA, authenticated native keyboard/workflows, actual delivery/model/export, independent-session contention and target-scale load checks as separate gates.',
  ],
  officialPublicReferences: [
    { url: 'https://supabase.com/docs/reference/api/v1-run-a-query', use: 'Generic query endpoint supports query, parameters and read_only; its contract does not provide a repeatable-read COMMIT proof.' },
    { url: 'https://raw.githubusercontent.com/supabase/mcp/main/packages/mcp-server-supabase/src/platform/api-platform.ts', use: 'Official MCP executeSql forwards query, parameters and read_only to the generic endpoint.' },
    { url: 'https://supabase.com/docs/reference/api/v1-read-only-query', use: 'Separate dedicated read-only endpoint documentation does not establish that the generic connected client uses it.' },
  ],
  concretePrivateFactoryReviewed: false, concretePrivateSinkReviewed: false, completePrivateFacilitiesReady: false,
  publicEncryptedSinkSourceReviewed: true, controlledTemporaryFilesystemPersistenceTested: true,
  executablePreparationAttestationIssued: false, runtimeExecutionReady: false,
  executedLive: false, privateCredentialsRead: false, databaseCalls: 0, authWrites: 0,
  fabricatedJwtOrAuthRows: false, providerNetworkCalls: 0, sdkJobs: 0, nativeActions: 0,
  ownerAcceptedCriteria: 3, ownerCriteria: 109,
  gates: { installedSql: false, genuineMfa: false, authenticatedNative: false, actualDelivery: false,
    actualModelUsage: false, governedExports: false, independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false },
  production: false, realBilling: false, installOriginalSix: false,
  limitation: 'This is an independent public source/local review. It is deliberately not kind wave5-runtime-harness-independent-preparation-review and cannot be promoted to a review of missing private facilities or completed runtime acceptance.',
};
const paragraphs = [
  '# Independent Wave 5 Supabase provider peer review — 2026-10-13',
  '',
  `**${local.value.summary.pass}/${local.value.summary.tests} local tests passed**, with no failures/skips and unchanged selected source hashes. ${coordinatorIntentVerified ? 'Public source review passed within those controlled boundaries.' : 'Source review requires one coordinator change: record the public case intent before calling preparation.'} The actual private factory and facilities remain unreviewed; runtime execution readiness and every live gate remain open. Owner acceptance remains **3/109**.`,
  '',
  `The frozen runtime bundle is \`${runtime.value.bundleSha256}\`; its existing owner approval is retained in [the recorded decision](runtime-owner-decision-20261012-r5.json). No second scope decision is requested for these fixes. No original six migrations, approved images, acceptance stores, sessions or shared Wave 3/4/Employee files were changed by this review.`,
  '',
  '## Findings and regressions',
  '',
  ...report.findings.flatMap(finding => [`- **${finding.id}: ${finding.title} — ${finding.status === 'provider-fixed-coordinator-change-required' ? 'provider fixed; coordinator change required' : 'fixed in the reviewed public source'}.** ${finding.evidence}`]),
  '',
  '## Actual local evidence',
  '',
  `- [Fresh serial local run](${local.binding.path.split('/').at(-1)}): ${local.value.summary.pass}/${local.value.summary.tests}, exit ${local.value.childExitCode}, ${local.value.actualStartedAt} through ${local.value.actualFinishedAt}. SHA-256 \`${local.binding.sha256}\`.`,
  `- [Root serial TAP log](${rootLog.path.split('/').at(-1)}): independently read 148/148, no failures/skips. The log has no embedded source bindings; the fresh peer run above separately binds current sources. SHA-256 \`${rootLog.sha256}\`.`,
  `- [Independent journal checks](${journal.binding.path.split('/').at(-1)}): ${journal.value.summary.pass}/${journal.value.summary.tests}. SHA-256 \`${journal.binding.sha256}\`.`,
  `- [Independent membership cancellation check](${membership.binding.path.split('/').at(-1)}): ${membership.value.summary.pass}/${membership.value.summary.tests}. SHA-256 \`${membership.binding.sha256}\`.`,
  `- [Coordinator case ordering probe](${caseProbe.binding.path.split('/').at(-1)}): ${coordinatorIntentVerified ? 'original case ID recorded before preparation' : 'failed; zero case journal entries preceded preparation'}. SHA-256 \`${caseProbe.binding.sha256}\`.`,
  `- [Installed-plan file audit](${installed.binding.path.split('/').at(-1)}): all 71 migration inputs match the frozen ordered review; a2 retains **541 function bodies, 215 tables, 72 explicit forced-RLS checks and 18 grant checks**. These are prepared expectations, not installed results. SHA-256 \`${installed.binding.sha256}\`.`,
  `- [Saved public runtime evidence review](${actualPublicEvidence.binding.path.split('/').at(-1)}): independently revalidated all 500 projections, nine preserved IDs, 491 new command responses and bounded activation/lease effects. Five stale preservation labels and one overwritten intermediate count remain documented; strict failed peer checks are retained. No missing count or complete outbound observation is fabricated. SHA-256 \`${actualPublicEvidence.binding.sha256}\`.`,
  '',
  '## Boundaries of this review',
  '',
  ...report.reviewedAreas.flatMap(area => [`**${area.area}.** ${area.conclusion}`, '']),
  'The generic Management query endpoint documents typed parameters and `read_only`; it does not promise a repeatable-read transaction COMMIT. The official MCP source forwards those fields to that endpoint. This supports retaining the bridge’s explicitly false committed/repeatable-read proof fields. See [Supabase query API](https://supabase.com/docs/reference/api/v1-run-a-query), [official MCP source](https://raw.githubusercontent.com/supabase/mcp/main/packages/mcp-server-supabase/src/platform/api-platform.ts) and [separate read-only API](https://supabase.com/docs/reference/api/v1-read-only-query).',
  '',
  '## Required before runtime completion',
  '',
  ...report.nextRequiredTechnicalReview.map(value => `- ${value}`),
  '',
  '## Historical failures preserved',
  '',
  ...report.preservedFailures.map(value => `- [${value.path.split('/').at(-1)}](${value.path.split('/').at(-1)}): ${value.description} SHA-256 \`${value.sha256}\`.`),
  '',
  `The JSON companion records current source hashes, actual commands/logs and scope bindings. This document does not issue an executable private-factory attestation, perform a live database/Auth/network/native operation, or accept any further requirements.`,
  '',
];
const bytes = JSON.stringify(report, null, 2) + '\n', markdown = paragraphs.join('\n');
await fs.writeFile(path.join(root, `${prefix}.json`), bytes, { flag: 'wx', mode: 0o600 });
await fs.writeFile(path.join(root, `${prefix}.md`), markdown, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: `${prefix}.json`, sha256: hashBytes(bytes), markdown: `${prefix}.md`,
  markdownSha256: hashBytes(markdown), result: report.result, pass: local.value.summary.pass,
  tests: local.value.summary.tests, runtimeExecutionReady: false, ownerAcceptedCriteria: 3, ownerCriteria: 109 }) + '\n');
