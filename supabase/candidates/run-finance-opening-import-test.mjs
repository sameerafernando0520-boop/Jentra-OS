import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';

import { exercise } from './tests/finance_opening_import.test.mjs';
import { exerciseReversal } from './tests/finance_opening_reversal.test.mjs';

const runtime = '../../build/launch-validation-runtime/node_modules/@electric-sql/pglite/dist/';
const candidate = '20261104090000_finance_opening_import.sql';
const reversalCandidate = '20261104150000_finance_opening_reversal.sql';
// PGlite has no pg_cron or pg_net. That migration adds a worker schedule helper,
// and it has no dependency in the finance or access path exercised here.
const excludedMigrations = ['20261009123000_wave5_supabase_schedule.sql'];
const staffMfaCandidates = [
  '20261028130000_company_access_administration.sql',
  '20261103120000_session_mfa_policy.sql',
  '20261103130000_admin_staff_accounts.sql',
];
const mode = process.argv[2];
const reversalModes = ['--run-isolated-with-reversal','--run-isolated-with-staff-mfa-and-reversal','--red-reversal'];
const withReversal = reversalModes.includes(mode);
assert.ok(process.argv.length === 3 && ['--run-isolated', '--run-isolated-with-staff-mfa', '--red',...reversalModes].includes(mode),
  'Use an isolated run or red-control mode. This runner has no database target options.');
const { version: runtimeVersion } = JSON.parse(await readFile(new URL(runtime + '../package.json', import.meta.url), 'utf8'));
assert.equal(runtimeVersion, '0.5.12', 'Use the reviewed PGlite 0.5.12 runtime.');
const { PGlite } = await import(runtime + 'index.js');
const { pgcrypto } = await import(runtime + 'contrib/pgcrypto.js');
const { btree_gist } = await import(runtime + 'contrib/btree_gist.js');
const db = new PGlite({ extensions: { pgcrypto, btree_gist } });
const sources = {};
const checks = [];
async function load(path) {
  const sql = await readFile(new URL(path, import.meta.url), 'utf8');
  sources[path] = createHash('sha256').update(sql).digest('hex');
  return sql.replaceAll('\r\n', '\n');
}
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create role service_role bypassrls;
    create role authenticator;
    create schema extensions;
    create schema auth;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text,
      updated_at timestamptz,version text,owner_id text,metadata jsonb);
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated;
    grant select,insert,update on storage.objects to authenticated;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
      raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
    create table auth.sessions(id uuid primary key,user_id uuid not null references auth.users(id),not_after timestamptz);
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb
    $$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create function auth.role() returns text language sql stable as $$select auth.jwt()->>'role'$$;
    grant usage on schema auth,extensions to authenticated,anon,service_role;`);
  const names = (await readdir(new URL('../migrations/', import.meta.url)))
    .filter(name => name.endsWith('.sql') && !excludedMigrations.includes(name)).sort();
  for (const name of names) {
    try {
      await db.exec(await load('../migrations/' + name));
    } catch (error) {
      throw Error('Baseline ' + name + ': ' + error.message, { cause: error });
    }
  }
  // One tracked migration owns BEGIN/COMMIT. Build the disposable baseline
  // first, then put every candidate and test mutation in our rollback scope.
  await db.exec('begin');
  if (mode === '--run-isolated-with-staff-mfa' || mode === '--run-isolated-with-staff-mfa-and-reversal') {
    for (const name of staffMfaCandidates) await db.exec(await load(name));
  }
  await db.exec('savepoint opening_candidate');
  if (mode !== '--red') {
    const sql = await load(candidate);
    assert.doesNotMatch(sql, /^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im);
    await db.exec(sql);
  }
  if (withReversal && mode !== '--red-reversal') {
    const sql = await load(reversalCandidate);
    assert.doesNotMatch(sql, /^\s*(?:(?:begin|commit|rollback)\s*;|\\(?:i|ir|include)\b)/im);
    await db.exec(sql);
  }
  const rehearsal = await exercise(db, checks);
  const openingChecks = checks.length;
  const reversalRehearsal = withReversal ? await exerciseReversal(db, checks) : undefined;
  if (withReversal) assert.ok(reversalRehearsal && checks.length > openingChecks, 'Missing reversal rehearsal');
  await db.exec('reset role; set constraints all immediate; rollback to savepoint opening_candidate');
  const { rows: [rollback] } = await db.query(`select
    to_regclass('finance.opening_batches') is null as candidate_removed,
    (select count(*) from finance.open_items)=0 as items_removed,
    (select count(*) from finance.journal_entries)=0 as journals_removed,
    (select count(*) from core.command_receipts)=0 as receipts_removed,
    (select count(*) from auth.users)=0 as actors_removed`);
  assert.ok(Object.values(rollback).every(Boolean));
  if (withReversal) {
    const { rows: [reversalRollback] } = await db.query("select to_regclass('finance.opening_reversals') is null as reversals_removed");
    assert.ok(reversalRollback.reversals_removed);
    Object.assign(rollback,reversalRollback);
  }
  await db.exec('rollback');
  console.log(JSON.stringify({
    engine: `PGlite ${runtimeVersion} with simulated Auth/Storage and one database session`,
    passed: checks.length, openingChecks, reversalChecks: checks.length-openingChecks,
    checks, rehearsal, reversalRehearsal, rollback, excludedMigrations, sources,
  }, null, 2));
} catch (error) {
  console.error(error.cause?.code ?? error.code ?? error.name, error.message);
  if (error.detail) console.error(error.detail);
  if (error.where) console.error(error.where);
  process.exitCode = 1;
} finally {
  await db.exec('rollback').catch(() => {});
  await db.close();
}
