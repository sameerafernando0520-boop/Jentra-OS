import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';

const base='docs/verification/ai-integrations-test-20261103/';
const load=async n=>JSON.parse(await readFile(base+n,'utf8'));
const refresh=process.argv[2]==='--refresh';
if(process.argv.length>3||process.argv[2]&&!refresh)throw Error('PREPARATION_MODE_INVALID');
if(refresh){let approved=false;try{await readFile(base+'external-delivery-owner-approval.json');approved=true;}catch(e){if(e.code!=='ENOENT')throw e;}if(approved)throw Error('APPROVED_CANDIDATE_IS_FROZEN');}
const s=await load('external-delivery-after-rollback.json');
for(const f of s.functions){
 const raw=Buffer.from(f.bodyBase64,'base64');
 if(createHash('md5').update(raw).digest('hex')!==f.bodyMd5)throw Error('EXACT_DATABASE_SOURCE_REQUIRED');
 f.body=raw.toString('utf8');
}
const receiver=await load('external-receiver-readback.json');
const tenant='babe6c86-a764-4d3a-80a3-952a7c096c2c',runtime='778237e3-3d4e-4871-8cc9-e08b07b989c7';
const delivery='091e0c08-5038-4169-8e28-ffde9e0d51c8',entity='caa2bb06-219a-47e9-8132-66d1271b0ffd',branch='3813692c-f0de-4c69-8e34-d56cf54695b1';
const md5=v=>createHash('md5').update(v).digest('hex');
const sha=v=>createHash('sha256').update(v).digest('hex');
const literal=v=>"'"+String(v).replaceAll("'","''")+"'";
if(s.projectId!=='xpdoufauvrbdmxgngetv'||s.delivery?.id!==delivery||s.delivery.state!=='retry'||s.delivery.attempt!==1||s.reservation||s.usage||s.receiverReceipts.length||s.outcomes.length||s.attempts.length!==1||s.reviews.length!==1||s.reviews[0].action!=='not_sent'||s.jobs.length!==3||s.jobs.some(j=>j.active)||!receiver.allModulesMatchLocal||receiver.receiver.version!==8)throw Error('EXACT_RECOVERABLE_PREFLIGHT_REQUIRED');
const prefix=`begin;\nset local statement_timeout='10s';\nset local lock_timeout='3s';\nset local search_path='';\n`;
const functionGuard=s.functions.map(f=>` if not exists(select 1 from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace where n.nspname=${literal(f.schema)} and p.proname=${literal(f.name)} and pg_catalog.pg_get_function_identity_arguments(p.oid)=${literal(f.args)} and md5(p.prosrc)=${literal(md5(f.body))} and p.prosecdef=${f.securityDefiner} and to_jsonb(p.proconfig) is not distinct from ${literal(JSON.stringify(f.config))}::jsonb and p.proacl::text is not distinct from ${literal(f.acl)}) then raise exception 'REVIEWED_FUNCTION_CHANGED';end if;`).join('\n');
const preimage=`do $guard$ begin\n${functionGuard}
 if not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id='${tenant}' and allowed) or not exists(select 1 from core.branches where id='${branch}' and tenant_id='${tenant}' and legal_entity_id='${entity}' and status='active') then raise exception 'EXACT_ACTIVE_SYNTHETIC_RT1_REQUIRED';end if;
 if (select count(*) from core.memberships where tenant_id='${tenant}' and status='active')<>5 or (select jsonb_agg(permission_code order by permission_code) from core.role_permissions where role_id='28d81f05-27c5-4673-85d5-eeb51a515f27') is distinct from '["ai.proposals.view","analytics.view","crm.opportunities.view"]'::jsonb then raise exception 'APPROVED_MEMBERSHIP_AND_READ_PERMISSIONS_CHANGED';end if;
 if not exists(select 1 from billing.plan_entitlements where plan_code='w5_runtime_20261008' and entitlement_code='quota.webhook.deliveries' and enabled and numeric_limit=100) then raise exception 'UNCHANGED_WEBHOOK_CAP_REQUIRED';end if;
 perform 1 from intelligence_control.delivery_heads where id='${delivery}' for update;
 if (select to_jsonb(d) from intelligence_control.delivery_heads d where id='${delivery}') is distinct from ${literal(JSON.stringify(s.delivery))}::jsonb then raise exception 'DELIVERY_PREIMAGE_CHANGED';end if;
 if exists(select 1 from intelligence_control.usage_reservations where invocation_id='${s.delivery.invocation_id}') or exists(select 1 from intelligence_control.usage_events where invocation_id='${s.delivery.invocation_id}') or exists(select 1 from intelligence_control.delivery_outcomes where delivery_id='${delivery}') or exists(select 1 from intelligence_control.edge_receiver_receipts where subscription_id='${s.delivery.subscription_id}' and event_id='${s.delivery.event_id}') then raise exception 'OUTCOME_RECONCILIATION_REQUIRED';end if;
 if (select count(*) from intelligence_control.delivery_attempts where delivery_id='${delivery}')<>1 or (select jsonb_agg(to_jsonb(r) order by recorded_at) from intelligence_control.delivery_reviews r where delivery_id='${delivery}') is distinct from ${literal(JSON.stringify(s.reviews))}::jsonb then raise exception 'ATTEMPT_REVIEW_CHANGED';end if;
 if (select count(*) from intelligence_control.delivery_heads where tenant_id='${tenant}')<>1 then raise exception 'EXACT_SINGLE_HEAD_REQUIRED';end if;
 if (select count(*) from cron.job where jobid in(4,5,6) and not active and jobname in('jentra-w5-20261009-delivery','jentra-w5-20261009-subscription','jentra-w5-20261009-health'))<>3 then raise exception 'PAUSED_JOBS_REQUIRED';end if;
 if (select jsonb_agg(to_jsonb(x) order by id) from intelligence_control.integration_subscriptions x where tenant_id='${tenant}') is distinct from ${literal(JSON.stringify(s.subscriptions))}::jsonb then raise exception 'SUBSCRIPTIONS_CHANGED';end if;
end $guard$;\n`;
const scope=s.runtimeScopes[0],edge=s.edgeAuthority;
const authority=`do $authority_guard$ begin
 perform 1 from intelligence_control.runtime_worker_scopes where runtime_id='${runtime}' for update;
 perform 1 from intelligence_control.edge_authorities where runtime_id='${runtime}' for update;
 if (select count(*) from intelligence_control.runtime_worker_scopes where runtime_id='${runtime}')<>1 or not exists(select 1 from intelligence_control.runtime_worker_scopes where runtime_id='${runtime}' and tenant_id='${tenant}' and legal_entity_id='${entity}' and branch_id='${branch}' and enabled and issued_at=${literal(scope.issuedAt)}::timestamptz and expires_at=${literal(scope.expiresAt)}::timestamptz and expires_at<=statement_timestamp()) then raise exception 'EXPIRED_EXACT_SCOPE_REQUIRED';end if;
 if not exists(select 1 from intelligence_control.edge_authorities where runtime_id='${runtime}' and enabled and issued_at=${literal(edge.issuedAt)}::timestamptz and expires_at=${literal(edge.expiresAt)}::timestamptz and expires_at<=statement_timestamp() and job_ids=array[4,5,6]::bigint[]) then raise exception 'EXPIRED_EXACT_EDGE_AUTHORITY_REQUIRED';end if;
end $authority_guard$;
update intelligence_control.runtime_worker_scopes set issued_at=statement_timestamp(),expires_at=statement_timestamp()+interval '30 minutes' where runtime_id='${runtime}' and tenant_id='${tenant}' and legal_entity_id='${entity}' and branch_id='${branch}';
update intelligence_control.edge_authorities set issued_at=statement_timestamp(),expires_at=statement_timestamp()+interval '30 minutes' where runtime_id='${runtime}';
`;
const active=`do $active_guard$ begin
 perform 1 from billing.tenant_subscriptions where tenant_id='${tenant}' for update;
 if not exists(select 1 from billing.tenant_subscriptions where tenant_id='${tenant}' and plan_code='w5_runtime_20261008' and seats=5 and status='trialing' and version=6 and trial_started_at<=statement_timestamp() and trial_ends_at>statement_timestamp()+interval '2 minutes' and trial_ends_at-trial_started_at=interval '30 minutes') then raise exception 'APPROVED_THIRTY_MINUTE_TRIAL_REQUIRED';end if;
 if not intelligence_control.runtime_scope_allowed('${runtime}','${tenant}','${entity}','${branch}') or not exists(select 1 from intelligence_control.edge_authorities where runtime_id='${runtime}' and enabled and issued_at<=statement_timestamp() and expires_at>statement_timestamp()+interval '2 minutes') then raise exception 'APPROVED_RUNTIME_AND_EDGE_WINDOW_REQUIRED';end if;
 perform intelligence_control.quota_limit('${tenant}','webhook.deliveries');
end $active_guard$;\n`;
const lease=`update intelligence_control.delivery_heads d set period_start=s.trial_started_at,period_end=s.trial_ends_at,attempt=2,state='leased',lease_id=gen_random_uuid(),lease_until=statement_timestamp()+interval '60 seconds'
 from billing.tenant_subscriptions s where d.id='${delivery}' and s.tenant_id=d.tenant_id;
insert into intelligence_control.delivery_attempts(tenant_id,delivery_id,attempt,lease_id,key_version,subscription_version,claimed_at)
 select d.tenant_id,d.id,d.attempt,d.lease_id,s.key_version,s.version,statement_timestamp() from intelligence_control.delivery_heads d join intelligence_control.integration_subscriptions s on s.tenant_id=d.tenant_id and s.id=d.subscription_id where d.id='${delivery}';
select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),'job',intelligence_control.delivery_authorize(d.id,d.lease_id),'leaseUntil',d.lease_until,'exactHeadOnly',(select count(*)=1 from intelligence_control.delivery_heads where tenant_id='${tenant}'),'attemptCount',(select count(*) from intelligence_control.delivery_attempts where delivery_id=d.id),'receipts',(select count(*) from intelligence_control.edge_receiver_receipts where tenant_id='${tenant}'),'reservationAbsent',not exists(select 1 from intelligence_control.usage_reservations where invocation_id=d.invocation_id),'scheduledJobsPaused',not exists(select 1 from cron.job where jobid in(4,5,6) and active)) as verified_evidence from intelligence_control.delivery_heads d where d.id='${delivery}';\n`;
const trialFixture=`-- Rollback-only fixture: no API/human MFA is claimed by this temporary database setup.\nupdate billing.tenant_subscriptions set trial_started_at=statement_timestamp(),trial_ends_at=statement_timestamp()+interval '30 minutes',version=6 where tenant_id='${tenant}' and version=5 and plan_code='w5_runtime_20261008' and seats=5;\n`;
const files={
 'external-delivery-renew-authority.sql':prefix+preimage+active.replace(/if not intelligence_control\.runtime_scope_allowed[\s\S]*?end if;\n/,'')+authority+`select jsonb_build_object('projectId','xpdoufauvrbdmxgngetv','observedAt',statement_timestamp(),'runtimeExpiresAt',(select expires_at from intelligence_control.runtime_worker_scopes where runtime_id='${runtime}' and branch_id='${branch}'),'edgeExpiresAt',(select expires_at from intelligence_control.edge_authorities where runtime_id='${runtime}'),'jobsPaused',not exists(select 1 from cron.job where jobid in(4,5,6) and active)) as verified_evidence;\ncommit;\n`,
 'external-delivery-lease.sql':prefix+preimage+active+lease+'commit;\n',
 'external-delivery-rollback.sql':prefix+preimage+trialFixture+authority+active+lease+'rollback;\n',
};
const options=refresh?{}:{flag:'wx'};
const artifacts=[];for(const [name,sql] of Object.entries(files)){await writeFile(base+name,sql,options);artifacts.push({path:base+name,sha256:sha(sql)});}
for(const name of ['external-delivery-acceptance-state.sql','external-delivery-after-rollback.json','external-receiver-readback.json'])artifacts.push({path:base+name,sha256:sha(await readFile(base+name))});
const sourcePaths=['tools/wave5/run_external_delivery_20261103.mjs','tools/wave5/external_delivery_once_20261103.mjs','tools/wave5/supabase_http_transport.mjs','tools/wave5/runtime_contract.mjs','tools/wave5/runtime_fixture_spec.mjs','workers/wave5/bounded_json.mjs','workers/wave5/persistent_control.mjs','workers/wave5/scoped_runtime.mjs','workers/wave5/worker_runtime.mjs','workers/wave5/integration_policy.mjs','workers/wave5/provider_credentials_20261014_r5_v7.mjs'];
const sources=[];for(const p of sourcePaths)sources.push({path:p,sha256:sha(await readFile(p))});
await writeFile(base+'external-delivery-recovery-candidate.json',JSON.stringify({preparedAt:new Date().toISOString(),projectId:s.projectId,approvalRequired:true,executed:false,deliveryId:delivery,invocationId:s.delivery.invocation_id,usageEventId:s.delivery.usage_event_id,eventId:s.delivery.event_id,originalPeriod:{start:s.delivery.period_start,end:s.delivery.period_end},expectedAttempt:2,trialDurationSeconds:1800,runtimeDurationSeconds:1800,edgeAuthorityDurationSeconds:1800,maximumSignedRequests:1,automaticRetries:0,materializeOtherDeliveries:false,newDeliveryOrInvocationIds:false,scheduledJobsRemainPaused:true,modelRequests:0,receiverDeployed:false,controlledLocalWorker:true,hostedScheduledDispatch:false,artifacts,sources},null,2)+'\n',options);
console.log(JSON.stringify({preparedFiles:artifacts.length,liveMutations:0,sends:0,approvalRequired:true}));
