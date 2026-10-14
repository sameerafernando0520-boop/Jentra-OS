import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const base='docs/verification/wave5/task3-v7-provider-20261014/';
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const evidence=[];
async function read(file,expected){const bytes=await fs.readFile(path.join(root,file)),sha256=hash(bytes);
 if(expected)assert.equal(sha256,expected,'candidate evidence drift: '+file);
 if(!evidence.some(value=>value.path===file))evidence.push({path:file,bytes:bytes.length,sha256});return bytes;
}
const json=async(file,expected)=>JSON.parse(await read(file,expected));
async function write(file,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';
 const handle=await fs.open(path.join(root,file),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:file,bytes:Buffer.byteLength(bytes),sha256:hash(bytes)};
}
const prep=await json(base+'source-preparation-a2.json','8db09e449d0d249b29306c96d7053d0a235123e979437e76b374f052d4d0f6ed');assert.equal(prep.written.length,7);
const initialPrep=await json(prep.priorPreparation.path,prep.priorPreparation.sha256);
assert.equal(initialPrep.written.length,7);assert.equal(prep.originalPreparationPreserved,true);
const v6=await json('docs/verification/wave5/worker-v6-diagnostic-runtime-review-20261014-r5.json',
 '7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25');
const priorProof=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof.json',
 '629eb4abaf456710ee35c5818748ca6fc4c81ee552f966d0eca09227ee70a177');
const correctedProof=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof-a2.json',
 'e20a9de5f0124c1ae1941172e57c8e8eb6bf5418603b5d9b23dc03ab8ada0e7a');
const savedLive=await json('docs/verification/wave5/task3-completion-20261013/worker-v6-independent-live-observation-20261014.json',
 '672e58bd95a812c89489a66974d2f5fdeccebb75a936d12fce03b625f9a11839');
assert.equal(savedLive.actualProbeStatus,503);assert.equal(savedLive.matchingProviderClassification.supabaseUrlClass,'exact_configured_https');
assert.equal(savedLive.matchingProviderClassification.serviceRoleShape,'opaque_secret_style');assert.equal(savedLive.keyAuthenticityOrRoleVerified,false);
for(const binding of savedLive.evidence)await read(binding.path,binding.sha256);
for(const binding of priorProof.sourceBindings)await read(binding.path,binding.sha256);
for(const binding of prep.predecessors)await read(binding.path,binding.sha256);
for(const binding of prep.written)await read(binding.path,binding.sha256);
const unchangedSources=new Map();
for(const binding of [...priorProof.sourceBindings,...prep.predecessors])if(/\.(mjs|ts|json)$/.test(binding.path))unchangedSources.set(binding.path,binding);
assert.deepEqual(correctedProof.sourceBindings,priorProof.sourceBindings);
const verification=await json(base+'local-verification-a3.json','a316bfdfeb416bdba7d038d9aedd46a80e7c446bc68be7800f2caefd6e061a28');
assert.equal(verification.exitCode,0);assert.equal(verification.sourcesUnchangedDuringRun,true);
assert.deepEqual(verification.counts,{tests:21,pass:21,fail:0,cancelled:0,skipped:0,todo:0});
await read(verification.log.path,verification.log.sha256);
const priorPassing=await json(base+'local-verification-a2.json','ed0bcd9e99b7cdb7d24af12b2a85de9b6424542cb9f2c135540e389f11d85c23');
await read(priorPassing.log.path,priorPassing.log.sha256);assert.equal(priorPassing.counts.tests,20);assert.equal(priorPassing.counts.fail,0);
const initial=await json(base+'local-verification-a1.json','0bbbf2296ef00a7a9f095860eee41dcc4862b8b0f420da10f2d83bfd4b826c90');
await read(initial.log.path,initial.log.sha256);assert.equal(initial.counts.tests,19);assert.equal(initial.counts.fail,1);
assert.ok(verification.syntax.length===7&&verification.syntax.every(check=>check.exitCode===0));
for(const binding of verification.sourceBindingsBefore)await read(binding.path,binding.sha256);
await read(base+'prepare_candidate_a1.mjs');await read(base+'finalize_candidate_a1.mjs');

const url='https://supabase.com/docs/guides/getting-started/api-keys#known-limitations';
const primary=await write(base+'primary-documentation-reference.json',{kind:'verified-primary-api-key-header-guidance',
 verifiedAt:new Date().toISOString(),source:{title:'Supabase API keys: known limitations',url},
 method:'Official page opened with web tool during this source-only implementation.',
 supportedClaims:['Publishable and secret API keys are not JWTs.','Opaque secret keys use apikey rather than Authorization Bearer.',
  'An authenticated user separately supplies its own JWT.'],
 localSourceInference:'The saved opaque shape is rejected by the old JWT-only guard. V7 changes privileged key format handling and header placement; the already-correct user JWT path stays unchanged.',
 realKeyContentsRead:false,realKeyValidityOrRoleClaimed:false,newDictionaryParsing:false,newEnvironmentNames:false});

const oldFiles=new Set(v6.deployments.flatMap(deployment=>deployment.files.map(file=>file.path)));
const newFiles=new Set(prep.written.map(file=>file.path));const permissible=new Set([...oldFiles,...newFiles]);
const maps={
 'supabase/functions/wave5-runtime/index_20261014_r5_v6.ts':'workers/wave5/entries/runtime_20261014_r5_v7.ts',
 'supabase/functions/wave5-receiver/index_20261014_r5_v6.ts':'workers/wave5/entries/receiver_20261014_r5_v7.ts',
 'workers/wave5/edge_runtime_20261014_r5_v6.mjs':'workers/wave5/edge_runtime_20261014_r5_v7.mjs',
 'workers/wave5/edge_receiver_20261014_r5_v6.mjs':'workers/wave5/edge_receiver_20261014_r5_v7.mjs',
 'workers/wave5/persistent_control.mjs':'workers/wave5/persistent_control_20261014_r5_v7.mjs',
 'workers/wave5/scoped_runtime.mjs':'workers/wave5/scoped_runtime_20261014_r5_v7.mjs',
};
const deployments=[];
for(const old of v6.deployments){
 const entrypoint=maps[old.entrypoint],graph=new Set(),staticGraph=new Set(),dynamicEdges=[];
 async function walk(file,includeDynamic,seen){
  if(seen.has(file))return;assert.ok(permissible.has(file),'unreviewed file in worker candidate: '+file);seen.add(file);
  const text=(await read(file)).toString();
  const statics=[...text.matchAll(/(?:import|export)[^\n]*?\bfrom\s*['"]([^'"]+)['"]/g)].map(match=>match[1]);
  const dynamics=[...text.matchAll(/\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g)].map(match=>match[1]);
  assert.equal((text.match(/\bimport\s*\(/g)||[]).length,dynamics.length,'nonliteral dynamic import');
  if(includeDynamic)for(const specifier of dynamics)dynamicEdges.push({owner:file,specifier,
   target:path.posix.normalize(path.posix.join(path.posix.dirname(file),specifier))});
  for(const specifier of [...statics,...(includeDynamic?dynamics:[])]){
   if(specifier.startsWith('node:'))continue;assert.ok(specifier.startsWith('.'),'unreviewed package import');
   await walk(path.posix.normalize(path.posix.join(path.posix.dirname(file),specifier)),includeDynamic,seen);
  }
 }
 await walk(entrypoint,false,staticGraph);await walk(entrypoint,true,graph);
 const paths=[old.files.find(file=>file.path.endsWith('/deno.json')).path,...[...graph].sort()];
 assert.equal(paths.length,old.name==='wave5-runtime'?17:10);
 assert.equal(staticGraph.size,old.name==='wave5-runtime'?16:8);assert.equal(graph.size,old.name==='wave5-runtime'?16:9);
 const files=[];for(const file of paths){const bytes=await read(file);files.push({path:file,bytes:bytes.length,sha256:hash(bytes)});}
 assert.ok(graph.has('workers/wave5/persistent_control_20261014_r5_v7.mjs'));
 assert.ok(graph.has('workers/wave5/provider_credentials_20261014_r5_v7.mjs'));
 if(old.name==='wave5-runtime'){
  assert.ok(graph.has('workers/wave5/scoped_runtime_20261014_r5_v7.mjs'));
  assert.ok(graph.has('workers/wave5/model_reader.mjs'));assert.ok(graph.has('workers/wave5/persistent_control.mjs'));
 }else{
  assert.equal(graph.has('workers/wave5/persistent_control.mjs'),false);
  assert.deepEqual([...graph].filter(file=>!staticGraph.has(file)),['workers/wave5/worker_runtime.mjs']);
 }
 for(const required of ['workers/wave5/worker_runtime.mjs','workers/wave5/edge_route_20261014_r5_v6.mjs','workers/wave5/edge_configuration.mjs'])assert.ok(graph.has(required));
 const payload={project_id:v6.projectId,name:old.name,entrypoint_path:entrypoint,verify_jwt:old.verifyJwt,
  files:await Promise.all(files.map(async binding=>({name:binding.path,content:(await read(binding.path,binding.sha256)).toString('utf8')})))};
 const payloadRef=await write(base+'payload-'+old.name+'-candidate.json',payload);
 const decoded=JSON.parse(await fs.readFile(path.join(root,payloadRef.path)));assert.equal(decoded.files.length,files.length);
 for(const binding of files){const rows=decoded.files.filter(file=>file.name===binding.path);assert.equal(rows.length,1);
  assert.equal(hash(Buffer.from(rows[0].content)),binding.sha256);}
 deployments.push({name:old.name,entrypoint,verifyJwt:old.verifyJwt,files,payload:payloadRef,
  staticReachableModuleCount:staticGraph.size,literalDynamicInclusiveModuleCount:graph.size,
  staticReachablePaths:[...staticGraph].sort(),literalDynamicInclusivePaths:[...graph].sort(),literalDynamicImports:dynamicEdges,
  privilegedRpcTransport:'workers/wave5/persistent_control_20261014_r5_v7.mjs',
  existingCallerJwtReaderAndTransportPreserved:old.name==='wave5-runtime',missingImports:0,unreviewedPackageImports:0});
}
const unique=new Map(deployments.flatMap(deployment=>deployment.files).map(binding=>[binding.path,binding]));
assert.equal(unique.size,20);assert.equal([...unique.keys()].filter(file=>/\.(mjs|ts)$/.test(file)).length,18);
const candidate={kind:'source-only-minimal-worker-v7-provider-compatibility-candidate',preparedAt:new Date().toISOString(),projectId:v6.projectId,
 author:'/root/completion_peer',predecessorBundleSha256:v6.bundleSha256,sourcePreparation:evidence.find(ref=>ref.path===base+'source-preparation-a2.json'),
 sources:prep.written,deployments,retainedLimits:v6.retainedLimits,primaryDocumentation:primary,
 compatibility:{strictServiceFormats:['legacy_jwt_at_least_32_chars','sb_secret_at_least_32_chars'],
  opaqueServiceHeaders:['apikey'],legacyServiceHeaders:['apikey','authorization_Bearer_same_service_jwt'],
  newCredentialDecoding:false,newSecretDictionaryParsing:false,newEnvironmentNames:false,newUrlAliases:false,
  defaultRuntimeAndReceiverRpcPortsVersion7:true,allPrivilegedScopedRpcPortsVersion7:true,
  scopedAllowlistExact:true,publicModelCallerJwtAndPublishableApikeyUnchanged:true,
  currentRequestUrlRouteAndTlsUnchanged:true,scheduleSecretHashGateUnchanged:true,receiverHmacGateUnchanged:true,
  callerMfaAndServerScopeUnchanged:true,responseErrorMappingsUnchanged:true,requestDeadlinesUnchanged:true,
  originalV6FiniteDiagnosticUnchanged:true,providerKeyShapeIsAuthenticityProof:false},
 counts:{newSourceFiles:7,runtimeDeploymentFiles:17,receiverDeploymentFiles:10,totalPayloadRows:27,
  runtimeStaticModules:16,runtimeLiteralDynamicInclusiveModules:16,receiverStaticModules:8,receiverLiteralDynamicInclusiveModules:9,
  uniqueDeploymentFiles:20,uniqueSourceModules:18},
 verification:{path:base+'local-verification-a3.json',sha256:'a316bfdfeb416bdba7d038d9aedd46a80e7c446bc68be7800f2caefd6e061a28',
  counts:verification.counts,sevenSyntaxChecksPassed:true,sourcesUnchangedDuringTests:true,originalFailedFixtureRunPreserved:true},
 sourcePreservation:{oldV6BindingPopulation:priorProof.sourceBindings.length,oldPredecessorBytesPreserved:true,
  unchangedPublicUserReader:true,oldSourcesOverwritten:0,oldArtifactsOverwritten:0},
 scope:{privateInputsRead:0,realEnvironmentRead:0,environmentWrites:0,secretChanges:0,liveQueries:0,liveWrites:0,
  sdkJobs:0,deployments:0,schedulesChanged:0,newAccounts:0,newGrants:0,newDestinations:0,expiryExtended:false},
 independentReviewRequired:true,exactDeploymentOperationDecisionPending:true,schedulesRemainPaused:true,
 actualV7Deployment:false,actualV7Probe:false,actualProviderCompatibilityProvedLive:false,actualDelivery:false,
 actualTrustedModelUsage:false,authenticatedNative:false,targetScaleLoad:false,additionalRequirementAcceptance:0,
 personalHumanExactSourceSignatureClaimed:false,productionReleaseReady:false,realBilling:false};
candidate.candidateBundleSha256=hash(JSON.stringify(candidate));
const candidateRef=await write(base+'candidate-manifest.json',candidate);
for(const binding of evidence)assert.equal(hash(await fs.readFile(path.join(root,binding.path))),binding.sha256,'final evidence drift');
const proof={kind:'hash-bound-source-only-v7-provider-compatibility-proof',preparedAt:new Date().toISOString(),author:'/root/completion_peer',
 candidate:candidateRef,candidateBundleSha256:candidate.candidateBundleSha256,sourceBindings:evidence,
 oldBindingPopulationPreserved:[...unchangedSources.values()],payloadInventory:deployments.map(deployment=>({name:deployment.name,
  payload:deployment.payload,files:deployment.files,staticModules:deployment.staticReachableModuleCount,
  literalDynamicInclusiveModules:deployment.literalDynamicInclusiveModuleCount})),
 controlledTests:verification,implementationReviewPending:true,independentAuthorApprovalClaimed:false,
 previousFailure:{path:base+'local-verification-a1.json',sha256:'0bbbf2296ef00a7a9f095860eee41dcc4862b8b0f420da10f2d83bfd4b826c90',
  cause:'Fake readiness omitted committed_webhook.v1; test fixture corrected and explicit preserved-readiness denial regression added. Production sources did not change for that fixture repair.'},
 laterSourceRefinement:{previousPreparation:prep.priorPreparation,currentPreparation:evidence.find(ref=>ref.path===base+'source-preparation-a2.json'),
  reason:'Reserved sb_ prefix family cannot bypass strict secret/publishable classification by matching a dotted legacy JWT shape.',
  onlyNewCredentialHelperChanged:true,finalTestsPass:21,oldPreparationsAndRunsPreserved:true},
 limitations:['Only controlled fake credentials and fake backend responses were used. No real key was read, decoded, selected from a dictionary, logged or verified.',
  'Credential format compatibility is separate from actual key role/permission/validity and installed worker success. Existing server caller authentication, HMAC, MFA, scope and readiness contracts remain authoritative.',
  'The candidate includes the unchanged V6 finite diagnostic. Its source counter remains per module/isolate, not a global cross-isolate rate cap.',
  'Public model reads intentionally retain the old transport overridden with the real caller JWT; privileged service-control RPCs exclusively use the V7 transport. This is required to avoid treating a publishable key as a privileged service credential.',
  'The complete literal dynamic import population includes worker_runtime.mjs. Both original and V7 persistent-control modules remain in the runtime candidate because the public user reader retains its original transport.',
  'The root must independently review and pin the exact source, payloads and operation decision. The live owner retains deployment, secrets, probes and schedules; no schedule resume is authorized by this source artifact.',
  'The original authority expires at 2026-10-14T09:57:07.481942Z or an earlier applicable scope expiry. No timer, cap, actor, grant, destination or authority extension is created.',
  'No authenticated Windows/keyboard/restart/recovery, load/concurrency, delivery, model-use, owner acceptance or release gate is closed.'],
 execution:{networkRequests:0,privateInputsRead:0,environmentWrites:0,sql:0,sdkJobs:0,deployments:0,sourceOnly:true,
  oldSourceFilesChanged:0,oldEvidenceOverwritten:0,scopeCapsAndExpiryExtended:false},
 primaryDocumentation:primary};
const proofRef=await write(base+'source-proof.json',proof);
const md=['# V7 provider credential compatibility candidate','',
 'Seven new source files are ready for independent review. All 21 controlled tests pass, and all seven syntax checks passed. Opaque service keys now use apikey only; legacy service JWTs retain the exact existing apikey and Bearer headers. This implements the verified [Supabase API-key guidance](https://supabase.com/docs/guides/getting-started/api-keys#known-limitations).','',
 'The same key validator protects the default runtime and receiver factories and the shared privileged RPC transport. Scoped controls import that V7 transport without altering their allowlist. Publishable keys, malformed keys and keys shorter than 32 characters are rejected for service use. Reserved sb_ prefixes are checked before the legacy JWT shape, preventing dotted API-key strings from using that fallback. No key is decoded and no secret dictionary or new environment name is read.','',
 'The public model reader remains unchanged: its requests keep the caller’s JWT in Authorization and the public key in apikey. Tests cover the actual default raw/scoped worker ports, signed receiver key and receipt calls, HMAC denial, provider readiness, legacy header equality and unchanged public-user headers. The first failed controlled run remains saved; only its incomplete readiness fixture was corrected, with a denial regression added.','',
 'The exact payload inventory is 17 runtime files and 10 receiver files, or 27 rows, 20 unique files and 18 unique source modules. The static/dynamic-inclusive graphs are 16/16 for runtime and 8/9 for receiver. The literal lazy worker_runtime.mjs dependency is retained. Runtime also retains the old persistent transport solely for the unchanged public model reader. All old sources and evidence remain intact.','',
 'Routing, TLS, runtime scope, schedule/HMAC/caller MFA checks, configuration, caps and request deadlines remain unchanged. The original expiry is 2026-10-14T09:57:07.481942Z. Schedules stay paused; the root and live owner retain the exact operation review, deployment and probe work. No real configuration or credentials were accessed and no live success or release acceptance is claimed.','',
 `Candidate manifest: ${candidateRef.path} (SHA-256 ${candidateRef.sha256}).`,
 `Canonical candidate bundle: ${candidate.candidateBundleSha256}.`,
 `Source proof: ${proofRef.path} (SHA-256 ${proofRef.sha256}).`,''];
const mdRef=await write(base+'source-proof.md',md.join('\n'));
console.log(JSON.stringify({candidate:candidateRef,canonicalBundle:candidate.candidateBundleSha256,proof:proofRef,markdown:mdRef,
 sources:prep.written,counts:candidate.counts,tests:verification.counts,allOldBindingsPreserved:true,independentReviewPending:true}));
