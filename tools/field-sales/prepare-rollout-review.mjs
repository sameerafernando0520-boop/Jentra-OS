// File preparation only. Deliberately has no database, CLI, browser or fetch dependency.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {candidates as firstThree,originalFunctions,project} from './prepare-rehearsal.mjs';
export const candidates=[...firstThree,
 'supabase/candidates/20261103090000_field_sales_mail_worker.sql',
 'supabase/candidates/20261103100000_field_sales_company_progression.sql',
 'supabase/candidates/20261103110000_field_sales_delivery_acknowledgement.sql'];
const hash=s=>createHash('sha256').update(s).digest('hex');
const quote=s=>"'"+s.replaceAll("'","''")+"'";
export async function prepareReview(args){
 assert.deepEqual(args,['--prepare-only'],'Only file preparation is supported. Execution requires separate authorization.');
 const root=new URL('../../',import.meta.url),out=new URL('docs/verification/field-rollout-20261103/review/',root);
 const sources={},chunks=[];
 for(const path of candidates){const sql=await readFile(new URL(path,root),'utf8');
  assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(sql));
  sources[path]=hash(sql);chunks.push('-- Source: '+path+'\n'+sql);
 }
 const signatures=[...originalFunctions,
  'api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid)',
  'api.transition_operational_document(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
  'api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
  'sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
  'sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)'];
 const catalog=`select jsonb_build_object(
 'functions',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'body',pg_get_functiondef(p.oid),'acl',p.proacl::text) order by p.oid) from pg_proc p where p.oid=any(array[${signatures.map(quote).join(',')}]::regprocedure[])),
 'permissions',(select md5(jsonb_agg(to_jsonb(p) order by code)::text) from core.permissions p),
 'entitlements',(select md5(jsonb_agg(to_jsonb(p) order by plan_code,entitlement_code)::text) from billing.plan_entitlements p),
 'schema_acls',(select jsonb_agg(jsonb_build_object('name',nspname,'acl',nspacl::text) order by nspname) from pg_namespace where nspname in('api','core','people','storage','sales')),
 'policies',(select md5(jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname)::text) from pg_policies p))`;
 const guard=`do $guard$ begin
 if current_setting('server_version_num')::integer/10000<>17 then raise exception 'POSTGRES_17_REQUIRED'; end if;
 if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_ALREADY_INSTALLED'; end if;
 if (select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations)<>'6ace1fe895a4615fa01746eb2632ae65' then raise exception 'MIGRATION_LEDGER_CHANGED_REVIEW_AGAIN'; end if;
end $guard$;`;
 const checks=`do $checks$ begin
 if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname like 'field_sales_%' and has_function_privilege('anon',p.oid,'execute'))<>6 then raise exception 'ANONYMOUS_SURFACE_INVALID'; end if;
 if exists(select 1 from field_sales.confirmation_transport where enabled) or exists(select 1 from field_sales.mail_policies where enabled) then raise exception 'MAIL_MUST_REMAIN_DISABLED'; end if;
 if has_function_privilege('authenticated','api.field_transition_canonical(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','execute') then raise exception 'CANONICAL_BYPASS'; end if;
 if has_function_privilege('anon','api.field_sales_mail_claim(uuid[],uuid)','execute') or has_function_privilege('authenticated','api.field_sales_mail_claim(uuid[],uuid)','execute') then raise exception 'WORKER_PUBLIC'; end if;
 if not has_function_privilege('service_role','api.field_sales_mail_claim(uuid[],uuid)','execute') then raise exception 'WORKER_GRANT_MISSING'; end if;
 if to_regclass('field_sales.delivery_one_current_challenge') is null then raise exception 'DELIVERY_CURRENT_CONSTRAINT_MISSING'; end if;
 if exists(select 1 from field_sales.order_progressions) or exists(select 1 from field_sales.delivery_responses) then raise exception 'REHEARSAL_MUST_NOT_CREATE_BUSINESS_DATA'; end if;
end $checks$;`;
 const sql=`-- PREPARED ONLY: six-candidate rehearsal requires NEW approval, distinct from the approved three-candidate trial.
-- Target ${project}; complete buffer only; no selected fragments. No migration ledger writes or email.
begin;
set transaction isolation level repeatable read;
set local lock_timeout='2s';
set local statement_timeout='45s';
${guard}
create temporary table field_rollout_before on commit drop as ${catalog};
alter table field_rollout_before rename column jsonb_build_object to value;
alter table field_rollout_before enable row level security;
savepoint field_rollout_candidate;
${chunks.join('\n\n')}
${checks}
rollback to savepoint field_rollout_candidate;
do $restored$ begin
 if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_NOT_ROLLED_BACK'; end if;
 if (select value from field_rollout_before) is distinct from (${catalog}) then raise exception 'ORIGINAL_STATE_NOT_RESTORED'; end if;
end $restored$;
rollback;
select jsonb_build_object('project',${quote(project)},'mode','six_candidate_rollback_only','candidate_removed',to_regnamespace('field_sales') is null,'migration_installed',false,'mail_enabled',false,'original_state_restored',true,'genuine_auth_tested',false,'observed_at',clock_timestamp()) as field_rollout_rehearsal;
`;
 await mkdir(out,{recursive:true});await writeFile(new URL('six-candidate-rollback.sql',out),sql);
 const compatibilityItems=[
  {id:'FS-COMPAT-01',severity:'breaking_for_restricted_principals',change:'Restricted representatives lose broad legacy CRM, commerce, export and file paths.',requirement:'Inventory affected integrations and dated portfolios; coordinated Sales client and capability rollout.'},
  {id:'FS-COMPAT-02',severity:'breaking_for_governed_confirmation',change:'Governed order confirmation requires independent current MFA company authority, accepted exact customer response and a reviewed fresh credit digest.',requirement:'Enable the new company client and allocate sales.field.orders.progress explicitly; older clients fail closed for governed orders.'},
  {id:'FS-COMPAT-03',severity:'potentially_breaking_for_hosted_schema',change:'Canonical API/private commerce functions are wrapped/renamed; private aliases lose client EXECUTE grants.',requirement:'Rehearse all six against the current complete hosted schema and inspect any installed function dependencies before persistent installation.'},
  {id:'FS-COMPAT-04',severity:'potentially_breaking_for_operations',change:'Mail delivery needs a live worker, verified Resend sender, secret versions and per-organization allowlist/policy; all default off.',requirement:'Complete sender/mailbox/HTTP pilot and monitoring before enabling a company.'}
 ].map(x=>({...x,ownerAccepted:false}));
 const manifest={project,mode:'prepare-only',preparedAtUtc:new Date().toISOString(),candidates:sources,
  sqlSha256:hash(sql),expectedMigrationVersionsMd5:'6ace1fe895a4615fa01746eb2632ae65',originalFunctionSignatures:signatures,
  providerChoice:'verified-domain-resend',providerChoiceSource:'Explicit user reply, 2026-11-03',
  installationAuthorized:false,deploymentAuthorized:false,sixCandidateHostedRehearsalAuthorized:false,
  threeCandidateHostedEvidence:'../hosted-rehearsal.json',compatibilityItems,
  pending:['sender domain and address','approved pilot mailbox','server-side Resend and HMAC secrets','six-candidate hosted rollback authorization/result','installation and deployment authorization','genuine Auth/MFA sessions and device checks','named company pilot signoff'],
  boundary:'Prepared review artifact only. Does not expand the prior three-candidate approval or execute any SQL.'};
 await writeFile(new URL('rollout-plan.json',out),JSON.stringify(manifest,null,2)+'\n');
 const spec={type:'database',pattern:'schema_change',source:'Jentra hosted PostgreSQL 17 baseline, 130 migrations',target:'Six reviewed Sales candidates; default disabled',
  description:'Portfolio governance, explicit company order progression and independent delivery quantity evidence with a private Resend worker.',
  constraints:{max_downtime_minutes:0,data_volume_gb:0,dependencies:['Sales web/mobile','desktop Sales','canonical commerce APIs','Supabase Auth/MFA','private mail worker','Resend verified domain'],special_requirements:['candidate_rollback_first','no_email_during_rehearsal','preserve_employee_app','explicit_per_company_pilot']},
  tables_to_migrate:[],schema_changes:[],note:'No existing-row migration or backfill. Generated generic plan must be read with the concrete phase and rollback runbook in rollout-runbook.md.'};
 await writeFile(new URL('migration-spec.json',out),JSON.stringify(spec,null,2)+'\n');
 return manifest;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))prepareReview(process.argv.slice(2))
 .then(r=>console.log(JSON.stringify({mode:r.mode,candidates:Object.keys(r.candidates).length,sqlSha256:r.sqlSha256,executed:false})))
 .catch(()=>{console.error('ROLLOUT_REVIEW_PREPARATION_FAILED');process.exitCode=1;});
