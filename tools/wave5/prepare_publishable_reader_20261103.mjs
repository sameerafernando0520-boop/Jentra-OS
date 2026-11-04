import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const base='docs/verification/ai-integrations-test-20261103/',previous='build/wave5-rpc-diagnostics-20261103/complete-candidate/',candidate='build/wave5-publishable-reader-20261103/candidate/';
const hash=b=>createHash('sha256').update(b).digest('hex');
const bytesBefore=await readFile(previous+'candidate.json');
if(hash(bytesBefore)!=='f1caa27d3b7661b6689de174e8f8b11fc2793f4ef6cd67e353aeec2034e254fa')throw Error('V11_BASELINE_MANIFEST_CHANGED');
const old=JSON.parse(bytesBefore),changed=new Set(['workers/wave5/model_reader.mjs','workers/wave5/persistent_control.mjs']),sources=[];
for(const s of old.sources){
 if(path.isAbsolute(s.path)||s.path.split('/').includes('..'))throw Error('SOURCE_PATH_INVALID');
 const b=await readFile(s.path);if(!changed.has(s.path)&&hash(b)!==s.sha256)throw Error('UNRELATED_SOURCE_CHANGED');
 await mkdir(path.dirname(candidate+s.path),{recursive:true});await writeFile(candidate+s.path,b,{flag:'wx'});sources.push({path:s.path,sha256:hash(b),bytes:b.length});
}
await copyFile(previous+'supabase/config.toml',candidate+'supabase/config.toml');
const testLog=await readFile(base+'publishable-reader-worker-tests.log','utf8');if(!/pass 319/.test(testLog)||!/fail 0/.test(testLog))throw Error('PASSING_WORKER_TESTS_REQUIRED');
const manifest={kind:'jentra-publishable-caller-key-repair',preparedAt:new Date().toISOString(),projectId:'xpdoufauvrbdmxgngetv',baselineRuntimeVersion:11,expectedRuntimeVersion:12,changedPaths:[...changed],sources};
const bytes=JSON.stringify(manifest,null,2)+'\n';await writeFile(candidate+'candidate.json',bytes,{flag:'wx'});
const report={kind:'publishable-reader-repair-candidate',observedAt:new Date().toISOString(),candidate,manifestSha256:hash(bytes),sourceInputs:sources.length,executableModules:sources.filter(s=>/\.(mjs|ts)$/.test(s.path)).length,changedPaths:[...changed],workerTests:{passed:319,failed:0},normalDenoCheckPassed:true,deployed:false,
 rootCause:'Hosted SUPABASE_ANON_KEY is an opaque publishable key; the old reader routed it through privileged credential validation, which rejects that key kind before HTTP.',
 behavior:'Use a dedicated caller transport: public key in apikey, genuine caller token in Authorization. Preserve authenticated scope and expired-trial denials; leave privileged worker credential validation unchanged.',
 hostedObservation:'v11-hosted-diagnostic-event.json',liveReadOnlyDenial:'publishable-reader-live-expired-trial-denial.json',providerChanged:false,paidFallback:false,permissionsChanged:false,databaseChanged:false,receiverChanged:false,windowRenewed:false,realModelRequests:0,
 remainingApproval:'Deploy this exact V12 candidate, renew only Synthetic RT1 trial/runtime for 30 minutes, and make one controlled model attempt using the preserved invocation and usage IDs after fresh four-record absence checks. Keep five seats, plan, caps and read permissions; do not resend delivery.',
 artifacts:await Promise.all(['workers/wave5/model_reader_publishable.test.mjs',base+'publishable-reader-worker-tests.log',base+'publishable-reader-deno.log',base+'publishable-reader-live-expired-trial-denial.json',base+'v11-hosted-diagnostic-event.json'].map(async p=>({path:p,sha256:hash(await readFile(p))})))};
await writeFile(base+'publishable-reader-repair-candidate.json',JSON.stringify(report,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify(report));
