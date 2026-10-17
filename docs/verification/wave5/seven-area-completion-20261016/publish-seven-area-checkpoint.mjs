import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
const root=new URL('../../../../',import.meta.url),dir=new URL('./',import.meta.url);
const hash=x=>createHash('sha256').update(x).digest('hex');
const read=async p=>JSON.parse(await fs.readFile(new URL(p,root),'utf8'));
async function binding(p){const b=await fs.readFile(new URL(p,root));return {path:p,bytes:b.length,sha256:hash(b)};}
const base='docs/verification/wave5/seven-area-completion-20261016/';
const matrixPath='docs/verification/wave5/task3-acceptance-20261013/delegated-technical-acceptance-matrix.json';
const matrix=await read(matrixPath),prerequisites=await read('docs/verification/wave5/task3-acceptance-20261013/open-requirement-prerequisites.json');
const groups=new Map(prerequisites.groups.map(g=>[g.id,g]));
const definitions=[
 ['area1_windows','Windows workflows',['G8'],'area1-windows',['source-and-historical-evidence-verification.json']],
 ['area2_finance','Analytics and finance',['G2'],'area2-finance',['area2-report.json']],
 ['area3_permissions_ai','Permissions, AI and operator access',['G1','G4','G7'],'area3-permissions-ai',['completion-report.json']],
 ['area4_integrations','Exports and integrations',['G3','G5'],'area4-integrations',['completion-report.json','source-proof.json']],
 ['area5_subscriptions','Subscriptions, trusted usage and quotas',['G6'],'area5-subscriptions',['sourceproof.json']],
 ['area6_load','Concurrency, limits and load',['G9'],'area6-load',['completion-report.json','source-proof.json']],
 ['area7_quality_acceptance','Quality, ownership and release',['G0','G10'],'area7-quality',['completion-report.json','quality-review.json']],
];
assert.equal(definitions.length,7);
const areas=[];
for(const [agent,area,groupIds,folder,candidates]of definitions){
 const rowIds=groupIds.flatMap(id=>{assert.ok(groups.has(id));return groups.get(id).rowIds;});
 let report=null;
 for(const file of candidates){try{report=await binding(base+folder+'/'+file);break;}catch(e){if(e.code!=='ENOENT')throw e;}}
 areas.push({agent:'/root/'+agent,area,folder:base+folder,assignedRows:rowIds.length,rowIds,
  report,sourceReviewPublished:report!==null,fullAreaAccepted:false,
  status:report?'Available source and evidence review published; complete acceptance still requires remaining actual observations.':'Source work and controlled verification in progress.'});
}
const assigned=areas.flatMap(a=>a.rowIds).sort(),open=matrix.rows.filter(r=>!r.accepted).map(r=>r.id).sort();
assert.equal(new Set(assigned).size,86);assert.deepEqual(assigned,open);assert.equal(matrix.totalAcceptedCount,23);
assert.equal(matrix.requirementCount,109);assert.equal(matrix.remainingOpenCount,86);
const current=await read(base+'current-state-verification-a1.json');assert.equal(current.cumulativeConservativeCharge,137);
const report={kind:'seven-agent-development-and-acceptance-checkpoint',recordedAt:new Date().toISOString(),projectId:'xpdoufauvrbdmxgngetv',
 requestedAgentCount:7,assignedAgentCount:7,maximumSimultaneousSubagents:3,areaRequirementCoverage:86,duplicateOrMissingAssignments:0,
 requirementCount:109,acceptedCount:23,originalHumanAccepted:3,delegatedTechnicalAccepted:20,openCount:86,newAcceptanceDecisions:0,
 wholeSystemComplete:false,productionReady:false,sourceWorkStillInProgress:areas.some(a=>!a.sourceReviewPublished),areas,
 currentActualDatabaseObservation:current.actualDatabaseObservedAt,cumulativeChargedCalls:137,currentSourceOnlyMaximumProposal:174,
 databaseWritesThisContinuation:0,privateCredentialsRead:false,actualTargetScaleLoad:false,actualWindowsAcceptance:false,
 currentInstalledMigrationCount:115,currentInstalledApiFunctionCount:363,
 inputBindings:[await binding(matrixPath),await binding(base+'current-state-verification-a1.json'),await binding(base+'continuation-call-inventory-a1.json')],
 remainingExternalGates:['An isolated Windows account/package/profile and private authenticated Connected session.',
  'A reviewed actual runtime renewal and completed export/health/worker evidence through genuine authorized sessions.',
  'Private PostgreSQL transport, genuine session capacity and all seven committed races plus the measured 500-company/2000-session workload.',
  'Genuine source manifests, historical/cohort/cash-scenario evidence, provider usage and distinct MFA/operator observations.',
  'Separate staging/production, migration rehearsal, isolated restore, alert delivery, accessibility, signed distribution and pilot evidence.'],
 limitations:['Seven agent assignments and passing controlled tests do not create acceptance for incomplete full statements.',
  'The current live state is a dated read-only observation; authority expiry was not extended and the 174-call continuation proposal is not approved or executed.']};
const name=process.argv[2];assert.match(name??'',/^[a-z0-9-]+\.json$/);
await fs.writeFile(new URL(name,dir),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
process.stdout.write(JSON.stringify({path:base+name,areas:areas.map(a=>({area:a.area,rows:a.assignedRows,reviewPublished:a.sourceReviewPublished})),accepted:23,open:86,wholeSystemComplete:false})+'\n');
