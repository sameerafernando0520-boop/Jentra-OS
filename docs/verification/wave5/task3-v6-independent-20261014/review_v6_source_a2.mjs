import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {decodePublicResult} from '../../../../tools/wave5/approved_management_installer.mjs';

const root=fileURLToPath(new URL('../../../../',import.meta.url));
const output='docs/verification/wave5/task3-v6-independent-20261014/';
const digest=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const evidence=[];
async function read(relative,expected){
 assert.match(relative,/^[a-zA-Z0-9_./-]+$/);assert.equal(relative.includes('..'),false);
 const bytes=await fs.readFile(path.join(root,relative)),sha256=digest(bytes);
 if(expected)assert.equal(sha256,expected,'exact evidence drift: '+relative);
 if(!evidence.some(ref=>ref.path===relative))evidence.push({path:relative,bytes:bytes.length,sha256});return bytes;
}
const json=async(relative,expected)=>JSON.parse(await read(relative,expected));
async function write(relative,value){const bytes=typeof value==='string'?value:JSON.stringify(value,null,2)+'\n';
 const handle=await fs.open(path.join(root,relative),'wx');try{await handle.writeFile(bytes);await handle.sync();}finally{await handle.close();}
 return {path:relative,bytes:Buffer.byteLength(bytes),sha256:digest(bytes)};
}
const startedAt=new Date().toISOString();
try{
 const proof=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof.json',
  '629eb4abaf456710ee35c5818748ca6fc4c81ee552f966d0eca09227ee70a177');
 const correction=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof-a2.json',
  'e20a9de5f0124c1ae1941172e57c8e8eb6bf5418603b5d9b23dc03ab8ada0e7a');
 assert.deepEqual(correction.sourceBindings,proof.sourceBindings);
 assert.deepEqual(correction.localVerification,proof.localVerification);
 assert.deepEqual(correction.retainedLimits,proof.retainedLimits);
 assert.equal(correction.countCorrection.sourceOrTestChanges,false);
 assert.equal(correction.countCorrection.priorProofPreserved,true);
 const preparation=await json('docs/verification/wave5/task3-v6-diagnostic-20261014/source-preparation.json',
  '0dce5f5fb9f609e33cb00b7a97dd9bbfb217ee6f170dd0eeab3427c557ceb0cc');
 const original=await json(proof.predecessor.path,proof.predecessor.sha256);
 const authorChecks=await json(proof.localVerification.path,proof.localVerification.sha256);
 assert.equal(proof.projectId,'xpdoufauvrbdmxgngetv');assert.equal(preparation.written.length,5);
 assert.deepEqual(proof.retainedLimits,original.retainedLimits);
 assert.equal(proof.retainedLimits.authorityExpiresAt,'2026-10-14T09:57:07.481942Z');
 assert.equal(proof.retainedLimits.maximumModelCalls,4);assert.equal(proof.retainedLimits.maximumScheduleRequestsOriginal,4320);
 assert.equal(proof.retainedLimits.scheduledRequestsAlreadyObserved,24);assert.equal(proof.retainedLimits.extendedExpiry,false);
 assert.equal(proof.schedulesRemainPaused,true);assert.equal(proof.providerFix,false);assert.equal(proof.environmentOrSecretsChanged,false);
 assert.equal(authorChecks.passed,true);assert.equal(authorChecks.exitCode,0);assert.equal(authorChecks.counts.tests,16);
 assert.equal(authorChecks.counts.pass,16);assert.equal(authorChecks.counts.fail,0);
 await read(authorChecks.log.path,authorChecks.log.sha256);
 for(const binding of proof.sourceBindings)assert.equal((await read(binding.path,binding.sha256)).length,binding.bytes);
 for(const binding of preparation.written)await read(binding.path,binding.sha256);
 const oldRoute=await read('workers/wave5/edge_route_20261014_r5_v5.mjs');
 const newRoute=await read('workers/wave5/edge_route_20261014_r5_v6.mjs');
 assert.ok(newRoute.subarray(0,oldRoute.length).equals(oldRoute));
 const appendix=newRoute.subarray(oldRoute.length).toString('utf8');
 assert.equal((appendix.match(/let providerDiagnosticRemaining=1/g)||[]).length,1);
 assert.equal((appendix.match(/providerDiagnosticRemaining--/g)||[]).length,1);
 assert.equal((appendix.match(/providerEnvValue\(env,'SUPABASE_[A-Z_]+'\)/g)||[]).length,3);
 for(const denied of [/\bJSON\.parse\s*\(/,/\b(?:fetch|atob)\s*\(/,/\bBuffer\b/,/\.toObject\s*\(/,
  /\bDeno\b/,/\bprocess\.env\b/,/\bObject\.(?:keys|entries|values)\s*\(env/,/\breq\.(?:url|headers|body|method)\b/])
  assert.equal(denied.test(appendix),false,'new appendix contains forbidden operation '+String(denied));
 const factoryDiffs=[];
 for(const worker of ['runtime','receiver']){
  const oldPath=`workers/wave5/edge_${worker}_20261014_r5_v5.mjs`,newPath=`workers/wave5/edge_${worker}_20261014_r5_v6.mjs`;
  const before=await read(oldPath),after=await read(newPath);
  assert.equal(before.toString().split('./edge_route_20261014_r5_v5.mjs').length,2);
  assert.equal(after.toString(),before.toString().replace('./edge_route_20261014_r5_v5.mjs','./edge_route_20261014_r5_v6.mjs'));
  const entryPath=`supabase/functions/wave5-${worker}/index_20261014_r5_v6.ts`,entry=(await read(entryPath)).toString();
  const factory=worker==='runtime'?'Runtime':'Receiver';
  const expected=`import {createEdge${factory}} from '../../../workers/wave5/edge_${worker}_20261014_r5_v6.mjs';\n`
   +`import {withBoundedProviderDiagnostic} from '../../../workers/wave5/edge_route_20261014_r5_v6.mjs';\n`
   +"import {edgeConfiguration} from '../../../workers/wave5/edge_configuration.mjs';\n\n"
   +'// The unchanged handler authenticates before this single finite observation.\n'
   +'// Provider keys and URL values never reach the diagnostic sink.\n'
   +'Deno.serve(withBoundedProviderDiagnostic({\n'
   +` handler:createEdge${factory}({env:Deno.env}),env:Deno.env,\n`
   +` configuredUrl:edgeConfiguration.url,worker:'${worker}',\n`
   +' observe:(classification:unknown)=>console.info(JSON.stringify(classification)),\n}));\n';
  assert.equal(entry.replaceAll('\r\n','\n'),expected);
  factoryDiffs.push({worker,oldPath,newPath,exactSingleImportReplacement:true,entrypoint:entryPath,
   exactEntrypointTemplate:true,diagnosticWrappersInstalled:1,priorIngressWrapperInstalled:false});
 }
 const closures=[];
 for(const deployment of original.deployments){
  const payload=await json(deployment.payload.path,deployment.payload.sha256);
  assert.equal(payload.project_id,proof.projectId);assert.equal(payload.name,deployment.name);
  assert.equal(payload.verify_jwt,false);assert.equal(payload.files.length,deployment.files.length);
  const current=proof.deployments.find(entry=>entry.name===deployment.name);
  assert.ok(current);assert.equal(current.verifyJwt,false);
  const expectedPaths=deployment.files.map(file=>file.path.replace('_20261014_r5_v5','_20261014_r5_v6')).sort();
  assert.deepEqual(current.files.map(file=>file.path).sort(),expectedPaths);
  for(const binding of deployment.files){
   const embedded=payload.files.filter(file=>file.name===binding.path);assert.equal(embedded.length,1);
   const bytes=await read(binding.path,binding.sha256);assert.equal(bytes.length,binding.bytes);
   assert.ok(Buffer.from(embedded[0].content).equals(bytes));
  }
  for(const binding of current.files){
   const bytes=await read(binding.path,binding.sha256);assert.equal(bytes.length,binding.bytes);
   if(!binding.path.includes('_20261014_r5_v6')){
    const retained=deployment.files.find(ref=>ref.path===binding.path);assert.ok(retained);
    assert.equal(binding.sha256,retained.sha256);assert.equal(binding.bytes,retained.bytes);
   }
  }
  const graph=new Set(),allowed=new Set(current.files.map(file=>file.path));
  async function visit(relative){
   if(graph.has(relative))return;assert.ok(allowed.has(relative),'new import outside reviewed closure: '+relative);graph.add(relative);
   const source=(await read(relative)).toString();
   for(const match of source.matchAll(/(?:import|export)[^\n]*?\bfrom\s*['"]([^'"]+)['"]/g)){
    const specifier=match[1];if(specifier.startsWith('node:'))continue;
    assert.ok(specifier.startsWith('.'),'external import in deployment closure');
    const imported=path.posix.normalize(path.posix.join(path.posix.dirname(relative),specifier));await visit(imported);
   }
  }
  await visit(current.entrypoint);
  const exactModules=current.files.filter(file=>/\.(?:mjs|ts)$/.test(file.path)).map(file=>file.path).sort();
  const retainedOnly=exactModules.filter(relative=>!graph.has(relative));
  assert.deepEqual(retainedOnly,deployment.name==='wave5-runtime'?[]:['workers/wave5/worker_runtime.mjs']);
  assert.equal(graph.size,deployment.name==='wave5-runtime'?14:7);
  assert.ok([...graph].every(relative=>exactModules.includes(relative)));
  const corrected=correction.deployments?.find(entry=>entry.name===deployment.name);
  assert.ok(corrected);assert.equal(corrected.staticReachableSourceModuleCount,graph.size);
  assert.equal(corrected.retainedSourceRowCount,exactModules.length);
  assert.deepEqual(corrected.files,current.files);
  assert.deepEqual(corrected.staticReachableSourcePaths,[...graph].sort());
  const dynamicGraph=new Set(),literalDynamicImports=[];
  async function visitDynamic(relative){
   if(dynamicGraph.has(relative))return;assert.ok(allowed.has(relative),'import outside complete declared graph: '+relative);dynamicGraph.add(relative);
   const source=(await read(relative)).toString();
   const staticImports=[...source.matchAll(/(?:import|export)[^\n]*?\bfrom\s*['"]([^'"]+)['"]/g)].map(match=>match[1]);
   const dynamicImports=[...source.matchAll(/\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g)].map(match=>match[1]);
   assert.equal((source.match(/\bimport\s*\(/g)||[]).length,dynamicImports.length,'nonliteral dynamic import in retained graph');
   for(const specifier of dynamicImports)literalDynamicImports.push({owner:relative,specifier,
    target:path.posix.normalize(path.posix.join(path.posix.dirname(relative),specifier))});
   for(const specifier of [...staticImports,...dynamicImports]){
    if(specifier.startsWith('node:'))continue;assert.ok(specifier.startsWith('.'));
    await visitDynamic(path.posix.normalize(path.posix.join(path.posix.dirname(relative),specifier)));
   }
  }
  await visitDynamic(current.entrypoint);
  assert.deepEqual([...dynamicGraph].sort(),exactModules);
  assert.deepEqual(literalDynamicImports,[{owner:'workers/wave5/persistent_control.mjs',specifier:'./worker_runtime.mjs',target:'workers/wave5/worker_runtime.mjs'}]);
  assert.equal(dynamicGraph.size,deployment.name==='wave5-runtime'?14:8);
  assert.equal(corrected.literalDynamicInclusiveSourceModuleCount,dynamicGraph.size);
  if(deployment.name==='wave5-receiver'){
   const receiver=(await read('workers/wave5/edge_receiver_20261014_r5_v6.mjs')).toString();
   assert.equal(receiver.includes('runDeliveryBatch'),false);
   const owner=(await read('workers/wave5/persistent_control.mjs')).toString();
   assert.equal(owner.split(/\r?\n/)[46]," const {runDelivery}=await import('./worker_runtime.mjs');");
   assert.equal(corrected.retainedExtraExplanation.receiverInvokesExport,false);
  }
  assert.equal(current.files.length,deployment.name==='wave5-runtime'?15:9);
  closures.push({name:current.name,entrypoint:current.entrypoint,verifyJwt:false,files:current.files,
   deploymentFiles:current.files.length,retainedSourceRows:exactModules.length,staticReachableSourceModules:graph.size,
   staticReachableSources:[...graph].sort(),retainedSourcesOutsideStaticGraph:retainedOnly,
   literalDynamicInclusiveSourceModules:dynamicGraph.size,literalDynamicInclusiveSourcePaths:[...dynamicGraph].sort(),
   exactLiteralDynamicImports:literalDynamicImports,allImportsInsideExactClosure:true,
   oldPayloadMatchesOldFiles:true,allNonversionedModulesUnchanged:true});
 }
 const testPath='docs/verification/wave5/task3-v6-diagnostic-20261014/provider_diagnostic.test.mjs';
 const peerTest=output+'provider_diagnostic_peer.test.mjs';
 await read(testPath,'181e6b5d4fa5d40e4e50b53d3ce0a266bd325765ef58a57be5392c8917cde4b3');await read(peerTest);
 const tests={path:output+'independent-local-verification-a1.json',sha256:'405f00c75bdf8e35d3b7aaa6052c79d90450ec24151115592472f4d7034915cf'};
 const checks=await json(tests.path,tests.sha256),log=checks.log,counts=checks.counts;
 await read(log.path,log.sha256);assert.equal(checks.exitCode,0);assert.equal(checks.sourcesUnchangedDuringRun,true);
 assert.deepEqual(counts,{tests:21,pass:21,fail:0,cancelled:0,skipped:0,todo:0});
 assert.ok(checks.syntaxChecks.length===5&&checks.syntaxChecks.every(check=>check.exitCode===0));
 for(const binding of checks.sourceBindingsBefore)await read(binding.path,binding.sha256);
 for(const binding of evidence)assert.equal(digest(await fs.readFile(path.join(root,binding.path))),binding.sha256,'final input drift: '+binding.path);
 const priorStop=await json(output+'independent-review-stop-a1.json','ddd1b4c57b735ba0ad4d7db3038b7820f7c10bf622f6639b15b8e8cf56aeeb2e');
 assert.ok(priorStop.failure.includes('worker_runtime.mjs'));
 const packet=await json('docs/verification/wave5/worker-v6-diagnostic-runtime-review-20261014-r5.json','7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25');
 assert.deepEqual(packet.retainedLimits,proof.retainedLimits);assert.equal(packet.schedulesMustRemainPaused,true);
 const actualPayloads=[];
 for(const deployment of packet.deployments){
  const source=closures.find(closure=>closure.name===deployment.name);assert.ok(source);assert.deepEqual(deployment.files,source.files);
  const payload=await json(deployment.payload.path,deployment.payload.sha256);
  assert.equal(payload.project_id,proof.projectId);assert.equal(payload.name,deployment.name);
  assert.equal(payload.entrypoint_path,deployment.entrypoint);assert.equal(payload.verify_jwt,false);
  assert.equal(payload.files.length,deployment.files.length);
  for(const binding of deployment.files){const rows=payload.files.filter(file=>file.name===binding.path);assert.equal(rows.length,1);
   const bytes=await read(binding.path,binding.sha256);assert.ok(Buffer.from(rows[0].content).equals(bytes));}
  actualPayloads.push(deployment.payload);
 }
 const v5Probe=await json('docs/verification/wave5/worker-v5-routing-fixed-unauthenticated-probe-20261014-r5.json');
 const v5Ingress=await json('docs/verification/wave5/worker-v5-routing-actual-finite-ingress-20261014-r5.json');
 const rows=decodePublicResult(v5Ingress.result).result;assert.equal(rows.length,1);
 const tuple=JSON.parse(rows[0].event_message);
 assert.equal(rows[0].request_id,v5Probe.responseRequestId);assert.equal(v5Ingress.savedProbeServerUuid,v5Probe.responseRequestId);
 assert.equal(tuple.kind,'wave5_ingress_v5');assert.equal(tuple.routeRecognized,true);
 assert.equal(tuple.originClass,'public_project_http');assert.equal(tuple.pathClass,'function_namespace');assert.equal(tuple.portClass,'default');
 assert.equal(v5Probe.status,503);assert.equal(v5Probe.code,'WORKER_PROVIDER_UNAVAILABLE');
 assert.equal(v5Probe.expectedUnauthenticatedHandlerDenial,false);assert.equal(v5Ingress.required403ProbePassed,false);
 assert.equal(v5Probe.schedulesResumed,false);assert.equal(v5Ingress.schedulesRemainPaused,true);
 const uniqueFiles=new Map(closures.flatMap(closure=>closure.files).map(binding=>[binding.path,binding]));
 const uniqueSources=[...uniqueFiles.keys()].filter(file=>/\.(?:mjs|ts)$/.test(file));
 assert.equal(uniqueFiles.size,18);assert.equal(uniqueSources.length,16);
 const review={kind:'independent-v6-finite-provider-diagnostic-source-review',reviewer:'/root/completion_peer',reviewedAt:new Date().toISOString(),
  projectId:proof.projectId,technicalVerdict:'approve exact source successor for one bounded existing-development diagnostic probe',
  sourceProof:{path:'docs/verification/wave5/task3-v6-diagnostic-20261014/source-proof.json',sha256:'629eb4abaf456710ee35c5818748ca6fc4c81ee552f966d0eca09227ee70a177'},
  correctedAuthorProof:evidence.find(ref=>ref.path.endsWith('/source-proof-a2.json')),
  sourcePreparation:evidence.find(ref=>ref.path.endsWith('/source-preparation.json')),sourceBindings:evidence,
  previousFailedAudit:{path:output+'independent-review-stop-a1.json',sha256:'ddd1b4c57b735ba0ad4d7db3038b7820f7c10bf622f6639b15b8e8cf56aeeb2e',
   cause:'Reviewer initially equated a static-only graph with the full retained dependency population. The final review separately verifies the exact receiver static graph of 7 and literal dynamic-inclusive graph of 8, including the fixed lazy import in runDeliveryBatch not called by the receiver. No arbitrary missing module is permitted.',beforeTests:true},
  independentValidation:{tests,log,counts,allFiveNodeSyntaxChecksPassed:true,allInputHashesUnchangedDuringRun:true},
  codeReview:{exactV5RoutePrefixBytes:oldRoute.length,exactV5RoutePrefixPreserved:true,originalEdgeRouteFunctionUnchanged:true,
   factories:factoryDiffs,handlerAuthenticationScopePayloadValidationAndProviderBehaviorPreserved:true,
   moduleScopeAttemptLatch:1,failedDiagnosticAlsoConsumesAttempt:true,multipleWrappersShareLatch:true,
   diagnosticAfterOriginalHandler:true,responseObjectStatusAndBytesPreserved:true,originalThrownOrRejectedErrorObjectPreserved:true,
   synchronousSinkFailureSwallowed:true,rejectedSinkSwallowed:true,sinkCatchGetterFailureSwallowed:true,
   getterFailuresSwallowedWithoutSecondAttempt:true,diagnosticDoesNotAwaitSink:true,
   descriptorKeys:['kind','worker','supabaseUrlClass','serviceRoleShape','secretKeysDictionaryPresent'],
   urlClasses:['exact_configured_https','exact_configured_https_with_slash','exact_project_http','missing','other'],
   serviceRoleShapeClasses:['legacy_jwt','opaque_secret_style','missing','other'],
   allowedDiagnosticEnvironmentNames:['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS'],
   rawUrlOrKeyLogged:false,keyDecoded:false,dictionaryParsed:false,dictionaryNamesEnumerated:false,
   unknownEnvironmentNamesRead:false,rawRequestFieldsRead:false,constructionEnvironmentRead:false,
   jwtShapeIsAuthenticationProof:false,dictionaryPresenceIsProviderReadinessProof:false,providerFix:false,environmentOrSecretAdaptation:false},
  retainedDeploymentClosure:{runtimeFiles:15,runtimeRetainedSourceRows:14,runtimeStaticReachableModules:14,runtimeLiteralDynamicInclusiveModules:14,
   receiverFiles:9,receiverRetainedSourceRows:8,receiverStaticReachableModules:7,receiverLiteralDynamicInclusiveModules:8,
   receiverRetainedSourcesOutsideStaticGraph:['workers/wave5/worker_runtime.mjs'],
   receiverLazyImport:{owner:'workers/wave5/persistent_control.mjs',line:47,export:'runDeliveryBatch',literalSpecifier:'./worker_runtime.mjs',receiverInvokesExport:false},
   totalFileRows:24,uniqueFiles:18,uniqueRetainedSourceRows:16,closures,actualNewPayloadBytesReviewed:true,actualPayloads,
   originalOperationPacket:{path:'docs/verification/wave5/worker-v6-diagnostic-runtime-review-20261014-r5.json',sha256:'7023830c0d803b59662a6ea55ef4855063a992c7caabaf244f89040ebdecef25',canonicalBundleSha256:packet.bundleSha256}},
  retainedLimits:proof.retainedLimits,
  savedV5Observation:{requestId:v5Probe.responseRequestId,status:503,code:'WORKER_PROVIDER_UNAVAILABLE',routeRecognized:true,
   internalTuple:tuple,required403Passed:false,schedulesRemainPaused:true,interpretation:'The saved request reached the exact route; the handler still reported provider configuration unavailable. It does not establish which real environment value failed.'},
  boundedEligibleNextOperation:{existingProjectOnly:true,existingWorkersOnly:['wave5-runtime','wave5-receiver'],maximumPublicProbeRequests:1,
   externalProbePublicHttps:true,probeEndpoint:'https://xpdoufauvrbdmxgngetv.supabase.co/functions/v1/wave5-runtime/schedule',
   method:'POST',body:'{}',credentialsSupplied:false,maximumProbeDeadlineMs:12000,maximumProbeResponseBytes:1024,
   redirectsFollowed:0,automaticRetries:0,maximumFiniteProviderObservationAttemptsPerIsolate:1,
   originalExpiryAndCapsMustRemainExact:true,newOnceOnlyIntentRequired:true,schedulesMustRemainPaused:true,
   deploymentReadbackMustMatchEveryReviewedModule:true,unchangedPeopleMetadataRequired:true,
   exactDeploymentPayloadAndOperationPacketRootReviewStillRequired:true,noProviderRepairAuthorizedByThisReview:true},
  scope:{sourceFilesEdited:0,oldArtifactsOverwritten:0,networkRequests:0,privateInputsRead:0,liveQueries:0,liveWrites:0,
   environmentWrites:0,sqlExecuted:false,sdkJobs:0,deployments:0,scheduledJobsChanged:0,onlyAdditivePublicReviewArtifactsWritten:true},
  limitations:['This independent review approves the exact source and retained closure for one bounded diagnostic under the existing development scope. Both exact prepared payloads match this retained source population. The root must bind the count correction and final operation decision before live-owner deployment.',
   'The counter bounds one attempted sample per loaded module/isolate. A cold new isolate has a new counter; this source cannot enforce a global cross-isolate lifetime cap. The operation packet must retain exactly one public probe and paused schedules.',
   'A legacy_jwt or opaque_secret_style value is a syntax shape, not token authenticity, role, permission, usability or a secret value. A nonempty dictionary string is presence only and may be malformed.',
   'The wrapper preserves actual original Response objects, status and bytes, or original thrown/rejected error objects. It wraps async completion to perform the diagnostic and does not promise identity of the original Promise.',
   'Only controlled fake environment inputs were inspected here. No real provider configuration was read, changed, parsed, repaired or confirmed.',
   'The saved V5 503 is preserved; the exact failing real provider variable is unknown until an authorized diagnostic provides its limited classification.',
   'No schedule resume, delivery, trusted model call, authenticated Windows, keyboard/restart/recovery, load acceptance, requirement owner signoff or production release follows from this diagnostic approval.'],
  personalHumanExactSourceSignatureClaimed:false,providerConfigRepaired:false,actualV6Deployment:false,actualV6Probe:false,
  actualAuthenticatedWorkerSuccess:false,schedulesResumed:false,actualDelivery:false,targetScaleLoad:false,
  ownerAcceptanceRowsAdded:0,authenticatedNative:false,productionReleaseReady:false,realBilling:false};
 const report=await write(output+'independent-source-review-a2.json',review);
 const md=['# Independent V6 source review','',
  'Approved the exact five-source V6 diagnostic for one bounded probe under the existing development scope. All 21 controlled Node checks and all five syntax checks passed. Both prepared deployment payloads also match every reviewed source byte; the parent must bind the additive count correction and final operation decision before execution.','',
  'The full 4,539-byte V5 route prefix is unchanged. Runtime and receiver factories change only their route import. Each entrypoint replaces the previous ingress wrapper with one provider diagnostic after the original handler. The shared module latch permits one attempted observation, including failed getters or sinks, across concurrent requests and wrappers. Response objects, status, bytes and original errors remain intact.','',
  'The diagnostic reads only SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and SUPABASE_SECRET_KEYS. Its five-field record contains a closed URL class, key shape and dictionary-presence boolean. It does not decode keys, parse dictionary JSON, inspect requests, emit raw values or repair provider configuration. Key shape and dictionary presence do not prove authentication or provider readiness.','',
  'The complete retained deployment population is 15 runtime files and 9 receiver files: 14 and 8 retained source rows respectively, or 18 unique files including 16 unique source rows. The static graphs are 14 runtime modules and 7 receiver modules. The complete graphs including fixed literal dynamic imports are 14 and 8: unchanged worker_runtime.mjs is lazily imported inside the shared runDeliveryBatch export, which the receiver does not call. Both exact graphs were verified with no omitted or unreviewed module. Every old and new payload row matches its source bytes. The original model cap of 4, schedule cap of 4,320, earlier observed 24 requests and 2026-10-14T09:57:07.481942Z authority expiry remain exact.','',
  `The saved V5 probe ${v5Probe.responseRequestId} reached the reviewed managed HTTP route and returned 503 WORKER_PROVIDER_UNAVAILABLE. It did not pass the required 403 gate. Schedules stay paused. V6’s permitted next step is one unauthenticated public HTTPS diagnostic probe, with no retries or redirects, followed only by finite observation review.`,'',
  'No live environment, private credential, SQL, deployment, SDK or native action was performed. This review makes no provider-fix, worker-success, personal human signature, acceptance, load or release claim. A new cold isolate can sample again; the reviewed operation must therefore retain its separate one-probe limit and paused schedules.','',
  `Exact review: ${report.path} (SHA-256 ${report.sha256}).`,
  `Independent controlled log: ${log.path} (SHA-256 ${log.sha256}).`, ''].join('\n');
 const human=await write(output+'independent-source-review-a2.md',md);
 console.log(JSON.stringify({approvedSource:true,operationPacketReviewPending:true,review:report,markdown:human,tests,counts,log,
  boundArtifacts:evidence.length,closure:{runtime:15,receiver:9,uniqueFiles:18,uniqueSourceModules:16}}));
}catch(error){
 const diagnostic=await write(output+'independent-review-stop-a2.json',{kind:'preserved-independent-v6-source-review-stop',startedAt,
  stoppedAt:new Date().toISOString(),failure:error.message,stack:error.stack,evidenceReadBeforeStop:evidence,
  networkRequests:0,privateInputsRead:0,sourceModified:false,existingArtifactsOverwritten:false,sdkJobs:0,liveOperations:0});
 console.error(JSON.stringify({passed:false,diagnostic}));process.exitCode=1;
}
