// Public, dependency-injected single-health-invocation controller. Importing this
// module does not read private input or perform network, SQL or filesystem I/O.
import {createHash} from 'node:crypto';
import {isDeepStrictEqual as same} from 'node:util';

export const PROJECT='xpdoufauvrbdmxgngetv', RUNTIME='778237e3-3d4e-4871-8cc9-e08b07b989c7';
export const BUNDLE='db525758554036fa99ec02d00c85bd8401ef7ebce787e2a983db1c69a08baf7b';
export const CANDIDATE='2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c';
export const SOURCE='tools/wave5/probe_worker_v7_health_20261014_r5.mjs';
export const PRIVATE_ADAPTER='scripts/wave5/run_private_health_scheduler_20261015_r5_a1.ps1';
export const TENANT='babe6c86-a764-4d3a-80a3-952a7c096c2c';
const ENTITY='caa2bb06-219a-47e9-8132-66d1271b0ffd', BRANCH='3813692c-f0de-4c69-8e34-d56cf54695b1';
const AUTHORITY_ISSUED='2026-10-13T09:57:07.481942Z', SCOPE_ISSUED='2026-10-13T08:13:04.144135Z';
const AUTHORITY_HASH='77cac80be8b4bccfad6c4a56fe14c52b03171e5524a46fe7a55ee4c958d90139';
const SCOPE_HASH='3119068e9ab1628e43855122d6e1ad8c2f89811561c15f2ec22d27336db2a387';
const EMPTY_HASH='4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945';
export const GUARDS=Object.freeze(['api.wave5_edge_control(uuid,text,jsonb)','api.wave5_runtime_worker(uuid,text,jsonb)',
  'api.wave5_health_collect(uuid,uuid)','intelligence_control.edge_schedule_tick(text)',
  'intelligence_control.runtime_scope_allowed(uuid,uuid,uuid,uuid)','intelligence_control.runtime_worker_required(uuid)',
  'intelligence_control.worker_required()'].sort());
const must=(ok,code)=>{if(!ok){const e=Error(code);e.publicCode=code;throw e;}};
const sha=value=>createHash('sha256').update(value).digest('hex');
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/.test(value);
const receipt=value=>value&&typeof value.path==='string'&&digest(value.sha256);
const utc=value=>new Date(Date.parse(value)).toISOString();
export const EFFECT_NAMES=Object.freeze(['ticks','outcomes','quotaPeriods','deliveryOutcomes','receiverReceipts','modelInvocations','modelOutcomes','usageEvents']);
export const JOBS=Object.freeze(['delivery','subscription','health'].map((kind,index)=>Object.freeze({jobId:index+4,
  name:'jentra-w5-20261009-'+kind,schedule:'* * * * *',command:`select intelligence_control.edge_schedule_tick('${kind}');`,active:false})));
const functionSql=`(SELECT jsonb_agg(jsonb_build_object('signature',s,'md5',md5(pg_get_functiondef(s::regprocedure))) ORDER BY s) FROM unnest(ARRAY[${GUARDS.map(s=>"'"+s+"'").join(',')}]) s)`;
const count=(table,where)=>`(SELECT count(*) FROM ${table} WHERE ${where})`;
const runtimeWhere=`runtime_id='${RUNTIME}'`,tenantWhere=`tenant_id='${TENANT}'`;
const effectSql=`jsonb_build_object('ticks',${count('intelligence_control.edge_ticks',runtimeWhere)},
 'outcomes',${count('intelligence_control.edge_tick_outcomes',runtimeWhere)},
 'quotaPeriods',${count('intelligence_control.quota_periods',tenantWhere)},
 'deliveryOutcomes',${count('intelligence_control.delivery_outcomes',tenantWhere)},
 'receiverReceipts',${count('intelligence_control.edge_receiver_receipts',runtimeWhere)},
 'modelInvocations',${count('intelligence_control.model_invocations',tenantWhere)},
 'modelOutcomes',(SELECT count(*) FROM intelligence_control.model_outcomes o JOIN intelligence_control.model_invocations i USING(invocation_id) WHERE i.tenant_id='${TENANT}'),
 'usageEvents',${count('intelligence_control.usage_events',tenantWhere)})`;
const exportsSql=`(SELECT count(*) FROM core.export_jobs WHERE tenant_id='${TENANT}' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6'
 AND status='completed' AND id IN('5594aa22-a243-337d-e574-9095f97b46c2','7ea25345-a8c0-45b0-f22b-8d1d0fba5318'))=2
 AND (SELECT count(*) FROM core.command_receipts WHERE tenant_id='${TENANT}' AND actor_id='8b740ab8-24f7-4455-a78b-aea0d99d20f6'
 AND command_name='finance.report.export' AND aggregate_type='report_export' AND
 ((command_id='d4a0ad64-f138-b857-30d6-6fe0afe64e4f' AND aggregate_id='5594aa22-a243-337d-e574-9095f97b46c2') OR
 (command_id='217bcee3-d103-9513-a3e7-cc56d26e45be' AND aggregate_id='7ea25345-a8c0-45b0-f22b-8d1d0fba5318')))=2`;
const stateSql=`jsonb_build_object('observedAt',statement_timestamp(),'timeZone',current_setting('TimeZone'),
 'migrationCount',(SELECT count(*) FROM supabase_migrations.schema_migrations),
 'apiFunctionCount',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='api'),
 'guardFingerprints',${functionSql},
 'scopeAllowed',intelligence_control.runtime_scope_allowed('${RUNTIME}','${TENANT}','${ENTITY}','${BRANCH}'),
 'authority',(SELECT jsonb_build_object('issuedAt',issued_at,'expiresAt',expires_at,'enabled',enabled,'jobIds',job_ids,
 'nonWindowHash',encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')) FROM intelligence_control.edge_authorities a WHERE ${runtimeWhere}),
 'scopes',(SELECT jsonb_build_object('count',count(*),'enabled',count(*) FILTER(WHERE enabled),'issuedMin',min(issued_at),'issuedMax',max(issued_at),
 'expiresMin',min(expires_at),'expiresMax',max(expires_at),'nonWindowHash',encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(s)-'expires_at' ORDER BY tenant_id,legal_entity_id,branch_id)::text,'[]'),'sha256'),'hex'))
 FROM intelligence_control.runtime_worker_scopes s WHERE ${runtimeWhere}),
 'ownJobs',(SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) ORDER BY jobid) FROM cron.job WHERE jobid IN(4,5,6)),
 'outsideJobHash',(SELECT encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(j) ORDER BY jobid)::text,'[]'),'sha256'),'hex') FROM cron.job j WHERE jobid NOT IN(4,5,6)),
 'completedExports',${exportsSql},'effects',${effectSql})`;
export const PREFLIGHT_SQL=`SELECT ${stateSql} AS snapshot;`;

export function validateGuardFingerprints(value){
  must(Array.isArray(value)&&value.length===GUARDS.length&&value.every((row,i)=>same(Object.keys(row).sort(),['md5','signature'])
    &&row.signature===GUARDS[i]&&typeof row.md5==='string'&&/^[a-f0-9]{32}$/.test(row.md5)),'EXACT_HEALTH_GUARD_FINGERPRINTS_REQUIRED');
}
export function validateReview(review,now=Date.now()){
  must(review?.kind==='independent-exact-v7-health-operation-review'&&review.technicalDecision==='approve'&&review.executionPermitted===true
    &&review.projectId===PROJECT&&review.runtimeBundleSha256===BUNDLE&&review.runtimeId===RUNTIME&&review.candidateBundleSha256===CANDIDATE
    &&review.deployedVersion===7&&review.maximumManagementAttempts===5&&review.maximumHealthInvocations===1
    &&review.historicalScheduleRequests===24&&review.maximumScheduleRequests===4320&&review.automaticRetries===0
    &&review.exportsCompletedFirst===true&&review.jobsRemainPaused===true&&review.clientScheduleSecretRetrieved===false
    &&review.controlledFixture===false,'EXACT_HEALTH_OPERATION_REVIEW_REQUIRED');
  for(const key of ['humanRenewalDecisionBinding','actualRenewalReadbackBinding','completedExportsBinding','sourceBinding','privateAdapterBinding'])
    must(receipt(review[key]),'PINNED_HEALTH_OPERATION_BINDINGS_REQUIRED');
  must(review.sourceBinding.path===SOURCE&&review.privateAdapterBinding.path===PRIVATE_ADAPTER,
    'EXACT_HEALTH_SOURCE_AND_ADAPTER_PATHS_REQUIRED');
  const anchor=Date.parse(review.serverWindowAnchor),expiry=Date.parse(review.renewedExpiry),deadline=Date.parse(review.authorizationExpiresAt);
  must(Number.isFinite(now)&&Number.isFinite(anchor)&&Number.isFinite(expiry)&&Number.isFinite(deadline)&&now>=anchor&&now<deadline
    &&deadline<=expiry&&expiry>anchor&&expiry-anchor<=7200000,'FRESH_REVIEWED_HEALTH_WINDOW_REQUIRED');
  must(expiry<=Date.parse(SCOPE_ISSUED)+7*86400000&&expiry<=Date.parse(AUTHORITY_ISSUED)+7*86400000,
    'EXISTING_SEVEN_DAY_TABLE_CONSTRAINT_REQUIRED');
  validateGuardFingerprints(review.guardFingerprints);return {expiry,deadline,anchor};
}
export function buildDispatchSql(review){
  validateReview(review,Date.parse(review.serverWindowAnchor));
  const expiry=utc(review.renewedExpiry),deadline=utc(review.authorizationExpiresAt),guards=JSON.stringify(review.guardFingerprints);
  // The existing scheduler disables/unschedules expired authorities. Its call
  // therefore appears only AFTER all WHERE guards, with both scope rows locked.
  return `WITH limits AS MATERIALIZED(SELECT set_config('lock_timeout','5s',true)),
 a AS MATERIALIZED(SELECT a.* FROM intelligence_control.edge_authorities a CROSS JOIN limits WHERE a.runtime_id='${RUNTIME}' FOR UPDATE OF a),
 s AS MATERIALIZED(SELECT s.* FROM intelligence_control.runtime_worker_scopes s CROSS JOIN a WHERE s.runtime_id=a.runtime_id FOR UPDATE OF s),
 b AS MATERIALIZED(SELECT b.* FROM core.branches b CROSS JOIN s WHERE b.tenant_id=s.tenant_id AND b.id=s.branch_id FOR SHARE OF b),
 j AS MATERIALIZED(SELECT j.* FROM cron.job j CROSS JOIN b WHERE j.jobid IN(4,5,6) ORDER BY j.jobid FOR SHARE OF j),
 current_state AS MATERIALIZED(SELECT ${stateSql} AS snapshot FROM a CROSS JOIN s CROSS JOIN b
 WHERE a.enabled AND a.issued_at='${AUTHORITY_ISSUED}'::timestamptz AND a.expires_at='${expiry}'::timestamptz
 AND a.job_ids=ARRAY[4,5,6]::bigint[] AND encode(extensions.digest((to_jsonb(a)-'expires_at')::text,'sha256'),'hex')='${AUTHORITY_HASH}'
 AND s.enabled AND s.tenant_id='${TENANT}' AND s.legal_entity_id='${ENTITY}' AND s.branch_id='${BRANCH}'
 AND s.issued_at='${SCOPE_ISSUED}'::timestamptz AND s.expires_at='${expiry}'::timestamptz
 AND encode(extensions.digest(jsonb_build_array(to_jsonb(s)-'expires_at')::text,'sha256'),'hex')='${SCOPE_HASH}'
 AND b.status='active' AND b.legal_entity_id=s.legal_entity_id
 AND (SELECT jsonb_agg(jsonb_build_object('jobId',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) ORDER BY jobid) FROM j)='${JSON.stringify(JOBS)}'::jsonb)
 SELECT intelligence_control.edge_schedule_tick('health') AS "requestId",statement_timestamp() AS "dispatchedAt"
 FROM current_state WHERE snapshot->>'timeZone'='UTC' AND snapshot->>'scopeAllowed'='true' AND snapshot->>'completedExports'='true'
 AND snapshot->>'migrationCount'='115' AND snapshot->>'apiFunctionCount'='363'
 AND snapshot->'guardFingerprints'='${guards}'::jsonb
 AND snapshot#>>'{authority,enabled}'='true' AND snapshot#>>'{authority,nonWindowHash}'='${AUTHORITY_HASH}'
 AND (snapshot#>>'{authority,issuedAt}')::timestamptz='${AUTHORITY_ISSUED}'::timestamptz
 AND (snapshot#>>'{authority,expiresAt}')::timestamptz='${expiry}'::timestamptz
 AND snapshot#>>'{scopes,nonWindowHash}'='${SCOPE_HASH}' AND snapshot#>>'{scopes,count}'='1' AND snapshot#>>'{scopes,enabled}'='1'
 AND (snapshot#>>'{scopes,issuedMin}')::timestamptz='${SCOPE_ISSUED}'::timestamptz
 AND (snapshot#>>'{scopes,expiresMin}')::timestamptz='${expiry}'::timestamptz
 AND snapshot->'ownJobs'='${JSON.stringify(JOBS)}'::jsonb AND snapshot->>'outsideJobHash'='${EMPTY_HASH}'
 AND snapshot->'effects'='${JSON.stringify(Object.fromEntries(EFFECT_NAMES.map(k=>[k,0])))}'::jsonb
 AND clock_timestamp()>='${utc(review.serverWindowAnchor)}'::timestamptz
 AND clock_timestamp()+interval '75 seconds'<'${deadline}'::timestamptz;`;
}
export function buildReadbackSql(requestId){
  must(Number.isSafeInteger(requestId)&&requestId>0,'EXACT_HEALTH_NET_REQUEST_ID_REQUIRED');
  return `SELECT ${stateSql} || jsonb_build_object('http',(SELECT jsonb_build_object('id',id,'status',status_code,'timedOut',timed_out,
 'content',CASE WHEN octet_length(content)<=1024 THEN content ELSE NULL END,'responseSha256',encode(extensions.digest(content,'sha256'),'hex'),
 'responseBytes',octet_length(content),'serverRequestId',headers->>'sb-request-id') FROM net._http_response WHERE id=${requestId}),
 'ticks',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'state',t.state,'startedAt',t.started_at,
 'tickSha256',encode(extensions.digest(to_jsonb(t)::text,'sha256'),'hex'),'outcomeSha256',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'),
 'success',o.success,'summary',o.summary,'recordedAt',o.recorded_at,'tickRow',to_jsonb(t),'outcomeRow',to_jsonb(o)) ORDER BY t.id),'[]'::jsonb)
 FROM intelligence_control.edge_ticks t LEFT JOIN intelligence_control.edge_tick_outcomes o ON o.runtime_id=t.runtime_id AND o.id=t.id WHERE t.runtime_id='${RUNTIME}')) AS snapshot;`;
}
export function validateState(value,review,{now=Date.now(),before=false}={}){
  validateReview(review,now);
  const observed=Date.parse(value?.observedAt),expiry=Date.parse(review.renewedExpiry);
  must(Number.isFinite(observed)&&Math.abs(now-observed)<60000&&observed>=Date.parse(review.serverWindowAnchor)
    &&observed<Date.parse(review.authorizationExpiresAt)&&value.timeZone==='UTC'&&value.scopeAllowed===true&&value.completedExports===true
    &&value.migrationCount===115&&value.apiFunctionCount===363&&same(value.guardFingerprints,review.guardFingerprints)
    &&value.authority?.enabled===true&&same(value.authority.jobIds,[4,5,6])&&value.authority.nonWindowHash===AUTHORITY_HASH
    &&Date.parse(value.authority.issuedAt)===Date.parse(AUTHORITY_ISSUED)&&Date.parse(value.authority.expiresAt)===expiry
    &&value.scopes?.count===1&&value.scopes.enabled===1&&value.scopes.nonWindowHash===SCOPE_HASH
    &&Date.parse(value.scopes.issuedMin)===Date.parse(SCOPE_ISSUED)&&Date.parse(value.scopes.issuedMax)===Date.parse(SCOPE_ISSUED)
    &&Date.parse(value.scopes.expiresMin)===expiry&&Date.parse(value.scopes.expiresMax)===expiry
    &&same(value.ownJobs,JOBS)&&value.outsideJobHash===EMPTY_HASH,'EXACT_RENEWED_PAUSED_HEALTH_STATE_REQUIRED');
  must(same(Object.keys(value.effects??{}).sort(),[...EFFECT_NAMES].sort())&&EFFECT_NAMES.every(key=>Number.isSafeInteger(value.effects[key])&&value.effects[key]>=0),
    'EXACT_HEALTH_EFFECT_COUNTS_REQUIRED');
  for(const key of EFFECT_NAMES)must(value.effects[key]===(before?0:Math.min(value.effects[key],['ticks','outcomes'].includes(key)?1:0)),
    'HEALTH_ONLY_EFFECTS_REQUIRED');
  must(value.effects.outcomes<=value.effects.ticks,'HEALTH_OUTCOME_REQUIRES_TICK');
  return value;
}
export function validateCompletedReadback(value,review,{requestId,dispatchedAt,now=Date.now()}={}){
  validateState(value,review,{now});
  must(Array.isArray(value.ticks)&&value.ticks.length<=1,'SINGLE_HEALTH_TICK_ONLY');
  if(value.ticks.length===1)must(value.ticks[0].kind==='health'&&['running','completed'].includes(value.ticks[0].state),
    'EXPECTED_HEALTH_TICK_STATE_REQUIRED');
  if(value.http===null)return null;
  const h=value.http;
  must(h?.id===requestId&&h.status===200&&h.timedOut===false&&typeof h.content==='string'&&h.responseBytes===Buffer.byteLength(h.content)
    &&h.responseBytes<=1024&&sha(h.content)===h.responseSha256&&uuid(h.serverRequestId),'SUCCESSFUL_ACTUAL_HEALTH_HTTP_REQUIRED');
  let response;try{response=JSON.parse(h.content);}catch{throw Error('EXACT_HEALTH_RESPONSE_REQUIRED');}
  must(same(response,{state:'completed',count:1,states:['collected']}),'EXACT_HEALTH_RESPONSE_REQUIRED');
  must(value.effects.ticks===1&&value.effects.outcomes===1&&value.ticks.length===1,'SINGLE_COMPLETED_HEALTH_TICK_REQUIRED');
  const tick=value.ticks[0],start=Date.parse(tick.startedAt),finished=Date.parse(tick.recordedAt);
  must(uuid(tick.id)&&tick.kind==='health'&&tick.state==='completed'&&tick.success===true&&same(tick.summary,{count:1,states:['collected']})
    &&digest(tick.tickSha256)&&digest(tick.outcomeSha256)&&start>=Date.parse(dispatchedAt)&&finished>=start
    &&finished<=Date.parse(value.observedAt)&&finished<Date.parse(review.authorizationExpiresAt),'ACTUAL_COMPLETED_HEALTH_LINEAGE_REQUIRED');
  must(tick.tickRow?.runtime_id===RUNTIME&&tick.tickRow.id===tick.id&&tick.tickRow.kind==='health'&&tick.tickRow.state==='completed'
    &&Date.parse(tick.tickRow.started_at)===start&&Date.parse(tick.tickRow.lease_until)>finished
    &&tick.outcomeRow?.runtime_id===RUNTIME&&tick.outcomeRow.id===tick.id&&tick.outcomeRow.success===true
    &&same(tick.outcomeRow.summary,tick.summary)&&Date.parse(tick.outcomeRow.recorded_at)===finished,'ACTUAL_HEALTH_RAW_ROWS_REQUIRED');
  return {response,readinessTick:{id:tick.id,kind:tick.kind,state:tick.state,tickSha256:tick.tickSha256,outcomeSha256:tick.outcomeSha256},
    responseSha256:h.responseSha256,serverRequestId:h.serverRequestId};
}

// Transport, durable evidence and sleeping are supplied by the separately
// reviewed owner adapter. AbortSignal and deadline reach every transport call.
export async function runHealthReadiness({review,transport,persist,once,wait,now=Date.now,signal,portTimeoutMs=15000,persistTimeoutMs=5000}={}){
  must(Number.isSafeInteger(portTimeoutMs)&&portTimeoutMs>0&&portTimeoutMs<=15000&&Number.isSafeInteger(persistTimeoutMs)
    &&persistTimeoutMs>0&&persistTimeoutMs<=5000,'BOUNDED_HEALTH_PORT_TIMEOUT_REQUIRED');
  const window=validateReview(review,now()),startedAt=now(),deadline=Math.min(window.deadline,startedAt+120000);
  must(deadline-startedAt>=90000,'HEALTH_RUN_RESOLUTION_MARGIN_REQUIRED');
  const controller=new AbortController(),combined=signal?AbortSignal.any([signal,controller.signal]):controller.signal;
  const timer=setTimeout(()=>controller.abort(),Math.max(1,deadline-now()));
  let attempts=0,invocations=0,requestId=null,dispatchedAt=null,before;
  const evidenceBindings=[];
  const check=()=>must(!combined.aborted&&now()<deadline,'HEALTH_RUN_EXPIRED');
  async function bounded(operation,timeoutMs,abortSignal){
    const child=new AbortController();
    const localSignal=abortSignal?AbortSignal.any([abortSignal,child.signal]):child.signal;
    let timeout,abortListener;
    try{return await Promise.race([
      Promise.resolve().then(()=>{must(!localSignal.aborted,'HEALTH_RUN_EXPIRED');return operation(localSignal);}),
      new Promise((_,reject)=>{abortListener=()=>reject(Error('HEALTH_PORT_CANCELLED'));
        localSignal.addEventListener('abort',abortListener,{once:true});
        timeout=setTimeout(()=>{child.abort();reject(Error('HEALTH_PORT_TIMEOUT'));},timeoutMs);}),
    ]);}finally{clearTimeout(timeout);if(abortListener)localSignal.removeEventListener('abort',abortListener);child.abort();}
  }
  // Local audit writes can finish after cancellation, for at most five seconds.
  const acknowledged=async(file,value)=>{const result=await bounded(()=>persist(file,value),persistTimeoutMs);
    must(receipt(result),'DURABLE_HEALTH_EVIDENCE_REQUIRED');return result;};
  async function call(kind,sql,readOnly){
    check();must(attempts<5,'FIVE_HEALTH_MANAGEMENT_ATTEMPTS_ONLY');
    await acknowledged(`${attempts+1}-${kind}-attempt.json`,{kind,readOnly,sqlSha256:sha(sql),actualAttemptAt:new Date(now()).toISOString()});
    check();attempts++;if(!readOnly){must(invocations===0,'ONE_HEALTH_INVOCATION_ONLY');invocations++;}
    const response=await bounded(portSignal=>transport({kind,query:sql,readOnly,signal:portSignal,
      deadline:Math.min(deadline,now()+portTimeoutMs)}),Math.min(portTimeoutMs,deadline-now()),combined);
    // A returned response must retain a receipt even if cancellation or domain
    // validation rejects it. Unexpected HTTP content is never published.
    await acknowledged(`${attempts}-${kind}-response.json`,{status:Number.isSafeInteger(response?.status)?response.status:null,
      rowCount:Array.isArray(response?.rows)?response.rows.length:null,responseSha256:sha(JSON.stringify(response?.rows??null)),
      rawSha256:digest(response?.rawSha256)?response.rawSha256:null,rawBytes:Number.isSafeInteger(response?.rawBytes)?response.rawBytes:null});
    if(Array.isArray(response?.rows)&&response.rows.length===1&&response.rows[0]?.snapshot){
      const observation=structuredClone(response.rows[0].snapshot);
      if(observation.http&&typeof observation.http==='object')delete observation.http.content;
      await acknowledged(`${attempts}-${kind}-observation.json`,observation);
    }
    check();must(response?.status===200&&Array.isArray(response.rows)&&response.rows.length===1,'ONE_SUCCESSFUL_HEALTH_QUERY_ROW_REQUIRED');
    return response.rows[0];
  }
  try{
    const intent=await bounded(()=>once({kind:'exclusive-one-deployed-v7-health-invocation-intent',startedAt:new Date(startedAt).toISOString(),
      projectId:PROJECT,runtimeId:RUNTIME,maximumManagementAttempts:5,maximumHealthInvocations:1,automaticRetries:0,
      historicalScheduleRequests:24,maximumScheduleRequests:4320,deadline:new Date(deadline).toISOString()}),persistTimeoutMs,combined);
    must(receipt(intent),'DURABLE_EXCLUSIVE_HEALTH_INTENT_REQUIRED');
    before=validateState((await call('preflight',PREFLIGHT_SQL,true)).snapshot,review,{now:now(),before:true});
    evidenceBindings.push(await acknowledged('before-state.json',before));
    must(deadline-now()>=75000,'HEALTH_DISPATCH_RESOLUTION_MARGIN_REQUIRED');
    const dispatch=await call('dispatch',buildDispatchSql(review),false);
    must(Number.isSafeInteger(dispatch.requestId)&&dispatch.requestId>0&&Number.isFinite(Date.parse(dispatch.dispatchedAt))
      &&Math.abs(now()-Date.parse(dispatch.dispatchedAt))<60000,'ACTUAL_HEALTH_DISPATCH_RECEIPT_REQUIRED');
    requestId=dispatch.requestId;dispatchedAt=dispatch.dispatchedAt;evidenceBindings.push(await acknowledged('dispatch.json',dispatch));
    for(let poll=0;poll<3;poll++){
      if(poll>0){check();await bounded(portSignal=>wait(35000,{signal:portSignal,deadline}),Math.min(40000,deadline-now()),combined);check();}
      const after=(await call('readback',buildReadbackSql(requestId),true)).snapshot;
      const result=validateCompletedReadback(after,review,{requestId,dispatchedAt,now:now()});
      if(!result){await acknowledged(`pending-${poll+1}.json`,{observedAt:after.observedAt,requestId,effects:after.effects});continue;}
      // Preserve the full successful public observation, including the exact HTTP
      // body, server UUID and tick/outcome rows. Unexpected error bodies stay out
      // of public evidence; the reviewed owner adapter handles private failures.
      const actualReadbackBinding=await acknowledged('after-state.json',after);evidenceBindings.push(actualReadbackBinding);
      const report={kind:'actual-v7-deployed-health-readiness-result',passed:true,controlledFixture:false,projectId:PROJECT,
        runtimeBundleSha256:BUNDLE,runtimeId:RUNTIME,deployedVersion:7,candidateBundleSha256:CANDIDATE,observedAt:after.observedAt,
        netRequestId:requestId,dispatchedAt,requestCount:1,managementAttempts:attempts,automaticRetries:0,
        authenticatedDatabaseOwnedInvocation:true,clientScheduleSecretRetrieved:false,hmacSignatureClaimed:false,
        status:200,response:result.response,responseSha256:result.responseSha256,serverRequestId:result.serverRequestId,
        readinessTick:result.readinessTick,healthOutcome:{success:true,summary:{count:1,states:['collected']}},
        effectsBefore:before.effects,effectsAfter:after.effects,guardFingerprints:review.guardFingerprints,actualReadbackBinding,evidenceBindings,
        historicalScheduleRequests:24,readinessInvocations:1,cumulativeScheduleRequests:25,maximumScheduleRequests:4320,
        jobsRemainPaused:true,actualDelivery:false,actualModelUsage:false,authenticatedNative:false,targetScaleLoad:false,productionReleaseReady:false};
      await acknowledged('99-result.json',report);return report;
    }
    throw Error('HEALTH_RESULT_NOT_ESTABLISHED_WITHIN_REVIEWED_POLLS');
  }catch(error){
    // A lost enqueue response has an unknown outcome. Never enqueue a replacement.
    await acknowledged('99-stop.json',{passed:false,failureCode:error.publicCode??'HEALTH_READINESS_STOP',managementAttempts:attempts,
      healthInvocationMayHaveOccurred:invocations===1,netRequestId:requestId,automaticRetries:0,secretsPrinted:false});
    throw error;
  }finally{clearTimeout(timer);controller.abort();}
}
