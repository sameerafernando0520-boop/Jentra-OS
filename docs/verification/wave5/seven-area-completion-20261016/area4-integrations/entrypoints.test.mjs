import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {Readable} from 'node:stream';
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {PROJECT,BUNDLE,RUNTIME,PLAN,GUARDS,JOBS,AUTHORITY_HASH,SCOPE_HASH,OUTSIDE_HASH,ISSUED,SCOPE_ISSUED,
 READ_SQL,BUDGET,schedulePlanBinding,validateWindow,validateRenewalTimeline,validateLockInventory,validateCallInventory,validatePreservedSources,buildResumeSql,validateSnapshot,
 createScheduleTransport,runScheduleResume,PRESERVED,exactFile,main as scheduleMain} from '../../../../../tools/wave5/resume_worker_schedules_20261015_r5_a1.mjs';
import {PLAN as HEALTH_PLAN,healthPlanBinding,readPublicFile,createHealthTransport,HEALTH_IMPORT_DEPENDENCIES,validateHealthImportInventory,main as healthMain} from '../../../../../tools/wave5/run_worker_v7_health_20261015_r5.mjs';
import {PREFLIGHT_SQL,buildDispatchSql,buildReadbackSql,SOURCE,CANDIDATE} from '../../../../../tools/wave5/probe_worker_v7_health_20261014_r5.mjs';

// Controlled fake records, clocks and transport streams. No private inputs,
// accounts, SQL execution, real sockets or persisted operation proof are used.
const digest='a'.repeat(64),hash=value=>createHash('sha256').update(value).digest('hex');
const instant=Date.parse('2026-10-16T00:10:00Z');
const window={notBefore:'2026-10-16T00:00:02Z',edgeExpiresAt:'2026-10-16T02:00:00Z',scopeExpiresAt:'2026-10-16T02:00:00Z',
 privateExpiresAt:'2026-10-16T02:00:00Z',expiresAt:'2026-10-16T02:00:00Z'};
const fingerprints=[...GUARDS].sort().map((signature,i)=>({signature,md5:String(i+1).repeat(32)}));
const tick={id:'10000000-0000-4000-8000-000000000001',kind:'health',state:'completed',tickSha256:digest,outcomeSha256:'b'.repeat(64)};
const plan={window,guardFingerprints:fingerprints,readinessTick:tick};
const binding=path=>({path,sha256:digest});
function timeline(){return {readback:{serverWindowAnchor:'2026-10-16T00:00:00.123456Z',appliedAt:'2026-10-16T00:00:02Z',
 observedAt:'2026-10-16T00:00:03Z',edge:{expiresAt:'2026-10-16T02:00:00.123456Z'}},
 human:{decidedAt:'2026-10-15T23:59:00Z',maximumWindowMs:7200000},metadata:{expiresAt:'2026-10-16T03:00:00Z'},
 before:{observedAt:'2026-10-16T00:00:00.123456Z'},after:{observedAt:'2026-10-16T00:00:03Z'},
 writeResponse:[{renewal_application:{runtimeId:RUNTIME,affectedRows:2,appliedAt:'2026-10-16T00:00:02Z',
 expiresAt:'2026-10-16T02:00:00.123456Z',applicationTimestampProvenance:'server-post-commit-observation'}}],window,now:instant};}
function state(active=false){return {observedAt:new Date(instant).toISOString(),timeZone:'UTC',migrationCount:115,apiFunctionCount:363,
 scopeAllowed:true,serviceRoleRpcGrants:true,completedOriginalExports:true,guardFingerprints:fingerprints,
 authority:{runtimeId:RUNTIME,enabled:true,nonWindowHash:AUTHORITY_HASH,jobIds:[4,5,6],issuedAt:ISSUED,expiresAt:window.edgeExpiresAt},
 scopes:{count:1,enabled:1,nonWindowHash:SCOPE_HASH,issuedMin:SCOPE_ISSUED,issuedMax:SCOPE_ISSUED,expiresMin:window.scopeExpiresAt,expiresMax:window.scopeExpiresAt},
 ownJobs:JOBS.map(job=>({...job,active})),outsideJobHash:OUTSIDE_HASH,recordedCronRuns:24,ticks:1,tickOutcomes:1,
 readinessTicks:[{...tick,success:true,summary:{count:1,states:['collected']}}],
 quotaPeriods:0,deliveryOutcomes:0,receiverReceipts:0,modelInvocations:0,modelOutcomes:0,usageEvents:0};}
function healthReview(){return {kind:'independent-exact-v7-health-operation-review',technicalDecision:'approve',executionPermitted:true,
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:RUNTIME,candidateBundleSha256:CANDIDATE,deployedVersion:7,
 maximumManagementAttempts:5,maximumHealthInvocations:1,historicalScheduleRequests:24,maximumScheduleRequests:4320,automaticRetries:0,
 exportsCompletedFirst:true,jobsRemainPaused:true,clientScheduleSecretRetrieved:false,controlledFixture:false,
 humanRenewalDecisionBinding:binding('controlled/human.json'),actualRenewalReadbackBinding:binding('controlled/renewal.json'),
 completedExportsBinding:binding('controlled/exports.json'),sourceBinding:binding(SOURCE),
 privateAdapterBinding:binding('scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1'),
 serverWindowAnchor:window.notBefore,renewedExpiry:window.edgeExpiresAt,authorizationExpiresAt:window.expiresAt,guardFingerprints:fingerprints};}
const output=()=>({write(){}});
const untouchedInput=()=>({[Symbol.asyncIterator](){assert.fail('stdin must not be read');}});
test('both launchers require generatedPlan and allow only the matching optional alias',()=>{
 for(const [fn,path] of [[healthPlanBinding,HEALTH_PLAN],[schedulePlanBinding,PLAN]]){
  const generatedPlan=binding(path);assert.deepEqual(fn({generatedPlan}),generatedPlan);
  assert.deepEqual(fn({generatedPlan,planBinding:generatedPlan}),generatedPlan);
  assert.throws(()=>fn({planBinding:generatedPlan}));assert.throws(()=>fn({generatedPlan,planBinding:{...generatedPlan,sha256:'f'.repeat(64)}}));
 }
});
test('both public readers accept the real pinned 1.37 MB predecessor review without private access',async()=>{
 const item=PRESERVED.find(x=>x.path==='docs/verification/wave5/complete-app-runtime-review-20261010-r5.json');
 assert.ok(item);const a=await exactFile(item.path,item.sha256),b=await readPublicFile(item);
 assert.ok(a.length>1048576&&a.length<=8388608);assert.deepEqual(a,b);assert.equal(hash(a),item.sha256);
});
test('exact source/public lock arrays cover the union once, reject omissions and conflicting aliases',()=>{
 const source=binding('tools/wave5/control.mjs'),pub=binding('docs/verification/wave5/control.json');
 assert.deepEqual(validateLockInventory({sourceBindings:[source],publicBindings:[pub]},[source,pub]),[source,pub]);
 assert.throws(()=>validateLockInventory({sourceBindings:[source],publicBindings:[]},[source,pub]));
 assert.throws(()=>validateLockInventory({sourceBindings:[source],publicBindings:[source,pub]},[source,pub]));
 assert.throws(()=>validateLockInventory({sourceBindings:[{...source,sha256:'f'.repeat(64)}],publicBindings:[pub]},[source,pub]));
});
test('health lock inventory covers the exact complete static import graph including a7 dependencies',async()=>{
 const seen=new Set();async function visit(file){if(seen.has(file))return;seen.add(file);const text=await fs.readFile(file,'utf8');
  for(const m of text.matchAll(/(?:from\s*|import\s*)['"](\.\.?\/[^'"]+)['"]/g))await visit(path.posix.normalize(path.posix.join(path.posix.dirname(file),m[1])));}
 await visit('tools/wave5/run_worker_v7_health_20261015_r5.mjs');assert.deepEqual([...seen].sort(),[...HEALTH_IMPORT_DEPENDENCIES].sort());
 const sourceBindings=HEALTH_IMPORT_DEPENDENCIES.map(binding);assert.equal(validateHealthImportInventory({sourceBindings}),true);
 assert.throws(()=>validateHealthImportInventory({sourceBindings:sourceBindings.slice(1)}));
});
test('current call inventory binds actual137 and proposed174 without granting approval',()=>{
 const doc={kind:'unapproved-bounded-seven-area-continuation-call-inventory',projectId:PROJECT,runtimeId:RUNTIME,sourceOnly:true,executionPermitted:false,
 approvalRecorded:false,actualBaseline:{chargedCalls:137},arithmetic:{actualPrior:137,ownerRefresh:1,renewal:3,priorAtExports:141,exportsOrdinary:24,
 exportsResolutionReserve:1,throughExportsMaximum:166,healthMaximum:5,throughHealthMaximum:171,schedulerMaximum:3,overallMaximum:174,maximumFutureAttempts:37},
 unchangedWorkerBounds:{knownHistoricalRequests:24,maximumWorkerRequests:4320}};
 assert.equal(validateCallInventory(doc),doc);assert.throws(()=>validateCallInventory({...doc,executionPermitted:true}));
 assert.throws(()=>validateCallInventory({...doc,actualBaseline:{chargedCalls:134}}));
});
test('deployed archive validates old immutable39 files while separately preserving current product candidate',async()=>{
 const result=await validatePreservedSources();assert.equal(result.passed,true);assert.equal(result.deployedArchiveBindings,39);
 assert.equal(result.currentProductCandidate.sha256,'7776efd148c1257c4cd78eba3345b13fe19406012cd4b58f7b0a6769ef77a72e');
 assert.equal(result.candidateDiffersFromDeployed,true);assert.equal(result.actualResumeAllowed,false);
});
test('raw preflight anchor differs from genuine post-COMMIT application time',()=>assert.equal(validateRenewalTimeline(timeline()),true));
test('renewal keeps microsecond anchor and rejects using appliedAt to calculate expiry',()=>{
 const v=timeline();v.readback.edge.expiresAt='2026-10-16T02:00:02Z';v.writeResponse[0].renewal_application.expiresAt=v.readback.edge.expiresAt;
 assert.throws(()=>validateRenewalTimeline(v),/EXACT_PREFLIGHT_ANCHORED_EXPIRY/);
});
test('renewal rejects timestamp fabrication, missing raw write, and excessive application delay',()=>{
 for(const change of [v=>v.writeResponse=[],v=>v.writeResponse[0].renewal_application.applicationTimestampProvenance='client-time',
  v=>v.writeResponse[0].renewal_application.appliedAt='2026-10-16T00:00:01Z',v=>v.before.observedAt=v.readback.appliedAt,
  v=>v.readback.appliedAt='2026-10-16T00:00:46Z',v=>v.human.maximumWindowMs=1.5]){
  const v=timeline();change(v);assert.throws(()=>validateRenewalTimeline(v));
 }
});
test('owner expiry truncates the server-anchor window',()=>{
 const v=timeline();v.metadata.expiresAt='2026-10-16T01:00:00Z';v.readback.edge.expiresAt=v.metadata.expiresAt;
 v.writeResponse[0].renewal_application.expiresAt=v.metadata.expiresAt;assert.equal(validateRenewalTimeline(v),true);
});
test('renewed window can cross UTC midnight but cannot exceed scope seven-day maximum',()=>{
 assert.equal(validateWindow({...window,notBefore:'2026-10-15T23:50:00Z',edgeExpiresAt:'2026-10-16T01:00:00Z',scopeExpiresAt:'2026-10-16T01:00:00Z',expiresAt:'2026-10-16T01:00:00Z'}).notBefore,'2026-10-15T23:50:00Z');
 assert.throws(()=>validateWindow({...window,notBefore:'2026-10-20T08:00:00Z',edgeExpiresAt:'2026-10-20T09:00:00Z',scopeExpiresAt:'2026-10-20T09:00:00Z',privateExpiresAt:'2026-10-20T09:00:00Z',expiresAt:'2026-10-20T09:00:00Z'}));
});
test('scheduler SQL only enables the three fixed jobs after all server-side guards',()=>{
 const sql=buildResumeSql(fingerprints,tick,window);assert.equal((sql.match(/cron\.alter_job/g)||[]).length,1);
 assert.match(sql,/ARRAY\[4,5,6\]/);assert.match(sql,/FOR UPDATE/);assert.match(sql,/EXACT_ONE_BOUND_HEALTH_READINESS_TICK_REQUIRED/);
 assert.match(sql,/clock_timestamp\(\).*2026-10-16/);assert.doesNotMatch(sql,/UPDATE intelligence_control\./);
 assert.throws(()=>buildResumeSql(fingerprints,tick,{...window,notBefore:"2026-10-16T00:00:00Z';DROP TABLE x;--"}));
});
test('snapshot requires both renewed rows, paused state and one health tick without deliveries',()=>{
 assert.equal(validateSnapshot(state(),{plan,now:instant}).ticks,1);
 for(const change of [v=>v.deliveryOutcomes=1,v=>v.authority.expiresAt='2026-10-14T09:57:07Z',v=>v.scopes.count=2,
  v=>v.ownJobs[0].active=true,v=>v.readinessTicks[0].tickSha256='f'.repeat(64),v=>v.recordedCronRuns=25]){
  const v=state();change(v);assert.throws(()=>validateSnapshot(v,{plan,now:instant}));
 }
});
test('scheduler five-key preflight never consumes stdin or dispatches',async()=>{
 const result=await scheduleMain(['--preflight',digest],{stdin:untouchedInput(),stdout:output(),now:()=>instant,
 publicGate:async()=>({plan,planSha256:digest})});
 assert.deepEqual(result,{passed:true,networkCalls:0,privateInputsRead:false,planSha256:digest,finalReviewSha256:digest});
});
test('health five-key preflight never consumes stdin or dispatches',async()=>{
 const proof={passed:true,networkCalls:0,privateInputsRead:false,planSha256:digest,finalReviewSha256:digest};
 assert.deepEqual(await healthMain(['--preflight',digest],{stdin:untouchedInput(),stdout:output(),preflight:async()=>({publicResult:proof})}),proof);
});
test('failed public gates stop both execute paths before private stdin',async()=>{
 for(const fn of [scheduleMain,healthMain])await assert.rejects(fn(['--execute',digest],{stdin:untouchedInput(),stdout:output(),
 publicGate:async()=>{throw Error('controlled public stop');},preflight:async()=>{throw Error('controlled public stop');}}),/controlled public stop/);
});
test('scheduler public gate repeats after input before any intent or transport',async()=>{
 let calls=0;await assert.rejects(scheduleMain(['--execute',digest],{stdin:Readable.from([JSON.stringify({projectId:PROJECT,bundleSha256:BUNDLE,ownerToken:'CONTROLLED_FAKE'})]),stdout:output(),now:()=>instant,
 publicGate:async()=>{if(++calls===2)throw Error('controlled changed binding');return {plan,planSha256:digest};},
 run:()=>assert.fail('must not run'),requestFactory:()=>assert.fail('must not open network')}),/controlled changed binding/);assert.equal(calls,2);
});
test('scheduler management input rejects actor/runtime-seal fields',async()=>{
 await assert.rejects(scheduleMain(['--execute',digest],{stdin:Readable.from([JSON.stringify({projectId:PROJECT,bundleSha256:BUNDLE,ownerToken:'CONTROLLED_FAKE',runtimeSeal:'never-read'})]),stdout:output(),now:()=>instant,
 publicGate:async()=>({plan,planSha256:digest}),run:()=>assert.fail('must not run')}),/EXACT_MANAGEMENT_ONLY_INPUT/);
});
test('health private input is bounded by UTF-8 bytes rather than characters',async()=>{
 await assert.rejects(healthMain(['--execute',digest],{stdin:Readable.from(['é'.repeat(4097)]),stdout:output(),
  preflight:async()=>({review:healthReview(),plan:{}}),run:()=>assert.fail('must not run')}),/PRIVATE_HEALTH_INPUT_LIMIT/);
});
test('scheduler private input has a bounded timeout',async()=>{
 const stdin={async *[Symbol.asyncIterator](){await new Promise(()=>{});},destroy(){}};
 await assert.rejects(scheduleMain(['--execute',digest],{stdin,stdout:output(),now:()=>instant,stdinTimeoutMs:5,
 publicGate:async()=>({plan,planSha256:digest})}),/PRIVATE_INPUT_TIMEOUT/);
});
function fakeRequestFactory(responses,log){return (url,options,callback)=>{
 const req=new EventEmitter();req.destroy=()=>{};req.end=body=>{log.push({url,options,body});const res=new EventEmitter();res.statusCode=200;callback(res);
  queueMicrotask(()=>{res.emit('data',Buffer.from(JSON.stringify(responses.shift())));res.emit('end');});};
 queueMicrotask(()=>{const socket=new EventEmitter();socket.encrypted=true;socket.authorized=true;req.emit('socket',socket);});return req;};}
test('scheduler transport enforces read/write/read and stops repeated mutation',async()=>{
 const log=[],writeSql=buildResumeSql(fingerprints,tick,window),transport=createScheduleTransport('CONTROLLED_FAKE',{writeSql,window,now:()=>instant,requestFactory:fakeRequestFactory([[],[],[]],log)});
 await assert.rejects(transport(writeSql,false),/EXACT_ORDERED/);await transport(READ_SQL,true);await transport(writeSql,false);
 await assert.rejects(transport(writeSql,false),/EXACT_ORDERED/);await transport(READ_SQL,true);
 await assert.rejects(transport(READ_SQL,true),/THREE_SCHEDULE/);assert.equal(log.length,3);assert.ok(log.every(x=>x.options.rejectUnauthorized===true));
});
test('health transport permits one dispatch and binds all readbacks to returned request ID',async()=>{
 const review=healthReview(),log=[],transport=createHealthTransport('CONTROLLED_FAKE',{review,now:()=>instant,
 requestFactory:fakeRequestFactory([[],[{requestId:25,dispatchedAt:new Date(instant).toISOString()}],[]],log)});
 await transport({kind:'preflight',query:PREFLIGHT_SQL,readOnly:true,deadline:instant+1000});
 await transport({kind:'dispatch',query:buildDispatchSql(review),readOnly:false,deadline:instant+1000});
 await assert.rejects(transport({kind:'dispatch',query:buildDispatchSql(review),readOnly:false,deadline:instant+1000}),/EXACT_ORDERED/);
 await assert.rejects(transport({kind:'readback',query:buildReadbackSql(26),readOnly:true,deadline:instant+1000}),/EXACT_ORDERED/);
 await transport({kind:'readback',query:buildReadbackSql(25),readOnly:true,deadline:instant+1000});assert.equal(log.length,3);
});
function schedulePorts({missing,uncertain=false,gateFailure=0}={}){
 const calls=[],writes=[];let gates=0;return {plan,calls,writes,now:()=>instant,
 validatePublicGate:async()=>{if(++gates===gateFailure)throw Error('controlled gate drift');},
 once:async value=>{writes.push({name:'once',value});return missing==='once'?null:binding('controlled/once');},
 persist:async(name,value)=>{writes.push({name,value});return name===missing?null:binding('controlled/'+name);},
 transport:async(sql,readOnly)=>{calls.push({sql,readOnly});if(!readOnly&&uncertain)throw Error('controlled uncertain write');
 return {status:200,raw:Buffer.from(JSON.stringify(readOnly?[{snapshot:state(calls.length===3)}]:[]))};}};
}
test('scheduler controller completes only with actual enabled readback and preserves all call accounting',async()=>{
 const p=schedulePorts(),result=await runScheduleResume(p);assert.equal(result.managementAttempts,3);assert.equal(result.maximumCumulativeManagementBound,174);
 assert.equal(result.enabledStateConfirmedByReadback,true);assert.equal(result.actualDelivery,false);assert.deepEqual(p.calls.map(x=>x.readOnly),[true,false,true]);assert.deepEqual(result.budget,BUDGET);
});
test('scheduler lost write response causes one readback and no replay',async()=>{
 const p=schedulePorts({uncertain:true}),result=await runScheduleResume(p);assert.equal(p.calls.length,3);assert.equal(p.calls.filter(x=>!x.readOnly).length,1);
 assert.equal(result.writeResponseUncertain,'SCHEDULE_WRITE_OUTCOME_UNCERTAIN');
});
test('missing durable acknowledgement prevents dispatch and cannot claim success',async()=>{
 for(const missing of ['once','01-write-intent.json','02-write-attempt.json']){
  const p=schedulePorts({missing});await assert.rejects(runScheduleResume(p));assert.equal(p.calls.filter(x=>!x.readOnly).length,0);
  assert.equal(p.writes.some(x=>x.name==='99-result.json'),false);
 }
});
test('public gate drift before write prevents schedule mutation',async()=>{
 const p=schedulePorts({gateFailure:2});await assert.rejects(runScheduleResume(p),/controlled gate drift/);assert.equal(p.calls.length,1);
});
test('expired renewed window stops before any durable intent or network',async()=>{
 const p=schedulePorts();p.now=()=>Date.parse(window.expiresAt);await assert.rejects(runScheduleResume(p),/EXPIRED/);assert.equal(p.writes.length,0);assert.equal(p.calls.length,0);
});
