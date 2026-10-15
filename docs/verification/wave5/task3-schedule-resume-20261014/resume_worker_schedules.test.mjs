import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {createHash} from 'node:crypto';
import {
 PROJECT,BUNDLE,RUNTIME,TENANT,ISSUED,EXPIRES,SOURCE,PROVIDER_REVIEW,PRESERVED,JOBS,GUARDS,EXPORT_COMMANDS,READ_SQL,
 buildResumeSql,validateTime,validateFingerprints,validateExportsProof,validateProviderAuthority,validateFinalReview,validateSnapshot,
 createScheduleTransport,runScheduleResume,main,
} from '../../../../tools/wave5/resume_worker_schedules_20261014_r5_v7.mjs';

// Deliberately fake records/clocks/transports only. No credentials, sockets,
// SQL execution, private files or environment variables are used by the tests.
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const now=Date.parse('2026-10-14T09:30:00Z');
const fingerprints=[...GUARDS].sort().map((signature,i)=>({signature,md5:String(i+1).repeat(32)}));
const metadata={kind:'wave5-private-owner-input-metadata',projectId:PROJECT,runtimeBundleSha256:BUNDLE,
 ownerSid:'S-1-5-21-CONTROLLED-FAKE',createdAt:'2026-10-14T09:00:00Z',expiresAt:'2026-10-14T11:00:00Z',
 privateFolder:'C:\\Controlled-fake-no-file-read',containsPlaintextCredential:false};
const exportsProof={kind:'genuine-export-only-successor-result',passed:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,
 completed:structuredClone(EXPORT_COMMANDS),actualOrdinaryAttempts:24,actualReadOnlyResolutionAttempts:0,rawWholeHashChanged:true,
 successfulDateCommandsReexecuted:false,oldUncertainCommandReplayed:false,artifacts:EXPORT_COMMANDS.map((row,i)=>({
  exportId:row.exportId,sourceHash:'a'.repeat(64),fileSha256:'b'.repeat(64),independentSessionId:'10000000-0000-4000-8000-000000000001',
  registeredPipelineReopen:i===0,statementFreshSourceReproduction:i===1,registeredStatementReopen:false}))};
const providerBinding={path:PROVIDER_REVIEW,sha256:'d'.repeat(64)};
const providerEvidence={path:'docs/verification/wave5/CONTROLLED_FAKE_NO_REAL_PROVIDER_REQUEST.json',sha256:'e'.repeat(64)};
const providerAuthority={kind:'independent-actual-v7-backend-provider-authority-review',technicalDecision:'approve',passed:true,
 independentlyReviewed:true,projectId:PROJECT,runtimeBundleSha256:BUNDLE,runtimeId:RUNTIME,deployedVersion:7,
 candidateBundleSha256:'2a540cabaf0b8ac10f1a553e07b5cea0e886cb9ec380ff8560f500eba4b1f35c',
 credentialSource:'existing-injected-worker-service-key',backendRole:'service_role',actualReadOnlyBackendAuthorizationVerified:true,
 actualServiceKeyRoleAndValidityVerified:true,unsignedProbeUsedAsRoleProof:false,keyFormatUsedAsRoleProof:false,secretsPublished:false,
 observedAt:new Date(now-1000).toISOString(),guardFingerprints:fingerprints,evidenceBindings:[providerEvidence],actualChecks:[{
  rpc:'wave5_runtime_worker',action:'entitlement',readOnly:true,httpStatus:200,authorized:true,runtimeId:RUNTIME,tenantId:TENANT,
  responseSha256:'f'.repeat(64),serverRequestId:'10000000-0000-4000-8000-000000000009',evidenceBinding:providerEvidence}]};
function finalReview(){return {kind:'independent-exact-three-job-schedule-resume-operation-review',technicalDecision:'approve',executionPermitted:true,
 projectId:PROJECT,runtimeBundleSha256:BUNDLE,sourceBinding:{path:SOURCE,sha256:'a'.repeat(64)},jobIds:[4,5,6],
 originalAuthorityExpiresAt:EXPIRES,originalAuthorityIssuedAt:ISSUED,authorizationExpiresAt:new Date(Date.parse(EXPIRES)).toISOString(),
 maximumScheduleRequestsOriginal:4320,scheduledRequestsAlreadyObserved:24,maximumManagementAttempts:3,automaticRetries:0,
 newUsers:0,newPermissions:0,newSecrets:0,newDestinations:0,extendedExpiry:false,personalHumanExactSourceSignatureClaimed:false,
 v7ProbeProof:PRESERVED[7],v7OwnerDecision:PRESERVED[6],exportsMustCompleteFirst:true,oldA4IntentReused:false,countersReset:false,
 currentOwnerSidVerifiedByPrivateAdapter:true,separateScheduleResumeDecision:true,guardFingerprints:fingerprints,
 readSqlSha256:hash(READ_SQL),writeSqlSha256:hash(buildResumeSql(fingerprints)),ownerSid:metadata.ownerSid,providerAuthorityBinding:providerBinding};}
function state(active=false){return {observedAt:new Date(now).toISOString(),scopeAllowed:true,migrationCount:115,apiFunctionCount:363,
 serviceRoleRpcGrants:true,completedOriginalExports:true,guardFingerprints:structuredClone(fingerprints),
 authority:{runtimeId:RUNTIME,enabled:true,issuedAt:ISSUED,expiresAt:EXPIRES,jobIds:[4,5,6]},
 ownJobs:JOBS.map(job=>({...job,active})),outsideJobHash:'4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945',
 ticks:0,quotaPeriods:0,recordedCronRuns:24};}
const receipt=file=>({path:file,sha256:'c'.repeat(64)});
function ports({write='ok',badBefore,badAfter,badPersist}={}){
 const calls=[],records=[],secrets=[];let mutationCalls=0;
 return {calls,records,secrets,mutationCount:()=>mutationCalls,
  now:()=>now,guardFingerprints:fingerprints,once:async value=>{records.push({file:'once',value});return receipt('once');},
  persist:async(file,value)=>{records.push({file,value});return file===badPersist?null:receipt(file);},
  appendPrivate:async(kind,value)=>{secrets.push({kind,value});return 'runtime-controlled-fake-error.sealed.json';},
  transport:async(sql,readOnly)=>{
   calls.push({sql,readOnly});if(readOnly)return {status:200,raw:Buffer.from(JSON.stringify([{snapshot:calls.length===1?(badBefore??state()):(badAfter??state(true))}]))};
   mutationCalls++;if(write==='uncertain')throw Error('CONTROLLED_FAKE_LOST_REPLY');
   return {status:write==='denied'?503:200,raw:Buffer.from(write==='denied'?'CONTROLLED_PRIVATE_ERROR':'[]')};
  }};
}

test('time: exact original authority boundary rejects equality, later clocks and extensions',()=>{
 assert.equal(validateTime(now),Date.parse(EXPIRES));assert.throws(()=>validateTime(Date.parse(EXPIRES)),/EXPIRED/);
 assert.throws(()=>validateTime(Date.parse(EXPIRES)+1),/EXPIRED/);
 assert.throws(()=>validateTime(now,{expiresAt:'2026-10-15T09:57:07Z'}),/EXPIRED/);
 assert.throws(()=>validateTime(Date.parse(ISSUED)-1),/EXPIRED/);
 assert.throws(()=>validateTime(NaN),/EXPIRED/);
});

test('fingerprints: exact sorted four fixed signatures and hexadecimal values only',()=>{
 assert.equal(validateFingerprints(fingerprints),fingerprints);
 for(const rows of [[],fingerprints.slice(1),[...fingerprints].reverse(),
  [{...fingerprints[0],md5:"a'; DROP TABLE x;--"},...fingerprints.slice(1)],
  [{...fingerprints[0],signature:'api.unknown()'},...fingerprints.slice(1)],
  [{...fingerprints[0],extra:true},...fingerprints.slice(1)]])assert.throws(()=>buildResumeSql(rows),/FINGERPRINTS/);
});

test('SQL: only three cron activations remain and exact scope/expiry/115/363/export/budget checks are present',()=>{
 const sql=buildResumeSql(fingerprints);
 assert.ok(sql.includes('FOREACH j IN ARRAY ARRAY[4,5,6]::bigint[] LOOP PERFORM cron.alter_job(j,active:=true)'));
 for(const guard of ['EXACT_UNEXPIRED_AUTHORITY_REQUIRED','EXACT_APPROVED_SCOPE_REQUIRED','EXACT_115_363_BASELINE_REQUIRED',
  'UNCHANGED_SERVER_AUTHORITY_GUARDS_REQUIRED','EXACT_TWO_COMPLETED_EXPORTS_FIRST_REQUIRED','EXACT_THREE_PAUSED_OWN_JOBS_REQUIRED',
  'OUTSIDE_JOB_PRESERVATION_REQUIRED','ZERO_WORKER_START_BASELINE_REQUIRED','PRESERVED_REQUEST_BUDGET_REQUIRED'])assert.ok(sql.includes(guard));
 assert.ok(sql.includes(ISSUED)&&sql.includes(EXPIRES)&&sql.includes('FOR UPDATE'));
 assert.ok(sql.includes("command_name='finance.report.export' AND aggregate_type='report_export'"));
 assert.equal(/\b(?:DELETE|TRUNCATE|INSERT|CREATE|GRANT|UPDATE)\b/i.test(sql.replace('FOR UPDATE','')),false);
 assert.equal(sql.includes('vault.decrypted_secrets'),false);assert.equal(sql.includes('set_config'),false);
 assert.equal(sql.includes('net.http_post'),false);assert.equal(sql.includes('cron.unschedule'),false);
 assert.equal(READ_SQL.startsWith('SELECT '),true);assert.equal(/\b(?:DELETE|UPDATE|INSERT|ALTER|CREATE|GRANT)\b/i.test(READ_SQL),false);
});

test('exports: exact two completed original commands and independent artifact reproductions are necessary',()=>{
 assert.equal(validateExportsProof(exportsProof),exportsProof);
 for(const changed of [{passed:false},{completed:[]},{completed:[...EXPORT_COMMANDS].reverse()},
  {actualOrdinaryAttempts:23},{actualReadOnlyResolutionAttempts:1},{oldUncertainCommandReplayed:true},
  {artifacts:exportsProof.artifacts.map(a=>({...a,registeredStatementReopen:true}))}])
  assert.throws(()=>validateExportsProof({...exportsProof,...changed}),/EXPORT/);
});

test('operation review: legitimate exact separate review with actual export proof validates only before expiry',()=>{
 assert.equal(validateFinalReview(finalReview(),{sourceSha256:'a'.repeat(64),metadata,exportsProof,providerAuthority,now}).executionPermitted,true);
 assert.throws(()=>validateFinalReview(finalReview(),{sourceSha256:'a'.repeat(64),metadata,exportsProof,providerAuthority,now:Date.parse(EXPIRES)}),/EXPIRED/);
});

test('operation review: deployment approval, altered jobs/source/caps/expiry and reset attempts cannot grant resume',()=>{
 for(const changes of [{kind:'direct-human-exact-worker-v7-operation-decision'},{executionPermitted:false},{separateScheduleResumeDecision:false},
  {jobIds:[4,5,7]},{sourceBinding:{path:SOURCE,sha256:'b'.repeat(64)}},{maximumScheduleRequestsOriginal:4321},
  {scheduledRequestsAlreadyObserved:0},{maximumManagementAttempts:4},{automaticRetries:1},{extendedExpiry:true},
  {newSecrets:1},{oldA4IntentReused:true},{countersReset:true},{personalHumanExactSourceSignatureClaimed:true},
  {writeSqlSha256:'b'.repeat(64)},{guardFingerprints:[]},{currentOwnerSidVerifiedByPrivateAdapter:false}])
  assert.throws(()=>validateFinalReview({...finalReview(),...changes},{sourceSha256:'a'.repeat(64),metadata,exportsProof,providerAuthority,now}));
});

test('metadata: expired, wrong owner/project/bundle and extension do not pass with a valid final review',()=>{
 for(const changes of [{expiresAt:'2026-10-14T09:00:00Z'},{ownerSid:'other'},{projectId:'foreign'},
  {runtimeBundleSha256:'b'.repeat(64)},{containsPlaintextCredential:true},{createdAt:'2026-10-14T10:00:00Z'}])
  assert.throws(()=>validateFinalReview(finalReview(),{sourceSha256:'a'.repeat(64),metadata:{...metadata,...changes},exportsProof,providerAuthority,now}));
});

test('provider authority: missing actual record cannot be replaced by unsigned403 or grant/format assertions',()=>{
 for(const actual of [undefined,null,{...providerAuthority,kind:'independent-actual-worker-v7-unsigned-probe-result-review'},
  {...providerAuthority,actualServiceKeyRoleAndValidityVerified:false},{...providerAuthority,unsignedProbeUsedAsRoleProof:true},
  {...providerAuthority,keyFormatUsedAsRoleProof:true},{...providerAuthority,secretsPublished:true}])
  assert.throws(()=>validateFinalReview(finalReview(),{sourceSha256:'a'.repeat(64),metadata,exportsProof,providerAuthority:actual,now}),/PROVIDER/);
});

test('provider authority: actual controlled read-only authorization record validates with its exact fixed public binding',()=>{
 assert.equal(validateProviderAuthority(providerAuthority,{binding:providerBinding,guardFingerprints:fingerprints,now}),providerAuthority);
 for(const binding of [{...providerBinding,path:'docs/verification/wave5/unsigned-probe.json'},
  {...providerBinding,sha256:'unknown'},undefined])
  assert.throws(()=>validateProviderAuthority(providerAuthority,{binding,guardFingerprints:fingerprints,now}),/PROVIDER/);
});

test('provider authority: foreign scope/version/role, stale or future clocks and mismatched guard source cannot pass',()=>{
 for(const changes of [{projectId:'foreign'},{runtimeBundleSha256:'a'.repeat(64)},{runtimeId:'foreign'},
  {deployedVersion:6},{candidateBundleSha256:'b'.repeat(64)},{backendRole:'anon'},{independentlyReviewed:false},
  {credentialSource:'arbitrary-local-key'},{guardFingerprints:[]},{observedAt:new Date(now+1).toISOString()},
  {observedAt:new Date(now-300000).toISOString()},{actualReadOnlyBackendAuthorizationVerified:false}])
  assert.throws(()=>validateProviderAuthority({...providerAuthority,...changes},{binding:providerBinding,guardFingerprints:fingerprints,now}),/PROVIDER/);
});

test('provider authority: denied/mutating/unknown backend checks or malformed/missing request evidence are rejected',()=>{
 const check=providerAuthority.actualChecks[0];
 for(const changes of [{rpc:'wave5_edge_control'},{action:'delivery.claim'},{readOnly:false},{httpStatus:403},{authorized:false},
  {tenantId:'foreign'},{runtimeId:'foreign'},{responseSha256:'unbound'},{serverRequestId:'not-a-server-uuid'},
  {evidenceBinding:{...providerEvidence,sha256:'a'.repeat(64)}}])
  assert.throws(()=>validateProviderAuthority({...providerAuthority,actualChecks:[{...check,...changes}]},
   {binding:providerBinding,guardFingerprints:fingerprints,now}),/PROVIDER/);
 for(const changes of [{evidenceBindings:[]},{actualChecks:[]},{evidenceBindings:[{path:'../secret',sha256:'e'.repeat(64)}]},
  {evidenceBindings:[providerEvidence,providerEvidence]}])
  assert.throws(()=>validateProviderAuthority({...providerAuthority,...changes},{binding:providerBinding,guardFingerprints:fingerprints,now}),/PROVIDER/);
});

test('snapshot: exact paused scope and hashes validate without resetting recorded24',()=>{
 const before=state();assert.equal(validateSnapshot(before,{guardFingerprints:fingerprints,now}),before);
 assert.equal(validateSnapshot(state(true),{active:true,guardFingerprints:fingerprints,now,before}).recordedCronRuns,24);
});

test('snapshot: tenant denial, stale clock, count drift, outside jobs, exports and role grants stop before activation',()=>{
 for(const changes of [{scopeAllowed:false},{observedAt:'2026-10-14T09:00:00Z'},{migrationCount:114},{apiFunctionCount:364},
  {serviceRoleRpcGrants:false},{completedOriginalExports:false},{guardFingerprints:[]},{outsideJobHash:'b'.repeat(64)},
  {ticks:1},{quotaPeriods:1},{recordedCronRuns:23},{recordedCronRuns:4320},{ownJobs:state(true).ownJobs},
  {authority:{...state().authority,expiresAt:'2026-10-15T09:57:07Z'}}])
  assert.throws(()=>validateSnapshot({...state(),...changes},{guardFingerprints:fingerprints,now}));
});

test('workflow: legitimate preparation, activation and readback are exactly read/write/read with durable acknowledgments',async()=>{
 const p=ports(),result=await runScheduleResume(p);assert.equal(result.passed,true);assert.equal(p.mutationCount(),1);
 assert.deepEqual(p.calls.map(c=>c.readOnly),[true,false,true]);assert.equal(result.managementAttempts,3);
 assert.equal(p.calls[0].sql,READ_SQL);assert.equal(p.calls[1].sql,buildResumeSql(fingerprints));assert.equal(p.calls[2].sql,READ_SQL);
 assert.equal(p.records[0].file,'once');assert.equal(p.records.at(-1).file,'99-result.json');assert.equal(p.secrets.length,0);
 assert.equal(result.countersReset,false);assert.equal(result.originalExpiry,EXPIRES);assert.equal(result.actualDelivery,false);
});

test('workflow: bad before snapshot persists stop and performs no activation',async()=>{
 const p=ports({badBefore:{...state(),completedOriginalExports:false}});await assert.rejects(runScheduleResume(p),/STATE/);
 assert.equal(p.mutationCount(),0);assert.equal(p.calls.length,1);assert.equal(p.records.at(-1).file,'99-stop.json');
});

test('workflow: unacknowledged once intent performs zero network calls',async()=>{
 const p=ports();p.once=async()=>null;await assert.rejects(runScheduleResume(p),/EXCLUSIVE/);assert.equal(p.calls.length,0);
});

test('workflow: unacknowledged preflight or write attempt is not dispatched',async()=>{
 for(const file of ['00-before-attempt.json','02-write-attempt.json']){
  const p=ports({badPersist:file});await assert.rejects(runScheduleResume(p));
  assert.equal(p.mutationCount(),0);assert.ok(p.calls.length<3);
 }
});

test('workflow: an uncertain write is never replayed and one actual readback can establish enabled state',async()=>{
 const p=ports({write:'uncertain'}),result=await runScheduleResume(p);
 assert.equal(result.enabledStateConfirmedByReadback,true);assert.equal(result.writeResponseUncertain,'SCHEDULE_WRITE_OUTCOME_UNCERTAIN');
 assert.equal(p.mutationCount(),1);assert.deepEqual(p.calls.map(c=>c.readOnly),[true,false,true]);
});

test('workflow: failed write plus paused readback stops with uncertain mutation and no replay',async()=>{
 const p=ports({write:'denied',badAfter:state(false)});await assert.rejects(runScheduleResume(p));
 assert.equal(p.mutationCount(),1);assert.equal(p.calls.length,3);assert.equal(p.secrets.length,1);
 assert.equal(p.records.at(-1).value.mutationMayBeCommitted,true);
 assert.equal(JSON.stringify(p.records).includes('CONTROLLED_PRIVATE_ERROR'),false);
});

test('workflow: expiry during preparation rejects before dispatch and does not alter authority',async()=>{
 const p=ports();p.now=()=>Date.parse(EXPIRES);await assert.rejects(runScheduleResume(p),/EXPIRED/);assert.equal(p.calls.length,0);
});

function requestHarness({authorized=true,encrypted=true,status=200,body='[]',error=false}={}){
 const calls=[];const requestFactory=(url,options,callback)=>{
  const req=new EventEmitter();req.destroy=()=>{req.destroyed=true;};req.end=bytes=>{
   calls.push({url,options,body:bytes});queueMicrotask(()=>{
    if(error){req.emit('error',Error('CONTROLLED_FAKE_TRANSPORT_SECRET'));return;}
    const res=new EventEmitter();res.statusCode=status;callback(res);res.emit('data',Buffer.from(body));res.emit('end');
   });};queueMicrotask(()=>{const socket=new EventEmitter();socket.authorized=authorized;socket.encrypted=encrypted;
    req.emit('socket',socket);if(!authorized)socket.emit('secureConnect');});return req;
 };return {calls,requestFactory};
}

test('transport: no construction IO, strict endpoint/query, verified TLS and exactly three charged attempts',async()=>{
 const h=requestHarness(),transport=createScheduleTransport('CONTROLLED_FAKE_TOKEN',{writeSql:buildResumeSql(fingerprints),requestFactory:h.requestFactory,now:()=>now});
 assert.equal(h.calls.length,0);await assert.rejects(transport('SELECT secret',true),/FIXED/);assert.equal(h.calls.length,0);
 for(const [sql,readOnly] of [[READ_SQL,true],[buildResumeSql(fingerprints),false],[READ_SQL,true]])await transport(sql,readOnly);
 assert.equal(h.calls.length,3);await assert.rejects(transport(READ_SQL,true),/THREE/);
 for(const call of h.calls){assert.equal(call.url,`https://api.supabase.com/v1/projects/${PROJECT}/database/query`);
  assert.equal(call.options.method,'POST');assert.equal(call.options.rejectUnauthorized,true);}
});

test('transport: unverified chain or plaintext socket never sends header-bearing body',async()=>{
 for(const options of [{authorized:false},{encrypted:false}]){
  const h=requestHarness(options),transport=createScheduleTransport('CONTROLLED_FAKE_TOKEN',{
   writeSql:buildResumeSql(fingerprints),requestFactory:h.requestFactory,now:()=>now});
  await assert.rejects(transport(READ_SQL,true),/VERIFIED_SCHEDULE_TLS_REQUIRED/);assert.equal(h.calls.length,0);
 }
});

test('transport: network error is sanitized and never automatically retried',async()=>{
 const h=requestHarness({error:true}),transport=createScheduleTransport('CONTROLLED_FAKE_TOKEN',{
  writeSql:buildResumeSql(fingerprints),requestFactory:h.requestFactory,now:()=>now});
 await assert.rejects(transport(READ_SQL,true),error=>error.message==='SCHEDULE_TRANSPORT_UNCERTAIN');assert.equal(h.calls.length,1);
});

test('CLI: expired execute rejects before reading any stdin or public operation gate',async()=>{
 let reads=0;const stdin={async *[Symbol.asyncIterator](){reads++;assert.fail('private read forbidden');}};
 await assert.rejects(main(['--execute','a'.repeat(64)],{stdin,stdout:{write(){assert.fail('no success');}},now:()=>Date.parse(EXPIRES)+1}),/EXPIRED/);
 assert.equal(reads,0);
});
