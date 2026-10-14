import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
const root=process.cwd(),base='docs/verification/wave5/task3-v6-diagnostic-20261014';
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const read=async file=>{const bytes=await fs.readFile(path.join(root,file));return{path:file,bytes:bytes.length,sha256:sha(bytes),content:bytes.toString('utf8')};};
const reference=({content,...binding})=>binding;
const v5File='docs/verification/wave5/worker-v5-routing-runtime-review-20261014-r5.json';
const v5Bytes=await read(v5File),v5=JSON.parse(v5Bytes.content);
const mapPath=file=>file.replaceAll('_20261014_r5_v5.','_20261014_r5_v6.');
const declarations=[];
for(const deployment of v5.deployments){
  const entrypoint=mapPath(deployment.entrypoint),files=[];
  for(const predecessor of deployment.files){
    const original=await read(predecessor.path);
    if(original.sha256!==predecessor.sha256)throw Error('V5_CLOSURE_SOURCE_DRIFT');
    const file=mapPath(predecessor.path),current=await read(file);
    if(file===predecessor.path&&current.sha256!==original.sha256)throw Error('UNCHANGED_CLOSURE_SOURCE_DRIFT');
    files.push(reference(current));
  }
  const seen=new Set();
  async function visit(file){
    if(seen.has(file))return;seen.add(file);
    const source=await read(file);
    const imports=[...source.content.matchAll(/(?:from\s+|import\s*\()(['"])([^'"]+)\1/g)].map(match=>match[2]);
    for(const specifier of imports){
      if(specifier.startsWith('node:'))continue;
      if(!specifier.startsWith('.'))throw Error('UNREVIEWED_EXTERNAL_IMPORT');
      const target=path.relative(root,path.resolve(root,path.dirname(file),specifier)).replaceAll('\\','/');
      if(!target.startsWith('workers/wave5/')&&!target.startsWith('supabase/functions/'))throw Error('IMPORT_OUTSIDE_EXISTING_WORKER_SCOPE');
      await visit(target);
    }
  }
  await visit(entrypoint);
  const sourcePaths=files.filter(file=>/\.(mjs|ts)$/.test(file.path)).map(file=>file.path);
  if(seen.size!==sourcePaths.length||sourcePaths.some(file=>!seen.has(file)))throw Error('EXACT_V5_IMPORT_CLOSURE_REQUIRED');
  declarations.push({name:deployment.name,entrypoint,verifyJwt:deployment.verifyJwt,files,
    actualSourceClosureCount:seen.size,retainedDeploymentFileCount:files.length});
}
if(declarations[0].files.length!==15||declarations[1].files.length!==9)throw Error('RETAINED_15_9_CLOSURE_REQUIRED');
const tracked=[...new Set([...v5.deployments.flatMap(value=>value.files.map(file=>file.path)),
  ...declarations.flatMap(value=>value.files.map(file=>file.path)),v5File,`${base}/provider_diagnostic.test.mjs`,
  `${base}/prepare_v6_sources.mjs`,`${base}/source-preparation.json`,`${base}/finalize_v6_proof.mjs`])];
const before=await Promise.all(tracked.map(read)),startedAt=new Date().toISOString();
const command=['--test','--test-isolation=none','--test-reporter=tap',`${base}/provider_diagnostic.test.mjs`];
const env=Object.fromEntries(Object.entries(process.env).filter(([key])=>['SYSTEMROOT','WINDIR','TEMP','TMP'].includes(key.toUpperCase())));
const run=await new Promise(resolve=>{const child=spawn(process.execPath,command,{cwd:root,env,windowsHide:true});let output='',spawnFailure=false;
  const timer=setTimeout(()=>child.kill(),30000);child.stdout.on('data',chunk=>output+=chunk);child.stderr.on('data',chunk=>output+=chunk);
  child.on('error',()=>spawnFailure=true);child.on('close',(exitCode,signal)=>{clearTimeout(timer);resolve({output,exitCode,signal,spawnFailure});});});
const after=await Promise.all(tracked.map(read)),count=label=>Number(run.output.match(new RegExp(`^# ${label} (\\d+)$`,'m'))?.[1]??-1);
const counts=Object.fromEntries(['tests','pass','fail','cancelled','skipped','todo'].map(label=>[label,count(label)]));
const unchanged=JSON.stringify(before.map(reference))===JSON.stringify(after.map(reference));
const passed=run.exitCode===0&&run.signal===null&&!run.spawnFailure&&counts.tests===16&&counts.pass===16
  &&counts.fail===0&&unchanged;
const log=`${base}/local-verification.tap`;await fs.writeFile(path.join(root,log),run.output,{flag:'wx'});
const local={kind:'actual-controlled-worker-v6-provider-diagnostic-verification',startedAt,finishedAt:new Date().toISOString(),passed,
  command:['node',...command],nodeVersion:process.version,exitCode:run.exitCode,signal:run.signal,counts,
  sourcesUnchangedDuringRun:unchanged,sourceBindingsBefore:before.map(reference),sourceBindingsAfter:after.map(reference),
  log:{path:log,bytes:Buffer.byteLength(run.output),sha256:sha(run.output)},networkCalls:0,privateCredentialsRead:false,
  environmentWrites:0,liveSqlMutations:0,deployments:0,schedulesChanged:0,SDKJobs:0,
  boundary:'Actual controlled Node tests against fake environment values and existing handlers. No live environment observation, worker success or release/load acceptance is claimed.'};
const localFile=`${base}/local-verification.json`,localContent=JSON.stringify(local,null,2)+'\n';
await fs.writeFile(path.join(root,localFile),localContent,{flag:'wx'});
const v5Route=before.find(file=>file.path==='workers/wave5/edge_route_20261014_r5_v5.mjs');
const v6Route=before.find(file=>file.path==='workers/wave5/edge_route_20261014_r5_v6.mjs');
if(!v6Route.content.startsWith(v5Route.content))throw Error('UNCHANGED_V5_ROUTE_PREFIX_REQUIRED');
const preservedFactories=[];
for(const worker of ['runtime','receiver']){
  const original=before.find(file=>file.path===`workers/wave5/edge_${worker}_20261014_r5_v5.mjs`);
  const current=before.find(file=>file.path===`workers/wave5/edge_${worker}_20261014_r5_v6.mjs`);
  if(current.content!==original.content.replace('./edge_route_20261014_r5_v5.mjs','./edge_route_20261014_r5_v6.mjs'))throw Error('FACTORY_IMPORT_ONLY_REQUIRED');
  preservedFactories.push({worker,predecessor:reference(original),successor:reference(current),importOnly:true});
}
const proof={kind:'additive-v6-closed-provider-configuration-diagnostic-source-proof',preparedAt:new Date().toISOString(),
  projectId:v5.projectId,predecessor:reference(v5Bytes),localVerification:{path:localFile,bytes:Buffer.byteLength(localContent),sha256:sha(localContent)},
  sourceBindings:before.map(reference),deployments:declarations,uniqueDeploymentModules:new Set(declarations.flatMap(value=>value.files.map(file=>file.path))).size,
  preservedRoute:{predecessor:reference(v5Route),successor:reference(v6Route),exactV5BytesPrefix:true,routeEligibilityUnchanged:true},preservedFactories,
  classification:{url:['exact_configured_https','exact_configured_https_with_slash','exact_project_http','missing','other'],
    serviceRole:['legacy_jwt','opaque_secret_style','missing','other'],knownDictionary:'SUPABASE_SECRET_KEYS',dictionaryPublished:'presence_boolean_only',
    permittedEnvironmentReads:['SUPABASE_URL','SUPABASE_SERVICE_ROLE_KEY','SUPABASE_SECRET_KEYS'],keyDecoded:false,dictionaryParsed:false,
    rawUrlOrKeyPublished:false,unknownVariableNamesReadOrPublished:false,requestFieldsReadByDiagnostic:false},
  maximumDiagnosticAttemptsPerModuleIsolate:1,diagnosticRunsAfterOriginalHandler:true,failedDiagnosticChangesHandlerOutput:false,
  retainedLimits:v5.retainedLimits,providerFix:false,aliasTrustAdded:false,environmentOrSecretsChanged:false,independentReviewPending:true,
  delegatedTechnicalOperationDecisionPending:true,personalHumanExactSourceSignatureClaimed:false,
  liveDeployment:false,actualFiniteProbe:false,schedulesRemainPaused:true,actualAuthenticatedWorkerSuccess:false,
  nativeAcceptance:false,targetScaleLoad:false,productionReleaseReady:false,
  officialReferences:[{url:'https://supabase.com/docs/guides/functions/secrets',usedFor:'Current injected URL, legacy service-role and newer secret-key dictionary names; diagnostic publishes only a closed class/presence.'},
    {url:'https://supabase.com/docs/guides/functions/auth',usedFor:'Authentication behavior must remain separately enforced; no auth/provider adaptation in this successor.'}]};
const proofFile=`${base}/source-proof.json`,proofBytes=JSON.stringify(proof,null,2)+'\n';
await fs.writeFile(path.join(root,proofFile),proofBytes,{flag:'wx'});
process.stdout.write(JSON.stringify({passed,counts,sourceClosure:declarations.map(value=>({name:value.name,files:value.files.length,modules:value.actualSourceClosureCount})),
  uniqueDeploymentModules:proof.uniqueDeploymentModules,localVerification:{path:localFile,sha256:sha(localContent)},
  sourceProof:{path:proofFile,sha256:sha(proofBytes)},v6Sources:before.filter(file=>file.path.includes('_20261014_r5_v6.')).map(reference)})+'\n');
if(!passed)process.exitCode=1;
