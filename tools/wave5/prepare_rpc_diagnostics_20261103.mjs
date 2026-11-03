import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const root=process.cwd(),base='docs/verification/ai-integrations-test-20261103';
const oldCandidate='build/wave5-cloudflare-free-20261102/2026-11-01T19-57-55.413Z';
const candidate='build/wave5-rpc-diagnostics-20261103/candidate';
const hash=b=>createHash('sha256').update(b).digest('hex');
const old=JSON.parse(await readFile(path.join(root,oldCandidate,'candidate.json'),'utf8'));
const sources=[];
for(const item of [...old.sources,{path:'workers/wave5/rpc_failure_diagnostics.mjs'}]){
 if(path.isAbsolute(item.path)||item.path.split('/').includes('..'))throw Error('RELATIVE_SOURCE_REQUIRED');
 const bytes=await readFile(path.join(root,item.path));
 if(item.sha256&&item.path!=='supabase/functions/wave5-runtime/index.ts'&&hash(bytes)!==item.sha256)throw Error('UNRELATED_RUNTIME_SOURCE_CHANGED');
 const target=path.join(root,candidate,item.path);await mkdir(path.dirname(target),{recursive:true});await writeFile(target,bytes,{flag:'wx'});
 sources.push({path:item.path,sha256:hash(bytes),bytes:bytes.length});
}
await copyFile(path.join(root,oldCandidate,'supabase/config.toml'),path.join(root,candidate,'supabase/config.toml'));
const manifest={kind:'jentra-rpc-diagnostics-only-candidate',preparedAt:new Date().toISOString(),projectId:'xpdoufauvrbdmxgngetv',baselineRuntimeVersion:9,
 source:sources.length,paidFallback:false,authorizationChanged:false,databaseChanged:false,receiverChanged:false,schedulesActivated:false,sources};
const bytes=JSON.stringify(manifest,null,2)+'\n';await writeFile(path.join(root,candidate,'candidate.json'),bytes,{flag:'wx'});
const verification={kind:'prepared-rpc-diagnostics-candidate',observedAt:new Date().toISOString(),candidate,manifestSha256:hash(bytes),sourceInputs:sources.length,
 executableModules:sources.filter(s=>/\.(?:mjs|ts)$/.test(s.path)).length,workerTests:{passed:309,failed:0},denoCheckPassed:true,
 diagnostics:{fields:['event','rpc','stage','status','code','errorKind'],rpcNames:['get_ai_forecast_evidence','wave5_runtime_worker','wave5_edge_control'],logsCredentials:false,logsPayloads:false,automaticRetries:false},
 approvalRequiredForReopeningTest:true,deployed:false,trialRenewedAgain:false,requestResent:false,
 artifacts:await Promise.all(['workers/wave5/rpc_failure_diagnostics.test.mjs',base+'/worker-tests.log',base+'/deno-check-corrected.log'].map(async p=>({path:p,sha256:hash(await readFile(path.join(root,p)))})))};
await writeFile(path.join(root,base,'diagnostics-candidate.json'),JSON.stringify(verification,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(verification));
