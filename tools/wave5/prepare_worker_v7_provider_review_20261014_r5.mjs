import fs from 'node:fs/promises';
import { hashBytes } from './runtime_contract.mjs';
const root = new URL('../../', import.meta.url), base = 'docs/verification/wave5/';
const must = (v, code) => { if (!v) throw Error(code); }, evidence = [];
async function bind(file, expected) {
  const b = await fs.readFile(new URL(file, root));
  const h = hashBytes(b); if (expected) must(h === expected, 'EXACT_V7_INPUT_REQUIRED');
  const entry = { path: file, bytes: b.length, sha256: h };
  if (!evidence.some(x => x.path === file)) evidence.push(entry);
  return { b, entry, value: file.endsWith('.json') ? JSON.parse(b) : null };
}
async function save(file, value) {
  const text = JSON.stringify(value, null, 2) + '\n';
  await fs.writeFile(new URL(file, root), text, { flag: 'wx' });
  return { path: file, bytes: Buffer.byteLength(text), sha256: hashBytes(text) };
}
const prior = (await bind(base + 'worker-v6-diagnostic-runtime-review-20261014-r5.json', '7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25')).value;
const candidateFile = base + 'task3-v7-provider-20261014/candidate-manifest.json';
const candidate = (await bind(candidateFile, '49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6')).value;
const proofFile = base + 'task3-v7-provider-20261014/source-proof.json';
const proof = (await bind(proofFile, 'ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013')).value;
const { candidateBundleSha256, ...candidateBody } = candidate;
must(hashBytes(JSON.stringify(candidateBody)) === candidateBundleSha256 && candidateBundleSha256 === '2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c', 'CANONICAL_V7_CANDIDATE_REQUIRED');
must(JSON.stringify(candidate.retainedLimits) === JSON.stringify(prior.retainedLimits) && Date.now() < Date.parse(prior.retainedLimits.authorityExpiresAt), 'UNCHANGED_V7_ORIGINAL_LIMITS_REQUIRED');
for (const b of proof.sourceBindings) await bind(b.path, b.sha256);
const testFile = base + 'worker-v7-provider-root-controlled-tests-20261014-r5.tap';
const test = await bind(testFile), normalized = test.b.toString('utf8').replaceAll('\r\n', '\n');
for (const line of ['tests 21', 'pass 21', 'fail 0', 'cancelled 0', 'skipped 0']) must(normalized.includes('ℹ ' + line + '\n') || normalized.includes('# ' + line + '\n'), 'ACTUAL_ROOT_V7_TEST_COUNTS_REQUIRED');
const deno = [];
for (const role of ['runtime', 'receiver']) {
  const file = base + 'worker-v7-provider-' + role + '-deno-20261014-r5.log';
  const checked = await bind(file), text = checked.b.toString('utf8');
  must(text.includes('Check ') && !/error:/i.test(text), 'ACTUAL_V7_DENO_RESULT_REQUIRED');
  deno.push({ role, exitCode: 0, log: checked.entry, config: 'supabase/functions/wave5-' + role + '/deno.json' });
}
await bind('build/wave5-local-tools-20261013-r5/deno-2.9.7/bin/deno.exe', 'e020f3e232bd16e33768dee528e5983349c962952051ced0a5d58ad42f5d9b33');
const deployments = [];
for (const d of candidate.deployments) {
  const payload = (await bind(d.payload.path, d.payload.sha256)).value;
  must(payload.project_id === candidate.projectId && payload.name === d.name && payload.entrypoint_path === d.entrypoint && payload.verify_jwt === false && payload.files.length === d.files.length, 'EXACT_V7_PAYLOAD_ENVELOPE_REQUIRED');
  for (const file of d.files) {
    const rows = payload.files.filter(x => x.name === file.path);
    must(rows.length === 1 && hashBytes(rows[0].content) === file.sha256, 'EXACT_V7_EMBEDDED_BYTES_REQUIRED');
    await bind(file.path, file.sha256);
  }
  deployments.push({ name: d.name, entrypoint: d.entrypoint, verifyJwt: false, files: d.files, payload: d.payload,
    staticReachableModuleCount: d.staticReachableModuleCount, literalDynamicInclusiveModuleCount: d.literalDynamicInclusiveModuleCount });
}
must(deployments.length === 2 && deployments[0].files.length === 17 && deployments[1].files.length === 10, 'EXACT_TWO_WORKER_V7_CLOSURES_REQUIRED');
const body = {
  kind: 'exact-minimal-worker-v7-provider-compatibility-operation-review', preparedAt: new Date().toISOString(), projectId: candidate.projectId,
  predecessorRuntimeBundleSha256: prior.bundleSha256, candidateBundleSha256, candidateManifest: {path: candidateFile, sha256:'49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6'},
  authorProof: {path: proofFile, sha256:'ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013'}, evidence, deployments,
  localVerification: {rootControlledTests:21,passed:21,failed:0,skipped:0,denoChecks:deno,denoExecChunk:'d015d4',cachedOnly:true,importedJavaScriptTypeChecked:false},
  independentSourceReviewPending:true, independentOperationReviewPending:true, delegatedTechnicalOperationDecisionPending:true, personalHumanExactSourceSignatureClaimed:false,
  sourceChange:'Only existing server-injected legacy JWT or strictly formatted opaque secret API keys are accepted; opaque privileged transport sends apikey only. Existing real user JWT requests are preserved.',
  callerAuthenticationAndScopeUnchanged:true, routeEligibilityUnchanged:true, vaultReferencesAndDestinationsUnchanged:true, environmentOrSecretsChanged:false,
  existingSourceFilesOverwritten:0, newVersionedFiles:7, payloadRows:27, returnedSourceRowsExpected:25, uniquePayloadFiles:20, uniqueSourceFiles:18,
  actions:['Replace only the two existing workers with the exact V7 candidate payloads after independent source and operation review.',
    'Read back every returned source module and verify unchanged People function metadata.',
    'Issue exactly one credential-free public HTTPS schedule probe: {} body, verified TLS, bounded response, no retry or redirect.',
    'Require the unchanged custom authentication denial: HTTP403 and WORKER_ACCESS_DENIED.',
    'Resume only original jobs4,5,6 after exact source and probe guards pass, through a separately bound resume helper that preserves original expiry and cumulative caps.'],
  retainedLimits:{...prior.retainedLimits}, schedulesRemainPausedUntilSourceAndProbeVerified:true, scheduleResumeRequiresExactCurrentResumeSourceReview:true,
  deploymentExecuted:false,schedulesResumed:false,actualProviderAuthorizationVerified:false,actualDelivery:false,actualTrustedModelUsage:false,
  authenticatedNative:false,nativeKeyboard:false,targetScaleLoad:false,additionalRequirementAcceptance:0,production:false,realBilling:false
};
const review = {...body, bundleSha256:hashBytes(JSON.stringify(body))};
const out = await save(base + 'worker-v7-provider-runtime-review-20261014-r5.json', review);
process.stdout.write(JSON.stringify({...out,bundleSha256:review.bundleSha256,candidateBundleSha256,deploymentExecuted:false})+'\n');
