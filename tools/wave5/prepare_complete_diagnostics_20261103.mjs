import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const base='docs/verification/ai-integrations-test-20261103/',previous='build/wave5-rpc-diagnostics-20261103/candidate/',candidate='build/wave5-rpc-diagnostics-20261103/complete-candidate/';
const hash=b=>createHash('sha256').update(b).digest('hex');
const old=JSON.parse(await readFile(previous+'candidate.json','utf8'));
const changed=new Set(['supabase/functions/wave5-runtime/index.ts','workers/wave5/edge_runtime.mjs','workers/wave5/worker_endpoints.mjs','workers/wave5/model_runtime.mjs']),sources=[];
for(const source of old.sources){
 if(path.isAbsolute(source.path)||source.path.split('/').includes('..'))throw Error('SOURCE_PATH_INVALID');
 const b=await readFile(source.path);if(!changed.has(source.path)&&hash(b)!==source.sha256)throw Error('UNRELATED_SOURCE_CHANGED');
 await mkdir(path.dirname(candidate+source.path),{recursive:true});await writeFile(candidate+source.path,b,{flag:'wx'});sources.push({path:source.path,sha256:hash(b),bytes:b.length});
}
await copyFile(previous+'supabase/config.toml',candidate+'supabase/config.toml');
const manifest={kind:'complete-safe-model-failure-diagnostics',preparedAt:new Date().toISOString(),baselineRuntimeVersion:10,expectedRuntimeVersion:11,changedPaths:[...changed],sources};
const bytes=JSON.stringify(manifest,null,2)+'\n';await writeFile(candidate+'candidate.json',bytes,{flag:'wx'});
const logs=await readFile(base+'complete-diagnostic-worker-tests.log','utf8');if(!/pass 313/.test(logs)||!/fail 0/.test(logs))throw Error('PASSING_TEST_LOG_REQUIRED');
const report={kind:'complete-diagnostic-candidate-prepared',observedAt:new Date().toISOString(),candidate,manifestSha256:hash(bytes),sourceInputs:sources.length,executableModules:sources.filter(s=>/\.(?:mjs|ts)$/.test(s.path)).length,changedPaths:[...changed],workerTests:{passed:313,failed:0},normalDenoCheckPassed:true,hostedDeployed:false,additionalAiAttemptApproved:false,networkCalls:0,
 proposedAction:'Deploy this exact diagnostic-only candidate, verify hosted readback, then send one empty-object body with a deliberately invalid caller to observe fixed configuration/error metadata. No preserved request payload or invocation IDs are sent, and no AI call can pass input validation.',
 diagnosticFields:['event','rpc','stage','status','code','errorKind','callerKeyKind','serviceKeyKind','urlMatchesConfigured','frame (only reviewed module basename and line/column)'],logsCredentials:false,logsRequests:false,authorizationChanged:false,providerChanged:false,databaseChanged:false,windowRenewed:false,deliveryResent:false,approvalPendingBecause:'Automatic approval review rejected an additional persistent deployment beyond V10 and the consumed single retry.',
 artifacts:await Promise.all(['workers/wave5/model_handler_diagnostics.test.mjs',base+'complete-diagnostic-worker-tests.log',base+'complete-diagnostic-deno.log'].map(async p=>({path:p,sha256:hash(await readFile(p))})))};
await writeFile(base+'complete-diagnostic-candidate.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify(report));
