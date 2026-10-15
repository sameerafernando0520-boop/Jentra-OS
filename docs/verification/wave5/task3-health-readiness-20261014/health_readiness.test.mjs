import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {PROJECT,RUNTIME,BUNDLE,CANDIDATE,SOURCE,GUARDS,JOBS,EFFECT_NAMES,PREFLIGHT_SQL,
  validateReview,validateGuardFingerprints,buildDispatchSql,buildReadbackSql,validateState,
  validateCompletedReadback,runHealthReadiness} from '../../../../tools/wave5/probe_worker_v7_health_20261014_r5.mjs';

// Synthetic public records and injected ports only. No sockets, SQL execution,
// credentials, accounts, SDK, private files or real authentication are used.
const hash=value=>createHash('sha256').update(value).digest('hex');
const instant=Date.parse('2026-10-15T00:10:00.000Z');
const binding=path=>({path,sha256:'a'.repeat(64)});
const effects=(ticks=0,outcomes=0)=>Object.fromEntries(EFFECT_NAMES.map(name=>[name,name==='ticks'?ticks:name==='outcomes'?outcomes:0]));
function review(){return {kind:'independent-exact-v7-health-operation-review',technicalDecision:'approve',executionPermitted:true,
  projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:RUNTIME,candidateBundleSha256:CANDIDATE,deployedVersion:7,
  maximumManagementAttempts:5,maximumHealthInvocations:1,historicalScheduleRequests:24,maximumScheduleRequests:4320,
  automaticRetries:0,exportsCompletedFirst:true,jobsRemainPaused:true,clientScheduleSecretRetrieved:false,controlledFixture:false,
  humanRenewalDecisionBinding:binding('controlled/human.json'),actualRenewalReadbackBinding:binding('controlled/renewal.json'),
  completedExportsBinding:binding('controlled/exports.json'),sourceBinding:binding(SOURCE),
  privateAdapterBinding:binding('scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1'),
  serverWindowAnchor:'2026-10-15T00:00:00.000Z',renewedExpiry:'2026-10-15T02:00:00.000Z',
  authorizationExpiresAt:'2026-10-15T01:59:00.000Z',
  guardFingerprints:GUARDS.map((signature,index)=>({signature,md5:String(index+1).repeat(32)}))};}
function state(now=instant,completed=false){return {observedAt:new Date(now).toISOString(),timeZone:'UTC',migrationCount:115,apiFunctionCount:363,
  guardFingerprints:review().guardFingerprints,scopeAllowed:true,completedExports:true,
  authority:{issuedAt:'2026-10-13T09:57:07.481942Z',expiresAt:review().renewedExpiry,enabled:true,jobIds:[4,5,6],
    nonWindowHash:'77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139'},
  scopes:{count:1,enabled:1,issuedMin:'2026-10-13T08:13:04.144135Z',issuedMax:'2026-10-13T08:13:04.144135Z',
    expiresMin:review().renewedExpiry,expiresMax:review().renewedExpiry,
    nonWindowHash:'3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387'},
  ownJobs:structuredClone(JOBS),outsideJobHash:'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
  effects:effects(completed?1:0,completed?1:0)};}
function readback(now=instant,completed=true){
  const content=JSON.stringify({state:'completed',count:1,states:['collected']});
  return {...state(now,completed),http:completed?{id:25,status:200,timedOut:false,content,responseBytes:Buffer.byteLength(content),
    responseSha256:hash(content),serverRequestId:'10000000-0000-4000-8000-000000000001'}:null,
    ticks:completed?[{id:'20000000-0000-4000-8000-000000000001',kind:'health',state:'completed',startedAt:new Date(instant).toISOString(),
      tickSha256:'b'.repeat(64),outcomeSha256:'c'.repeat(64),success:true,summary:{count:1,states:['collected']},recordedAt:new Date(now).toISOString(),
      tickRow:{runtime_id:RUNTIME,id:'20000000-0000-4000-8000-000000000001',kind:'health',state:'completed',
        started_at:new Date(instant).toISOString(),lease_until:new Date(instant+90000).toISOString()},
      outcomeRow:{runtime_id:RUNTIME,id:'20000000-0000-4000-8000-000000000001',success:true,summary:{count:1,states:['collected']},recorded_at:new Date(now).toISOString()}}]:[]};
}
function ports({pending=0,brokenDispatch=false,missingReceipt,badPreflight,changedAfter}={}){
  let clock=instant,polls=0;const calls=[],writes=[],waits=[];
  return {review:review(),calls,writes,waits,now:()=>clock,
    once:async value=>{writes.push({file:'once',value});return missingReceipt==='once'?null:binding('controlled/once');},
    persist:async(file,value)=>{writes.push({file,value});return file===missingReceipt?null:binding(file);},
    wait:async(ms,options)=>{assert.equal(options.signal.aborted,false);waits.push(ms);clock+=ms;},
    transport:async request=>{
      calls.push(request);assert.equal(request.signal.aborted,false);
      assert.ok(request.deadline>clock);assert.ok(request.deadline<=clock+15000);
      if(request.kind==='preflight')return {status:200,rows:[{snapshot:badPreflight??state(clock)}]};
      if(request.kind==='dispatch'){
        if(brokenDispatch)throw Error('CONTROLLED_LOST_DISPATCH_RESPONSE');
        return {status:200,rows:[{requestId:25,dispatchedAt:new Date(clock).toISOString()}]};
      }
      return {status:200,rows:[{snapshot:changedAfter??readback(clock,polls++>=pending)}]};
    }};
}
const readArgs={requestId:25,dispatchedAt:new Date(instant).toISOString(),now:instant};

test('review requires a renewed bounded window and all actual evidence bindings',()=>{
  assert.equal(validateReview(review(),instant).expiry,Date.parse(review().renewedExpiry));
  for(const change of [{executionPermitted:false},{controlledFixture:true},{exportsCompletedFirst:false},{jobsRemainPaused:false},
    {clientScheduleSecretRetrieved:true},{deployedVersion:6},{maximumManagementAttempts:6},{maximumHealthInvocations:2},
    {historicalScheduleRequests:0},{maximumScheduleRequests:4321},{automaticRetries:1},{humanRenewalDecisionBinding:null},
    {actualRenewalReadbackBinding:null},{completedExportsBinding:null},{sourceBinding:binding('wrong.mjs')},
    {authorizationExpiresAt:'2026-10-14T09:57:07.481942Z'},{renewedExpiry:'2026-10-15T02:00:00.001Z'},
    {serverWindowAnchor:'2026-10-15T01:00:00.000Z'}])assert.throws(()=>validateReview({...review(),...change},instant));
});
test('table seven-day limits and both exact deployment/role guards are retained',()=>{
  assert.ok(GUARDS.includes('intelligence_control.worker_required()'));
  assert.ok(GUARDS.includes('api.wave5_health_collect(uuid,uuid)'));
  assert.throws(()=>validateReview({...review(),serverWindowAnchor:'2026-10-21T00:00:00Z',renewedExpiry:'2026-10-21T02:00:00Z',
    authorizationExpiresAt:'2026-10-21T01:59:00Z'},Date.parse('2026-10-21T00:10:00Z')),/SEVEN_DAY/);
});
test('SQL injection and arbitrary request identifiers are rejected before query construction',()=>{
  for(const fingerprint of [{signature:GUARDS[0],md5:"';DROP TABLE x;--"},{signature:'api.other()',md5:'a'.repeat(32)}])
    assert.throws(()=>validateGuardFingerprints([fingerprint,...review().guardFingerprints.slice(1)]),/GUARD/);
  assert.throws(()=>buildDispatchSql({...review(),renewedExpiry:"2026-10-15T02:00:00Z';select secret"}));
  for(const requestId of [0,-1,1.5,NaN,'25','25;DROP',Number.MAX_SAFE_INTEGER+1])assert.throws(()=>buildReadbackSql(requestId));
});
test('dispatch locks existing authority and scope and guards before one existing health call',()=>{
  const sql=buildDispatchSql(review());
  assert.equal([...sql.matchAll(/SELECT intelligence_control\.edge_schedule_tick\('health'\)/g)].length,1);
  for(const required of ['FOR UPDATE OF a','FOR UPDATE OF s',"snapshot->>'scopeAllowed'='true'",'75 seconds',
    'completedExports','nonWindowHash','ownJobs','guardFingerprints','effects'])assert.ok(sql.includes(required),required);
  assert.doesNotMatch(sql,/vault\.decrypted_secrets|cron\.alter_job|cron\.unschedule|UPDATE intelligence_control|INSERT INTO/i);
  assert.ok(buildReadbackSql(25).includes('FROM net._http_response WHERE id=25'));
});
test('state rejects expired scope, changed jobs, installation drift, missing exports and side effects',()=>{
  assert.equal(validateState(state(),review(),{now:instant,before:true}).effects.ticks,0);
  for(const changed of [{scopeAllowed:false},{migrationCount:114},{apiFunctionCount:362},{completedExports:false},
    {guardFingerprints:[]},{ownJobs:JOBS.map(row=>({...row,active:true}))},{outsideJobHash:'a'.repeat(64)},
    {scopes:{...state().scopes,expiresMin:'2026-10-14T08:13:04.144135Z'}},
    {authority:{...state().authority,issuedAt:'2026-10-15T00:00:00Z'}},
    {effects:{...effects(),usageEvents:1}},{effects:effects(1,0)}])
    assert.throws(()=>validateState({...state(),...changed},review(),{now:instant,before:true}));
});
test('completed readback requires exact HTTP and actual sole successful health outcome',()=>{
  assert.equal(validateCompletedReadback(readback(),review(),readArgs).readinessTick.kind,'health');
  const variants=[{http:{...readback().http,status:403}},{http:{...readback().http,id:26}},
    {http:{...readback().http,serverRequestId:null}},{http:{...readback().http,responseSha256:'d'.repeat(64)}},
    {http:{...readback().http,timedOut:true}},{effects:effects(0,1)},{effects:{...effects(1,1),modelInvocations:1}},
    {ticks:[]},{ticks:[...readback().ticks,...readback().ticks]},
    {ticks:[{...readback().ticks[0],kind:'delivery'}]},{ticks:[{...readback().ticks[0],state:'failed'}]},
    {ticks:[{...readback().ticks[0],startedAt:'2026-10-14T00:00:00Z'}]},
    {ticks:[{...readback().ticks[0],success:false}]},{ticks:[{...readback().ticks[0],summary:{count:0,states:[]}}]},
    {ticks:[{...readback().ticks[0],tickRow:null}]},{ticks:[{...readback().ticks[0],outcomeRow:{...readback().ticks[0].outcomeRow,id:'other'}}]}];
  for(const changes of variants)assert.throws(()=>validateCompletedReadback({...readback(),...changes},review(),readArgs));
});
test('success dispatches exactly once with durable intent and preserves 24 plus one accounting',async()=>{
  const p=ports(),result=await runHealthReadiness(p);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight','dispatch','readback']);
  assert.equal(p.calls[0].query,PREFLIGHT_SQL);assert.equal(p.calls[1].query,buildDispatchSql(p.review));
  assert.equal(p.calls[2].query,buildReadbackSql(25));assert.equal(p.calls.filter(call=>!call.readOnly).length,1);
  assert.equal(p.writes[0].file,'once');assert.equal(p.writes.at(-1).file,'99-result.json');
  assert.equal(result.cumulativeScheduleRequests,25);assert.equal(result.maximumScheduleRequests,4320);
  assert.equal(result.jobsRemainPaused,true);assert.equal(result.authenticatedNative,false);assert.equal(result.actualModelUsage,false);
  assert.equal(result.evidenceBindings.length,3);assert.equal(result.actualReadbackBinding.path,'after-state.json');
  const saved=p.writes.find(row=>row.file==='after-state.json').value;
  assert.equal(saved.http.serverRequestId,result.serverRequestId);assert.equal(saved.ticks[0].tickRow.id,result.readinessTick.id);
});
test('two pending reads consume exactly five attempts and never issue another tick',async()=>{
  const p=ports({pending:2}),result=await runHealthReadiness(p);
  assert.equal(result.managementAttempts,5);assert.deepEqual(p.waits,[35000,35000]);
  assert.equal(p.calls.filter(call=>!call.readOnly).length,1);assert.equal(result.requestCount,1);
});
test('three pending reads stop without a sixth management call or mutation replay',async()=>{
  const p=ports({pending:3});await assert.rejects(runHealthReadiness(p),/NOT_ESTABLISHED/);
  assert.equal(p.calls.length,5);assert.equal(p.calls.filter(call=>!call.readOnly).length,1);
  assert.equal(p.writes.at(-1).file,'99-stop.json');assert.equal(p.writes.at(-1).value.automaticRetries,0);
});
test('lost dispatch response preserves uncertain outcome and never retries mutation or guesses request ID',async()=>{
  const p=ports({brokenDispatch:true});await assert.rejects(runHealthReadiness(p),/LOST_DISPATCH/);
  assert.equal(p.calls.length,2);const stop=p.writes.at(-1).value;
  assert.equal(stop.healthInvocationMayHaveOccurred,true);assert.equal(stop.netRequestId,null);
});
test('missing durable intent or attempt acknowledgment prevents corresponding network action',async()=>{
  for(const [missingReceipt,expectedCalls] of [['once',0],['1-preflight-attempt.json',0],['2-dispatch-attempt.json',1]]){
    const p=ports({missingReceipt});await assert.rejects(runHealthReadiness(p),/DURABLE/);
    assert.equal(p.calls.length,expectedCalls);assert.equal(p.calls.filter(call=>!call.readOnly).length,0);
  }
});
test('stale preflight and changed readback stop rather than widening the approved state',async()=>{
  const p=ports({badPreflight:{...state(),scopeAllowed:false}});await assert.rejects(runHealthReadiness(p),/PAUSED/);
  assert.equal(p.calls.length,1);
  const q=ports({changedAfter:{...readback(),effects:{...effects(1,1),receiverReceipts:1}}});
  await assert.rejects(runHealthReadiness(q),/EFFECTS/);assert.equal(q.calls.length,3);
});
test('expired operation fails before any intent, persistence or network port',async()=>{
  const p=ports();p.now=()=>Date.parse(p.review.authorizationExpiresAt);
  await assert.rejects(runHealthReadiness(p),/WINDOW/);assert.equal(p.calls.length,0);assert.equal(p.writes.length,0);
});
test('cancellation and short remaining window prevent dispatch',async()=>{
  const p=ports(),controller=new AbortController();controller.abort();p.signal=controller.signal;
  await assert.rejects(runHealthReadiness(p),/EXPIRED|CANCELLED/);assert.equal(p.calls.length,0);
  const q=ports();q.review.authorizationExpiresAt=new Date(instant+89999).toISOString();
  await assert.rejects(runHealthReadiness(q),/MARGIN/);assert.equal(q.calls.length,0);
});
test('an uncooperative transport is bounded and receives cancellation without replay',async()=>{
  const p=ports();let request;p.portTimeoutMs=10;p.transport=async value=>{request=value;return new Promise(()=>{});};
  await assert.rejects(runHealthReadiness(p),/CANCELLED|TIMEOUT/);
  assert.equal(request.signal.aborted,true);assert.equal(p.writes.at(-1).value.managementAttempts,1);
});
test('a stalled audit sink and invalid timeout cannot hold the controller indefinitely',async()=>{
  const p=ports();p.persistTimeoutMs=10;p.once=()=>new Promise(()=>{});
  await assert.rejects(runHealthReadiness(p),/CANCELLED|TIMEOUT/);assert.equal(p.calls.length,0);
  await assert.rejects(runHealthReadiness({...ports(),portTimeoutMs:15001}),/BOUNDED/);
});
