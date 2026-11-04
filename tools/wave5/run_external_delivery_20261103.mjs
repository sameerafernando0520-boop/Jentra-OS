import {readFile,writeFile} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomUUID} from 'node:crypto';
import {totpFromPrivateSecret,decodeReceivedAccessToken} from './supabase_http_transport.mjs';
import {readBoundedJson} from '../../workers/wave5/bounded_json.mjs';
import {PersistentDeliveryControl,createWorkerRpc} from '../../workers/wave5/persistent_control.mjs';
import {createScopedWorkerRpc} from '../../workers/wave5/scoped_runtime.mjs';
import {runDelivery} from '../../workers/wave5/worker_runtime.mjs';
import {pinnedHttpsPost} from '../../workers/wave5/integration_policy.mjs';
import {lookup} from 'node:dns/promises';
import {createExactSinglePost,validateExactLeasedDelivery,deliveryTarget as t,bytesSha256} from './external_delivery_once_20261103.mjs';

const base='docs/verification/ai-integrations-test-20261103/';
const origin='https://'+t.projectId+'.supabase.co';
const mode=process.argv[2],must=(v,c)=>{if(!v)throw Error(c);};
const load=async n=>JSON.parse((await readFile(base+n,'utf8')).replace(/^\ufeff/,''));
const save=(n,v)=>writeFile(base+n,JSON.stringify(v,null,2)+'\n',{flag:'wx'});
const env={...process.env};delete env.SUPABASE_ACCESS_TOKEN;
const cli=async args=>promisify(execFile)('C:\\Users\\sheha\\scoop\\shims\\supabase.exe',args,{env,windowsHide:true,encoding:'utf8',timeout:45000,maxBuffer:2097152});
let phase='validate-approval',anon,admin,postCalls=0,keyBuffers=[];
async function checkBindings(){
 const bytes=await readFile(base+'external-delivery-recovery-candidate.json'),plan=JSON.parse(bytes);
 must(plan.projectId===t.projectId&&plan.deliveryId===t.deliveryId&&plan.maximumSignedRequests===1&&plan.automaticRetries===0&&plan.modelRequests===0&&plan.materializeOtherDeliveries===false,'EXACT_REVIEW_PLAN_REQUIRED');
 for(const a of [...plan.artifacts,...plan.sources])must(bytesSha256(await readFile(a.path))===a.sha256,'REVIEWED_ARTIFACT_CHANGED');
 return {plan,planSha256:bytesSha256(bytes)};
}
async function checkMetadata(){
 const baseline=await load('external-receiver-readback.json'),runtime=await load('publishable-repair-deployed.json');
 const list=JSON.parse((await cli(['functions','list','--project-ref',t.projectId,'--output','json'])).stdout);
 for(const [slug,expected] of [['wave5-receiver',baseline.receiver],['wave5-runtime',runtime.runtimeAfter]]){
  const live=list.find(x=>x.slug===slug);
  must(live?.status==='ACTIVE'&&['id','version','updated_at','verify_jwt','ezbr_sha256'].every(k=>live[k]===expected[k]),'HOSTED_WORKER_CHANGED');
 }
}
async function keys(){
 const k=JSON.parse((await cli(['projects','api-keys','--project-ref',t.projectId,'--output','json'])).stdout);
 anon=k.find(x=>x.name==='anon')?.api_key;admin=k.find(x=>x.name==='service_role')?.api_key;
 must(anon?.startsWith('eyJ')&&admin?.startsWith('eyJ'),'EXISTING_SERVICE_KEYS_REQUIRED');
}
async function http(route,{token,key=anon,body,method='POST',api=false}={}){
 must(/^\/auth\/v1\/(token\?grant_type=password|user|factors\/[a-f0-9-]{36}\/(challenge|verify))$/.test(route)||['wave5_subscription_authorize','get_wave5_subscription','schedule_synthetic_subscription','apply_synthetic_subscription'].some(n=>route==='/rest/v1/rpc/'+n),'EXACT_AUTH_OR_SUBSCRIPTION_ROUTE_REQUIRED');
 const r=await fetch(origin+route,{method,redirect:'error',signal:AbortSignal.timeout(20000),headers:{apikey:key,...(token?{authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'content-type':'application/json'}),...(api?{'content-profile':'api','accept-profile':'api'}:{})},body:body===undefined?undefined:JSON.stringify(body)});
 return {ok:r.ok,status:r.status,date:r.headers.get('date'),value:await readBoundedJson(r,1048576)};
}
const rpc=(n,token,body,key=anon)=>http('/rest/v1/rpc/'+n,{token,key,body,api:true});
async function genuineBillingMfa(){
 const c=JSON.parse(await readFile('build/temp-test-profile-20261102/scoped-setup-20261103/billing-credentials.private.json','utf8'));
 must(c.userId==='c6aa32c0-d91f-4555-8687-e77fdf878e0c','EXACT_SYNTHETIC_BILLING_ACTOR_REQUIRED');
 const signed=await http('/auth/v1/token?grant_type=password',{body:{email:c.email,password:c.password}});must(signed.ok&&signed.value?.user?.id===c.userId,'REAL_PASSWORD_AUTH_REQUIRED');
 const challenge=await http('/auth/v1/factors/'+c.factorId+'/challenge',{token:signed.value.access_token,body:{}});must(challenge.ok&&challenge.value?.id,'REAL_MFA_CHALLENGE_REQUIRED');
 const now=Date.parse(challenge.date);must(Number.isFinite(now)&&Math.abs(now-Date.now())<15000,'SERVER_CLOCK_REQUIRED');
 const verified=await http('/auth/v1/factors/'+c.factorId+'/verify',{token:signed.value.access_token,body:{challenge_id:challenge.value.id,code:totpFromPrivateSecret(c.secret,now)}});must(verified.ok&&verified.value?.access_token,'REAL_MFA_VERIFY_REQUIRED');
 const token=verified.value.access_token,claims=decodeReceivedAccessToken(token),user=await http('/auth/v1/user',{token,method:'GET'});
 must(claims.sub===c.userId&&claims.aal==='aal2'&&user.ok&&user.value.id===c.userId,'REAL_ONLINE_MFA_IDENTITY_REQUIRED');
 await save('external-delivery-billing-mfa.json',{observedAt:new Date().toISOString(),actorId:c.userId,factorId:c.factorId,sessionId:claims.session_id,aal:'aal2',onlineAuthVerified:true,constructedClaims:false});
 return token;
}
async function main(){
 must(['validate','trial','send'].includes(mode)&&process.argv.length===3,'EXPLICIT_MODE_REQUIRED');
 const {plan,planSha256}=await checkBindings();
 if(mode==='validate'){console.log(JSON.stringify({passed:true,networkCalls:0,secretReads:0,reviewedArtifacts:plan.artifacts.length,reviewedSources:plan.sources.length,planSha256}));return;}
 const approval=await load('external-delivery-owner-approval.json');
 must(approval.answer==='Approve one free RT1 delivery test'&&approval.planSha256===planSha256&&approval.maximumSignedRequests===1&&approval.trialRuntimeEdgeSeconds===1800&&approval.projectId===t.projectId,'EXACT_OWNER_DELIVERY_APPROVAL_REQUIRED');
 await save('external-delivery-'+mode+'-once-intent.json',{recordedAt:new Date().toISOString(),projectId:t.projectId,mode,planSha256,questionItemId:approval.questionItemId,automaticRetry:false});
 phase='verify-current-hosted-metadata';await checkMetadata();await keys();
 if(mode==='trial'){
  const p=await load('external-delivery-before-trial.json');
  must(Date.now()-Date.parse(p.observedAt)<300000&&p.syntheticAllowed&&p.nonFixtureBillingMemberships===0&&p.activeMemberCount===5&&p.subscription.version==='5'&&p.subscription.plan==='w5_runtime_20261008'&&p.subscription.seats===5&&p.modelInvocationCount===1&&p.aiOutcome.state==='settled'&&p.aiOutcome.tokens==='247'&&p.delivery.state==='retry'&&p.delivery.attempt===1&&p.receiverReceipts.length===0&&!p.reservation&&!p.usage&&p.outcomes.length===0&&p.allHeads.length===1&&p.jobs.length===3&&p.jobs.every(j=>!j.active)&&JSON.stringify(p.readerPermissions)===JSON.stringify(['ai.proposals.view','analytics.view','crm.opportunities.view']),'FRESH_SYNTHETIC_PREFLIGHT_REQUIRED');
  phase='genuine-billing-mfa';const token=await genuineBillingMfa();
  const allowed=await rpc('wave5_subscription_authorize',token,{p_tenant_id:t.tenantId});must(allowed.ok&&allowed.value==='c6aa32c0-d91f-4555-8687-e77fdf878e0c','GENUINE_BILLING_AUTHORIZATION_REQUIRED');
  const before=await rpc('get_wave5_subscription',token,{p_tenant_id:t.tenantId}),s=before.value;
  must(before.ok&&s?.syntheticTarget===true&&s.version==='5'&&s.plan==='w5_runtime_20261008'&&s.seats===5&&Date.parse(s.trialStart)===Date.parse(p.subscription.trialStart)&&Date.parse(s.trialEnd)===Date.parse(p.subscription.trialEnd),'EXACT_TRIAL_PREIMAGE_REQUIRED');
  const start=Date.parse(before.date);must(Number.isFinite(start)&&Math.abs(start-Date.now())<10000,'SERVER_START_REQUIRED');
  const request={p_tenant_id:t.tenantId,p_command_id:randomUUID(),p_idempotency_key:randomUUID(),p_client_timestamp:new Date().toISOString(),p_expected_version:'5',p_plan_code:s.plan,p_seats:5,p_trial_starts_at:new Date(start).toISOString(),p_trial_ends_at:new Date(start+1800000).toISOString()};
  phase='schedule-approved-trial';await save('external-delivery-trial-schedule-intent.json',{recordedAt:new Date().toISOString(),request});
  const scheduled=await rpc('schedule_synthetic_subscription',token,request),revision=scheduled.value?.entity??scheduled.value;
  await save('external-delivery-trial-schedule-response.json',{observedAt:new Date().toISOString(),status:scheduled.status,revisionId:revision?.id??null,state:revision?.state??null});
  must(scheduled.ok&&revision?.state==='scheduled'&&/^[a-f0-9-]{36}$/.test(revision.id),'SCHEDULED_SYNTHETIC_REVISION_REQUIRED');
  phase='apply-approved-trial';await save('external-delivery-trial-apply-intent.json',{recordedAt:new Date().toISOString(),revisionId:revision.id});
  const applied=await rpc('apply_synthetic_subscription',admin,{p_tenant_id:t.tenantId,p_revision_id:revision.id},admin);
  await save('external-delivery-trial-apply-response.json',{observedAt:new Date().toISOString(),status:applied.status,entityId:applied.value?.entity?.id??null});
  const after=await rpc('get_wave5_subscription',token,{p_tenant_id:t.tenantId});
  must(applied.ok&&after.ok&&after.value?.version==='6'&&after.value.plan===s.plan&&after.value.seats===5&&Date.parse(after.value.trialStart)===start&&Date.parse(after.value.trialEnd)===start+1800000,'EXACT_THIRTY_MINUTE_ACTIVATION_REQUIRED');
  await save('external-delivery-trial-activated.json',{observedAt:new Date().toISOString(),projectId:t.projectId,before:s,after:after.value,durationSeconds:1800,revisionId:revision.id,genuineMfa:true,modelRequests:0,deliverySent:false});
  console.log(JSON.stringify({trialVersion:after.value.version,trialStart:after.value.trialStart,trialEnd:after.value.trialEnd,seats:5,modelRequests:0,deliverySent:false}));return;
 }
 phase='validate-exact-recovered-lease';
 const leased=await load('external-delivery-leased-job.json'),job=validateExactLeasedDelivery(leased);
 const scoped=createScopedWorkerRpc({runtimeId:t.runtimeId,url:origin,serviceKey:admin});
 const raw=createWorkerRpc({url:origin,serviceKey:admin});
 const control=new PersistentDeliveryControl(scoped);
 // The reviewed SQL already leased the exact head. No batch or generic claim
 // runs here, so the four unrelated queued test fixtures stay unmaterialized.
 let selected=false;control.claimCommittedDelivery=async()=>{must(!selected,'ONE_EXISTING_LEASE_LIMIT');selected=true;return job;};
 const post=createExactSinglePost({job,persistIntent:e=>save('external-delivery-signed-request-intent.json',e),post:async(...args)=>{postCalls++;return pinnedHttpsPost(...args);}});
 const vault={read:async ref=>{
  must(ref==='w5/runtime/20261008/delivery/v1','EXACT_RUNTIME_SIGNING_KEY_REQUIRED');
  const r=await raw('wave5_edge_control',{p_runtime_id:t.runtimeId,p_action:'key',p_payload:{ref}});must(/^[a-f0-9]{64}$/.test(r?.value??''),'SERVER_SIGNING_KEY_REQUIRED');
  const b=Buffer.from(r.value,'hex');keyBuffers.push(b);return b;
 }};
 phase='one-controlled-signed-request';
 const outcome=await runDelivery({control,secrets:{deliveryKey:()=>control.deliverySecret(job,vault)},resolve:async hostname=>(await lookup(hostname,{all:true})).map(x=>x.address),post,now:Math.floor(Date.now()/1000),signal:AbortSignal.timeout(45000)});
 await save('external-delivery-send-result.json',{observedAt:new Date().toISOString(),projectId:t.projectId,deliveryId:t.deliveryId,invocationId:t.invocationId,usageEventId:t.usageEventId,leaseId:job.leaseId,attempt:2,controlledLocalWorker:true,hostedScheduledDispatch:false,postCalls,outcome,automaticRetries:0,persistedReceiptAndAccountingVerified:false});
 console.log(JSON.stringify({postCalls,outcome,persistedReceiptAndAccountingVerified:false}));
}
main().catch(async error=>{
 const result={observedAt:new Date().toISOString(),mode,phase,code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'PRIVATE_CONTROLLED_DELIVERY_STOP',postCalls,automaticRetry:false,secretsPrinted:false};
 await save('external-delivery-stop-'+Date.now()+'.json',result).catch(()=>{});console.error(JSON.stringify(result));process.exitCode=1;
}).finally(()=>{for(const b of keyBuffers)b.fill(0);keyBuffers=[];admin=null;anon=null;});
