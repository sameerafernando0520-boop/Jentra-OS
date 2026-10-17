import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=new URL('../../../../',import.meta.url),folder=new URL('./',import.meta.url);
const read=async relative=>JSON.parse(await fs.readFile(new URL(relative,root),'utf8'));
const hash=x=>createHash('sha256').update(x).digest('hex');
async function bind(relative){const bytes=await fs.readFile(new URL(relative,root));return {path:relative,bytes:bytes.length,sha256:hash(bytes)};}
const base='docs/verification/wave5/seven-area-completion-20261016/';
const observed=await read(base+'root-readonly-result-a1.json');
assert.notEqual(observed.rawResult.isError,true);
const wrapper=JSON.parse(observed.rawResult.content.find(c=>c.type==='text').text).result;
const block=wrapper.match(/^<untrusted-data-[^>]+>\s*\n([\s\S]*?)\n<\/untrusted-data-[^>]+>/m);
assert.ok(block,'Actual result data block required');
const rows=JSON.parse(block[1]);assert.equal(rows.length,1);
const snapshot=rows[0].snapshot;
const dependency=await read('docs/verification/wave5/runtime-expiry-dependency-readonly-20261014-r5-a1.json');
assert.equal(snapshot.migrationCount,115);assert.equal(snapshot.apiFunctionCount,363);
assert.deepEqual(snapshot.guardFunctionBindings,dependency.snapshot.guardFunctionBindings);
assert.equal(snapshot.authority.nonWindowHash,dependency.snapshot.authority.nonWindowHash);
assert.equal(snapshot.scopes.nonWindowHash,dependency.snapshot.scopes.nonWindowHash);
assert.equal(snapshot.authority.unexpired,false);assert.equal(snapshot.scopes.unexpired,0);
assert.deepEqual(snapshot.ownJobs,dependency.snapshot.ownJobs);assert.equal(snapshot.ownJobs.length,3);
assert.ok(snapshot.ownJobs.every(job=>job.active===false));
assert.deepEqual(snapshot.ownTicks,{count:0,running:0});
assert.deepEqual(snapshot.global.finance,{lines:18,exports:0,journals:9,scenarios:0,publications:3,dateDecisions:3,dateProposals:3,processEvents:7,classifications:1});
for(const name of ['ticks','quotaPeriods','deliveryOutcomes','receiverReceipts'])assert.equal(snapshot.global[name],0);
assert.equal(snapshot.global.netResponseCount,24);assert.equal(snapshot.global.allKnownHandler404,true);
const advisorGroups={};
for(const type of ['security','performance']){
 const record=await read(base+'root-'+type+'-advisors-result-a1.json');assert.equal(record.result.status,'fulfilled');
 assert.notEqual(record.result.value.isError,true);
 advisorGroups[type]=JSON.parse(record.result.value.content.find(c=>c.type==='text').text).result.lints.map(lint=>({name:lint.name,level:lint.level,count:lint.count,remediation:lint.remediation}));
}
const files=['root-readonly-attempt-a1.json','root-readonly-result-a1.json','root-advisors-attempt-a1.json','root-security-advisors-result-a1.json','root-performance-advisors-result-a1.json'];
const report={kind:'independent-current-live-state-projection-verification',passed:true,verifiedAt:new Date().toISOString(),
 projectId:'xpdoufauvrbdmxgngetv',actualDatabaseObservedAt:snapshot.observedAt,sourceBindings:await Promise.all(files.map(f=>bind(base+f))),
 actualDatabaseReadCalls:1,actualAdvisorReadCalls:2,cumulativeConservativeCharge:137,originalPriorCharge:134,
 guardFunctionBindingsVerified:7,installedMigrationCount:115,installedApiFunctionCount:363,scopeAndAuthorityExpired:true,
 threeSchedulesRemainPaused:true,actualWorkerTicks:0,actualExports:0,actualScenarios:0,finance:snapshot.global.finance,
 advisorGroups,mutations:0,privateInputsRead:false,requirementsNewlyAccepted:0,
 proposedBudgetOnly:{actualPrior:137,ownerReadiness:1,renewalControl:3,priorAtExports:141,exportsOrdinary:24,exportsResolutionReserve:1,
  throughExports:166,healthMaximum:5,throughHealth:171,scheduleMaximum:3,totalMaximum:174,approved:false},
 limitation:'Current-state and advisor observations are read-only. They do not create actual renewal, native, contention, provider, load or production acceptance.'};
await fs.writeFile(new URL('current-state-verification-a1.json',folder),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({passed:true,observedAt:snapshot.observedAt,guardFunctions:7,actualCharge:137,advisorGroups})+'\n');
