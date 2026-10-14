import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {builtinModules} from 'node:module';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const author='docs/verification/wave5/task3-v7-provider-20261014/';
const output='docs/verification/wave5/task3-v7-independent-20261014/';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const evidence=new Map(),checks=[],startedAt=new Date().toISOString();
async function read(relative,expected){
 assert.ok(!path.isAbsolute(relative)&&!relative.split('/').includes('..'),'relative workspace input only');
 const bytes=await fs.readFile(path.join(root,relative));const binding={path:relative,bytes:bytes.length,sha256:sha(bytes)};
 if(expected){assert.equal(binding.sha256,expected.sha256??expected,'input hash drift: '+relative);
  if(expected.bytes!==undefined)assert.equal(binding.bytes,expected.bytes,'input size drift: '+relative);}
 if(evidence.has(relative))assert.deepEqual(binding,evidence.get(relative),'input changed during review: '+relative);
 else evidence.set(relative,binding);return bytes;
}
const json=async(relative,expected)=>JSON.parse(await read(relative,expected));
async function write(relative,value){
 assert.ok(relative.startsWith(output),'review writes outside owned folder');
 const bytes=Buffer.from(typeof value==='string'?value:JSON.stringify(value,null,2)+'\n');
 const fd=await fs.open(path.join(root,relative),'wx');try{await fd.writeFile(bytes);await fd.sync();}finally{await fd.close();}
 return {path:relative,bytes:bytes.length,sha256:sha(bytes)};
}
async function check(name,callback){await callback();checks.push({name,passed:true});}
const text=async(relative)=>(await read(relative)).toString('utf8');
function replaceOnce(source,from,to){assert.equal(source.split(from).length-1,1,'exact transformation must occur once');return source.replace(from,to);}

try{
 const candidate=await json(author+'candidate-manifest.json','49a943f5a26de7d17c49ac3fef3f3bd43a2a53122297cebb55c786792523bbc6');
 const proof=await json(author+'source-proof.json','ea94c14e3ee120216796546f6f57e5a6b4820c0ae01b53266816c9efc3688013');
 const prep=await json(candidate.sourcePreparation.path,candidate.sourcePreparation);
 const old=await json('docs/verification/wave5/worker-v6-diagnostic-runtime-review-20261014-r5.json',
  '7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25');
 const originalProof=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof.json',
  '629eb4abaf456710ee35c5818748ca6fc4c81ee552f966d0eca09227ee70a177');
 await check('all frozen candidate, author-proof and original predecessor bindings match current actual bytes',async()=>{
  await read(proof.candidate.path,proof.candidate);for(const binding of proof.sourceBindings)await read(binding.path,binding);
  for(const binding of [...prep.predecessors,...prep.written,...originalProof.sourceBindings])await read(binding.path,binding);
  assert.equal(originalProof.sourceBindings.length,28);assert.equal(prep.predecessors.length,4);
  assert.deepEqual(candidate.sources,prep.written);assert.equal(prep.written.length,7);
  assert.equal(proof.candidateBundleSha256,candidate.candidateBundleSha256);
  const {candidateBundleSha256,...unsigned}=candidate;assert.equal(sha(JSON.stringify(unsigned)),candidateBundleSha256);
  assert.equal(candidate.predecessorBundleSha256,old.bundleSha256);
 });
 const authorTests=await json(candidate.verification.path,candidate.verification);
 await check('final author test result, TAP identities, source bindings and seven syntax checks are genuine saved outputs',async()=>{
  assert.equal(authorTests.exitCode,0);assert.equal(authorTests.sourcesUnchangedDuringRun,true);
  assert.deepEqual(authorTests.counts,{tests:21,pass:21,fail:0,cancelled:0,skipped:0,todo:0});
  const tap=(await read(authorTests.log.path,authorTests.log)).toString();
  assert.ok(tap.includes('# tests 21')&&tap.includes('# pass 21')&&tap.includes('# fail 0'));
  assert.equal((tap.match(/^ok \d+ - /gm)||[]).length,21);
  assert.equal(authorTests.syntax.length,7);assert.ok(authorTests.syntax.every(item=>item.exitCode===0));
  for(const binding of authorTests.sourceBindingsBefore)await read(binding.path,binding);
 });
 const transformations=[];
 await check('privileged transport successor reverses exactly to original with only helper import/header selection changed',async()=>{
  const before=await text('workers/wave5/persistent_control.mjs');let after=await text('workers/wave5/persistent_control_20261014_r5_v7.mjs');
  after=replaceOnce(after,"import {serviceProviderHeaders} from './provider_credentials_20261014_r5_v7.mjs';\n",'');
  after=replaceOnce(after,' const providerHeaders=serviceProviderHeaders(serviceKey);\n','');
  after=replaceOnce(after,"headers:{...providerHeaders,'content-profile'","headers:{'apikey':serviceKey,'authorization':`Bearer ${serviceKey}`,'content-profile'");
  assert.equal(after,before);transformations.push({role:'persistent_control',exactReverseDiff:true,changes:['one new helper import','one service header selector','one header spread'],
   originalTransportBodyAndUrlGuardDeadlineErrorMappingUnchanged:true});
 });
 await check('scoped allowlist and both authenticated factories reverse exactly to original except V7 imports and key-shape guard',async()=>{
  assert.equal(replaceOnce(await text('workers/wave5/scoped_runtime_20261014_r5_v7.mjs'),
   './persistent_control_20261014_r5_v7.mjs','./persistent_control.mjs'),await text('workers/wave5/scoped_runtime.mjs'));
  for(const role of ['runtime','receiver']){
   let after=await text(`workers/wave5/edge_${role}_20261014_r5_v7.mjs`);
   after=replaceOnce(after,"import {serviceCredentialKind} from './provider_credentials_20261014_r5_v7.mjs';\n",'');
   after=replaceOnce(after,'./persistent_control_20261014_r5_v7.mjs','./persistent_control.mjs');
   if(role==='runtime')after=replaceOnce(after,'./scoped_runtime_20261014_r5_v7.mjs','./scoped_runtime.mjs');
   after=replaceOnce(after,"if(serviceCredentialKind(serviceKey)===null)throw Error('WORKER_PROVIDER_UNAVAILABLE');",
    role==='runtime'?"if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey))throw Error('WORKER_PROVIDER_UNAVAILABLE');"
     :"if(!/^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$/.test(serviceKey??''))throw Error('WORKER_PROVIDER_UNAVAILABLE');");
   assert.equal(after,await text(`workers/wave5/edge_${role}_20261014_r5_v6.mjs`));
   transformations.push({role,exactReverseDiff:true,changes:['one helper import','privileged V7 module imports','one key-shape guard'],
    urlCustomAuthenticationHmacScopeBodyLimitsConcurrencyDeadlineAndErrorMappingUnchanged:true});
  }
 });
 await check('both entrypoint executable tails and diagnostic arguments remain exact after relative import relocation',async()=>{
  for(const role of ['runtime','receiver']){
   const before=await text(`supabase/functions/wave5-${role}/index_20261014_r5_v6.ts`);
   let after=await text(`workers/wave5/entries/${role}_20261014_r5_v7.ts`);
   after=replaceOnce(after,`../edge_${role}_20261014_r5_v7.mjs`,`../../../workers/wave5/edge_${role}_20261014_r5_v6.mjs`);
   after=replaceOnce(after,'../edge_route_20261014_r5_v6.mjs','../../../workers/wave5/edge_route_20261014_r5_v6.mjs');
   after=replaceOnce(after,'../edge_configuration.mjs','../../../workers/wave5/edge_configuration.mjs');
   after=replaceOnce(after,'// Caller authentication stays in the reviewed handler. The V6 diagnostic\n// still emits only its single finite configuration-shape observation.',
    '// The unchanged handler authenticates before this single finite observation.\n// Provider keys and URL values never reach the diagnostic sink.');
   assert.equal(after,before);transformations.push({role:role+'_entrypoint',exactReverseDiff:true,
    changes:['three relocated imports with V7 factory','two comment lines'],diagnosticExecutableTailUnchanged:true});
  }
 });
 const closures=[];
 await check('both actual payloads equal actual source bytes and every static/literal dynamic import is inside exact reviewed closure',async()=>{
  for(const deployment of candidate.deployments){
   const payload=await json(deployment.payload.path,deployment.payload);
   assert.equal(payload.project_id,candidate.projectId);assert.equal(payload.name,deployment.name);
   assert.equal(payload.entrypoint_path,deployment.entrypoint);assert.equal(payload.verify_jwt,false);assert.equal(deployment.verifyJwt,false);
   const paths=deployment.files.map(binding=>binding.path);assert.equal(new Set(paths).size,paths.length);
   assert.equal(payload.files.length,paths.length);assert.deepEqual(payload.files.map(row=>row.name).sort(),[...paths].sort());
   for(const binding of deployment.files){const bytes=await read(binding.path,binding);const row=payload.files.find(row=>row.name===binding.path);
    assert.ok(Buffer.from(row.content,'utf8').equals(bytes),'payload must preserve source bytes without normalization');}
   const allowed=new Set(paths),staticGraph=new Set(),dynamicGraph=new Set(),dynamicEdges=[],builtinImports=new Set();
   async function visit(file,includeDynamic,seen){
    if(seen.has(file))return;assert.ok(allowed.has(file),'dependency outside declared payload: '+file);seen.add(file);
    const source=await text(file);
    const statics=[...source.matchAll(/(?:import|export)[^\n]*?\bfrom\s*['"]([^'"]+)['"]/g)].map(match=>match[1]);
    const sideEffects=[...source.matchAll(/(?:^|\n)\s*import\s*['"]([^'"]+)['"]/g)].map(match=>match[1]);
    const dynamics=[...source.matchAll(/\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g)].map(match=>match[1]);
    assert.equal((source.match(/\bimport\s*\(/g)||[]).length,dynamics.length,'nonliteral dynamic import not permitted');
    for(const specifier of [...statics,...sideEffects,...(includeDynamic?dynamics:[])]){
     if(specifier.startsWith('node:')){assert.ok(builtinModules.includes(specifier)||builtinModules.includes(specifier.slice(5)));builtinImports.add(specifier);continue;}
     assert.ok(specifier.startsWith('.'),'external package import not permitted: '+specifier);
     const target=path.posix.normalize(path.posix.join(path.posix.dirname(file),specifier));
     if(includeDynamic&&dynamics.includes(specifier))dynamicEdges.push({owner:file,specifier,target});
     await visit(target,includeDynamic,seen);
    }
   }
   await visit(deployment.entrypoint,false,staticGraph);await visit(deployment.entrypoint,true,dynamicGraph);
   assert.deepEqual([...staticGraph].sort(),deployment.staticReachablePaths);assert.deepEqual([...dynamicGraph].sort(),deployment.literalDynamicInclusivePaths);
   assert.equal(staticGraph.size,deployment.staticReachableModuleCount);assert.equal(dynamicGraph.size,deployment.literalDynamicInclusiveModuleCount);
   assert.deepEqual(dynamicEdges,deployment.literalDynamicImports);
   assert.deepEqual([...dynamicGraph].sort(),paths.filter(file=>/\.(mjs|ts)$/.test(file)).sort());
   const runtime=deployment.name==='wave5-runtime';assert.equal(paths.length,runtime?17:10);
   assert.equal(staticGraph.size,runtime?16:8);assert.equal(dynamicGraph.size,runtime?16:9);
   assert.ok(dynamicGraph.has('workers/wave5/worker_runtime.mjs'));
   assert.ok(dynamicGraph.has('workers/wave5/persistent_control_20261014_r5_v7.mjs'));
   assert.equal(dynamicGraph.has('workers/wave5/persistent_control.mjs'),runtime);
   assert.equal(dynamicGraph.has('workers/wave5/model_reader.mjs'),runtime);
   if(!runtime)assert.deepEqual([...dynamicGraph].filter(file=>!staticGraph.has(file)),['workers/wave5/worker_runtime.mjs']);
   const receiverSource=await text('workers/wave5/edge_receiver_20261014_r5_v7.mjs');assert.equal(receiverSource.includes('runDeliveryBatch'),false);
   closures.push({name:deployment.name,payload:deployment.payload,entrypoint:deployment.entrypoint,files:deployment.files,
    staticModuleCount:staticGraph.size,literalDynamicInclusiveModuleCount:dynamicGraph.size,staticPaths:[...staticGraph].sort(),
    literalDynamicInclusivePaths:[...dynamicGraph].sort(),literalDynamicImports:dynamicEdges,nodeBuiltins:[...builtinImports].sort(),
    allPayloadRowsMatchActualSourceBytes:true,sourceNormalization:false,missingImports:0,externalPackages:0});
  }
  const unique=new Set(closures.flatMap(closure=>closure.files.map(binding=>binding.path)));
  assert.equal(unique.size,20);assert.equal([...unique].filter(file=>/\.(mjs|ts)$/.test(file)).length,18);
 });
 await check('actual unchanged public caller reader exclusively retains its original transport and does not import V7 service classifier',async()=>{
  const reader=await text('workers/wave5/model_reader.mjs');
  assert.ok(reader.startsWith("import {createWorkerRpc} from './persistent_control.mjs';"));
  assert.ok(reader.includes('authorization:`Bearer ${accessToken}`'));assert.equal(reader.includes('_v7'),false);
  const helper=await text('workers/wave5/provider_credentials_20261014_r5_v7.mjs');
  assert.equal(/JSON\.parse|atob\(|process\.env|Deno\.env|SUPABASE_SECRET_KEYS|fetch\(/.test(helper),false);
  assert.ok(helper.indexOf("value.startsWith('sb_')")<helper.indexOf("return 'legacy_jwt'"));
 });
 await check('original configuration, custom authentication, finite diagnostic, budgets and earlier expiry are retained exactly',async()=>{
  assert.deepEqual(candidate.retainedLimits,old.retainedLimits);
  assert.equal(candidate.retainedLimits.maximumModelCalls,4);assert.equal(candidate.retainedLimits.maximumScheduleRequestsOriginal,4320);
  assert.equal(candidate.retainedLimits.scheduledRequestsAlreadyObserved,24);assert.equal(candidate.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');
  assert.equal(candidate.retainedLimits.extendedExpiry,false);
  for(const unchanged of ['workers/wave5/edge_route_20261014_r5_v6.mjs','workers/wave5/edge_configuration.mjs',
   'workers/wave5/integration_policy.mjs','workers/wave5/worker_endpoints.mjs','workers/wave5/model_reader.mjs','workers/wave5/model_runtime.mjs']){
   const binding=old.deployments.flatMap(item=>item.files).find(binding=>binding.path===unchanged);assert.ok(binding);await read(unchanged,binding);
  }
  for(const flag of ['actualV7Deployment','actualV7Probe','actualProviderCompatibilityProvedLive','actualDelivery','actualTrustedModelUsage',
   'authenticatedNative','targetScaleLoad','productionReleaseReady','personalHumanExactSourceSignatureClaimed'])assert.equal(candidate[flag],false);
 });

 await read(output+'independent-review-stop-a1.json','32a41cf2122fa82a1961f489a242e28f1b3a8450839f941803326e363acf5274');
 const priorRun=await json(output+'independent-local-verification-a1.json');await read(priorRun.log.path,priorRun.log);
 assert.deepEqual(priorRun.counts,{tests:36,pass:35,fail:1,cancelled:0,skipped:0,todo:0});
 for(const binding of priorRun.sourceBindingsBefore.filter(binding=>binding.path.startsWith(output)))await read(binding.path,binding);
 const testFiles=[author+'provider_compatibility.test.mjs',output+'provider_credentials_peer_a2.test.mjs'];
 for(const file of [...testFiles,output+'verify_v7_source_a2.mjs'])await read(file);
 const sourcesBefore=[...evidence.values()];
 const testStartedAt=new Date().toISOString();
 const command=[process.execPath,'--test','--test-isolation=none','--test-reporter=tap','--test-timeout=5000',...testFiles];
 const run=spawnSync(command[0],command.slice(1),{cwd:root,encoding:'utf8',timeout:30000,maxBuffer:2*1024*1024,windowsHide:true});
 const log=await write(output+'independent-local-verification-a2.tap',(run.stdout??'')+(run.stderr??''));
 const counts={};for(const name of ['tests','pass','fail','cancelled','skipped','todo'])counts[name]=Number(new RegExp(`^# ${name} (\\d+)$`,'m').exec(run.stdout??'')?.[1]??NaN);
 const testIdentities=[...(run.stdout??'').matchAll(/^(ok|not ok) (\d+) - (.*)$/gm)].map(match=>({status:match[1],index:Number(match[2]),name:match[3]}));
 const peerCases=testIdentities.filter(item=>item.name.startsWith('peer:')).length;
 const authorCases=testIdentities.length-peerCases;
 const syntaxChecks=candidate.sources.map(binding=>{const check=spawnSync(process.execPath,['--check',binding.path],
  {cwd:root,encoding:'utf8',timeout:10000,maxBuffer:65536,windowsHide:true});
  return {path:binding.path,exitCode:check.status,signal:check.signal,error:check.error?.message??null,stdout:check.stdout,stderr:check.stderr};});
 const changed=[];for(const binding of sourcesBefore){const bytes=await fs.readFile(path.join(root,binding.path));if(sha(bytes)!==binding.sha256)changed.push(binding.path);}
 const testEvidence=await write(output+'independent-local-verification-a2.json',{
  kind:'independent-controlled-v7-provider-adversarial-verification',startedAt:testStartedAt,finishedAt:new Date().toISOString(),
  command,nodeVersion:process.version,exitCode:run.status,signal:run.signal,error:run.error?.message??null,counts,
  authorControlledCases:authorCases,peerControlledCases:peerCases,testIdentities,log,syntaxChecks,sourceBindingsBefore:sourcesBefore,
  sourcesUnchangedDuringRun:changed.length===0,changedFiles:changed,actualProjectNetworkRequests:0,privateInputsRead:0,
  liveApiQueries:0,liveWrites:0,sdkJobs:0,originalSourcesEdited:0,oldArtifactsOverwritten:0});
 await check('fresh independent run passes 36 actual controlled tests and seven syntax checks with all bound sources unchanged',async()=>{
  assert.equal(run.status,0,'fresh controlled test failure: '+log.path);assert.equal(run.error,undefined);
  assert.deepEqual(counts,{tests:36,pass:36,fail:0,cancelled:0,skipped:0,todo:0});
  assert.equal(testIdentities.length,counts.tests);assert.ok(testIdentities.every(item=>item.status==='ok'));
  const registeredNames=[];for(const file of testFiles)registeredNames.push(...(await text(file)).matchAll(/\btest\('([^']+)'/g));
  assert.deepEqual(testIdentities.map(item=>item.name).sort(),registeredNames.map(match=>match[1]).sort());
  assert.equal(peerCases,15);assert.equal(authorCases,21);
  assert.ok(syntaxChecks.every(item=>item.exitCode===0));assert.deepEqual(changed,[]);
 });
 const review={kind:'independent-v7-provider-credential-source-review',reviewedAt:new Date().toISOString(),startedAt,
  reviewer:'/root/requirement_acceptance',authority:'Delegated technical review requested by the user through the parent; no personal human signature or live-operation authority is claimed.',
  projectId:candidate.projectId,passed:true,technicalVerdict:'approve the exact frozen V7 source and both byte-identical candidate payloads for separate root/operation-owner decision',
  candidate:evidence.get(author+'candidate-manifest.json'),candidateBundleSha256:candidate.candidateBundleSha256,
  authorProof:evidence.get(author+'source-proof.json'),sourcePreparation:evidence.get(candidate.sourcePreparation.path),
  sourceBindings:sourcesBefore,checkedSourceBindings:sourcesBefore.length,checks,transformations,closure:closures,
  counts:{newSourceFiles:7,runtimePayloadFiles:17,receiverPayloadFiles:10,totalPayloadRows:27,uniquePayloadFiles:20,uniqueSourceModules:18,
   runtimeStaticModules:16,runtimeLiteralDynamicInclusiveModules:16,receiverStaticModules:8,receiverLiteralDynamicInclusiveModules:9,
   sourceReviewChecks:checks.length,controlledTests:testIdentities.length,authorCases,peerCases,syntaxChecks:7},
  independentValidation:{evidence:testEvidence,log,counts,allSevenSyntaxChecksPassed:true,sourcesUnchangedDuringRun:true},
  credentialPolicy:{minimumCharacters:32,reservedSbFamilyCheckedBeforeLegacyShape:true,acceptedServiceFormats:['strict_sb_secret_shape','legacy_three_segment_shape'],
   opaqueSecretHeaders:['apikey'],legacyHeaders:['apikey','authorization_Bearer_same_key'],headerSelectionImmutable:true,
   roleOrAuthenticityValidated:false,callerAuthorizationGrantedByShape:false,keyDecoded:false,dictionaryParsed:false,newEnvironmentNames:false,
   actualCallerJwtReaderUnchanged:true,privilegedDefaultAndScopedPortsUseV7:true,unknownScopedRpcRejectedBeforeFetch:true},
  retainedLimits:candidate.retainedLimits,
  primaryDocumentation:{url:'https://supabase.com/docs/guides/getting-started/api-keys#known-limitations',
   method:'Independent reviewer opened the official API-key documentation with the web tool during this source review.',
   supportedClaim:'Opaque publishable/secret keys are not JWTs and use apikey; signed-in users separately provide their own JWT.',
   localInference:'The reviewed new header selector matches the official transport guidance. Syntax compatibility does not establish the actual injected key role, validity, permission or installed behavior.'},
  previousFailedReview:{path:output+'independent-review-stop-a1.json',sha256:'32a41cf2122fa82a1961f489a242e28f1b3a8450839f941803326e363acf5274',
   reason:'Peer fixture expected 400 for the extra-event-field case; the exact original receiver returns a sanitized 503 before any RPC. The successor compares both versions and asserts zero backend dispatch. The earlier passing 35 and failed one cases remain preserved. Initial peer case metadata was corrected from 16 to the actual 15.'},
  sourceOnly:true,liveExecutionAuthorized:false,exactDeploymentOperationDecisionStillRequired:true,finalOwnerReviewStillRequired:true,
  actualV7Deployment:false,actualV7Probe:false,actualProviderCompatibilityProvedLive:false,authenticatedNative:false,targetScaleLoad:false,
  actualDelivery:false,actualTrustedModelUsage:false,schedulesResumed:false,ownerAcceptanceRowsAdded:0,productionReleaseReady:false,
  personalHumanExactSourceSignatureClaimed:false,
  execution:{onlyAdditiveReviewArtifactsWritten:true,workerSourceFilesEdited:0,oldEvidenceOverwritten:0,projectNetworkRequests:0,
   privateInputsRead:0,liveApiQueries:0,liveWrites:0,deployments:0,scheduleChanges:0,sdkJobs:0},
  limitations:[
   'All service keys, caller tokens, actors, clocks and HTTP replies in the fresh controlled tests are deliberately fake. No real project request, DNS lookup, model call or private input was used.',
   'The legacy branch checks only an existing three-segment structural shape, not JWT signature, issuer, expiry or service role. The opaque branch checks a reserved prefix and characters, not secret authenticity. The injected trusted server configuration and server authority remain separate prerequisites.',
   'The raw RPC transport retains the old URL guard and internal name interpolation. The reviewed scoped wrapper retains its exact allowlist; internal default raw ports still call only the fixed edge-control RPC. This source review does not turn the raw transport into a public arbitrary-RPC API.',
   'The unchanged V6 finite diagnostic remains one attempt per loaded module/isolate, including errors. A cold isolate has a new counter; root must retain the separate bounded operation and paused schedule constraints.',
   'The official guidance explains API-key transport. The saved V6 shape observation and a local syntax classifier do not establish key role/permission or why an installed worker might fail.',
   'Existing invalid-event response mapping is preserved: signed whitespace or alternate canonical key order returns 400 EVENT_CONTRACT_MISMATCH; an extra schema field makes forecastEvent throw and returns 503 RECEIVER_UNAVAILABLE. Both V6 and V7 perform zero backend dispatch in these cases. This bounded source change does not revise that existing status mapping.',
   'Both payloads and all imports are actual source bytes, including the old public-caller transport and literal lazy worker_runtime. No normalization was used. Any source or payload change requires an additive successor review.',
   'No operation packet, actual deployment/readback/probe, provider success, delivery, model usage, native workflow, target-scale load, requirement acceptance or release gate is closed by this source-only record.'
  ]};
 const report=await write(output+'independent-source-review-a2.json',review);
 const markdown=await write(output+'independent-source-review-a2.md',[
  '# Independent V7 source review','',
  'The exact frozen V7 sources and both candidate payloads pass independent source review. All 36 controlled cases pass: the author’s 21 cases and 15 additional peer cases. All seven syntax checks pass. Every bound input stayed unchanged during this run. The root and operation owner still need to decide the exact live operation.','',
  'Opaque service keys use only `apikey`. Legacy service JWT shapes keep the original `apikey` and Bearer headers. Reserved `sb_` families are checked first; malformed, unknown and publishable forms cannot use the legacy fallback. The classifier establishes format only. It does not authenticate a key, establish its role, authorize a caller or discover credentials. This transport behavior follows the [official Supabase API-key guidance](https://supabase.com/docs/guides/getting-started/api-keys#known-limitations).','',
  'Exact reverse diffs verify the original URL guard, scope allowlist, caller checks, schedule-secret hash, receiver HMAC, body limits, concurrency caps, deadlines, error mapping and finite V6 diagnostic. The privileged default and scoped ports use V7. The unchanged public model reader retains its original transport and independently sends the caller’s JWT with the public API key. Denied or stale public authority cannot fall back to the service key.','',
  'The payloads contain 17 runtime files and 10 receiver files, or 27 rows, 20 unique files and 18 source modules. Actual static and literal dynamic import graphs are 16/16 for runtime and 8/9 for receiver. The fixed lazy worker_runtime module is retained; the receiver does not invoke its delivery-batch export. Every payload row equals its current source bytes without normalization.','',
  'Additional peer cases cover invalid key types and encodings, foreign routes, exact project configuration, unsigned schedules, denied ticks, eight concurrent request slots, stream cancellation, downstream abort, private-error suppression, canonical event bytes, forged HMAC on every fault route, unknown scoped RPCs, rejected caller reads and changed public authority. All ports use controlled fake inputs; no project network or private credential operation was performed.','',
  'The first peer run is preserved with 35 passes and one fixture failure. The successor binds the actual predecessor behavior: signed whitespace and alternate key order return 400; an extra schema field returns a sanitized 503. Both versions make zero backend calls for those cases. The final case counts come from actual registered test identities and TAP results.','',
  'The original caps remain four model calls and 4,320 schedule requests, with 24 earlier requests retained. Authority still expires on October 14, 2026 at 09:57:07.481942 UTC or an earlier applicable expiry. This review adds no live authority, schedule resume, native acceptance, load result, requirement decision or production release claim.','',
  `Exact review: ${report.path} (SHA-256 ${report.sha256}).`,
  `Fresh test evidence: ${testEvidence.path} (SHA-256 ${testEvidence.sha256}).`,
  `Fresh TAP log: ${log.path} (SHA-256 ${log.sha256}).`,''].join('\n'));
 console.log(JSON.stringify({passed:true,report,markdown,tests:testEvidence,log,counts,sourceReviewChecks:checks.length,boundInputs:sourcesBefore.length,
  candidateBundleSha256:candidate.candidateBundleSha256,sourceOnly:true,liveExecutionAuthorized:false}));
}catch(error){
 const stop=await write(output+'independent-review-stop-a2.json',{kind:'preserved-independent-v7-source-review-stop',startedAt,
  stoppedAt:new Date().toISOString(),failure:error.message,stack:error.stack,checksBeforeStop:checks,sourceBindingsRead:[...evidence.values()],
  sourceOnly:true,projectNetworkRequests:0,privateInputsRead:0,workerSourcesEdited:0,oldEvidenceOverwritten:0,sdkJobs:0,liveOperations:0});
 console.error(JSON.stringify({passed:false,stop}));process.exitCode=1;
}
