import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';

const workspace=fileURLToPath(new URL('../../../',import.meta.url));
const folder='docs/verification/ai-integrations-20261031';
const probe='docs/verification/ai-integrations/2026-10-30T23-21-56-155Z-e73f5427-94b5-4fd7-9999-d4c953e1bb07';
const read=name=>fs.readFile(path.join(workspace,name));
const json=async name=>JSON.parse((await read(name)).toString('utf8').replace(/^\uFEFF/,''));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
async function filesUnder(name){
 const result=[];
 for(const entry of await fs.readdir(path.join(workspace,name),{withFileTypes:true})){
  const child=name+'/'+entry.name;
  if(entry.isDirectory())result.push(...await filesUnder(child));
  else if(entry.isFile())result.push(child);
 }
 return result.sort();
}
async function manifest(names){return Promise.all([...new Set(names)].sort().map(async name=>{
 const bytes=await read(name);return {path:name,bytes:bytes.length,sha256:hash(bytes)};
}));}

const workerLog=(await read(folder+'/worker-suite-isolated-final.log')).toString('utf8');
assert.match(workerLog,/\btests 287\b/);assert.match(workerLog,/\bpass 287\b/);assert.match(workerLog,/\bfail 0\b/);
assert.match(workerLog,/\bcancelled 0\b/);assert.match(workerLog,/\bskipped 0\b/);
const deno=(await read(folder+'/deno-check-final.log')).toString('utf8');
assert.equal((deno.match(/Check supabase\/functions\//g)??[]).length,2);assert.doesNotMatch(deno,/error:/i);
const postgres=await json(folder+'/accounting-postgres-result.json');
assert.equal(postgres.passed,9);assert.equal(postgres.hostedDatabaseQueried,false);
assert.equal(postgres.sqlSha256,hash(await read('tools/wave5/hosted_accounting_readonly.sql')));
const cli=await json(folder+'/accounting-cli-check.json');assert.equal(cli.passed,3);assert.equal(cli.exit,2);
const access=await json(folder+'/backend-access.json');assert.equal(access.state,'renewed-authentication-required');
const live=await json(probe+'/report.json');
assert.equal((await read(probe+'/report.sha256')).toString('utf8').trim(),hash(await read(probe+'/report.json')));
assert.equal(live.requests,4);assert.equal(live.credentialsSupplied,false);
assert.deepEqual(live.observations.map(o=>[o.status,o.code]),[
 [403,'WORKER_ACCESS_DENIED'],[403,'AUTH_REQUIRED'],[503,'MODEL_PROVIDER_UNAVAILABLE'],[403,'INTEGRATION_ACCESS_DENIED']]);
const journal=(await read(probe+'/requests.jsonl')).toString('utf8').trim().split('\n').map(JSON.parse);
assert.equal(journal.length,8);
for(let i=0;i<4;i++){
 assert.equal(journal[i*2].type,'request-intent');assert.equal(journal[i*2+1].type,'request-result');
 assert.equal(journal[i*2].endpointIndex,i);assert.equal(journal[i*2+1].endpointIndex,i);
 assert.equal(journal[i*2].credentialsSupplied,false);
}
const inputs=(await filesUnder('workers/wave5')).filter(n=>/\.(mjs|ts)$/.test(n));
inputs.push('supabase/functions/wave5-runtime/index.ts','supabase/functions/wave5-runtime/deno.json',
 'supabase/functions/wave5-receiver/index.ts','supabase/functions/wave5-receiver/deno.json',
 'tools/wave5/hosted_probe.mjs','tools/wave5/verify_hosted.mjs','tools/wave5/hosted_accounting.mjs',
 'tools/wave5/hosted_accounting_readonly.sql','tools/wave5/check_hosted_accounting.mjs');
const evidence=(await filesUnder(folder)).filter(n=>!n.endsWith('/verification.json'));
evidence.push(...await filesUnder(probe));
const report={kind:'jentra-ai-integrations-development-verification',recordedAt:new Date().toISOString(),
 clientDate:'2026-10-31',clientTimezone:'Asia/Colombo',baselineCommit:'678584047d7f4a5fd0e50192b2d3ea576f33b1c7',
 projectId:live.projectId,workerTests:{passed:287,failed:0,cancelled:0,skipped:0,normalProcessIsolation:true},
 isolatedPostgres:{passed:9,hostedDatabaseQueried:false},accountingCliSynthetic:{passed:3,expectedExit:2},
 denoEntrypoints:{checked:2,exitCode:0},backendAccess:access,
 hostedObservation:{path:probe+'/report.json',startedAt:live.startedAt,finishedAt:live.finishedAt,
  observations:live.observations.map(({endpoint,status,code,state})=>({endpoint,status,code,state}))},
 review:{standards:{rootReviewCompleted:true,rootFindings:0,independentVerdictComplete:false,
  reason:'Review agent hit usage limit after focused checks and before a final verdict.'},
  spec:{rootReviewCompleted:true,rootFindings:0,independentVerdictComplete:false,
   reason:'No completed independent Spec verdict was available at this publication.'}},
 gates:{hostedModelResponseVerified:false,hostedUsageAccountingVerified:false,externalDeliveryVerified:false,
  runtimeAuthorityVerified:false,installedSourceVerified:false,authenticatedHumanMfaVerified:false,
  ownerAcceptanceAwarded:false},
 operations:{workerDeployed:false,migrationInstalled:false,authorityRenewed:false,modelCalls:0,
  signedDeliveries:0,secretValuesPrinted:false,committed:false,pushed:false},
 currentSourceHashes:await manifest(inputs),evidence:await manifest(evidence),
 boundary:'Current local source hashes, controlled tests and four actual unsigned hosted responses. No authenticated model, hosted ledger, signed delivery, installed-source readback or current runtime authority is certified.'};
await fs.writeFile(path.join(workspace,folder,'verification.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({sourceFiles:report.currentSourceHashes.length,evidenceFiles:report.evidence.length,
 workerTests:287,isolatedPostgresChecks:9,denoEntrypoints:2,positiveHostedGates:false})+'\n');
