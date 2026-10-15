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
