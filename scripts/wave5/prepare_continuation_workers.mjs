// Local source/evidence/payload preparation only. No approval, provisioning,
// deployment, secret access, worker launch or external delivery is performed.
import {readFile,readdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
const revision=process.argv[2];
if(!/^r\d+$/.test(revision??''))throw Error('CONTINUATION_REVISION_REQUIRED');
const base='docs/verification/wave5/',suffix=`20261009-${revision}`;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=async p=>JSON.parse((await readFile(p,'utf8')).replace(/^\uFEFF/,''));
async function save(p,value){await writeFile(p,JSON.stringify(value,null,2)+'\n',{flag:'wx'});}
const priorPath=base+'complete-app-runtime-review-20261009.json',prior=await json(priorPath);
const {bundleSha256,...body}=prior;
if(sha(JSON.stringify(body))!==bundleSha256||bundleSha256!=='13ffe2fdfd412fae36d3ff08c1f33bb59d9de85f20b2707e77ba6b9629eae83e'||prior.ownerApproved!==false)throw Error('ORIGINAL_REVIEW_BINDING_CHANGED');
for(const m of prior.migrations)if(sha(await readFile(m.path))!==m.sha256)throw Error('MIGRATION_DRIFT:'+m.path);
const originalArtifactDrift=[];
for(const a of prior.artifacts){const actual=sha(await readFile(a.path));if(actual!==a.sha256)originalArtifactDrift.push({path:a.path,originalSha256:a.sha256,currentSha256:actual});}
const files=(await readdir('workers/wave5')).filter(f=>f.endsWith('.mjs')).sort().map(f=>'workers/wave5/'+f);
const testRecord=base+`complete-app-worker-tests-${suffix}.json`;
const sourceRecord=base+`complete-app-worker-source-${suffix}.json`;
let testCount,existingTests;
try{existingTests=await json(testRecord);}catch(error){if(error.code!=='ENOENT')throw error;}
if(existingTests){
 // A later evidence dependency can fail after the controlled run is saved.
 // Resume only when every tested worker input and log still matches; preserve
 // the original test timestamps/bytes instead of overwriting or inventing a run.
 const existingSource=await json(sourceRecord);
 if(existingTests.exitCode!==0||existingTests.failed!==0||existingSource.files.length!==files.length||sha(await readFile(existingTests.log))!==existingTests.logSha256)throw Error('EXISTING_TEST_EVIDENCE_INVALID');
 for(const f of existingSource.files)if(!files.includes(f.path)||sha(await readFile(f.path))!==f.sha256)throw Error('EXISTING_TEST_SOURCE_DRIFT');
 testCount=existingTests.tests;
}else{
 const tests=spawnSync(process.execPath,['--test',...files.filter(f=>f.endsWith('.test.mjs'))],{encoding:'utf8'});
 const output=(tests.stdout??'')+(tests.stderr??'');testCount=Number(/tests (\d+)/.exec(output)?.[1]);
 if(tests.status!==0||!testCount||!/fail 0/.test(output))throw Error('CURRENT_WORKER_TESTS_FAILED');
 const log=base+`complete-app-worker-tests-${suffix}.log`;await writeFile(log,output,{flag:'wx'});
 await save(testRecord,{observedAt:new Date().toISOString(),exitCode:tests.status,tests:testCount,passed:testCount,failed:0,controlled:true,
  command:'node --test workers/wave5/*.test.mjs',log,logSha256:sha(output),externalCalls:false,deployed:false});
 await save(sourceRecord,{observedAt:new Date().toISOString(),exitCode:0,controlled:true,deployed:false,
  files:await Promise.all(files.map(async p=>({path:p,sha256:sha(await readFile(p))}))),tests:testRecord});
}
const entrypoints=[];
for(const name of ['runtime','receiver']){
 const entrypoint=`supabase/functions/wave5-${name}/index.ts`,config=`supabase/functions/wave5-${name}/deno.json`;
 const log=base+`supabase-${name}-deno-${suffix}.log`,bytes=await readFile(log);
 if(!bytes.toString('utf8').includes('Check ')||bytes.toString('utf8').includes('error:'))throw Error('FRESH_DENO_RESULT_REQUIRED:'+name);
 entrypoints.push({entrypoint,config,exitCode:0,entrypointSha256:sha(await readFile(entrypoint)),configSha256:sha(await readFile(config)),log,logSha256:sha(bytes)});
}
const denoRecord=base+`supabase-entrypoint-checks-${suffix}.json`;
await save(denoRecord,{observedAt:new Date().toISOString(),checksRerun:true,entrypoints,command:'deno check --reload --config <per-entrypoint deno.json> <index.ts>',
 importedJavaScriptTypeChecked:false,javaScriptVerification:`${testCount} controlled Node tests`,deployed:false});
const deployments=[];
for(const name of ['wave5-runtime','wave5-receiver']){
 const original=await json(base+`supabase-deploy-${name}-20261009.json`),closure=new Map();
 async function visit(p){
  if(closure.has(p))return;
  const content=await readFile(p,'utf8');closure.set(p,content);
  for(const match of content.matchAll(/(?:from\s*|import\s*\(\s*)['"](\.[^'"]+)['"]/g)){
   const next=path.posix.normalize(path.posix.join(path.posix.dirname(p),match[1]));
   if(!/^(supabase\/functions|workers\/wave5)\//.test(next))throw Error('DEPLOYMENT_PATH_ESCAPE');
   await visit(next);
  }
 }
 await visit(original.entrypoint_path);await visit(`supabase/functions/${name}/deno.json`);
 const uploadFiles=[...closure].sort(([a],[b])=>a.localeCompare(b)).map(([name,content])=>({name,content}));
 const payload={...original,files:uploadFiles},payloadPath=base+`supabase-deploy-${name}-${suffix}.json`;
 await save(payloadPath,payload);
 const definition=prior.deployments.find(d=>d.name===name);
 deployments.push({...definition,payloadPath,files:uploadFiles.map(f=>({path:f.name,sha256:sha(f.content)}))});
}
const componentPath=base+`continuation-worker-component-${suffix}.json`;
await save(componentPath,{preparedAt:new Date().toISOString(),revision,originalReview:{path:priorPath,bundleSha256,sha256:sha(await readFile(priorPath)),ownerApproved:false},
 originalArtifactDrift,migrations:prior.migrations.length,migrationHashesUnchanged:true,sourceRecord,testRecord,denoRecord,deployments,
 modifiedSource:originalArtifactDrift.filter(a=>a.path.startsWith('workers/wave5/')),addedSource:['workers/wave5/request_deadline.test.mjs'],
 requestDeadline:{maximumMs:65000,bodyReadsCancellable:true,callerCancellationPropagated:true,receiverFetchesBounded:true,timeoutHttpStatus:408,timeoutCode:'REQUEST_TIMEOUT'},
 actualModelUsage:false,actualWorkerDelivery:false,installedSql:false,realMfa:false,independentContention:false,targetScaleLoad:false,ownerAccepted:false,
 requiresRefreshedFullReview:true,oldReviewCannotApproveChangedSource:true});
console.log(JSON.stringify({componentPath,tests:testCount,migrations:prior.migrations.length,originalArtifactDrift:originalArtifactDrift.map(d=>d.path),
 deployments:deployments.map(d=>({name:d.name,payloadPath:d.payloadPath,files:d.files.length})),entrypointsChecked:entrypoints.length,liveOperationsPerformed:false}));
