// Isolated SQL name-resolution regression for the actual MFA fixture branches.
// Business command bodies and TAP formatting are minimal fixtures; the private
// schemas, roles, JWT claims, security-definer probes and CASE statements run in
// PostgreSQL. No hosted target or production permission is changed.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

if (!process.env.JENTRA_PGLITE_MODULE) throw Error('Set JENTRA_PGLITE_MODULE.');
const { PGlite } = await import(pathToFileURL(process.env.JENTRA_PGLITE_MODULE).href);
const db = new PGlite();
const source = async path => (await readFile(new URL(`../../${path}`, import.meta.url), 'utf8')).replaceAll('\r\n', '\n');
const audit = await source('supabase/assurance_tests/assurance_core_test.sql');
const period = await source('supabase/wave_tests/wave3_period_test.sql');
function probe(text, name) {
  const start = text.indexOf(`create function pg_temp.${name}(`);
  assert(start >= 0, `Missing fixture probe ${name}`);
  const end = text.indexOf('$$;', text.indexOf('as $$', start));
  return text.slice(start, end + 3);
}
const auditCase = audit.match(/select case when to_regprocedure\('core.session_has_mfa\(\)'\)[\s\S]*? end;/)?.[0];
const periodCase = period.match(/select case when to_regprocedure\('core.session_has_mfa\(\)'\)[\s\S]*? end;/)?.[0];
assert(auditCase && periodCase, 'Fixture CASE statements required.');
let checks = 0;
try {
  await db.exec(`
    create role authenticated; create schema assurance; create schema finance; create schema core;
    revoke all on schema assurance,finance from public,authenticated;
    grant usage on schema core to authenticated;
    create function public.ok(value boolean, label text) returns text language sql as $$
      select case when value then 'ok' else 'not ok' end $$;
    create function public.throws_ok(query text, code text, message text, label text) returns text
    language plpgsql as $$begin execute query; return 'not ok'; exception when others then
      if sqlstate=code and sqlerrm=message then return 'ok'; end if; raise; end$$;
    create function public.lives_ok(query text, label text) returns text language plpgsql as $$
      begin execute query; return 'ok'; end$$;
    create function assurance.recent_mfa() returns boolean language sql stable as $$
      select coalesce(current_setting('test.verified',true),'false')::boolean $$;
    create function finance.period_require_recent_mfa() returns void language plpgsql as $$begin
      if not coalesce(current_setting('test.verified',true),'false')::boolean then
        raise exception using errcode='42501',message='RECENT_MFA_REQUIRED'; end if; end$$;
    revoke all on function assurance.recent_mfa(),finance.period_require_recent_mfa() from public,authenticated;
    create function pg_temp.cmd(jsonb,bigint,text) returns void language plpgsql as $$begin
      raise exception using errcode='42501',message='ASSURANCE_RECENT_MFA_REQUIRED';end$$;
    create function pg_temp.e(text) returns jsonb language sql as $$select '{}'::jsonb$$;
    create function pg_temp.ver() returns bigint language sql as $$select 1::bigint$$;
    create function pg_temp.call(text,jsonb,bigint) returns void language plpgsql as $$begin
      raise exception using errcode='42501',message='RECENT_MFA_REQUIRED';end$$;
    create function pg_temp.period_payload(text,text) returns jsonb language sql as $$select '{}'::jsonb$$;
    create function pg_temp.period_id() returns uuid language sql as $$select '10000000-0000-0000-0000-000000000001'::uuid$$;
    create table finance.fiscal_periods(id uuid,version bigint);
    grant usage on schema finance to authenticated;
    grant select on finance.fiscal_periods to authenticated;
    insert into finance.fiscal_periods values('10000000-0000-0000-0000-000000000001',1);
  `);
  await db.exec(probe(audit, 'assurance_session_mfa'));
  await db.exec(probe(period, 'period_session_mfa'));
  for (const installed of [false, true]) {
    if (installed) await db.exec('create function core.session_has_mfa() returns boolean language sql as $$select true$$;');
    await db.exec(`select set_config('test.verified','true',false); set role authenticated;`);
    await assert.rejects(db.query('select assurance.recent_mfa()'), {code:'42501'}); checks++;
    await assert.rejects(db.query('select finance.period_require_recent_mfa()'), {code:'42501'}); checks++;
    for (const statement of [auditCase, periodCase]) {
      const result = await db.query(statement);
      assert.equal(Object.values(result.rows[0])[0], 'ok'); checks++;
    }
    await db.exec('reset role');
  }
  await db.exec("select set_config('test.verified','false',false); set role authenticated;");
  assert.equal(Object.values((await db.query(auditCase)).rows[0])[0], 'not ok'); checks++;
  await assert.rejects(db.query(periodCase), {code:'42501',message:'RECENT_MFA_REQUIRED'}); checks++;
  await db.exec('reset role');
  for (const file of ['supabase/tests/assurance_installed_test.sql',
    'supabase/tests/wave3_negative_stock_multi_actor_installed_test.sql',
    'supabase/tests/wave3_negative_stock_policy_installed_test.sql',
    'supabase/tests/wave3_representative_read_plans_installed_test.sql']) {
    const generated = await source(file);
    const expected = file.includes('assurance_') ? auditCase : periodCase;
    assert(generated.replace(/\s+/g, ' ').includes(expected.replace(/\s+/g, ' ')), `Generated MFA branch differs: ${file}`); checks++;
  }
  console.log(`${checks} restricted-role MFA fixture assertions passed; private permissions preserved.`);
} finally { await db.close(); }
