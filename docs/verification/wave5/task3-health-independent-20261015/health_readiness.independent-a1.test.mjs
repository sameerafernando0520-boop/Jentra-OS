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

// Appended after the exact, hash-bound authored fixture/test bytes by the local
// runner. These are synthetic injected-port cases, never actual health evidence.

test('peer: a missing before-state receipt prevents any health dispatch',async()=>{
  const p=ports({missingReceipt:'before-state.json'});
  await assert.rejects(runHealthReadiness(p),/DURABLE_HEALTH_EVIDENCE_REQUIRED/);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight']);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,false);
  assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
});

test('peer: a missing successful-readback receipt prevents a readiness result without replay',async()=>{
  const p=ports({missingReceipt:'after-state.json'});
  await assert.rejects(runHealthReadiness(p),/DURABLE_HEALTH_EVIDENCE_REQUIRED/);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight','dispatch','readback']);
  assert.equal(p.calls.filter(call=>!call.readOnly).length,1);
  assert.equal(p.writes.at(-1).value.netRequestId,25);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,true);
  assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
});

test('peer: an unsuccessful preflight retains bounded response metadata before stopping',async()=>{
  const p=ports();
  p.transport=async request=>{p.calls.push(request);return {status:503,rows:[],rawSha256:'d'.repeat(64),rawBytes:57};};
  await assert.rejects(runHealthReadiness(p),/ONE_SUCCESSFUL_HEALTH_QUERY_ROW_REQUIRED/);
  const response=p.writes.find(row=>row.file==='1-preflight-response.json')?.value;
  assert.deepEqual(response,{status:503,rowCount:0,responseSha256:hash('[]'),rawSha256:'d'.repeat(64),rawBytes:57});
  assert.equal(p.calls.length,1);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,false);
});

test('peer: rejected scope and timezone snapshots are saved before domain validation',async()=>{
  for(const change of [{scopeAllowed:false},{timeZone:'Asia/Colombo'}]){
    const p=ports({badPreflight:{...state(),...change}});
    await assert.rejects(runHealthReadiness(p),/EXACT_RENEWED_PAUSED_HEALTH_STATE_REQUIRED/);
    const observation=p.writes.find(row=>row.file==='1-preflight-observation.json')?.value;
    assert.ok(observation);
    for(const [key,value]of Object.entries(change))assert.equal(observation[key],value);
    assert.ok(p.writes.findIndex(row=>row.file==='1-preflight-observation.json')<p.writes.findIndex(row=>row.file==='99-stop.json'));
    assert.equal(p.calls.length,1);
    assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
  }
});

test('peer: a response returned at the run deadline is audited without dispatch',async()=>{
  const p=ports();let clock=instant;p.now=()=>clock;
  p.transport=async request=>{p.calls.push(request);clock=instant+120000;
    return {status:200,rows:[{snapshot:state()}],rawSha256:'e'.repeat(64),rawBytes:768};};
  await assert.rejects(runHealthReadiness(p),/HEALTH_RUN_EXPIRED/);
  assert.equal(p.calls.length,1);
  assert.ok(p.writes.some(row=>row.file==='1-preflight-response.json'));
  assert.ok(p.writes.some(row=>row.file==='1-preflight-observation.json'));
  assert.equal(p.writes.at(-1).file,'99-stop.json');
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,false);
});

test('peer: unexpected HTTP error and malformed bodies never appear in public evidence',async()=>{
  const sentinel='CONTROLLED_PRIVATE_BODY_SENTINEL_7f44';
  for(const status of [503,200]){
    const content=status===503?sentinel:'{"unexpected":"'+sentinel+'"}';
    const changed=readback();changed.http={...changed.http,status,content,responseBytes:Buffer.byteLength(content),responseSha256:hash(content)};
    const p=ports({changedAfter:changed});
    await assert.rejects(runHealthReadiness(p));
    assert.equal(p.calls.length,3);
    assert.equal(p.calls.filter(call=>!call.readOnly).length,1);
    const saved=JSON.stringify(p.writes);
    assert.equal(saved.includes(sentinel),false);
    const observation=p.writes.find(row=>row.file==='3-readback-observation.json')?.value;
    assert.equal(Object.hasOwn(observation.http,'content'),false);
    assert.equal(observation.http.responseSha256,hash(content));
    assert.equal(p.writes.some(row=>row.file==='after-state.json'||row.file==='99-result.json'),false);
  }
});

test('peer: controller stops at each non-health side effect and never retries health',async()=>{
  for(const name of EFFECT_NAMES.filter(name=>!['ticks','outcomes'].includes(name))){
    const changed=readback();changed.effects[name]=1;
    const p=ports({changedAfter:changed});
    await assert.rejects(runHealthReadiness(p),/HEALTH_ONLY_EFFECTS_REQUIRED/);
    assert.equal(p.calls.length,3,name);
    assert.equal(p.calls.filter(call=>!call.readOnly).length,1,name);
    assert.equal(p.waits.length,0,name);
    assert.equal(p.writes.at(-1).file,'99-stop.json');
    assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
  }
});

test('peer: cancellation after dispatch begins preserves uncertainty and aborts the port',async()=>{
  const p=ports(),controller=new AbortController(),original=p.transport;p.signal=controller.signal;
  let dispatchSignal;
  p.transport=async request=>{
    if(request.kind==='dispatch'){
      p.calls.push(request);dispatchSignal=request.signal;controller.abort();return new Promise(()=>{});
    }
    return original(request);
  };
  await assert.rejects(runHealthReadiness(p),/CANCELLED|EXPIRED/);
  assert.equal(dispatchSignal.aborted,true);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight','dispatch']);
  const stop=p.writes.at(-1).value;
  assert.equal(stop.healthInvocationMayHaveOccurred,true);
  assert.equal(stop.netRequestId,null);
  assert.equal(stop.managementAttempts,2);
  assert.equal(stop.automaticRetries,0);
});

test('peer: failed dispatch evidence retains the known ID and cannot trigger a replacement',async()=>{
  const p=ports({missingReceipt:'dispatch.json'});
  await assert.rejects(runHealthReadiness(p),/DURABLE_HEALTH_EVIDENCE_REQUIRED/);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight','dispatch']);
  assert.equal(p.writes.at(-1).value.netRequestId,25);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,true);
  assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
});

test('peer: a stalled after-state sink is bounded and the stop can still be persisted',async()=>{
  const p=ports(),original=p.persist;p.persistTimeoutMs=10;
  p.persist=async(file,value)=>file==='after-state.json'?new Promise(()=>{}):original(file,value);
  await assert.rejects(runHealthReadiness(p),/TIMEOUT|CANCELLED/);
  assert.equal(p.calls.length,3);
  assert.equal(p.writes.at(-1).file,'99-stop.json');
  assert.equal(p.writes.at(-1).value.netRequestId,25);
  assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
});

test('peer: slow setup uses the original startup deadline and preserves the dispatch reserve',async()=>{
  const p=ports(),original=p.once;let clock=instant;p.now=()=>clock;
  p.once=async value=>{const receipt=await original(value);clock=instant+45001;return receipt;};
  await assert.rejects(runHealthReadiness(p),/HEALTH_DISPATCH_RESOLUTION_MARGIN_REQUIRED/);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight']);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,false);
});

test('peer: crossing the startup deadline during a wait forbids a later readback or replay',async()=>{
  const p=ports({pending:3});let clock=instant;p.now=()=>clock;
  p.wait=async()=>{clock=instant+120000;};
  await assert.rejects(runHealthReadiness(p),/HEALTH_RUN_EXPIRED/);
  assert.deepEqual(p.calls.map(call=>call.kind),['preflight','dispatch','readback']);
  assert.equal(p.writes.at(-1).value.netRequestId,25);
  assert.equal(p.writes.at(-1).value.healthInvocationMayHaveOccurred,true);
  assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
});

test('peer: successful HTTP cannot substitute for exact runtime, raw outcome and lease lineage',async()=>{
  for(const mutate of [
    value=>{value.ticks[0].tickRow.runtime_id='30000000-0000-4000-8000-000000000001';},
    value=>{value.ticks[0].outcomeRow.runtime_id='30000000-0000-4000-8000-000000000001';},
    value=>{value.ticks[0].tickRow.lease_until=value.ticks[0].recordedAt;},
    value=>{value.ticks[0].state='failed';value.ticks[0].tickRow.state='failed';},
  ]){
    const changed=readback();mutate(changed);const p=ports({changedAfter:changed});
    await assert.rejects(runHealthReadiness(p),/RAW_ROWS|TICK_STATE/);
    assert.equal(p.calls.length,3);
    assert.equal(p.calls.filter(call=>!call.readOnly).length,1);
    assert.equal(p.writes.some(row=>row.file==='99-result.json'),false);
  }
});

test('peer: the only saved full HTTP content is the verified exact positive health body',async()=>{
  const p=ports(),result=await runHealthReadiness(p);
  const observations=p.writes.filter(row=>row.file.endsWith('-observation.json'));
  for(const row of observations)if(row.value.http)assert.equal(Object.hasOwn(row.value.http,'content'),false);
  const after=p.writes.find(row=>row.file==='after-state.json').value;
  assert.equal(after.http.content,JSON.stringify({state:'completed',count:1,states:['collected']}));
  assert.equal(hash(after.http.content),result.responseSha256);
  assert.equal(after.ticks[0].tickRow.runtime_id,RUNTIME);
  assert.equal(result.actualDelivery,false);
  assert.equal(result.actualModelUsage,false);
  assert.equal(result.productionReleaseReady,false);
});
