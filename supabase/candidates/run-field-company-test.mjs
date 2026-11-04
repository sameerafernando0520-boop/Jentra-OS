// No network, connection string, linked project, migration ledger or install.
import assert from 'node:assert/strict';
import {readFile,readdir,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {PGlite} from '../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';
import {pgcrypto} from '../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
import {btree_gist} from '../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/btree_gist.js';
import {exercise} from './tests/field_confirmation.test.mjs';
import {exercise as governanceRegression} from './tests/field_sales_governance.test.mjs';
import {exercise as companyExercise} from './tests/field_company.test.mjs';

const prefixThrough='20260910135507_harden_receivables_reference_indexes.sql';
const employeeMigrations=['20260925181927_wave4_employee_foundation.sql','20260929224939_wave4_private_hr.sql'];

export function validateCandidate(sql) {
 assert.equal(typeof sql,'string');
 assert.ok(!/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im.test(sql),'Candidate cannot control transactions or include files.');
 assert.ok(sql.includes('create function api.field_sales_confirmation_subjects'),'Expected exact company workspace candidate.');
}
export async function main(args) {
 assert.deepEqual(args,['--run-isolated'],'Only --run-isolated is supported; no target options.');
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
  await db.exec('savepoint field_candidate');
  await load('supabase/candidates/run-field-company-test.mjs');
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
  assert.ok(Object.values(rollback).every(Boolean),'Candidate, fixtures, receipts and permission definition roll back.');
  await db.exec('rollback');
  rollback.baseline_removed=(await db.query("select to_regnamespace('core') is null and to_regnamespace('auth') is null and to_regnamespace('storage') is null removed")).rows[0].removed;
  assert.equal(rollback.baseline_removed,true,'The outer transaction removes the entire simulated baseline.');
  const output=new URL('../../docs/verification/field-company-20261102/',import.meta.url);await mkdir(output,{recursive:true});
  const report={atUtc:new Date().toISOString(),engine:'PGlite 0.5.12 / PostgreSQL 18',passed:checks.length,governanceRegressionPassed:governancePassed,confirmationPassed,companyPassed:checks.length-governancePassed-confirmationPassed,checks,rollback,sources,
   baseline:{prefixThrough,additionalMigrations:employeeMigrations,
    executionNormalization:'CRLF to LF in baseline migrations only; SHA-256 hashes bind the original unmodified source bytes.',
    rollbackFunctions:changedFunctions},
   installedMigration:false,deployed:false,hostedAccess:false,supabaseStackExecuted:false,
   boundary:'Exact repository migration prefix through 20260910135507 plus workforce foundation 20260925181927 and private HR 20260929224939, then governance, email-confirmation and company-workspace candidates, in an isolated PGlite transaction. Auth/Storage and provider acknowledgements are simulated. No email transport, hosted Supabase session, device acceptance, delivery acknowledgement or canonical progression is established. The company workspace rolls back independently and restores the original command body and ACL. Candidate schema, functions, ACLs, permission/entitlement changes and all fixtures/receipts roll back; outer rollback removes the baseline.'};
  await writeFile(new URL('postgres-result.json',output),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({passed:checks.length,rollback}));
 } finally {await db.exec('rollback').catch(()=>{});await db.close();}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 main(process.argv.slice(2)).catch(error=>{console.error(error.cause?.code??error.code??error.name,error.message);process.exitCode=1;});
}
