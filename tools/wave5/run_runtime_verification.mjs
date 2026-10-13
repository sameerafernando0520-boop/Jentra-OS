import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { PROJECT_ID, requireGuard, isSha, hashBytes, hashJson, validateRuntimeReview, validatePlan, validateApproval, validatePreparation,
  reviewedExecutionContext, safeFailure } from './runtime_contract.mjs';
import { runLiveVerification } from './runtime_coordinator.mjs';

const workspace = path.resolve(fileURLToPath(new URL('../../', import.meta.url)));
const evidenceRoot = path.join(workspace, 'docs', 'verification', 'wave5', 'harness-runs');
const supportedArgs = new Set(['--review', '--harness-review', '--plan', '--approval', '--preparation', '--provider', '--evidence']);
const inside = (parent, child) => { const relative = path.relative(parent, child); return relative === '' ||
  (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); };

function parseArgs(argv) {
  const out = { execute: false };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === '--execute') { requireGuard(!out.execute, 'DUPLICATE_ARGUMENT'); out.execute = true; continue; }
    requireGuard(supportedArgs.has(arg) && !Object.hasOwn(out, arg) && argv[index + 1] && !argv[index + 1].startsWith('--'), 'INVALID_ARGUMENT');
    out[arg] = argv[++index];
  }
  requireGuard(out['--review'] && out['--harness-review'], 'REVIEW_ARGUMENTS_REQUIRED');
  return out;
}

async function publicJsonFile(relativeOrAbsolute) {
  const candidate = path.resolve(workspace, relativeOrAbsolute);
  requireGuard(inside(workspace, candidate), 'PUBLIC_REVIEW_MUST_BE_IN_WORKSPACE');
  const resolved = await fs.realpath(candidate);
  requireGuard(inside(workspace, resolved) && !inside(path.join(workspace, '.git'), resolved), 'PUBLIC_REVIEW_SYMLINK_BOUNDARY');
  const bytes = await fs.readFile(resolved);
  return { value: JSON.parse(bytes.toString('utf8')), sha256: hashBytes(bytes), path: resolved };
}

async function validateHarness(harness, review, runtimeFileSha256) {
  requireGuard(harness?.kind === 'wave5-runtime-harness-review' && harness.projectId === PROJECT_ID && harness.ownerApproved === false
    && harness.runtimeReview.bundleSha256 === review.bundleSha256 && harness.runtimeReview.sha256 === runtimeFileSha256
    && harness.executedLive === false && harness.gates.independentSessionContention === false && harness.gates.targetScaleLoad === false,
    'HASH_BOUND_HARNESS_REVIEW_REQUIRED');
  requireGuard(Array.isArray(harness.files) && harness.files.length >= 5 && Array.isArray(harness.contractSources)
    && harness.contractSources.length >= 7, 'HARNESS_SOURCE_BINDINGS_REQUIRED');
  const requiredCode = ['tools/wave5/runtime_contract.mjs', 'tools/wave5/runtime_coordinator.mjs', 'tools/wave5/run_runtime_verification.mjs'];
  requireGuard(requiredCode.every(file => harness.files.some(ref => ref.path === file)), 'CURRENT_COORDINATOR_BINDINGS_REQUIRED');
  const all = [...harness.files, ...harness.contractSources];
  requireGuard(new Set(all.map(ref => ref.path)).size === all.length, 'DUPLICATE_HARNESS_BINDING');
  for (const ref of all) {
    requireGuard(typeof ref.path === 'string' && !path.isAbsolute(ref.path) && isSha(ref.sha256), 'INVALID_HARNESS_FILE_BINDING');
    const resolved = await fs.realpath(path.join(workspace, ref.path));
    requireGuard(inside(workspace, resolved) && !inside(path.join(workspace, '.git'), resolved), 'HARNESS_FILE_OUTSIDE_WORKSPACE');
    requireGuard(hashBytes(await fs.readFile(resolved)) === ref.sha256, 'HARNESS_SOURCE_DRIFT');
  }
}

// An exclusive append-only public journal preserves starts even when a process crashes.
export async function createJournal(filename) {
  requireGuard(typeof filename === 'string' && /^[a-z0-9][a-z0-9_.-]{0,90}\.ndjson$/.test(filename), 'NEW_EVIDENCE_FILENAME_REQUIRED');
  await fs.mkdir(evidenceRoot, { recursive: true });
  requireGuard(await fs.realpath(evidenceRoot) === evidenceRoot, 'EVIDENCE_DIRECTORY_SYMLINK_BOUNDARY');
  const destination = path.join(evidenceRoot, filename), handle = await fs.open(destination, 'wx', 0o600);
  let tail = Promise.resolve(); let writeFailure = null;
  return { destination, async write(entry) {
    requireGuard(!writeFailure, 'EVIDENCE_WRITE_FAILED');
    const bytes = JSON.stringify(entry) + '\n';
    const next = tail.then(async () => { await handle.write(bytes); await handle.sync(); });
    tail = next.catch(error => { writeFailure = error; });
    await next;
  }, async close() { await tail; await handle.close(); requireGuard(!writeFailure, 'EVIDENCE_WRITE_FAILED'); } };
}

export async function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const runtimeFile = await publicJsonFile(args['--review']);
  const review = validateRuntimeReview(runtimeFile.value);
  const harnessFile = await publicJsonFile(args['--harness-review']);
  await validateHarness(harnessFile.value, review, runtimeFile.sha256);
  const planFile = args['--plan'] ? await publicJsonFile(args['--plan']) : null;
  if (planFile) validatePlan(planFile.value, review);
  if (!args.execute) return { mode: 'offline-validation', executedLive: false, networkCalls: 0,
    runtimeBundleSha256: review.bundleSha256, harnessReviewSha256: harnessFile.sha256, planValidated: Boolean(planFile),
    independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false };
  // No private module is even loaded without the exact direct-user decision and reviewed concrete plan.
  requireGuard(args['--approval'] && planFile, 'EXPLICIT_OWNER_APPROVAL_REQUIRED');
  const approvalFile = await publicJsonFile(args['--approval']);
  const approval = approvalFile.value;
  validateApproval(approval, review, { runtimeFileSha256: runtimeFile.sha256 });
  requireGuard(args['--preparation'], 'REVIEWED_PREPARATION_REQUIRED');
  const preparationFile = await publicJsonFile(args['--preparation']), preparation = preparationFile.value;
  const binding = { runtimeFileSha256: runtimeFile.sha256, harnessReviewSha256: harnessFile.sha256,
    planSha256: planFile.sha256, planBodySha256: hashJson(planFile.value), privateProviderSha256: preparation.privateProviderSha256 };
  requireGuard(Object.values(binding).every(isSha), 'EXACT_EXECUTION_HASHES_REQUIRED');
  validatePreparation(preparation, review, binding);
  const independentFile = await publicJsonFile(preparation.independentReview.path);
  requireGuard(independentFile.sha256 === preparation.independentReview.sha256, 'INDEPENDENT_PREPARATION_REVIEW_DRIFT');
  binding.independentReviewBodySha256 = hashJson(independentFile.value);
  const executionContext = reviewedExecutionContext({ review, plan: planFile.value, approval, preparation,
    independentReview: independentFile.value, binding });
  requireGuard(args['--provider'] && path.isAbsolute(args['--provider']) && args['--evidence'], 'REVIEWED_PRIVATE_PROVIDER_REQUIRED');
  const providerPath = await fs.realpath(args['--provider']);
  requireGuard(!inside(workspace, providerPath) && path.extname(providerPath) === '.mjs', 'PRIVATE_PROVIDER_MUST_BE_OUTSIDE_REPOSITORY');
  const providerBytes = await fs.readFile(providerPath);
  requireGuard(hashBytes(providerBytes) === preparation.privateProviderSha256, 'PRIVATE_PROVIDER_SOURCE_DRIFT');
  const journal = await createJournal(args['--evidence']);
  let report;
  try {
    await journal.write({ type: 'approved-run-intent', observedAt: new Date().toISOString(), projectId: PROJECT_ID,
      runtimeBundleSha256: review.bundleSha256, runtimeFileSha256: runtimeFile.sha256,
      harnessReviewSha256: harnessFile.sha256, planSha256: planFile.sha256,
      approvalSha256: approvalFile.sha256, preparationSha256: preparationFile.sha256,
      independentReviewSha256: independentFile.sha256, privateProviderSha256: preparation.privateProviderSha256 });
    const module = await import(pathToFileURL(providerPath).href);
    requireGuard(typeof module.createWave5PrivateProvider === 'function', 'PRIVATE_PROVIDER_FACTORY_REQUIRED');
    const provider = await module.createWave5PrivateProvider(Object.freeze({ projectId: PROJECT_ID, ...executionContext }));
    report = await runLiveVerification({ ...executionContext, provider, journal: journal.write.bind(journal) });
  } catch (error) {
    await journal.write({ type: 'approved-run-failure', finishedAt: new Date().toISOString(), failureCode: safeFailure(error),
      independentSessionContention: false, targetScaleLoad: false, ownerAcceptance: false });
    throw error;
  } finally { await journal.close(); }
  return { mode: 'live-execution', evidencePath: journal.destination, passed: report.passed, failureCode: report.failureCode, gates: report.gates };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { const result = await main(); process.stdout.write(JSON.stringify(result, null, 2) + '\n'); if (result.passed === false) process.exitCode = 1; }
  catch (error) { process.stderr.write(JSON.stringify({ failureCode: safeFailure(error), executedGatePassed: false }) + '\n'); process.exitCode = 1; }
}
