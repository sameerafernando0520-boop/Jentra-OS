// No network, connection string, linked project, migration ledger or install.
import assert from 'node:assert/strict';
import {readFile,readdir,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {exercise} from './tests/field_confirmation.test.mjs';
import {exercise as governanceRegression} from './tests/field_sales_governance.test.mjs';
import {exercise as companyExercise} from './tests/field_company.test.mjs';
import {exercise as mailExercise} from './tests/field_mail.test.mjs';
import {exercise as progressionExercise} from './tests/field_progression.test.mjs';
import {exercise as deliveryExercise} from './tests/field_delivery.test.mjs';
import {diagnosePostingDateBoundary} from './tests/field_posting_date_boundary.mjs';

const prefixThrough='20260910135507_harden_receivables_reference_indexes.sql';
const employeeMigrations=['20260925181927_wave4_employee_foundation.sql','20260929224939_wave4_private_hr.sql'];

export function validateCandidate(sql) {
 assert.equal(typeof sql,'string');
 assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(sql),'Candidate cannot control transactions or include files.');
 assert.ok(sql.includes('create function api.field_sales_confirmation_subjects'),'Expected exact company workspace candidate.');
}
export async function main(args) {
 assert.deepEqual(args,['--run-isolated'],'Only --run-isolated is supported; no target options.');
 const {PGlite}=await import('../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js');
 const {pgcrypto}=await import('../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js');
 const {btree_gist}=await import('../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/btree_gist.js');
 const runtime=JSON.parse(await readFile(new URL('../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/package.json',import.meta.url),'utf8'));
 assert.equal(runtime.version,'0.5.12','Use the already-present pinned isolated runtime.');
 const db=new PGlite({extensions:{pgcrypto,btree_gist}}),sources={};
 const load=async path=>{
  const sql=await readFile(new URL('../../'+path,import.meta.url),'utf8');
  sources[path]=createHash('sha256').update(sql).digest('hex');return sql;
 };
 const checks=[];
 try {
  await db.exec(`begin;create role anon;create role authenticated;create role service_role bypassrls;create role authenticator;
   create schema extensions;create schema auth;create schema storage;
   create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
   create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
   alter table storage.objects enable row level security;
   grant usage on schema storage to authenticated;grant select,insert,update on storage.objects to authenticated;
   create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
    raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
   create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),not_after timestamptz);
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
   create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
   grant usage on schema auth,extensions to authenticated,anon,service_role;`);
  const names=(await readdir(new URL('../migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')&&n<=prefixThrough).sort();
  for(const name of names){
   const sql=(await load('supabase/migrations/'+name)).replaceAll('\r\n','\n');
   try {await db.exec(sql);} catch(error){throw Error('Baseline '+name+': '+error.message,{cause:error});}
  }
  for(const name of employeeMigrations){
   const sql=(await load('supabase/migrations/'+name)).replaceAll('\r\n','\n');
   try{await db.exec(sql);}catch(error){throw Error('Employee baseline '+name+': '+error.message,{cause:error});}
  }
  const changedFunctions=['core.has_permission(uuid,text,uuid,uuid)','core.list_capabilities(uuid)',
   'core.wave2_replay(uuid,text,uuid,text)','core.wave3_replay(uuid,text,uuid,uuid,text)',
   'core.bootstrap_tenant_impl(text,text,text,text,text,text,text,text,uuid)',
   'people.require_access(uuid,uuid,uuid,text)'];
  const definitions=()=>db.query(`select p.oid,p.proacl::text,pg_get_functiondef(p.oid) definition from pg_proc p
   where p.oid=any($1::regprocedure[]) order by p.oid`,[changedFunctions]);
  const before=await definitions();
  assert.equal(before.rows.length,changedFunctions.length,'Every modified original function is included in the rollback comparison.');
  const permissionsBefore=(await db.query("select md5(jsonb_agg(to_jsonb(p) order by p.code)::text) digest from core.permissions p")).rows[0].digest;
  const entitlementsBefore=(await db.query("select md5(jsonb_agg(to_jsonb(p) order by p.plan_code,p.entitlement_code)::text) digest from billing.plan_entitlements p")).rows[0].digest;
  const catalog=async()=>({scope:'Isolated repository baseline: column projection only; function semantics, ACLs, RLS and rollout behavior require the separate review register.',
   tables:Object.fromEntries((await db.query(`select table_schema||'.'||table_name name,
    jsonb_object_agg(column_name,jsonb_build_object('type',udt_name,'nullable',is_nullable='YES','default',column_default) order by ordinal_position) columns
    from information_schema.columns where table_schema not in('pg_catalog','information_schema','auth','storage','extensions')
    group by table_schema,table_name order by table_schema,table_name`)).rows.map(r=>[r.name,{columns:r.columns}]))});
  const schemaBefore=await catalog();
  await db.exec('savepoint field_candidate');
  await load('supabase/candidates/run-field-rollout-test.mjs');
  await load('workers/field-sales/mail_worker.mjs');
  const governance=await load('supabase/candidates/20261031090000_field_sales_governance.sql');
  await db.exec(governance);
  const emailChanged=['field_sales.entity(field_sales.order_requests)','field_sales.guard_order()'];
  const emailDefinitions=()=>db.query(`select p.oid,p.proacl::text,pg_get_functiondef(p.oid) definition from pg_proc p where p.oid=any($1::regprocedure[]) order by p.oid`,[emailChanged]);
  const emailBefore=await emailDefinitions();
  const schemaAcls=()=>db.query("select nspname,nspacl::text from pg_namespace where nspname in('api','field_sales') order by nspname");
  const schemaAclBefore=(await schemaAcls()).rows;
  await db.exec('savepoint email_candidate');
  const candidate=await load('supabase/candidates/20261102090000_field_order_email_confirmation.sql');
  await db.exec(candidate);
  await load('supabase/candidates/tests/field_sales_governance.test.mjs');
  await governanceRegression(db,checks);
  const governancePassed=checks.length;
  await load('supabase/candidates/tests/field_confirmation.test.mjs');
  await exercise(db,checks);
  const confirmationPassed=checks.length-governancePassed;
  await db.exec('reset role');
  const originalCommandDefinition=(await db.query("select proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid='api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)'::regprocedure")).rows;
  await db.exec('savepoint company_candidate');
  const company=await load('supabase/candidates/20261102120000_field_confirmation_company_workspace.sql');
  validateCandidate(company);await db.exec(company);
  await load('supabase/candidates/tests/field_company.test.mjs');
  await companyExercise(db,checks);
  const companyPassed=checks.length-governancePassed-confirmationPassed;
  await db.exec('reset role');
  const readyDefinition=(await db.query("select proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid='field_sales.confirmation_ready(uuid)'::regprocedure")).rows;
  await db.exec('savepoint mail_candidate');
  const mail=await load('supabase/candidates/20261103090000_field_sales_mail_worker.sql');
  assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(mail));
  await db.exec(mail);
  await load('supabase/candidates/tests/field_mail.test.mjs');
  await mailExercise(db,checks);
  const mailPassed=checks.length-governancePassed-confirmationPassed-companyPassed;
  await db.exec('reset role');
  const progressionSignatures=['api.get_sales_order_credit_preview(uuid,uuid,uuid,uuid)',
   'api.transition_operational_document(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
   'api.reserve_sales_order_stock(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
   'sales.flow_upsert(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
   'sales.flow_post(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
   'field_sales.guard_order()','field_sales.entity(field_sales.order_requests)',
   'field_sales.confirmation_status(field_sales.order_requests)'];
  const progressionDefinitions=()=>db.query('select oid,proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid=any($1::regprocedure[]) order by oid',[progressionSignatures]);
  const progressionBefore=(await progressionDefinitions()).rows;
  await db.exec('savepoint progression_candidate');
  const progression=await load('supabase/candidates/20261103100000_field_sales_company_progression.sql');
  assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(progression));await db.exec(progression);
  await load('supabase/candidates/tests/field_progression.test.mjs');
  const progressionContext=await progressionExercise(db,checks);
  const progressionPassed=checks.length-governancePassed-confirmationPassed-companyPassed-mailPassed;
  await db.exec('reset role');
  const deliverySignatures=['api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)',
   'field_sales.mail_current(uuid,text)','field_sales.mail_dispatch(uuid,text,text,text,text)','field_sales.mail_sources(uuid[])',
   'field_sales.entity(field_sales.order_requests)'];
  const deliveryDefinitions=()=>db.query('select oid,proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid=any($1::regprocedure[]) order by oid',[deliverySignatures]);
  const deliveryBefore=(await deliveryDefinitions()).rows;
  await db.exec('savepoint delivery_candidate');
  const delivery=await load('supabase/candidates/20261103110000_field_sales_delivery_acknowledgement.sql');
  assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(delivery));await db.exec(delivery);
  await load('supabase/candidates/tests/field_delivery.test.mjs');
  await deliveryExercise(db,checks,progressionContext);
  const deliveryPassed=checks.length-governancePassed-confirmationPassed-companyPassed-mailPassed-progressionPassed;
  await db.exec('reset role');
  await load('supabase/candidates/tests/field_posting_date_boundary.mjs');
  const postingDateBoundary=await diagnosePostingDateBoundary(db);
  await db.exec('reset role');const schemaAfter=await catalog();
  await db.exec('reset role;rollback to savepoint delivery_candidate');
  assert.deepEqual((await deliveryDefinitions()).rows,deliveryBefore);
  assert.equal((await db.query("select to_regclass('field_sales.delivery_challenges') is null and to_regclass('field_sales.delivery_responses') is null and to_regprocedure('api.field_sales_delivery_request_code(text)') is null removed")).rows[0].removed,true);
  await db.exec('reset role;rollback to savepoint progression_candidate');
  assert.deepEqual((await progressionDefinitions()).rows,progressionBefore);
  assert.equal((await db.query("select to_regclass('field_sales.order_progressions') is null and to_regclass('field_sales.progression_permits') is null removed")).rows[0].removed,true);
  await db.exec('reset role;rollback to savepoint mail_candidate');
  assert.equal((await db.query("select to_regclass('field_sales.mail_policies') is null and to_regclass('field_sales.mail_jobs') is null and to_regprocedure('api.field_sales_mail_claim(uuid[],uuid)') is null and to_regprocedure('api.field_sales_mail_step(uuid,uuid,uuid,text,text,text)') is null removed")).rows[0].removed,true);
  assert.deepEqual((await db.query("select proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid='field_sales.confirmation_ready(uuid)'::regprocedure")).rows,readyDefinition);
  await db.exec('reset role;rollback to savepoint company_candidate');
  const companyRemoved=(await db.query(`select to_regprocedure('api.field_sales_confirmation_subjects(uuid,uuid,uuid,uuid,integer)') is null
   and to_regprocedure('api.field_sales_confirmation_challenges(uuid,uuid,uuid,uuid,uuid,integer)') is null
   and to_regprocedure('api.field_sales_confirmation_company_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)') is null
   and to_regclass('field_sales.confirmation_one_current_request') is null
   and to_regclass('field_sales.confirmation_contacts') is not null removed`)).rows[0].removed;
  assert.equal(companyRemoved,true,'Company workspace extension rolls back independently.');
  assert.deepEqual((await db.query("select proacl::text,pg_get_functiondef(oid) definition from pg_proc where oid='api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)'::regprocedure")).rows,originalCommandDefinition,'Original command ACL and body restore after company extension.');
  await db.exec('reset role;rollback to savepoint email_candidate');
  assert.deepEqual((await emailDefinitions()).rows,emailBefore.rows,'Email extension restores the prior governance functions and ACLs.');
  assert.deepEqual((await schemaAcls()).rows,schemaAclBefore,'Anonymous API and private worker schema grants roll back.');
  const emailRemoved=(await db.query(`select to_regclass('field_sales.confirmation_contacts') is null
   and to_regclass('field_sales.confirmation_transport') is null and to_regclass('field_sales.confirmation_challenges') is null
   and to_regclass('field_sales.order_responses') is null
   and to_regprocedure('api.field_sales_confirmation_verify(text,text)') is null
   and to_regprocedure('api.field_sales_confirmation_request_code(text)') is null
   and to_regprocedure('api.field_sales_confirmation_respond(text,text,text,text,boolean)') is null
   and to_regprocedure('api.field_sales_confirmation_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb,bigint)') is null
   and to_regprocedure('api.field_sales_confirmation_contacts(uuid,uuid,uuid,uuid,uuid,integer)') is null
   and to_regprocedure('api.field_sales_confirmation_receipt(uuid,uuid,uuid,uuid)') is null
   and to_regclass('field_sales.order_requests') is not null removed`)).rows[0].removed;
  assert.equal(emailRemoved,true,'Email candidate rolls back independently of its governance prerequisite.');
  await db.exec('reset role;rollback to savepoint field_candidate');
  const rollback=(await db.query(`select to_regnamespace('field_sales') is null candidate_removed,
   (select count(*) from auth.users)=0 fixtures_removed,(select count(*) from core.tenants)=0 tenants_removed,
   (select count(*) from auth.sessions)=0 auth_sessions_removed,
   (select count(*) from core.command_receipts)=0 receipts_removed,
   (select count(*) from people.employees)=0 employee_fixtures_removed,
   (select count(*) from people_private.account_links)=0 employee_links_removed,
   (select md5(jsonb_agg(to_jsonb(p) order by p.code)::text) from core.permissions p)=$1 original_permissions_restored,
   (select md5(jsonb_agg(to_jsonb(p) order by p.plan_code,p.entitlement_code)::text) from billing.plan_entitlements p)=$2 original_entitlements_restored,
   not exists(select 1 from pg_policies where policyname like 'field_%') policies_removed`,[permissionsBefore,entitlementsBefore])).rows[0];
  assert.deepEqual((await definitions()).rows,before.rows,'Every modified original function and ACL is restored.');
  rollback.original_functions_and_acls_restored=true;
  rollback.email_extension_removed=emailRemoved;
  rollback.governance_functions_and_acls_restored=true;
  rollback.api_schema_acl_restored=true;
  rollback.private_schema_acl_restored=true;
  rollback.company_workspace_removed=companyRemoved;
  rollback.original_confirmation_command_acl_restored=true;
  rollback.mail_worker_extension_removed=true;
  rollback.original_confirmation_ready_restored=true;
  rollback.company_progression_extension_removed=true;
  rollback.canonical_commands_and_acls_restored=true;
  rollback.delivery_extension_removed=true;
  rollback.mail_dispatch_and_recipient_rate_restored=true;
  assert.ok(Object.values(rollback).every(Boolean),'Candidate, fixtures, receipts and permission definition roll back.');
  await db.exec('rollback');
  rollback.baseline_removed=(await db.query("select to_regnamespace('core') is null and to_regnamespace('auth') is null and to_regnamespace('storage') is null removed")).rows[0].removed;
  assert.equal(rollback.baseline_removed,true,'The outer transaction removes the entire simulated baseline.');
  const output=new URL('../../docs/verification/field-rollout-20261103/',import.meta.url);await mkdir(output,{recursive:true});
  await writeFile(new URL('schema-before.json',output),JSON.stringify(schemaBefore,null,2)+'\n');
  await writeFile(new URL('schema-after.json',output),JSON.stringify(schemaAfter,null,2)+'\n');
  const report={atUtc:new Date().toISOString(),engine:'PGlite 0.5.12 / PostgreSQL 18',passed:checks.length,governanceRegressionPassed:governancePassed,confirmationPassed,companyPassed,mailPassed,progressionPassed,deliveryPassed,postingDateBoundary,checks,rollback,sources,
   baseline:{prefixThrough,additionalMigrations:employeeMigrations,
    executionNormalization:'CRLF to LF in baseline migrations only; SHA-256 hashes bind the original unmodified source bytes.',
    rollbackFunctions:changedFunctions},
   installedMigration:false,deployed:false,hostedAccess:false,supabaseStackExecuted:false,
   boundary:'Exact repository migration prefix through 20260910135507 plus workforce foundation 20260925181927 and private HR 20260929224939, followed by all six Sales candidates, in an isolated PGlite transaction. Auth/Storage identities, MFA claims and Resend responses are simulated. Canonical order confirmation, non-stocked partial-delivery posting and independent recipient quantity acknowledgement are exercised on synthetic fixtures only. No real email, hosted session, physical-device acceptance or company signoff is established. Each extension restores prior function bodies and ACLs independently. Candidate schema, permissions/entitlements and all fixtures/receipts roll back; outer rollback removes the baseline.'};
  await writeFile(new URL('postgres-result.json',output),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({passed:checks.length,rollback}));
 } finally {await db.exec('rollback').catch(()=>{});await db.close();}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 main(process.argv.slice(2)).catch(error=>{console.error(error.cause?.code??error.code??error.name,error.message);process.exitCode=1;});
}
