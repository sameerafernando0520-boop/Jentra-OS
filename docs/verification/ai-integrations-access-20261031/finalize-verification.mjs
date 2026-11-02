import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../../../',import.meta.url));
const folder='docs/verification/ai-integrations-access-20261031';
const probe='docs/verification/ai-integrations/2026-10-31T13-07-56-047Z-e55d0468-989e-4b0f-a576-185b2d558dbf';
const read=p=>fs.readFile(path.join(root,p));
const json=async p=>JSON.parse((await read(p)).toString('utf8').replace(/^\uFEFF/,''));
const sha=b=>createHash('sha256').update(b).digest('hex');
const old=await json('docs/verification/ai-integrations-20261031/verification.json');
const metadata=await json(folder+'/hosted-project-metadata-refresh.json');
const preflight=await json(folder+'/hosted-preflight.json');
const snapshot=await json(folder+'/hosted-accounting-snapshot.json');
const assessment=await json(folder+'/hosted-accounting-assessment.json');
const transaction=await json(folder+'/editor-transaction-result.json');
const accounting=await json(folder+'/accounting-postgres-after-wrapper-fix.json');
const comparison=await json(folder+'/deployed-source-comparison.json');
const http=await json(probe+'/report.json');
assert.equal(metadata.projectId,'xpdoufauvrbdmxgngetv');assert.equal(metadata.status,'ACTIVE_HEALTHY');
assert.equal(metadata.savedCliAuthenticationVerified,true);assert.equal(metadata.modelSecretPresent,false);
assert.equal(snapshot.projectId,metadata.projectId);assert.equal(snapshot.authorityActive,false);
assert.equal(snapshot.models.length,0);assert.equal(snapshot.quotas.length,0);
assert.equal(snapshot.deliveries.length,1);assert.equal(snapshot.deliveries[0].state,'retry');
assert.equal(snapshot.deliveries[0].receiptPresent,false);assert.equal(assessment.ledgerReconciled,false);
assert.deepEqual(assessment.failures,['RUNTIME_AUTHORITY_INACTIVE','DELIVERY_OUTCOME_UNRESOLVED',
 'NONEMPTY_MODEL_USAGE_REQUIRED','NONEMPTY_QUOTA_REQUIRED']);
const sqlSha=sha(await read('tools/wave5/hosted_accounting_readonly.sql'));
assert.equal(transaction.passed,4);assert.equal(accounting.passed,9);
assert.equal(transaction.sqlSha256,sqlSha);assert.equal(accounting.sqlSha256,sqlSha);
assert.equal(comparison.returnedModules,25);assert.equal(comparison.exactByteMatches,23);
for(const row of comparison.rows){
 assert.equal(sha(await read(row.downloadedPath)),row.downloadedSha256);
 if(row.localSha256!==null)assert.equal(sha(await read(row.localPath)),row.localSha256);
}
const inputHashes=[];
for(const row of old.currentSourceHashes){
 const bytes=await read(row.path),currentSha=sha(bytes);
 inputHashes.push({path:row.path,bytes:bytes.length,sha256:currentSha,changedSinceInitialCheck:currentSha!==row.sha256});
}
assert.deepEqual(inputHashes.filter(row=>row.changedSinceInitialCheck).map(row=>row.path),['tools/wave5/hosted_accounting_readonly.sql']);
assert.equal(sha(await read(probe+'/report.json')),(await read(probe+'/report.sha256')).toString('utf8').trim());
assert.deepEqual(http.observations.map(row=>[row.status,row.code]),[
 [403,'WORKER_ACCESS_DENIED'],[403,'AUTH_REQUIRED'],[503,'MODEL_PROVIDER_UNAVAILABLE'],[403,'INTEGRATION_ACCESS_DENIED']]);
async function walk(directory){
 const result=[];
 for(const entry of await fs.readdir(path.join(root,directory),{withFileTypes:true})){
  const file=directory+'/'+entry.name;
  if(entry.isDirectory())result.push(...await walk(file));else if(entry.isFile())result.push(file);
 }
 return result;
}
const evidence=[];
for(const file of [...await walk(folder),...await walk(probe)].sort()){
 if(file.endsWith('/current-verification.json'))continue;
 const bytes=await read(file);evidence.push({path:file,bytes:bytes.length,sha256:sha(bytes)});
}
const report={kind:'jentra-hosted-ai-integrations-current-checkpoint',recordedAt:new Date().toISOString(),
 projectId:metadata.projectId,clientDate:'2026-10-31',clientTimezone:'Asia/Colombo',
 access:{savedCliLoginRestored:true,authenticatedBrowser:true,staleProcessOverrideOmitted:true,
  globalEnvironmentChanged:false,secretValuesRecorded:false},
 catalogCheckpoint:{observedAt:preflight.result.observedAt,migrations:preflight.result.migrationCount,
  apiFunctions:preflight.result.apiFunctionCount},
 databaseObservation:{observedAt:snapshot.observedAt,readOnlyQueryExecuted:true,models:0,quotaPeriods:0,
  retryDeliveries:1,acknowledgedDeliveries:0,runtimeAuthorityActive:false,ledgerReconciled:false,
  failures:assessment.failures},
 deployedSource:{downloadedModules:25,exactCurrentSourceMatches:23,
  mismatches:comparison.rows.filter(row=>!row.exactByteMatch).map(row=>row.localPath),
  currentSourceFullyInstalled:false},
 localVerification:{workerTestsUnchangedSince287Pass:true,accountingChecks:9,transactionRegressions:4,
  denoEntrypointsUnchangedSince2Pass:true,sqlSha256:sqlSha},
 latestHttpProbe:{path:probe+'/report.json',observedAt:http.finishedAt,
  observations:http.observations.map(({endpoint,status,code,state})=>({endpoint,status,code,state}))},
 blockingInput:{requiredSecret:'W5_OPENAI_API_KEY',missingAt:metadata.observedAt,
  preparedPage:'https://supabase.com/dashboard/project/xpdoufauvrbdmxgngetv/functions/secrets',
  secretSavedByAgent:false},
 operations:{cliAuthenticationRefreshed:true,migrationInstalled:false,workerDeployed:false,
  runtimeAuthorityRenewed:false,modelCalls:0,signedDeliveries:0,deliveryReplayed:false,committed:false,pushed:false},
 gates:{actualHostedModelResponse:false,actualTrustedModelUsage:false,externalDelivery:false,
  businessUserMfaAcceptance:false,ownerSignoff:false},
 currentSourceHashes:inputHashes,evidence,
 boundary:'Actual CLI metadata, deployed source downloads and read-only SQL Editor observations. Missing provider configuration, inactive runtime and unresolved original delivery prevent positive model/usage/delivery acceptance.'};
await fs.writeFile(path.join(root,folder,'current-verification.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify({projectConfirmed:true,sourceInputs:inputHashes.length,evidenceFiles:evidence.length,
 hostedAccountingObserved:true,modelSecretMissing:true,positiveModelAndDeliveryGates:false}));
