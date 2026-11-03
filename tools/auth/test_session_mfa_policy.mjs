// Isolated PostgreSQL helper verification. No network, Supabase project, real
// accounts, migrations, or application data are used by this runner.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const modulePath = process.env.JENTRA_PGLITE_MODULE;
if (!modulePath) throw Error('Set JENTRA_PGLITE_MODULE to a local PGlite module.');
const { PGlite } = await import(pathToFileURL(modulePath).href);
const db = new PGlite();
let checks = 0;
const actor = '10000000-0000-0000-0000-000000000001';
const tenant = '20000000-0000-0000-0000-000000000001';

async function source(path) {
  return readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
}
function definition(sql, name) {
  const start = sql.indexOf(`create function ${name}(`);
  const body = sql.indexOf('as $$', start);
  const end = sql.indexOf('$$;', body + 5);
  assert(start >= 0 && body >= start && end > body, `Missing ${name}`);
  return sql.slice(start, end + 3);
}
async function claims({ level = 'aal2', age = 60, uid = actor, amr } = {}) {
  const token = {
    sub: uid,
    aal: level,
    amr: amr === undefined
      ? [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) - age }]
      : amr,
  };
  await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify(token)]);
}
async function result(sql) {
  return (await db.query(sql)).rows[0].result;
}
async function allowed(label, expected) {
  assert.equal(await result('select core.session_has_mfa() as result'), expected, label);
  assert.equal(await result('select assurance.recent_mfa() as result'), expected, label);
  if (expected) {
    await db.query('select finance.period_require_recent_mfa()');
    await db.query('select workspace_admin.require_admin($1::uuid, $2)', [tenant, 'core.members.invite']);
  } else {
    for (const sql of [
      'select finance.period_require_recent_mfa()',
      `select workspace_admin.require_admin('${tenant}'::uuid, 'core.members.invite')`,
    ]) {
      await assert.rejects(db.query(sql), { code: '42501' }, label);
    }
  }
  checks += 4;
}

try {
  // Only the auth claim adapters and permission fixture are substituted. The
  // three historic MFA guards and new candidate execute as real PostgreSQL.
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema core; create schema assurance;
    create schema finance; create schema workspace_admin;
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
    $$;
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(auth.jwt()->>'sub', '')::uuid
    $$;
    create table core.tenants(id uuid primary key, status text);
    insert into core.tenants values ('${tenant}', 'active');
    create function core.require_permission(t uuid, permission text) returns void
    language plpgsql as $$begin
      if coalesce(current_setting('jentra.test.permission', true), '') <> 'allowed' then
        raise exception using errcode='42501', message='PERMISSION_DENIED';
      end if;
    end$$;
    select set_config('jentra.test.permission', 'allowed', false);
  `);
  for (const [file, name] of [
    ['supabase/migrations/20261018153931_assurance_engagement_core.sql', 'assurance.recent_mfa'],
    ['supabase/migrations/20260924185321_wave3_period_governance.sql', 'finance.period_require_recent_mfa'],
    ['supabase/candidates/20261028130000_company_access_administration.sql', 'workspace_admin.require_admin'],
  ]) {
    await db.exec(definition(await source(file), name));
  }

  await claims({ age: 8 * 3600 });
  assert.equal(await result('select assurance.recent_mfa() as result'), false);
  await assert.rejects(db.query('select finance.period_require_recent_mfa()'), { code: '42501' });
  await assert.rejects(db.query('select workspace_admin.require_admin($1::uuid, $2)', [tenant, 'core.members.invite']), { code: '42501' });
  checks += 3;

  await db.exec('begin');
  await db.exec(await source('supabase/candidates/20261103120000_session_mfa_policy.sql'));
  // Error assertions below use individual savepoints so a refused action does
  // not abort the candidate transaction in PostgreSQL.
  const originalQuery = db.query.bind(db);
  db.query = async (...args) => {
    await originalQuery('savepoint assertion');
    try {
      const response = await originalQuery(...args);
      await originalQuery('release savepoint assertion');
      return response;
    } catch (error) {
      await originalQuery('rollback to savepoint assertion');
      await originalQuery('release savepoint assertion');
      throw error;
    }
  };
  for (const age of [60, 8 * 3600, 30 * 86400]) {
    await claims({ age });
    await allowed(`verified session with MFA ${age}s ago`, true);
  }
  await claims({ age: 8 * 3600 });
  assert.equal(await result('select assurance.recent_mfa(1) as result'), true);
  checks++;

  for (const [label, token] of [
    ['new password login', { level: 'aal1' }],
    ['logout with no actor', { uid: null }],
    ['missing MFA evidence', { amr: null }],
    ['empty MFA evidence', { amr: [] }],
    ['malformed MFA evidence', { amr: {} }],
    ['password alone', { amr: [{ method: 'password', timestamp: 1780000000 }] }],
    ['invalid timestamp', { amr: [{ method: 'totp', timestamp: 'invalid' }] }],
    ['overflow timestamp', { amr: [{ method: 'totp', timestamp: '999999999999999999999' }] }],
    ['missing timestamp', { amr: [{ method: 'totp' }] }],
    ['future timestamp', { age: -3600 }],
  ]) {
    await claims(token);
    await allowed(label, false);
  }
  await claims();
  await db.query("select set_config('jentra.test.permission', 'denied', false)");
  await assert.rejects(db.query('select workspace_admin.require_admin($1::uuid, $2)', [tenant, 'core.members.invite']), { code: '42501', message: 'PERMISSION_DENIED' });
  await db.query("select set_config('jentra.test.permission', 'allowed', false)");
  await db.query("update core.tenants set status = 'suspended'");
  await assert.rejects(db.query('select workspace_admin.require_admin($1::uuid, $2)', [tenant, 'core.members.invite']), { code: '42501', message: 'ADMIN_ACCESS_DENIED' });
  checks += 2;
  await db.exec('rollback');
  db.query = originalQuery;
  assert.equal(await result("select to_regprocedure('core.session_has_mfa()') is null as result"), true);
  checks++;

  // The company administration schema is optional; policy installation must
  // also succeed when only the installed Finance/Audit schemas are present.
  await db.exec('drop schema workspace_admin cascade; begin');
  await db.exec(await source('supabase/candidates/20261103120000_session_mfa_policy.sql'));
  await db.exec('create schema workspace_admin');
  await db.exec(definition(
    await source('supabase/candidates/20261028130000_company_access_administration.sql'),
    'workspace_admin.require_admin',
  ));
  await claims({ age: 8 * 3600 });
  assert.equal(await result('select assurance.recent_mfa() as result'), true);
  await db.query('select workspace_admin.require_admin($1::uuid, $2)', [tenant, 'core.members.invite']);
  await db.exec('rollback');
  checks += 2;
  console.log(`${checks} isolated PostgreSQL assertions passed; candidate changes rolled back.`);
} finally {
  await db.close();
}
