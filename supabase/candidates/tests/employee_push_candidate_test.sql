-- ISOLATED LOCAL/CI DATABASE ONLY. Never run against hosted/production projects.
-- Existing Supabase migrations must already be installed. The uninstalled push
-- candidate and every synthetic fixture are transaction-local and rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- The local-only runner inlines this candidate before staging the suite.
\ir ../20261023090000_employee_push.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select plan(47);

create function pg_temp.pid(label text) returns uuid language sql immutable as
 $$select md5('employee-push-isolated-rollback-v1:'||label)::uuid$$;
create function pg_temp.push_actor(label text,level text default 'aal1',session_label text default null)
returns void language plpgsql as $$begin
 perform set_config('request.jwt.claim.sub',pg_temp.pid(label)::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.pid(label),'role','authenticated',
  'aal',level,'session_id',pg_temp.pid(coalesce(session_label,label||'.session')))::text,true);
end $$;
create function pg_temp.push_register(device text,command text,target text default 'SYNTHETIC_FID_A_12345678901234567890')
returns jsonb language sql as $$select api.employee_push_register(pg_temp.pid('tenant'),pg_temp.pid('entity'),
 pg_temp.pid('branch'),pg_temp.pid(device),target,'android',pg_temp.pid(command))$$;
create temporary table push_results(name text primary key,value jsonb);
grant select,insert,update on push_results to authenticated,service_role;

insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.pid(label),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
 label||'@employee-push.rollback.invalid','',now(),now(),now()
from unnest(array['employee-a','employee-b','outsider']) label;
insert into auth.sessions(id,user_id,created_at,updated_at)
select pg_temp.pid(label||'.session'),pg_temp.pid(label),now(),now()
from unnest(array['employee-a','employee-b','outsider']) label;
insert into core.tenants(id,name,slug,created_by)
values(pg_temp.pid('tenant'),'Synthetic push rollback','employee-push-isolated-rollback',pg_temp.pid('employee-a'));
insert into core.legal_entities(id,tenant_id,name,code,created_by)
values(pg_temp.pid('entity'),pg_temp.pid('tenant'),'Synthetic entity','PUSHQA',pg_temp.pid('employee-a'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.pid(label),pg_temp.pid('tenant'),pg_temp.pid('entity'),'Synthetic '||label,
 case when label='branch' then 'PUSH1' else 'PUSH2' end,pg_temp.pid('employee-a')
from unnest(array['branch','other-branch']) label;
insert into billing.plans(code,name) values('employee_push_isolated','Synthetic push plan');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
values('employee_push_isolated','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.pid('tenant'),'employee_push_isolated','trialing',5,now()+interval '2 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.pid(label||'.membership'),pg_temp.pid('tenant'),pg_temp.pid(label),'active'
from unnest(array['employee-a','employee-b']) label;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
values(pg_temp.pid('employee-role'),pg_temp.pid('tenant'),'push.employee','Synthetic employee self role',false);
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.pid('tenant'),pg_temp.pid('employee-role'),cap
from unnest(array['people.view','people.self.view']) cap;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.pid('tenant'),pg_temp.pid(label||'.membership'),pg_temp.pid('employee-role'),
 pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-a')
from unnest(array['employee-a','employee-b']) label;
insert into people.employees(id,tenant_id,legal_entity_id,code,display_name,created_by,updated_by)
select pg_temp.pid(label||'.employee'),pg_temp.pid('tenant'),pg_temp.pid('entity'),
 case when label='employee-a' then 'PUSH_A' else 'PUSH_B' end,'Synthetic '||label,
 pg_temp.pid('employee-a'),pg_temp.pid('employee-a')
from unnest(array['employee-a','employee-b']) label;
insert into people.employment_spells(id,tenant_id,legal_entity_id,employee_id,start_date,created_by)
select pg_temp.pid(label||'.spell'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid(label||'.employee'),
 current_date-1,pg_temp.pid('employee-a') from unnest(array['employee-a','employee-b']) label;
insert into people.employment_assignments(id,tenant_id,legal_entity_id,employee_id,spell_id,branch_id,start_date,job_title,employment_type,created_by)
select pg_temp.pid(label||'.assignment'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid(label||'.employee'),
 pg_temp.pid(label||'.spell'),pg_temp.pid('branch'),current_date-1,'Synthetic employee','permanent',pg_temp.pid('employee-a')
from unnest(array['employee-a','employee-b']) label;
insert into people_private.account_links(id,tenant_id,legal_entity_id,branch_id,employee_id,membership_id,user_id,status,initiated_by,accepted_at)
select pg_temp.pid(label||'.link'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),
 pg_temp.pid(label||'.employee'),pg_temp.pid(label||'.membership'),pg_temp.pid(label),'accepted',pg_temp.pid('employee-a'),now()
from unnest(array['employee-a','employee-b']) label;

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='employee_push' and relkind='r'),'private push tables enforce RLS');
select ok(not has_schema_privilege('authenticated','employee_push','USAGE'),'authenticated cannot browse private push schema');
select ok(not has_table_privilege('service_role','employee_push.devices','SELECT'),'service cannot directly read FIDs');
select ok(not has_function_privilege('anon','api.employee_push_register(uuid,uuid,uuid,uuid,text,text,uuid)','EXECUTE'),'anonymous cannot register');
select ok(not has_function_privilege('authenticated','api.employee_push_claim(integer)','EXECUTE'),'employee cannot claim worker deliveries');
select is((select count(*) from core.role_permissions where role_id=pg_temp.pid('employee-role')),2::bigint,'employee receives only existing view/self permissions');

select pg_temp.push_actor('employee-a');
set local role authenticated;
insert into push_results values('registered',pg_temp.push_register('device-a','register-a'));
select is((select value->>'status' from push_results where name='registered'),'active','own accepted employee registers at AAL1 without MFA role');
select is(pg_temp.push_register('device-a','register-a'),(select value from push_results where name='registered'),'identical retry returns original acknowledgement');
select throws_ok($$select pg_temp.push_register('device-a','register-a','SYNTHETIC_DIFFERENT_FID_123456789012345')$$,
 '22023','PUSH_COMMAND_REUSED','changed command body cannot rebind');
select throws_ok($$select api.employee_push_register(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('other-branch'),
 pg_temp.pid('device-x'),'SYNTHETIC_FID_X_12345678901234567890','android',pg_temp.pid('foreign-branch'))$$,
 '42501',null,'foreign branch registration denied');
select throws_ok($$select api.employee_push_register(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),
 pg_temp.pid('device-x'),'SYNTHETIC_FID_X_12345678901234567890','web',pg_temp.pid('web'))$$,
 '22023','PUSH_REGISTRATION_INVALID','web push is outside this slice');
select throws_ok($$select pg_temp.push_register('device-x','oversize',repeat('x',4097))$$,
 '22023','PUSH_REGISTRATION_INVALID','oversized target rejected');
reset role;
select is((select employee_id from employee_push.devices where installation_id=pg_temp.pid('device-a')),
 pg_temp.pid('employee-a.employee'),'employee subject derived from accepted link');
select ok((select expires_at>now()+interval '23 hours' and expires_at<=clock_timestamp()+interval '24 hours'
 from employee_push.devices where installation_id=pg_temp.pid('device-a')),'binding has bounded 24-hour lifetime');
select ok(not (select response ? 'token' from employee_push.receipts where command_id=pg_temp.pid('register-a')),'receipt contains no target');

-- A second caller cannot seize the first installation or remove its binding.
select pg_temp.push_actor('employee-b');
set local role authenticated;
select throws_ok($$select pg_temp.push_register('device-a','seize-a','SYNTHETIC_FID_B_12345678901234567890')$$,
 '42501','PUSH_INSTALLATION_BOUND','foreign active installation cannot be seized');
select is(api.employee_push_remove(pg_temp.pid('device-a'),pg_temp.pid('foreign-remove'))->>'removed','false','foreign removal gives no own-binding removal proof');
select pg_temp.push_register('device-b','register-b','SYNTHETIC_FID_B_12345678901234567890');
reset role;
select is((select status from employee_push.devices where installation_id=pg_temp.pid('device-a')),'active','foreign removal did not affect first employee');

-- Retained session rows are not proof that a time-boxed session is still live.
insert into workflow.notifications(id,tenant_id,legal_entity_id,branch_id,recipient_id,notification_type,title,body,created_by,updated_by)
values(pg_temp.pid('notice-expired-session'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-b'),
 'people.test','Synthetic notice','Synthetic body',pg_temp.pid('employee-a'),pg_temp.pid('employee-a'));
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into push_results values('lease-expired-session',api.employee_push_claim(20)->0);
reset role;
update auth.sessions set not_after=statement_timestamp()-interval '1 minute' where id=pg_temp.pid('employee-b.session');
select pg_temp.push_actor('employee-b');
set local role authenticated;
select throws_ok($$select pg_temp.push_register('device-b','expired-session','SYNTHETIC_FID_B_12345678901234567890')$$,
 '42501','PUSH_SESSION_REQUIRED','retained expired session cannot register');
reset role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
select is(api.employee_push_target((select (value->>'delivery_id')::uuid from push_results where name='lease-expired-session'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-expired-session')),null::jsonb,'retained expired session suppresses a claimed target');
reset role;
update auth.sessions set not_after=null where id=pg_temp.pid('employee-b.session');

-- A previously removed installation cannot bypass the same active-device cap.
select pg_temp.push_actor('employee-b');
set local role authenticated;
select pg_temp.push_register('limit-removed','limit-removed-register','SYNTHETIC_FID_REMOVED_12345678901234567890');
select api.employee_push_remove(pg_temp.pid('limit-removed'),pg_temp.pid('limit-remove'));
select pg_temp.push_register('limit-'||n,'limit-register-'||n,'SYNTHETIC_FID_LIMIT_12345678901234567890_'||n)
from generate_series(2,10) n;
select throws_ok($$select pg_temp.push_register('limit-removed','limit-reactivate','SYNTHETIC_FID_REMOVED_12345678901234567890')$$,
 '54000','PUSH_DEVICE_LIMIT','removed installation reactivation respects active-device cap');
select lives_ok($$select pg_temp.push_register('device-b','limit-active-rotation','SYNTHETIC_FID_B_12345678901234567890')$$,
 'existing active own binding can rotate at device cap');
reset role;
delete from employee_push.devices where installation_id=pg_temp.pid('limit-removed')
 or installation_id in(select pg_temp.pid('limit-'||n) from generate_series(2,10) n);

-- Insert authoritative synthetic notification rows as fixture owner, never via
-- an employee API. No HR event producer is manufactured by the candidate.
insert into workflow.notifications(id,tenant_id,legal_entity_id,branch_id,recipient_id,notification_type,title,body,created_by,updated_by)
values(pg_temp.pid('notice-a'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-a'),
 'people.test','Synthetic private title','SYNTHETIC_PRIVATE_BODY',pg_temp.pid('employee-a'),pg_temp.pid('employee-a'));
select is((select count(*) from employee_push.deliveries where state='pending'),1::bigint,'outbox enqueues only exact recipient device');
select is((select installation_id from employee_push.deliveries where notification_id=pg_temp.pid('notice-a')),
 pg_temp.pid('device-a'),'second employee device excluded');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into push_results values('lease-a',api.employee_push_claim(20)->0);
select is(jsonb_array_length(api.employee_push_claim(20)),0,'live lease excludes a second claim');
insert into push_results values('target-a',api.employee_push_target(
 (select (value->>'delivery_id')::uuid from push_results where name='lease-a'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-a')));
select is((select value->>'notification_id' from push_results where name='target-a'),pg_temp.pid('notice-a')::text,'worker target is exact queued notification');
select ok(not (select value ?| array['body','title','employee_id','user_id'] from push_results where name='target-a'),'worker target excludes HR content/subjects');
select is(api.employee_push_finish((select (value->>'delivery_id')::uuid from push_results where name='lease-a'),
 pg_temp.pid('wrong-lease'),'sent'),false,'stale lease cannot acknowledge delivery');
select is(api.employee_push_finish((select (value->>'delivery_id')::uuid from push_results where name='lease-a'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-a'),'retry'),true,'current lease records retry');
select is(jsonb_array_length(api.employee_push_claim(20)),0,'backoff prevents immediate retry');
reset role;
update employee_push.deliveries set available_at=clock_timestamp()-interval '1 second' where notification_id=pg_temp.pid('notice-a');
set local role service_role;
insert into push_results values('lease-retry',api.employee_push_claim(20)->0);
select ok((select value->>'lease_id' from push_results where name='lease-retry')<>
 (select value->>'lease_id' from push_results where name='lease-a'),'retry issues a new lease identity');
reset role;
update people_private.account_links set status='revoked',version=version+1 where id=pg_temp.pid('employee-a.link');
set local role service_role;
select is(api.employee_push_target((select (value->>'delivery_id')::uuid from push_results where name='lease-retry'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-retry')),null::jsonb,'revoked link suppresses target after claim');
reset role;
select is((select state from employee_push.deliveries where notification_id=pg_temp.pid('notice-a')),'skipped','revoked target is terminally skipped');
select pg_temp.push_actor('employee-a');
set local role authenticated;
select is(api.employee_push_remove(pg_temp.pid('device-a'),pg_temp.pid('remove-after-revoke'))->>'removed','true','own removal succeeds after People link revocation');
reset role;
select ok((select token is null and token_hash is null and status='removed' from employee_push.devices
 where installation_id=pg_temp.pid('device-a')),'removal wipes private target');

-- Missing sessions cannot register, even with a valid user/link/permissions.
select pg_temp.push_actor('employee-b','aal1','missing-session');
set local role authenticated;
select throws_ok($$select pg_temp.push_register('device-missing-session','missing-session')$$,
 '42501','PUSH_SESSION_REQUIRED','JWT session must exist for the exact actor');
reset role;
update core.roles set requires_mfa=true where id=pg_temp.pid('employee-role');
select pg_temp.push_actor('employee-b');
set local role authenticated;
select throws_ok($$select pg_temp.push_register('device-b','mfa-denied','SYNTHETIC_FID_B_12345678901234567890')$$,
 '42501',null,'MFA role cannot register with AAL1');
reset role;
update core.roles set requires_mfa=false where id=pg_temp.pid('employee-role');
update billing.plan_entitlements set enabled=false where plan_code='employee_push_isolated' and entitlement_code='module.people';
set local role authenticated;
select throws_ok($$select pg_temp.push_register('device-b','module-denied','SYNTHETIC_FID_B_12345678901234567890')$$,
 '42501','PEOPLE_ENTITLEMENT_REQUIRED','disabled People entitlement blocks registration');
select is(api.employee_push_remove(pg_temp.pid('device-b'),pg_temp.pid('remove-after-module-loss'))->>'removed','true','own removal still succeeds after module loss');
reset role;
update billing.plan_entitlements set enabled=true where plan_code='employee_push_isolated' and entitlement_code='module.people';
set local role authenticated;
select pg_temp.push_register('device-b','register-b-again','SYNTHETIC_FID_B_12345678901234567890');
select is(api.employee_push_remove(pg_temp.pid('device-b'),pg_temp.pid('remove-after-module-loss'))->>'removed','false','historic removal replay cannot prove or revoke a newer active registration');
reset role;
insert into workflow.notifications(id,tenant_id,legal_entity_id,branch_id,recipient_id,notification_type,title,body,created_by,updated_by)
values(pg_temp.pid('notice-b'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-b'),
 'people.test','Synthetic notice','Synthetic body',pg_temp.pid('employee-a'),pg_temp.pid('employee-a'));
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into push_results values('lease-b',api.employee_push_claim(20)->0);
reset role;
delete from auth.sessions where id=pg_temp.pid('employee-b.session');
set local role service_role;
select is(api.employee_push_target((select (value->>'delivery_id')::uuid from push_results where name='lease-b'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-b')),null::jsonb,'deleted session invalidates previously claimed target');
reset role;
select is((select count(*) from employee_push.devices where user_id=pg_temp.pid('employee-b')),0::bigint,'session deletion cascades private binding');
select is((select count(*) from employee_push.deliveries where notification_id=pg_temp.pid('notice-b')),0::bigint,'session deletion removes queued deliveries');

-- Re-register under a fresh session to exercise invalid-target acknowledgement.
insert into auth.sessions(id,user_id,created_at,updated_at)
values(pg_temp.pid('employee-b.session2'),pg_temp.pid('employee-b'),now(),now());
select pg_temp.push_actor('employee-b','aal1','employee-b.session2');
set local role authenticated;
select pg_temp.push_register('device-b','register-b-new-session','SYNTHETIC_FID_B_12345678901234567890');
reset role;
insert into workflow.notifications(id,tenant_id,legal_entity_id,branch_id,recipient_id,notification_type,title,body,created_by,updated_by)
values(pg_temp.pid('notice-invalid'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-b'),
 'people.test','Synthetic notice','Synthetic body',pg_temp.pid('employee-a'),pg_temp.pid('employee-a'));
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
insert into push_results values('lease-invalid',api.employee_push_claim(20)->0);
select is(api.employee_push_finish((select (value->>'delivery_id')::uuid from push_results where name='lease-invalid'),
 (select (value->>'lease_id')::uuid from push_results where name='lease-invalid'),'invalid_token'),true,'worker can retire exact invalid target');
reset role;
select ok((select token is null and token_hash is null and status='invalid' from employee_push.devices
 where installation_id=pg_temp.pid('device-b')),'invalid target acknowledgement wipes FID');
select is((select state from employee_push.deliveries where notification_id=pg_temp.pid('notice-invalid')),'dead','invalid target does not retry forever');
select ok(not exists(select 1 from core.role_permissions where role_id=pg_temp.pid('employee-role') and
 permission_code not in ('people.view','people.self.view')),'ordinary employees still hold no staff grants');
select * from finish();
rollback;
