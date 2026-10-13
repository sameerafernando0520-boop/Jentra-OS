import fs from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { hashBytes, hashJson, PROJECT_ID } from './runtime_contract.mjs';
import { loadApprovedInputs, decodePublicResult, BUNDLE } from './approved_management_installer.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url)), base = 'docs/verification/wave5/';
const attempt = process.argv[2]; if (!/^a[1-9][0-9]*$/.test(attempt ?? '') || process.argv.length !== 3) throw Error('NEW_ROUTING_PEER_ATTEMPT_REQUIRED');
const prefix = `${base}worker-routing-independent-peer-review-20261013-r5-${attempt}`;
const bindings = new Map();
const bind = async relative => { const bytes = await fs.readFile(path.join(root, relative));
  const result = { path: relative, bytes: bytes.length, sha256: hashBytes(bytes) }; bindings.set(relative, result); return result; };
const read = async relative => { await bind(relative); return JSON.parse(await fs.readFile(path.join(root, relative), 'utf8')); };
const approved = await loadApprovedInputs(); assert.equal(approved.inspectedBindings, 5539);
const candidatePath = `${base}worker-routing-runtime-review-20261013-r5-a2.json`, candidate = await read(candidatePath);
assert.equal(candidate.projectId, PROJECT_ID); assert.equal(candidate.originalApprovedBundleSha256, BUNDLE);
assert.equal(candidate.ownerApproved, false); assert.equal(candidate.bundleSha256, 'bce677a0c8e53fea2ba44c30b81e0fa2d897d8f43af5dc6d109e2a1e6feaa552');
const { bundleSha256, ...body } = candidate; assert.equal(hashBytes(JSON.stringify(body)), bundleSha256);
const dependencies = [];
for (const deployment of candidate.deployments) {
  const payloadBinding = await bind(deployment.payload.path); assert.equal(payloadBinding.sha256, deployment.payload.sha256);
  const payload = await read(deployment.payload.path);
  assert.equal(payload.project_id, PROJECT_ID); assert.equal(payload.name, deployment.name);
  assert.equal(payload.entrypoint_path, deployment.entrypoint); assert.equal(payload.verify_jwt, false);
  assert.equal(payload.files.length, deployment.name === 'wave5-runtime' ? 15 : 9);
  assert.equal(new Set(payload.files.map(file => file.name)).size, payload.files.length);
  assert.deepEqual(payload.files.map(file => file.name).sort(), deployment.files.map(file => file.path).sort());
  const available = new Set(payload.files.map(file => file.name)); let relativeImports = 0;
  for (const file of payload.files) {
    const expected = deployment.files.find(value => value.path === file.name);
    assert.equal(hashBytes(file.content), expected.sha256); assert.equal((await bind(file.name)).sha256, expected.sha256);
    for (const match of file.content.matchAll(/(?:from\s+|import\s*)['"](\.{1,2}\/[^'"]+)['"]/g)) {
      const dependency = path.posix.normalize(path.posix.join(path.posix.dirname(file.name), match[1]));
      assert.ok(!dependency.startsWith('../') && !path.posix.isAbsolute(dependency)); assert.ok(available.has(dependency)); relativeImports++;
    }
  }
  const original = await read(`${base}supabase-deploy-${deployment.name}-20261009-r14.json`);
  let retainedDependencies = 0;
  for (const file of original.files) {
    if (file.name.endsWith('/index.ts') || /^workers\/wave5\/edge_(runtime|receiver)\.mjs$/.test(file.name)) continue;
    const successor = payload.files.find(value => value.name === file.name); assert.ok(successor);
    assert.equal(successor.content, file.content); retainedDependencies++;
  }
  dependencies.push({ name: deployment.name, fileCount: payload.files.length, relativeImportsResolved: relativeImports,
    originalUnchangedDependenciesRetained: retainedDependencies, verifyJwt: false, payload: payloadBinding });
}
const routeHelper = await bind('workers/wave5/edge_route_20261013_r5.mjs');
const normalization = source => source.replaceAll('\r\n', '\n');
for (const name of ['runtime', 'receiver']) {
  const originalPath = `workers/wave5/edge_${name}.mjs`, successorPath = `workers/wave5/edge_${name}_20261013_r5.mjs`;
  const original = normalization(await fs.readFile(path.join(root, originalPath), 'utf8'));
  const successor = normalization(await fs.readFile(path.join(root, successorPath), 'utf8'));
  const oldBlock = name === 'runtime' ? "   const url=new URL(req.url),base=new URL(config.workerUrl);\n   if(url.origin!==base.origin||req.method!=='POST')return reply(404,{code:'NOT_FOUND'});\n   const route=url.pathname.slice(base.pathname.length);\n   if(!url.pathname.startsWith(base.pathname+'/')||url.search||!['/schedule','/external/forecast','/model/suggestion'].includes(route))return reply(404,{code:'NOT_FOUND'});"
    : "   const url=new URL(req.url),expected=new URL(config.receiverUrl),prefix=expected.pathname.slice(0,-'accept'.length);\n   const mode=url.pathname.slice(prefix.length);\n   if(url.origin!==expected.origin||url.search||!url.pathname.startsWith(prefix)||!['accept','redirect','timeout','reject'].includes(mode))return reply(404,{code:'NOT_FOUND'});";
  const newBlock = name === 'runtime' ? "   const route=edgeRoute(req.url,config.workerUrl,['/schedule','/external/forecast','/model/suggestion']);\n   if(req.method!=='POST'||route===null)return reply(404,{code:'NOT_FOUND'});"
    : "   const route=edgeRoute(req.url,config.receiverUrl.slice(0,-'/accept'.length),['/accept','/redirect','/timeout','/reject']);\n   if(route===null)return reply(404,{code:'NOT_FOUND'});\n   const mode=route.slice(1);";
  assert.ok(original.includes(oldBlock));
  assert.equal(successor, "import {edgeRoute} from './edge_route_20261013_r5.mjs';\n" + original.replace(oldBlock, newBlock));
  await bind(originalPath); await bind(successorPath);
}
const local = await read(candidate.localVerification.path); assert.equal(bindings.get(candidate.localVerification.path).sha256, candidate.localVerification.sha256);
for (const field of ['tests', 'passed']) assert.equal(local[field], 105); assert.equal(local.failed, 0); assert.equal(local.skipped, 0);
for (const source of local.testedSource) assert.equal((await bind(source.path)).sha256, source.sha256);
for (const log of [local.nodeTestLog, local.deno.runtimeLog, local.deno.receiverLog]) assert.equal((await bind(log.path)).sha256, log.sha256);
assert.equal(local.deno.runtimeExitCode, 0); assert.equal(local.deno.receiverExitCode, 0); assert.equal(local.deno.importedJavaScriptTypeChecked, false);
const failure = await read(candidate.liveFailure.evidence.path); assert.equal(bindings.get(candidate.liveFailure.evidence.path).sha256, candidate.liveFailure.evidence.sha256);
const paused = decodePublicResult(failure)[0].snapshot; assert.equal(paused.netResponseCount, 18); assert.equal(paused.allKnownHandler404, true);
assert.equal(paused.ownJobs.length, 3); assert.deepEqual(paused.ownJobs.map(job => job.jobId).sort(), [4, 5, 6]);
assert.ok(paused.ownJobs.every(job => job.active === false));
for (const key of ['ticks', 'deliveryOutcomes', 'receiverReceipts', 'quotaPeriods']) assert.equal(paused[key], 0);
for (const key of ['maximumModelCalls', 'maximumScheduleRequestsOriginal', 'scheduleRequestsAlreadyObserved'])
  assert.equal(candidate.retainedLimits[key], { maximumModelCalls: 4, maximumScheduleRequestsOriginal: 4320, scheduleRequestsAlreadyObserved: 18 }[key]);
await bind('tools/wave5/worker_routing_peer_20261013_r5.test.mjs'); await bind('tools/wave5/review_worker_routing_peer_20261013_r5.mjs');
await bind('dist/Jentra OS Worker Routing Review 20261013 r5 a2.html');
const filesBefore = [...bindings.values()], testFiles = (await fs.readdir(path.join(root, 'workers/wave5'))).filter(name => name.endsWith('.test.mjs'))
  .sort().map(name => `workers/wave5/${name}`).concat('tools/wave5/worker_routing_peer_20261013_r5.test.mjs');
const command = ['--test', '--test-isolation=none', '--test-reporter=tap', ...testFiles];
let output = '', exitCode, signal; const started = new Date().toISOString();
await new Promise(resolve => { const child = spawn(process.execPath, command, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'],
  env: { SystemRoot: process.env.SystemRoot, WINDIR: process.env.WINDIR, TEMP: process.env.TEMP, TMP: process.env.TMP } });
  child.stdout.on('data', bytes => { output += bytes.toString('utf8'); }); child.stderr.on('data', bytes => { output += bytes.toString('utf8'); });
  child.on('error', () => { output += '\nCHILD_SPAWN_FAILED\n'; }); child.on('close', (code, gotSignal) => { exitCode = code; signal = gotSignal; resolve(); }); });
const finished = new Date().toISOString(), filesAfter = await Promise.all(filesBefore.map(value => bind(value.path)));
const summary = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name =>
  [name, Number(output.match(new RegExp(`^# ${name} (\\d+)$`, 'm'))?.[1] ?? NaN)]));
const selectedSourcesUnchanged = hashJson(filesBefore) === hashJson(filesAfter);
await loadApprovedInputs();
const passed = exitCode === 0 && summary.tests === summary.pass && summary.tests > 0
  && ['fail', 'cancelled', 'skipped', 'todo'].every(name => summary[name] === 0) && selectedSourcesUnchanged;
const log = { path: `${prefix}.tap`, sha256: hashBytes(output), bytes: Buffer.byteLength(output) };
const report = { kind: 'independent-source-local-focused-worker-routing-review', projectId: PROJECT_ID,
  reviewer: '/root/provider_review_20261013', actualStartedAt: started, actualFinishedAt: finished,
  verdict: passed ? 'approve-for-owner-review' : 'local-check-failed', passed,
  candidate: bindings.get(candidatePath), candidateBundleSha256: bundleSha256, originalApprovedBundleSha256: BUNDLE,
  originalReviewInputsVerifiedBeforeAndAfter: 5539, selectedSourcesUnchanged, filesBefore, filesAfter,
  exactRoutingOnlyTransformationVerified: true, allOriginalAuthenticationAndBodyChecksPreserved: true,
  exactConfiguredHttpsOriginRetained: true, payloadClosures: dependencies, routeHelper,
  localCommand: ['node', ...command], childExitCode: exitCode, childSignal: signal, summary, log,
  originalLocalVerification: candidate.localVerification,
  denoEvidenceReviewed: { bothSavedEntrypointChecksPassed: true, importedJavaScriptTypeChecked: false, freshDenoInvocationsByPeer: 0 },
  savedFailure: { ...candidate.liveFailure, actualInternalRequestUrlObserved: false, routingCauseInference: true },
  securityAssessment: [ 'Both exact function-name and public namespaces stay on the configured HTTPS origin.',
    'Other functions, lookalike prefixes, ports, origins, URL userinfo, queries, fragments, encoded routes and extra suffixes cannot reach a reviewed route.',
    'The original schedule hash/server permit, caller Auth, revocable external credential, model scope and byte-HMAC/live subscription checks remain verbatim.',
    'Keys, scopes, caps, destination, authority expiry, schedule allowance and gateway authentication flags are unchanged.',
    'Malformed paths and unsigned receiver requests cannot reach private keys or durable receipt calls in the independent probes.' ],
  findings: [], ownerApprovedByThisPeer: false, deployedByThisPeer: false, livePostPatchVerified: false,
  requestScope: 'Exactly two named deployment successors and the previously bounded same three test schedules after explicit owner approval.',
  providerNetworkCalls: 0, liveSqlCalls: 0, authWrites: 0, credentialsReadOrPrinted: false, sdkJobs: 0, nativeActions: 0,
  fullProviderCoordinatorPassed: false, privatePgDriverVerified: false, completeExternalObserverVerified: false,
  targetScaleLoad: false, nativeKeyboard: false, ownerAcceptedCriteria: 3, ownerCriteria: 109, newOwnerAcceptance: false,
  production: false, realBilling: false,
  officialPublicReference: 'https://supabase.com/docs/guides/functions/routing',
  limitation: 'Source/local approval readiness only. The saved 18 handler 404 responses and official function-name route contract support the proposed cause as an inference; live internal URLs and patched routing remain unverified. This peer cannot approve the deployment for the owner or claim delivery/load/native acceptance.' };
const bytes = JSON.stringify(report, null, 2) + '\n';
const markdown = `# Independent worker routing review — 2026-10-13\n\n**${report.verdict}** for exact candidate bundle \`${bundleSha256}\`. The two candidate factories change only route selection; authentication, HMAC, scopes, response handling, deadlines and key cleanup remain verbatim. Both payload closures are complete (**15 runtime files, 9 receiver files**) and retain all original unchanged dependencies. All **5539** original review inputs still match before and after review.\n\nThe fresh independent Node run passed **${summary.pass}/${summary.tests}**, with no failures/skips and unchanged selected hashes. It includes original-versus-candidate platform probes, cross-function/origin/credential rejection and HMAC/revocation parity. Root's saved 105-test run and both Deno entrypoint checks match their hashes; imported JavaScript was not type-checked by Deno.\n\nThe official [Supabase routing guide](https://supabase.com/docs/guides/functions/routing) specifies function-name path prefixes. The saved 18 handler 404 results make the diagnosis plausible; the actual internal URL and patched live behavior remain unverified. The same jobs 4/5/6 are paused.\n\nThis is technical approval readiness for the owner's exact deployment decision. It performs no deploy, secret read, live SQL, Auth, native or provider-network operation. Actual delivery, full provider, complete outbound observation, 2,000-session load and owner acceptance remain separate. Acceptance remains **3/109**.\n`;
await fs.writeFile(path.join(root, log.path), output, { flag: 'wx', mode: 0o600 });
await fs.writeFile(path.join(root, `${prefix}.json`), bytes, { flag: 'wx', mode: 0o600 });
await fs.writeFile(path.join(root, `${prefix}.md`), markdown, { flag: 'wx', mode: 0o600 });
process.stdout.write(JSON.stringify({ verdict: report.verdict, path: `${prefix}.json`, sha256: hashBytes(bytes),
  markdown: `${prefix}.md`, markdownSha256: hashBytes(markdown), passed, summary, selectedSourcesUnchanged }) + '\n');
if (!passed) process.exitCode = 1;
