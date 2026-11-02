// No hosted target, sockets, sender or installed Supabase migration. Requires the
// pinned build-only PGlite runtime and official pgTAP 1.3.4 source, see README.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {PGlite} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/index.js';
import {pgcrypto} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/pgcrypto.js';
import {btree_gist} from '../../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/contrib/btree_gist.js';
import {buildSuite} from '../../../supabase/candidates/run-company-access-test.mjs';

assert.equal(process.argv.length,2,'This isolated probe has no target/connection arguments.');
const sha=value=>createHash('sha256').update(value).digest('hex');
const archive=await readFile(new URL('../../../build/pgTAP-1.3.4.zip',import.meta.url));
const template=await readFile(new URL('../../../build/pgtap-1.3.4.sql.in',import.meta.url),'utf8');
assert.equal(sha(archive),'5de16455e3e29898813f05cc9f396a31f878309a94d8adb34e80f423a5841736');
assert.equal(sha(template),'383ecd73edfd1c7ed5f3b835134ee1fe74e201ee31599346c92ea029b65dcdce');
// Exact substitutions from the upstream Makefile for modern PostgreSQL.
const pgtap=template.replaceAll('__OS__','linux').replaceAll('__VERSION__','1.3')
 .replaceAll('MODULE_PATHNAME','pgtap');
assert.ok(!/__OS__|__VERSION__|MODULE_PATHNAME/.test(pgtap));
const db=new PGlite({extensions:{pgcrypto,btree_gist}}),sources={};
try{
 await db.exec(`begin;create role anon;create role authenticated;create role service_role bypassrls;create role authenticator;
 create schema extensions;create schema auth;create schema supabase_migrations;
 create table supabase_migrations.schema_migrations(version text primary key,statements text[],name text);
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
  raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
 create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
 grant usage on schema auth,extensions to anon,authenticated,service_role;`);
 for(const path of ['supabase/migrations/20260831193714_create_greenfield_foundation.sql',
  'supabase/migrations/20260831193857_harden_foundation_rls_and_indexes.sql',
  'supabase/migrations/20260901090317_create_wave2_shared_foundation_schema.sql',
  'supabase/migrations/20260901090331_create_wave2_command_helpers.sql']){
  const sql=await readFile(new URL('../../../'+path,import.meta.url),'utf8');sources[path]=sha(sql);
  await db.exec(path.endsWith('create_wave2_shared_foundation_schema.sql')
   ? sql.slice(0,sql.indexOf('insert into storage.buckets')) : sql);
 }
 await db.exec('set local search_path=extensions,public,pg_catalog;');
 await db.exec(pgtap);
 await db.exec('commit;');
 const candidatePath='supabase/candidates/20261028130000_company_access_administration.sql';
 const harnessPath='supabase/candidates/tests/company_access_administration_test.sql';
 const candidate=await readFile(new URL('../../../'+candidatePath,import.meta.url),'utf8');
 const harness=await readFile(new URL('../../../'+harnessPath,import.meta.url),'utf8');
 sources[candidatePath]=sha(candidate);sources[harnessPath]=sha(harness);
 const suite=buildSuite(candidate,harness);
 const extension='create extension if not exists pgtap with schema extensions;';
 assert.equal(suite.split(extension).length,2,'Only the existing extension load is substituted.');
 const results=await db.exec(suite.replace(extension,'-- Exact upstream pgTAP SQL already loaded in this in-memory engine.'));
 const tap=results.flatMap(result=>result.rows.flatMap(row=>Object.values(row)))
  .filter(value=>typeof value==='string'&&/^(?:not ok|ok |[0-9]+\.\.[0-9]+)/.test(value));
 await writeFile(new URL('pgtap-output.tap',import.meta.url),tap.join('\n')+'\n');
 assert.ok(!tap.some(line=>line.startsWith('not ok')),tap.filter(line=>line.startsWith('not ok')).join('\n'));
 const passed=tap.filter(line=>/^ok [0-9]+\b/.test(line)).length;
 assert.ok(passed>0,'The harness must actually execute assertions.');
 assert.ok(tap.includes('1..'+passed),'The pgTAP plan must match the assertion count.');
 const rollback=(await db.query(`select to_regnamespace('workspace_admin') is null candidate_removed,
  (select count(*) from auth.users)=0 users_removed,(select count(*) from core.tenants)=0 companies_removed,
  (select count(*) from core.command_receipts)=0 receipts_removed`)).rows[0];
 assert.ok(Object.values(rollback).every(value=>value===true),'All candidate/fixture effects roll back.');
 const report={atUtc:new Date().toISOString(),engine:'PGlite 0.5.12 / PostgreSQL 18',
  framework:'Official pgTAP 1.3.4 source',passed,failed:0,rollback,sources,
  pgtapSource:'https://github.com/theory/pgtap/releases/tag/v1.3.4',pgtapArchiveSha256:sha(archive),
  pgtapTemplateSha256:sha(template),hostedAccess:false,supabaseStackExecuted:false,installedMigration:false,
  fixtureBoundary:'Auth users/JWT and an empty migration-ledger table are simulated. Actual foundation/Wave 2 business schema prefix, command helpers, candidate and pgTAP assertions execute. Only CREATE EXTENSION pgtap is replaced by the pinned upstream SQL already loaded. No harness assertions are substituted.'};
 await writeFile(new URL('pgtap-result.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({passed,failed:0,rollback}));
}catch(error){console.error(error.code??error.name,error.message);process.exitCode=1;}
finally{await db.close();}
