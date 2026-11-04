// Actual foundation, command helpers and company candidate in isolated PGlite.
// The engine has one session: the private guard fixture changes table-backed
// authority just after preflight succeeds, simulating authority lost while the
// command waits for its tenant lock. This does not test concurrent transactions.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

assert.equal(process.argv.length, 2, 'This local-only test accepts no target arguments.');
if (!process.env.JENTRA_PGLITE_MODULE) throw Error('Set JENTRA_PGLITE_MODULE to a local PGlite module.');
const moduleUrl = pathToFileURL(process.env.JENTRA_PGLITE_MODULE);
const { PGlite } = await import(moduleUrl.href);
const { pgcrypto } = await import(new URL('contrib/pgcrypto.js', moduleUrl).href);
const { btree_gist } = await import(new URL('contrib/btree_gist.js', moduleUrl).href);
const db = new PGlite({ extensions: { pgcrypto, btree_gist } });
const source = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
const uid = n => `20000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const owner = uid(1), staff = uid(2), membership = uid(3);
let checks = 0, nextRequest = 10;
const scalar = async (sql, args = []) => Object.values((await db.query(sql, args)).rows[0])[0];

async function signIn() {
  await db.exec('reset role');
  await db.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({
    sub: owner, email: 'owner@company-access.invalid', aal: 'aal2',
    amr: [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) }],
  })]);
  await db.exec('set local role authenticated');
}

function request(tenant, action, payload, version) {
  return [tenant, uid(nextRequest++), uid(nextRequest++), new Date().toISOString(),
    action, payload, version];
}
const command = args => scalar('select api.workspace_admin_command($1,$2,$3,$4,$5,$6,$7)', args);

async function rejectsAfterPreflight(mode, args) {
  await db.exec('savepoint reauthorization');
  let rejection;
  try {
    await db.query("select set_config('test.admin_authority_change', $1, true)", [mode]);
    await command(args);
  } catch (error) {
    rejection = error;
  } finally {
    await db.exec('rollback to savepoint reauthorization; release savepoint reauthorization');
  }
  assert.equal(rejection?.code, '42501',
    `${mode} after preflight must refuse ${args[4]} before mutation or replay; got ${rejection?.message ?? 'success'}`);
  checks++;
}

try {
  await db.exec(`begin;
    create role anon; create role authenticated; create role service_role bypassrls; create role authenticator;
    create schema extensions; create schema auth;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,
      raw_user_meta_data jsonb default '{}',raw_app_meta_data jsonb default '{}');
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    grant usage on schema auth,extensions to anon,authenticated,service_role;
  `);
  for (const path of [
    'supabase/migrations/20260831193714_create_greenfield_foundation.sql',
    'supabase/migrations/20260831193857_harden_foundation_rls_and_indexes.sql',
    'supabase/migrations/20260901090317_create_wave2_shared_foundation_schema.sql',
    'supabase/migrations/20260901090331_create_wave2_command_helpers.sql',
  ]) {
    const sql = await source(path);
    // Storage needs Supabase services and is outside the administration fixture.
    await db.exec(path.endsWith('create_wave2_shared_foundation_schema.sql')
      ? sql.slice(0, sql.indexOf('insert into storage.buckets')) : sql);
  }
  await db.query(`insert into auth.users(id,email,email_confirmed_at) values
    ($1,'owner@company-access.invalid',now()),($2,'staff@company-access.invalid',now())`, [owner, staff]);
  await signIn();
  const bootstrap = await scalar(`select api.bootstrap_tenant('Synthetic admin group','admin-lock-test',
    'Synthetic company','SC','Main branch','HQ','Asia/Colombo','LKR',$1)`, [uid(4)]);
  const tenant = bootstrap.tenant_id, company = bootstrap.legal_entity_id;
  await db.exec('reset role');
  await db.query(`insert into core.memberships(id,tenant_id,user_id,status)
    values($1,$2,$3,'active')`, [membership, tenant, staff]);
  await db.exec(await source('supabase/candidates/20261028130000_company_access_administration.sql'));
  await signIn();

  const edit = request(tenant, 'update_entity', { id: company, name: 'Confirmed company' }, 1);
  const receipt = await command(edit);
  assert.equal(receipt.entity.name, 'Confirmed company'); checks++;
  assert.deepEqual(await command(edit), receipt); checks++;
  const suspend = await command(request(tenant, 'set_member_status', { id: membership, status: 'suspended' }, 1));
  assert.equal(suspend.entity.status, 'suspended'); checks++;
  await db.exec('reset role');
  await db.query("update core.memberships set status='active' where id=$1", [membership]);

  // Preserve the exact production guard and add only a test-owned transition
  // after it returns successfully. The command body is never substituted.
  await db.exec(`
    alter function workspace_admin.require_admin(uuid,text) rename to require_admin_before_test;
    create function workspace_admin.require_admin(t uuid, permission text) returns void
    language plpgsql security definer set search_path='' as $$
    declare mode text;
    begin
      perform workspace_admin.require_admin_before_test(t,permission);
      mode := current_setting('test.admin_authority_change',true);
      perform set_config('test.admin_authority_change','',true);
      if mode='membership' then
        update core.memberships set status='revoked' where tenant_id=t and user_id=auth.uid();
      elsif mode='delegation' then
        delete from core.role_assignments where tenant_id=t and membership_id in
          (select id from core.memberships where tenant_id=t and user_id=auth.uid());
      elsif mode='tenant' then
        update core.tenants set status='suspended' where id=t;
      end if;
    end $$;
  `);
  const staffVersion = await scalar('select version from core.memberships where id=$1', [membership]);
  await signIn();
  for (const mode of ['membership', 'delegation', 'tenant']) {
    await rejectsAfterPreflight(mode, request(tenant, 'update_entity', { id: company, name: 'Unauthorized edit' }, 2));
    await rejectsAfterPreflight(mode, request(tenant, 'set_member_status', { id: membership, status: 'revoked' }, staffVersion));
    await rejectsAfterPreflight(mode, edit);
  }
  assert.deepEqual(await command(edit), receipt); checks++;
  await db.exec('reset role; rollback;');
  assert.equal(await scalar("select to_regnamespace('workspace_admin') is null"), true); checks++;
  console.log(`${checks} isolated company reauthorization assertions passed; all fixture/candidate effects rolled back. Concurrent transactions and hosted Supabase were not exercised.`);
} finally {
  await db.close();
}
