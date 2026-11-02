-- ISOLATED LOCAL/CI ONLY. Every candidate/fixture/receipt is rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
create function pg_temp.admin_definition(p oid) returns text language sql stable set search_path='' as $$select pg_catalog.pg_get_functiondef(p)$$;
create temporary table admin_functions as select p.oid,pg_temp.admin_definition(p.oid) definition,p.proacl
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('api','core','billing','people','employee_self','employee_push') and p.prokind='f';
create temporary table admin_protected as select
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.permissions p) permissions,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.role_assignments p) assignments,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.role_permissions p) grants,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from billing.plan_entitlements p) entitlements,
 (select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from supabase_migrations.schema_migrations p) ledger;
\ir ../20261028130000_company_access_administration.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
select ok(not exists(select 1 from admin_functions f left join pg_proc p on p.oid=f.oid
 where p.oid is null or pg_temp.admin_definition(p.oid) is distinct from f.definition or p.proacl is distinct from f.proacl),
 'CA-A8 every original function and execution grant remains unchanged');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.permissions p),(select permissions from admin_protected),'CA-A8 permissions unchanged');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.role_assignments p),(select assignments from admin_protected),'CA-A8 assignments unchanged');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from core.role_permissions p),(select grants from admin_protected),'CA-A8 role grants unchanged');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from billing.plan_entitlements p),(select entitlements from admin_protected),'CA-A8 entitlements unchanged');
select is((select md5(coalesce(jsonb_agg(to_jsonb(p) order by to_jsonb(p)::text),'[]')::text) from supabase_migrations.schema_migrations p),(select ledger from admin_protected),'CA-A8 migration ledger unchanged');
select ok((select bool_and(p.prosecdef and p.proconfig @> array['search_path=""'] and
 not has_function_privilege('anon',p.oid,'EXECUTE') and not has_function_privilege('service_role',p.oid,'EXECUTE'))
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname in
 ('workspace_admin_list','workspace_admin_command','workspace_my_invitations','workspace_accept_invitation')),'CA-N2 API grant/search-path boundary');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='workspace_admin'
 and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'))),'CA-N2 private helpers are not directly executable');
create function pg_temp.admin_id(label text) returns uuid language sql immutable as $$select md5('company-access-rollback-v1:'||label)::uuid$$;
create function pg_temp.admin_actor(label text,level text default 'aal2') returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.admin_id(label)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.admin_id(label),'email',label||'@company-access.invalid',
  'role','authenticated','aal',level,'amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now())::bigint)))::text,true);
end $$;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
 select pg_temp.admin_id(label),label||'@company-access.invalid',now(),'{}','{}' from unnest(array['owner','staff','invitee','other']) label;
create temporary table admin_results(key text primary key,value jsonb);
grant select,insert,update on admin_results to authenticated;
select pg_temp.admin_actor('owner');set local role authenticated;
insert into admin_results values('bootstrap',api.bootstrap_tenant('Synthetic admin group','admin-'||replace(gen_random_uuid()::text,'-',''),
 'Synthetic company','SC','Main branch','HQ','Asia/Colombo','LKR',gen_random_uuid()));
reset role;
create function pg_temp.admin_tenant() returns uuid language sql stable as $$select (value->>'tenant_id')::uuid from admin_results where key='bootstrap'$$;
create function pg_temp.admin_command(action text,payload jsonb,version bigint default null) returns jsonb language sql as $$
 select api.workspace_admin_command(pg_temp.admin_tenant(),gen_random_uuid(),gen_random_uuid(),now(),action,payload,version)$$;
select pg_temp.admin_actor('owner');set local role authenticated;
select is(jsonb_array_length(api.workspace_admin_list(pg_temp.admin_tenant(),'entities')->'items'),1,'CA-01 initial company list');
select throws_ok($$select api.workspace_admin_list(pg_temp.admin_tenant(),'entities',null,201)$$,'22023',null,'CA-N1 page cap enforced');
select throws_ok($$select pg_temp.admin_command('create_entity','{"name":"Second","code":"SE","currency_code":"LKR","timezone":"Asia/Colombo"}')$$,'23514',null,'CA-A2 starter company limit enforced');
select pg_temp.admin_actor('owner','aal1');
select throws_ok($$select api.workspace_admin_list(pg_temp.admin_tenant(),'members')$$,'42501',null,'CA-A1 AAL1 cannot administer staff');
reset role;
update billing.tenant_subscriptions set plan_code='growth' where tenant_id=pg_temp.admin_tenant();
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.admin_id('membership'),pg_temp.admin_tenant(),pg_temp.admin_id('staff'),'active');
select pg_temp.admin_actor('owner');set local role authenticated;
insert into admin_results values('company',pg_temp.admin_command('create_entity','{"name":"Second","code":"SE","currency_code":"LKR","timezone":"Asia/Colombo"}'));
select is((select value->'entity'->>'version' from admin_results where key='company'),'1','CA-02 company create confirms version');
select throws_ok($$select pg_temp.admin_command('update_entity',jsonb_build_object('id',(select value->'entity'->>'id' from admin_results where key='company'),'name','Stale'),2)$$,'40001',null,'CA-A3 stale company edit refused');
select throws_ok($$select pg_temp.admin_command('create_role','{"name":"Unsafe","code":"unsafe","permissions":["finance.view"],"requires_mfa":false}')$$,'22023',null,'CA-A4 privileged role requires MFA');
insert into admin_results values('role',pg_temp.admin_command('create_role','{"name":"Reader","code":"admin_test_reader","permissions":["sales.view"],"requires_mfa":false}'));
select is((select value->'entity'->'permissions' from admin_results where key='role'),'["sales.view"]'::jsonb,'CA-04 exact custom role permissions');
insert into admin_results values('invitation',pg_temp.admin_command('create_invitation',jsonb_build_object('email','invitee@company-access.invalid',
 'role_id',(select value->'entity'->>'id' from admin_results where key='role'))));
select ok(not (select value::text like '%token%' from admin_results where key='invitation'),'CA-E7 no invitation secret enters receipts');
select pg_temp.admin_actor('other');
select throws_ok($$select api.workspace_admin_list(pg_temp.admin_tenant(),'members')$$,'42501',null,'CA-A1 foreign actor cannot read staff');
select throws_ok($$select api.workspace_accept_invitation((select (value->'entity'->>'id')::uuid from admin_results where key='invitation'),gen_random_uuid())$$,'42501',null,'CA-A6 wrong email cannot accept');
select pg_temp.admin_actor('invitee');
select is(jsonb_array_length(api.workspace_my_invitations()->'items'),1,'CA-07 verified invitee sees own invitation');
insert into admin_results values('accept',api.workspace_accept_invitation((select (value->'entity'->>'id')::uuid from admin_results where key='invitation'),pg_temp.admin_id('accept-request')));
select is((select value->'entity'->>'status' from admin_results where key='accept'),'active','CA-07 invitation joins active membership');
select is(api.workspace_accept_invitation((select (value->'entity'->>'id')::uuid from admin_results where key='invitation'),pg_temp.admin_id('accept-request')),
 (select value from admin_results where key='accept'),'CA-A6 acceptance replay returns one original receipt');
select pg_temp.admin_actor('owner');
insert into admin_results values('grant',pg_temp.admin_command('set_assignment',jsonb_build_object('id',pg_temp.admin_id('membership'),
 'role_id',(select value->'entity'->>'id' from admin_results where key='role'),'granted',true),1));
insert into admin_results values('staff-invitation',pg_temp.admin_command('create_invitation',jsonb_build_object('email','staff@company-access.invalid',
 'role_id',(select value->'entity'->>'id' from admin_results where key='role'))));
insert into admin_results values('suspend',pg_temp.admin_command('set_member_status',jsonb_build_object('id',pg_temp.admin_id('membership'),'status','suspended'),2));
select is((select value->'entity'->>'version' from admin_results where key='suspend'),'3','CA-06 suspension advances the membership version');
select is((select i->>'status' from jsonb_array_elements(api.workspace_admin_list(pg_temp.admin_tenant(),'invitations')->'items') i
 where i->>'id'=(select value->'entity'->>'id' from admin_results where key='staff-invitation')),'revoked','CA-06 suspension revokes outstanding staff invitations');
select throws_ok($$select pg_temp.admin_command('create_invitation',jsonb_build_object('email','staff@company-access.invalid',
 'role_id',(select value->'entity'->>'id' from admin_results where key='role')))$$,'42501',null,'CA-06 a new invitation cannot restore retained suspended roles');
select pg_temp.admin_actor('staff');
select throws_ok($$select api.workspace_accept_invitation((select (value->'entity'->>'id')::uuid from admin_results where key='staff-invitation'),gen_random_uuid())$$,
 '42501',null,'CA-06 suspended staff cannot accept a revoked invitation');
select pg_temp.admin_actor('owner');
insert into admin_results values('restore',pg_temp.admin_command('set_member_status',jsonb_build_object('id',pg_temp.admin_id('membership'),'status','active'),3));
select is((select value->'entity'->>'version' from admin_results where key='restore'),'4','CA-06 restore is an explicit versioned administrator decision');
select throws_ok($$select api.create_invitation(pg_temp.admin_tenant(),'other@company-access.invalid',
 (select id from core.roles where tenant_id=pg_temp.admin_tenant() and code='tenant_owner'))$$,
 '42501',null,'CA-07 legacy issuance cannot bypass owner-role protection');
insert into admin_results values('legacy-staff',api.create_invitation(pg_temp.admin_tenant(),'staff@company-access.invalid',
 (select (value->'entity'->>'id')::uuid from admin_results where key='role')));
reset role;
-- Reproduce a previously suspended membership with a still-pending legacy token.
update core.memberships set status='suspended' where id=pg_temp.admin_id('membership');
select pg_temp.admin_actor('staff');set local role authenticated;
select throws_ok($$select api.accept_invitation((select value->>'token' from admin_results where key='legacy-staff'))$$,
 '42501',null,'CA-06 legacy acceptance cannot resurrect suspended staff roles');
select pg_temp.admin_actor('owner');
insert into admin_results values('legacy-other',api.create_invitation(pg_temp.admin_tenant(),'other@company-access.invalid',
 (select (value->'entity'->>'id')::uuid from admin_results where key='role')));
reset role;
update auth.users set email_confirmed_at=null where id=pg_temp.admin_id('other');
select pg_temp.admin_actor('other');set local role authenticated;
select throws_ok($$select api.accept_invitation((select value->>'token' from admin_results where key='legacy-other'))$$,
 '42501',null,'CA-07 legacy acceptance requires canonical verified email');
reset role;
update auth.users set email_confirmed_at=now() where id=pg_temp.admin_id('other');
select pg_temp.admin_actor('other');set local role authenticated;
insert into admin_results values('legacy-accepted',api.accept_invitation((select value->>'token' from admin_results where key='legacy-other')));
select is((select value->>'tenant_id' from admin_results where key='legacy-accepted'),pg_temp.admin_tenant()::text,
 'CA-07 valid legacy acceptance remains compatible');
reset role;
set constraints all immediate;
select * from finish();
rollback;
