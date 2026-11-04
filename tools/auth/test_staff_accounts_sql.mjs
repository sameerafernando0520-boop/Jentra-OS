// In-memory PostgreSQL verification using actual candidate functions and the
// foundation permission helpers. Auth Admin user creation is a synthetic fixture.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

if (!process.env.JENTRA_PGLITE_MODULE) throw Error('Set JENTRA_PGLITE_MODULE.');
const { PGlite } = await import(pathToFileURL(process.env.JENTRA_PGLITE_MODULE).href);
const db = new PGlite();
const uid = n => `10000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const owner = uid(1), tenant = uid(2), ownerRole = uid(3), sales = uid(4), inventory = uid(5);
let checks = 0;
const source = path => readFile(new URL(`../../${path}`, import.meta.url), 'utf8');
function definition(sql, name) {
  const start = sql.indexOf(`create function ${name}(`);
  const body = sql.indexOf('as $$', start), end = sql.indexOf('$$;', body + 5);
  assert(start >= 0 && body > start && end > body, name);
  return sql.slice(start, end + 3);
}
async function claims(actor = owner, aal = 'aal2') {
  await db.query("select set_config('request.jwt.claims',$1,false)", [JSON.stringify({ sub: actor, aal,
    amr: [{ method: 'totp', timestamp: Math.floor(Date.now() / 1000) - 8 * 3600 }] })]);
}
async function runAs(role, action) {
  await db.exec(`set role ${role}`);
  try { return await action(); } finally { await db.exec('reset role'); }
}
const result = async (sql, args = []) => (await db.query(sql, args)).rows[0].result;
const reserve = (requestId, username, roles = [sales, inventory], name = 'Synthetic staff') => runAs('authenticated', () => result(
  'select api.workspace_staff_reserve($1,$2,$3,$4,$5::uuid[]) as result', [tenant, requestId, username, name, roles]));
const complete = (requestId, user) => runAs('authenticated', () => result(
  'select api.workspace_staff_complete($1,$2,$3) as result', [tenant, requestId, user]));
async function authUser(reservation, user, patch = {}) {
  await db.query('insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data) values($1,$2,now(),$3::jsonb)', [user,
    reservation.email, JSON.stringify({ jentra_staff_request: reservation.request_id, jentra_tenant_id: tenant,
      jentra_created_by: owner, jentra_username: reservation.username, ...patch })]);
}
async function denied(action, message) {
  await assert.rejects(action, { code: '42501' }, message); checks++;
}

try {
  await db.exec(`
    create role anon; create role authenticated; create role service_role;
    create schema auth; create schema core; create schema api; create schema audit;
    create schema billing; create schema assurance; create schema finance; create schema workspace_admin;
    grant usage on schema api to authenticated;
    create function auth.jwt() returns jsonb language sql stable as $$select current_setting('request.jwt.claims')::jsonb$$;
    create function auth.uid() returns uuid language sql stable as $$select (auth.jwt()->>'sub')::uuid$$;
    create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_app_meta_data jsonb default '{}');
    create table core.tenants(id uuid primary key,status text);
    create table core.memberships(id uuid primary key default gen_random_uuid(),tenant_id uuid,user_id uuid,status text,invited_by uuid,joined_at timestamptz);
    create table core.roles(id uuid primary key,tenant_id uuid,code text,requires_mfa boolean);
    create table core.permissions(code text primary key,privileged boolean);
    create table core.role_permissions(tenant_id uuid,role_id uuid,permission_code text);
    create table core.role_assignments(id uuid default gen_random_uuid(),tenant_id uuid,membership_id uuid,role_id uuid,created_by uuid,legal_entity_id uuid,branch_id uuid);
    create table billing.tenant_subscriptions(tenant_id uuid,status text,seats integer,trial_ends_at timestamptz);
    create table audit.events(tenant_id uuid,actor_id uuid,request_id uuid,event_type text,aggregate_type text,aggregate_id uuid,after_context jsonb);
    insert into auth.users(id,email,email_confirmed_at) values('${owner}','owner@example.test',now());
    insert into core.tenants values('${tenant}','active');
    insert into core.memberships(id,tenant_id,user_id,status) values('${uid(6)}','${tenant}','${owner}','active');
    insert into core.roles values('${ownerRole}','${tenant}','tenant_owner',true),('${sales}','${tenant}','sales_staff',false),('${inventory}','${tenant}','inventory_staff',true);
    insert into core.permissions values('core.members.invite',true),('core.roles.manage',true),('sales.view',false),('inventory.view',true);
    insert into core.role_permissions select '${tenant}','${ownerRole}',code from core.permissions;
    insert into core.role_permissions values('${tenant}','${sales}','sales.view'),('${tenant}','${inventory}','inventory.view');
    insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values('${tenant}','${uid(6)}','${ownerRole}','${owner}');
    insert into billing.tenant_subscriptions values('${tenant}','active',10,null);
  `);
  const foundation = await source('supabase/migrations/20260831193714_create_greenfield_foundation.sql');
  for (const name of ['core.has_permission', 'core.require_permission']) await db.exec(definition(foundation, name));
  await db.exec(await source('supabase/candidates/20261103120000_session_mfa_policy.sql'));
  const admin = await source('supabase/candidates/20261028130000_company_access_administration.sql');
  for (const name of ['workspace_admin.require_admin', 'workspace_admin.require_role', 'workspace_admin.require_seat']) await db.exec(definition(admin, name));
  await db.exec(await source('supabase/candidates/20261103130000_admin_staff_accounts.sql'));
  await claims();

  await denied(runAs('authenticated', () => db.query('select * from workspace_admin.staff_accounts')), 'no direct credential registry reads');
  await denied(runAs('anon', () => db.query('select api.workspace_staff_login_target($1)', ['company_sales'])), 'no public username resolution');
  await denied(runAs('authenticated', () => db.query('select api.workspace_staff_login_target($1)', ['company_sales'])), 'no client username resolution');
  await claims(owner, 'aal1');
  await denied(reserve(uid(10), 'company_sales'), 'new sign-in cannot create staff before MFA');
  await claims(uid(99));
  await denied(reserve(uid(10), 'company_sales'), 'foreign actor cannot provision');
  await claims();
  await denied(reserve(uid(10), 'company_sales', [ownerRole]), 'owner role cannot be delegated');
  await denied(reserve(uid(10), 'company_sales', [uid(99)]), 'foreign role cannot be delegated');

  const reservation = await reserve(uid(10), ' Company_Sales ');
  assert.equal(reservation.username, 'company_sales'); checks++;
  assert.equal(reservation.user_id, null); checks++;
  assert.deepEqual(reservation.role_ids, [sales, inventory].sort()); checks++;
  await assert.rejects(reserve(uid(10), 'changed_username'), { code: '22023' }); checks++;
  await assert.rejects(reserve(uid(10), 'company_sales', [sales]), { code: '22023' }); checks++;
  await assert.rejects(reserve(uid(10), 'company_sales', [sales, inventory], 'Changed name'), { code: '22023' }); checks++;
  await assert.rejects(reserve(uid(11), 'company_sales'), { code: '23505' }); checks++;
  await denied(complete(uid(10), owner), 'existing owner identity cannot be adopted');
  await authUser(reservation, uid(12), { jentra_created_by: uid(99) });
  await denied(complete(uid(10), uid(12)), 'untrusted metadata cannot bind identity');
  await db.query('update auth.users set raw_app_meta_data=jsonb_set(raw_app_meta_data,\'{jentra_created_by}\',to_jsonb($1::text)) where id=$2', [owner, uid(12)]);
  await claims(owner, 'aal1');
  await denied(complete(uid(10), uid(12)), 'completion rechecks MFA');
  await claims();
  await db.query("delete from core.role_permissions where role_id=$1 and permission_code='inventory.view'", [ownerRole]);
  await denied(complete(uid(10), uid(12)), 'completion rechecks current delegability');
  await db.query("insert into core.role_permissions values($1,$2,'inventory.view')", [tenant, ownerRole]);
  const receipt = await complete(uid(10), uid(12));
  assert.equal(receipt.status, 'active'); checks++;
  assert.equal(await result('select count(*)::int as result from core.role_assignments where membership_id=$1', [receipt.membership_id]), 2); checks++;
  assert.deepEqual(await complete(uid(10), uid(12)), receipt); checks++;
  assert.equal(await result('select count(*)::int as result from audit.events'), 1); checks++;
  await db.query('delete from core.role_assignments where membership_id=$1 and role_id=$2', [receipt.membership_id, inventory]);
  await denied(complete(uid(10), uid(12)), 'replay must not confirm or restore revoked delegation');
  assert.equal(await result('select count(*)::int as result from core.role_assignments where membership_id=$1', [receipt.membership_id]), 1); checks++;
  await db.query('insert into core.role_assignments(tenant_id,membership_id,role_id,created_by) values($1,$2,$3,$4)', [tenant,receipt.membership_id,inventory,owner]);
  await db.query("update core.memberships set status='suspended' where id=$1", [receipt.membership_id]);
  await denied(complete(uid(10), uid(12)), 'replay cannot restore suspended membership');
  await db.query("update core.memberships set status='active' where id=$1", [receipt.membership_id]);
  const target = await runAs('service_role', () => result('select api.workspace_staff_login_target($1) as result', ['company_sales']));
  assert.equal(target.email, reservation.email); checks++;
  for (let attempt = 0; attempt < 12; attempt++) await runAs('service_role', () => db.query('select api.workspace_staff_login_target($1)', ['guessed_user']));
  assert.equal((await runAs('service_role', () => result('select api.workspace_staff_login_target($1) as result', ['guessed_user']))).limited, true); checks++;
  assert.equal(await result('select count(*)::int as result from workspace_admin.staff_login_attempts') <= 3, true); checks++;
  const expired=await reserve(uid(30),'expired_pending');
  await db.query("update workspace_admin.staff_accounts set created_at=now()-interval '25 hours' where request_id=$1",[uid(30)]);
  const recovered=await reserve(uid(31),'expired_pending');
  assert.equal(recovered.request_id,uid(31));checks++;
  assert.equal(await result('select count(*)::int as result from workspace_admin.staff_accounts where request_id=$1',[expired.request_id]),0);checks++;
  await authUser(recovered,uid(32));
  await db.query("update workspace_admin.staff_accounts set created_at=now()-interval '25 hours' where request_id=$1",[uid(31)]);
  await assert.rejects(reserve(uid(33),'expired_pending'),{code:'23505'});checks++;
  await db.query('update billing.tenant_subscriptions set seats=3');
  await assert.rejects(reserve(uid(34),'beyond_pending_budget'),{code:'23514'});checks++;
  await db.query('update billing.tenant_subscriptions set seats=2');
  await assert.rejects(reserve(uid(20), 'another_staff'), { code: '23514' }); checks++;
  assert.equal(await result("select not exists(select 1 from information_schema.columns where table_schema='workspace_admin' and table_name='staff_accounts' and column_name like '%password%') as result"), true); checks++;
  console.log(`${checks} isolated staff-account PostgreSQL assertions passed; database discarded.`);
} finally {
  await db.close();
}
