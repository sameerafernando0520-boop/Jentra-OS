// Disposable, local-only old/current-baseline composition. No target options.
import assert from 'node:assert/strict';
import {readFile,readdir,mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {exercise as governance} from './tests/field_sales_governance.test.mjs';
import {exercise as confirmation} from './tests/field_confirmation.test.mjs';
import {exercise as company} from './tests/field_company.test.mjs';
import {exercise as mail} from './tests/field_mail.test.mjs';
import {exercise as progression} from './tests/field_progression.test.mjs';
import {exercise as delivery} from './tests/field_delivery.test.mjs';
import {exerciseBusinessDate} from './tests/sales_business_date.test.mjs';

const candidate='20261105100000_sales_legal_entity_business_date.sql';
const six=['20261031090000_field_sales_governance.sql','20261102090000_field_order_email_confirmation.sql',
 '20261102120000_field_confirmation_company_workspace.sql','20261103090000_field_sales_mail_worker.sql',
 '20261103100000_field_sales_company_progression.sql','20261103110000_field_sales_delivery_acknowledgement.sql'];
const runtime='../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/';
const prefixThrough='20260910135507_harden_receivables_reference_indexes.sql';
const staff=['20260925181927_wave4_employee_foundation.sql','20260929224939_wave4_private_hr.sql'];
const excluded=['20261009123000_wave5_supabase_schedule.sql'];
export function validateArgs(args){
 assert.ok(args[0]==='--run-isolated' && (args.length===1 || (args.length===2 && args[1]==='--record-evidence')),
  'Use --run-isolated with optional --record-evidence. Hosted and linked targets are forbidden.');
}
export function validateCandidate(sql){assert.doesNotMatch(sql,/^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im);}
export async function main(args){
 validateArgs(args);
 assert.equal(JSON.parse(await readFile(new URL(runtime+'package.json',import.meta.url),'utf8')).version,'0.5.12');
 const {PGlite}=await import(runtime+'dist/index.js');
 const {pgcrypto}=await import(runtime+'dist/contrib/pgcrypto.js');
 const {btree_gist}=await import(runtime+'dist/contrib/btree_gist.js');
 const sources={},results=[];
 const load=async path=>{const s=await readFile(new URL('../../'+path,import.meta.url),'utf8');sources[path]=createHash('sha256').update(s).digest('hex');return s.replaceAll('\r\n','\n');};
 for(const path of ['supabase/candidates/run-sales-business-date-test.mjs','supabase/candidates/tests/sales_business_date.test.mjs',
  ...['field_sales_governance','field_confirmation','field_company','field_mail','field_progression','field_delivery'].map(n=>'supabase/candidates/tests/'+n+'.test.mjs'),
  'workers/field-sales/mail_worker.mjs'])await load(path);
 const migrationNames=(await readdir(new URL('../migrations/',import.meta.url))).filter(n=>n.endsWith('.sql')).sort();
 for(const mode of ['old-prefix','current-repository']){
  const db=new PGlite({extensions:{pgcrypto,btree_gist}});
  try{
   await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create role authenticator;create role other_date_definer;
    create schema extensions;create schema auth;create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,updated_at timestamptz,version text,owner_id text,metadata jsonb);
    alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,update on storage.objects to authenticated;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
    create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),not_after timestamptz);
    create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    grant usage on schema auth,extensions to authenticated,anon,service_role;`);
   const names=mode==='old-prefix'?[...migrationNames.filter(n=>n<=prefixThrough),...staff]:migrationNames.filter(n=>!excluded.includes(n));
   for(const name of names){try{await db.exec(await load('supabase/migrations/'+name));}catch(e){throw Error(mode+' baseline '+name+': '+e.message,{cause:e});}}
   for(const zone of ['UTC','Asia/Colombo','America/Los_Angeles']){
    await db.exec('begin;savepoint complete_sales_stack');
    const checks=[];
    const install=async n=>{const s=await load('supabase/candidates/'+n);validateCandidate(s);await db.exec(s);};
    await install(six[0]);await install(six[1]);
    await governance(db,checks);
    await confirmation(db,checks,{timezone:zone});
    await db.exec('reset role');await install(six[2]);await company(db,checks);
    await db.exec('reset role');await install(six[3]);await mail(db,checks);
    await db.exec('reset role');await install(six[4]);const ctx=await progression(db,checks);
    await db.exec('reset role');await install(six[5]);
    const changed=()=>db.query(`select oid,proacl::text,proowner,proconfig,prosecdef,pg_get_functiondef(oid) definition from pg_proc
     where oid=any(array['sales.field_flow_post_canonical(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)',
      'sales.flow_post_stock(text,jsonb,uuid,uuid)','finance.flow_refresh_credit(jsonb)','finance.flow_post_journal(jsonb,jsonb,text,uuid,uuid,uuid)']::regprocedure[])
      or oid=to_regprocedure('sales.flow_post_without_negative_policy(text,uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)') order by oid`);
    const before=(await changed()).rows;
    const sql=await load('supabase/candidates/'+candidate);validateCandidate(sql);
    const expectedRefusals={body:'BUSINESS_DATE_SOURCE_UNREVIEWED',acl:'BUSINESS_DATE_ACL_UNREVIEWED',owner:'BUSINESS_DATE_DEFINER_OWNER_UNREVIEWED'};
    for(const [attack,message] of Object.entries(expectedRefusals)){
     await db.exec('savepoint unknown_source');
     const signature='finance.flow_refresh_credit(jsonb)';
     if(attack==='body'){
      const d=(await db.query('select pg_get_functiondef($1::regprocedure) d',[signature])).rows[0].d;
      await db.exec(d.replace('begin','begin\n-- unknown source alteration\n'));
     }else if(attack==='acl')await db.exec('grant execute on function finance.flow_refresh_credit(jsonb) to authenticated');
     else await db.exec(`grant usage on schema core to other_date_definer;
      alter function finance.flow_refresh_credit(jsonb) owner to other_date_definer`);
     let error;try{await db.exec(sql);}catch(e){error=e;}
     await db.exec('rollback to savepoint unknown_source;release savepoint unknown_source');
     assert.equal(error?.message,message);
     checks.push('candidate refuses unreviewed '+attack+' without retained changes');
     assert.deepEqual((await changed()).rows,before);
    }
    await db.exec('savepoint business_date_candidate');await db.exec(sql);
    const after=(await changed()).rows;
    assert.deepEqual(after.map(({definition,...p})=>p),before.map(({definition,...p})=>p));checks.push('replacement function identities owners search paths security and ACLs are unchanged');
    const {rows:[{document_date:documentDate,utc_date:utcDate}]}=await db.query(`select
     core.legal_entity_business_date($1,$2)::text document_date,(statement_timestamp() at time zone 'UTC')::date::text utc_date`,[ctx.tenantId,ctx.entityId]);
    await delivery(db,checks,ctx,{documentDate});
    const baseChecks=checks.length;
    await exerciseBusinessDate(db,checks,ctx,zone,documentDate);
    await db.exec('reset role;set constraints all immediate;rollback to savepoint business_date_candidate');
    assert.deepEqual((await changed()).rows,before);
    assert.equal((await db.query("select to_regprocedure('core.legal_entity_business_date(uuid,uuid,timestamptz)') is null gone")).rows[0].gone,true);
    await db.exec('rollback to savepoint complete_sales_stack');
    const rollback=(await db.query(`select to_regnamespace('field_sales') is null candidate_removed,
     (select count(*) from auth.users)=0 actors_removed,(select count(*) from core.command_receipts)=0 receipts_removed,
     (select count(*) from sales.deliveries)=0 deliveries_removed,(select count(*) from finance.journal_entries)=0 journals_removed`)).rows[0];
    assert.ok(Object.values(rollback).every(Boolean));await db.exec('rollback');
    results.push({baseline:mode,baselineMigrations:names.length,zone,passed:checks.length,composedChecks:baseChecks,businessDateChecks:checks.length-baseChecks,checks,rollback,priorDefinitionsRestored:true,
     originalCommercialDatePolicyUnchanged:true,fixtureTimezone:zone,documentDate,utcDate});
    console.log(JSON.stringify({baseline:mode,zone,passed:checks.length,rollback:true}));
   }
  }finally{await db.exec('rollback').catch(()=>{});await db.close();}
 }
 const report={atUtc:new Date().toISOString(),engine:'PGlite 0.5.12 / PostgreSQL 18',candidate:'supabase/candidates/'+candidate,
  results,passed:results.reduce((n,r)=>n+r.passed,0),sources,excludedCurrentMigrations:excluded,
  installed:false,deployed:false,realEmailSent:false,genuineAuthOrDeviceAcceptance:false,
  scope:'Unapplied Sales/journal business-date candidate. Auth/MFA/provider are synthetic. Old and complete repository baselines run in disposable in-memory engines; every candidate and fixture rolls back. The cron/net scheduler migration is unsupported and unrelated to these paths. Earlier UTC diagnostic history is unchanged. Other AP/manual/inventory/report UTC guards are not converted.'};
 if(args.includes('--record-evidence')){
  const out=new URL('../../docs/verification/sales-business-date-20261105/',import.meta.url);await mkdir(out,{recursive:true});
  await writeFile(new URL('result.json',out),JSON.stringify(report,null,2)+'\n');
 }
 return report;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main(process.argv.slice(2))
 .then(r=>console.log(JSON.stringify({passed:r.passed,scenarios:r.results.length,installed:false})))
 .catch(e=>{console.error(e.cause?.code??e.code??e.name,e.message,e.detail??'',e.where??'');process.exitCode=1;});
