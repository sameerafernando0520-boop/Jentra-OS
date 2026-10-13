import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PROJECT_ID, hashBytes, hashJson, requireGuard, validateRuntimeReview, validateApproval } from './runtime_contract.mjs';

// Source inspection only. This does not query logs or invent dispatch counts.
const root = path.resolve(fileURLToPath(new URL('../../', import.meta.url))), folder = 'docs/verification/wave5',
  attempt = process.argv[2], evidenceDate = process.argv[3];
requireGuard(/^a[1-9][0-9]*$/.test(attempt ?? '') && /^20[0-9]{6}$/.test(evidenceDate ?? ''), 'NEW_LOCAL_ATTEMPT_REQUIRED');
const startedAt = new Date().toISOString(), reviewPath = `${folder}/complete-app-runtime-review-20261010-r5.json`,
  ownerPath = `${folder}/runtime-owner-decision-20261012-r5.json`;
const read = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  return { bytes, ref: { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) } }; };
const reviewInput = await read(reviewPath), review = JSON.parse(reviewInput.bytes); validateRuntimeReview(review);
const ownerInput = await read(ownerPath); validateApproval(JSON.parse(ownerInput.bytes), review, { runtimeFileSha256: reviewInput.ref.sha256 });
const workers = review.deployments.map(({ name, entrypoint, files }) => ({ name, entrypoint, files })),
  paths = [...new Set([reviewPath, ownerPath, `${folder}/runtime-fixture-contract-20261012-r5.json`,
    'tools/wave5/inspect_external_observation.mjs', 'tools/wave5/runtime_coordinator.mjs', 'tools/wave5/supabase_runtime_provider.mjs',
    'tools/wave5/supabase_management_read.mjs', 'workers/wave5/runtime_launcher.mjs', ...workers.flatMap(value => value.files.map(file => file.path))])];
requireGuard(workers.length === 2 && workers.map(value => value.name).sort().join(',') === 'wave5-receiver,wave5-runtime'
  && paths.every(value => !path.isAbsolute(value) && !value.split('/').includes('..')), 'HARNESS_SOURCE_BINDINGS_REQUIRED');
const before = await Promise.all(paths.map(async relative => (await read(relative)).ref)), byPath = new Map(before.map(value => [value.path, value]));
const inventory = workers.map(worker => ({ name: worker.name, entrypoint: worker.entrypoint,
  files: worker.files.map(file => ({ ...byPath.get(file.path), approvedSha256: file.sha256,
    currentLocalBytesMatchApproved: byPath.get(file.path).sha256 === file.sha256 })), liveDeploymentSourceRead: false }));
const after = await Promise.all(paths.map(async relative => (await read(relative)).ref));
requireGuard(hashJson(before) === hashJson(after), 'HARNESS_SOURCE_DRIFT');
const record = { kind: 'local-source-wave5-external-transport-observer-investigation', projectId: PROJECT_ID,
  actualStartedAt: startedAt, actualFinishedAt: new Date().toISOString(), runtimeBundleSha256: review.bundleSha256,
  operationScopeSha256: review.sourceContinuation.unchangedRuntimeOperationScopeSha256,
  sameApprovedOperationScope: true, additionalOwnerDecisionRequired: false, selectedSourcesUnchanged: true,
  sourcesBefore: before, sourcesAfter: after, reviewedWorkerInventory: inventory,
  currentLocalWorkerBytesMatchApproved: inventory.every(value => value.files.every(file => file.currentLocalBytesMatchApproved)),
  findings: [
    { path: 'workers/wave5/openai_model_adapter.mjs', detail: 'Both input-token counting and generation use the privately supplied fetch transport. The reviewed source does not persist a complete external dispatch trace around those actual sends.' },
    { path: 'workers/wave5/integration_policy.mjs', detail: 'Webhook dispatch uses pinned HTTPS and the original bounded signed bytes. Its outcome is retained separately from reservation/attempt rows; an attempt row precedes send and does not itself count a send.' },
    { path: 'workers/wave5/edge_runtime.mjs', detail: 'The local active-request count is private to each handler instance. It is not an exposed complete remote active/inflight observation facility.' },
    { path: 'tools/wave5/supabase_runtime_provider.mjs', detail: 'RPC traces are supplied to the required private observeExternalTransport hook. The public provider does not implement that complete remote-worker facility.' },
  ],
  officialDocumentation: [
    { url: 'https://supabase.com/docs/guides/functions/logging', accessedOn: evidenceDate,
      supports: 'Invocation views describe request/response metadata; runtime logs describe platform events, exceptions and custom console output. Log messages and rates are bounded.' },
    { url: 'https://supabase.com/docs/guides/observability/log-field-reference', accessedOn: evidenceDate,
      supports: 'function_edge_logs describe invocation HTTP requests/responses; function_logs describe console output. These sources do not document complete automatic outbound model/webhook-send tracing.' },
    { url: 'https://supabase.com/docs/guides/observability/client-side-tracing', accessedOn: evidenceDate,
      supports: 'SDK trace propagation can correlate requests to Supabase services. Calls to third-party hosts through custom fetch are not tagged by that SDK propagation.' },
  ],
  inference: 'The reviewed source plus these documented default facilities cannot establish the required complete outbound trace. This local investigation does not claim that no separate owner-private telemetry facility exists in the project.',
  genuineRemoteWorkerObserverImplemented: false, actualPrivateObserverConfigured: false,
  actualFullWindowObserved: false, allReviewedRemoteWorkerTransportsObserved: false,
  modelDispatchesObserved: null, webhookDispatchesObserved: null, inactiveAndDrainedOwnJobsVerified: false,
  concreteRequiredFacility: 'A real privately configured observer must bind every reviewed worker/deployment and actual transport, retain complete no-gap coverage of the before/after load interval, count both OpenAI HTTP paths and pinned webhook sends, and independently establish inactive/drained own jobs. Partial logs, SQL ledger rows and local RPC traces remain separate evidence. Changes to reviewed deployed source require a concrete source/deployment technical review before execution.',
  executedLive: false, networkRuntimeCalls: 0, liveLogsQueried: false, authWrites: 0, installedSqlWrites: 0,
  workerDeployments: 0, paidServicesEnabled: 0, sdkJobs: 0, nativeActions: 0,
  production: false, realBilling: false, acceptedRequirementsAdded: 0,
  gates: { actualExternalTransportObservation: false, targetScaleLoad: false, ownerAcceptance: false } };
const destination = `${folder}/external-worker-observation-investigation-${evidenceDate}-r5-${attempt}.json`, bytes = JSON.stringify(record, null, 2) + '\n';
await fs.writeFile(path.join(root, destination), bytes, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ path: destination, sha256: hashBytes(bytes), selectedSourcesUnchanged: true,
  currentLocalWorkerBytesMatchApproved: record.currentLocalWorkerBytesMatchApproved,
  actualExternalTransportObservation: false, modelDispatchesObserved: null, webhookDispatchesObserved: null }) + '\n');
