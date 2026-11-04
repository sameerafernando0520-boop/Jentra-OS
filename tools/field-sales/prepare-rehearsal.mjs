import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export const project='xpdoufauvrbdmxgngetv';
export const candidates=[
 'supabase/candidates/20261031090000_field_sales_governance.sql',
 'supabase/candidates/20261102090000_field_order_email_confirmation.sql',
 'supabase/candidates/20261102120000_field_confirmation_company_workspace.sql',
];
export const originalFunctions=[
 'core.has_permission(uuid,text,uuid,uuid)','core.list_capabilities(uuid)',
 'core.wave2_replay(uuid,text,uuid,text)','core.wave3_replay(uuid,text,uuid,uuid,text)',
 'core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)',
 'people.require_access(uuid,uuid,uuid,text)',
];
const quote=v=>"'"+v.replaceAll("'","''")+"'";
export async function prepare(args){
 assert.deepEqual(args,['--prepare-only'],'Only --prepare-only is supported. No database connection or install.');
 const root=new URL('../../',import.meta.url),out=new URL('docs/verification/field-rollout-20261103/',root);
 const sources={};const chunks=[];
 for(const path of candidates){
  const sql=await readFile(new URL(path,root),'utf8');
  assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(sql),'A candidate cannot control the rehearsal transaction.');
  sources[path]=createHash('sha256').update(sql).digest('hex');chunks.push('-- Source: '+path+'\n'+sql);
 }
 const functions=originalFunctions.map(quote).join(',');
 const definitions=`select coalesce(jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),'acl',p.proacl::text) order by p.oid),'[]') from pg_proc p where p.oid=any(array[${functions}]::regprocedure[])`;
 const permissions="select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.code)::text,'')) from core.permissions p";
 const entitlements="select md5(coalesce(jsonb_agg(to_jsonb(p) order by p.plan_code,p.entitlement_code)::text,'')) from billing.plan_entitlements p";
 const acls="select jsonb_agg(jsonb_build_object('schema',nspname,'acl',nspacl::text) order by nspname) from pg_namespace where nspname in('api','core','people','storage')";
 const policies="select md5(coalesce(jsonb_agg(to_jsonb(p) order by schemaname,tablename,policyname)::text,'')) from pg_policies p";
 const snapshot=`jsonb_build_object('definitions',(${definitions}),'permissions',(${permissions}),'entitlements',(${entitlements}),'schema_acls',(${acls}),'policies',(${policies}))`;
 const sql=`-- REVIEWED TARGET: ${project}. Complete buffer only. NEVER select a fragment.\n-- No COMMIT, migration ledger insert, Auth fixture, sender enablement or live order.\nbegin;\nset transaction isolation level repeatable read;\nset local lock_timeout='2s';\nset local statement_timeout='45s';\ndo $guard$ begin\n if current_setting('server_version_num')::integer/10000<>17 then raise exception 'POSTGRES_17_REQUIRED'; end if;\n if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_ALREADY_INSTALLED'; end if;\n if (select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations)<>'6ace1fe895a4615fa01746eb2632ae65' then raise exception 'MIGRATION_LEDGER_CHANGED_REVIEW_AGAIN'; end if;\nend $guard$;\ncreate temporary table field_rehearsal_before on commit drop as select ${snapshot} value;\nsavepoint field_rehearsal_candidate;\n${chunks.join('\n\n')}\n\n-- Assertions run on the actual complete hosted schema; no Auth identities are invented.\ndo $checks$ begin\n if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname like 'field_sales_confirmation_%' and has_function_privilege('anon',p.oid,'execute'))<>3 then raise exception 'ANONYMOUS_SURFACE_INVALID'; end if;\n if has_function_privilege('authenticated','api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)','execute') then raise exception 'LEGACY_COMMAND_BYPASS'; end if;\n if exists(select 1 from field_sales.confirmation_transport where enabled) then raise exception 'TRANSPORT_MUST_REMAIN_OFF'; end if;\n if to_regclass('field_sales.confirmation_one_current_request') is null then raise exception 'CURRENT_CHALLENGE_CONSTRAINT_MISSING'; end if;\nend $checks$;\nrollback to savepoint field_rehearsal_candidate;\ndo $restored$ begin\n if to_regnamespace('field_sales') is not null then raise exception 'CANDIDATE_NOT_ROLLED_BACK'; end if;\n if (select value from field_rehearsal_before) is distinct from ${snapshot} then raise exception 'ORIGINAL_STATE_NOT_RESTORED'; end if;\nend $restored$;\nrollback;\nselect jsonb_build_object('project',${quote(project)},'server_version',current_setting('server_version'),'schema_compatibility','three_candidates_composed_on_full_hosted_schema','anonymous_surface',3,'original_functions_acls_permissions_entitlements_policies_restored',true,'candidate_removed',to_regnamespace('field_sales') is null,'migration_count',(select count(*) from supabase_migrations.schema_migrations),'migration_versions_md5',(select md5(string_agg(version,',' order by version)) from supabase_migrations.schema_migrations),'migration_installed',false,'transport_enabled',false,'genuine_auth_flow_tested',false,'observed_at',clock_timestamp()) as field_sales_rehearsal;\n`;
 // Explicit RLS avoids a console auto-fix being appended after ROLLBACK, when
 // this session-local temporary table has already been removed.
 const protectedSql=sql.replace('savepoint field_rehearsal_candidate;',
  'alter table field_rehearsal_before enable row level security;\nsavepoint field_rehearsal_candidate;');
 await mkdir(out,{recursive:true});
 await writeFile(new URL('full-schema-rollback.sql',out),protectedSql);
 const manifest={project,mode:'prepare-only',sources,sqlSha256:createHash('sha256').update(protectedSql).digest('hex'),expectedMigrationVersionsMd5:'6ace1fe895a4615fa01746eb2632ae65',originalFunctions,temporarySnapshotRls:true,executionClaim:false,scope:'PostgreSQL 17 full-schema DDL/ACL compatibility and restoration only; genuine Auth, HTTP, device and business acceptance remain separate.'};
 await writeFile(new URL('rehearsal-plan.json',out),JSON.stringify(manifest,null,2)+'\n');
 return manifest;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 prepare(process.argv.slice(2)).then(r=>console.log(JSON.stringify({project:r.project,mode:r.mode,sources:Object.keys(r.sources).length,sqlSha256:r.sqlSha256}))).catch(()=>{console.error('REHEARSAL_PREPARATION_FAILED');process.exitCode=1;});
}
