import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { hashBytes, hashJson, PROJECT_ID, requireGuard, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';
import { RUNTIME_FIXTURE_BINDING, RACE_FIXTURES, INVALID_BOUNDARIES, FIXTURE_CAPS } from './runtime_fixture_spec.mjs';
import { CASE_READ_RECIPES } from './supabase_runtime_provider.mjs';
import { READ_QUERY_SHA256, committedRecipeHash } from './supabase_read_store.mjs';

const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url))), folder = 'docs/verification/wave5';
const localName = process.argv[2], suffix = process.argv[3], evidenceDate = process.argv[4] ?? '20261012';
requireGuard(/^supabase-provider-local-verification-20[0-9]{6}-r5-a[1-9][0-9]*\.json$/.test(localName ?? '') && /^20[0-9]{6}$/.test(evidenceDate)
  && /^a[1-9][0-9]*$/.test(suffix ?? ''), 'NEW_EVIDENCE_FILENAME_REQUIRED');
const read = async relative => { const bytes = await fs.readFile(path.join(root, relative)); return { value: JSON.parse(bytes),
  ref: { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) } }; };
const local = await read(`${folder}/${localName}`), result = local.value;
requireGuard(result.passed === true && result.summary.tests === result.summary.pass && result.childExitCode === 0
  && result.selectedSourcesUnchanged === true && hashJson(result.filesBefore) === hashJson(result.filesAfter)
  && result.networkCalls === 0 && result.executedLive === false, 'HARNESS_SOURCE_BINDINGS_REQUIRED');
for (const expected of result.filesAfter) {
  const bytes = await fs.readFile(path.join(root, expected.path)); requireGuard(hashBytes(bytes) === expected.sha256, 'HARNESS_SOURCE_DRIFT');
}
const runtime = await read(`${folder}/complete-app-runtime-review-20261010-r5.json`); validateRuntimeReview(runtime.value);
const owner = await read(`${folder}/runtime-owner-decision-20261012-r5.json`); validateApproval(owner.value, runtime.value, { runtimeFileSha256: runtime.ref.sha256 });
const additional = [];
for (const relative of ['tools/wave5/supabase_provider_plan.mjs', 'tools/wave5/compose_supabase_provider_preparation.mjs']) {
  if (result.filesAfter.some(ref => ref.path === relative)) continue;
  const bytes = await fs.readFile(path.join(root, relative)); additional.push({ path: relative, bytes: bytes.length, sha256: hashBytes(bytes) });
}
const body = { kind: 'source-bound-wave5-supabase-provider-preparation-plan', projectId: PROJECT_ID, observedAt: new Date().toISOString(),
  runtimeReview: { ...runtime.ref, bundleSha256: runtime.value.bundleSha256, operationScopeSha256: RUNTIME_FIXTURE_BINDING.operationScopeSha256 },
  ownerDecision: { ...owner.ref, decision: owner.value.decision, approvedAt: owner.value.approvedAt, sourceReference: owner.value.source.reference },
  sameApprovedOperationScope: true, additionalOwnerDecisionRequired: false, publicProviderPathsImplemented: true,
  privateFactoryConfigured: false, privatePreparationVerdictAvailable: false, executablePlanPrepared: false, actualExecutionReady: false,
  localVerification: { ...local.ref, summary: result.summary, actualStartedAt: result.actualStartedAt, actualFinishedAt: result.actualFinishedAt },
  sources: [...result.filesAfter, ...additional], caps: FIXTURE_CAPS,
  caseRecipes: Object.entries(RACE_FIXTURES).map(([kind, definition]) => ({ kind, scopeKey: definition.scopeKey, participants: definition.participants,
    readQueries: CASE_READ_RECIPES[kind], committedQuerySha256: committedRecipeHash(CASE_READ_RECIPES[kind]),
    mapping: definition, executionStatus: 'not-executed' })),
  boundaries: Object.entries(INVALID_BOUNDARIES).map(([kind, definition]) => ({ kind, sourceAvailability: definition.status,
    querySha256: READ_QUERY_SHA256.scopeSnapshot, executionStatus: 'not-executed', gatePassed: false })),
  load: { genuineDistinctSessions: 2000, exactScopes: 500, warmupSeconds: 60, measurementSeconds: 300, maximumRunSeconds: 900,
    maximumRequests: 100000, maximumInflight: 2000, workloadPercent: { indexedReads: 70, ordinaryForecastCommands: 20, boundedAnalytics: 10 },
    p95StrictlyUnderMs: { indexedReads: 500, ordinaryForecastCommands: 1500, boundedAnalytics: 3000 },
    committedQuerySha256: READ_QUERY_SHA256.loadLedgers, actualRunPerformed: false },
  concreteMissingPrivateInputs: ['Genuine six Auth Admin-returned IDs and private actor/session/MFA state.',
    'Fixed-project anon/service-role transport credentials.', 'Reviewed real local PostgreSQL driver/config/credentials with verified TLS and exact required privileges.',
    'Actual nonempty capped opportunities/process fixtures and indexed forecasts across every500 exact reviewed scope; server-valid fixture calendar.',
    'Fresh complete installed114 ledger/fingerprints/grants/forcedRLS/preservation and genuine supported-capacity verifier.',
    'Source-bound complete external-worker transport observer plus drained/inactive own jobs over the full measured window.',
    'Source-bound owner-private preparation append facility: new outside-repository folder, private encryption key/ACL, trusted external head retention and verified host file/directory persistence semantics.',
    'Outside-repository private factory and imported dependencies byte-verified with a concrete plan and independent technical preparation verdict.'],
  phasePrerequisites: ['Finish real installed-contract/preflight before invoking actual user/setup RPCs.',
    'Acknowledge original case setup identity, membership/assignment baseline and every preparatory RPC/admin-write intent before dispatch; append failures or uncertain results stop later preparation/restoration.',
    'Keep private invitation recovery material outside public evidence; incomplete recovery prefixes never authorize replay or restoration.',
    'Activate/admission before model/delivery/quota buckets; preserve any busy quota period.',
    'Accept-only registration after earlier forecasts and before other3 receiver registrations for the one-lease case.',
    'Restore exact load-001 seats to4 before both original membership reactivations, preserving all version/history evidence.',
    'Genuine per-slot sessions remain online verified; no global Auth policy changes or constructed claims.',
    'Preserve uncertain original effects; no automatic replay/cleanup.'],
  production: false, realBilling: false, replayInstalledSix: false, changedAcceptanceOrSessionStores: false,
  executedLive: false, networkCalls: 0, sdkJobs: 0, nativeActions: 0, authWrites: 0, installedSqlWrites: 0,
  gates: { installedSql: false, genuineMfa: false, authenticatedNative: false, actualDelivery: false,
    independentSessionContention: false, targetScaleLoad: false, invalidBoundaryRejections: false, ownerAcceptance: false },
  limitation: 'This is source-bound implementation/preparation evidence, not the independent private preparation verdict or executable live readiness. It records no new owner acceptance.' };
const destination = `${folder}/supabase-provider-preparation-plan-${evidenceDate}-r5-${suffix}.json`, bytes = JSON.stringify(body, null, 2) + '\n';
await fs.writeFile(path.join(root, destination), bytes, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: destination, sha256: hashBytes(bytes), actualExecutionReady: false,
  privatePreparationVerdictAvailable: false, additionalOwnerDecisionRequired: false }) + '\n');
