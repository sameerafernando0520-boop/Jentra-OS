-- ISOLATED LOCAL/CI ONLY. Source candidates and synthetic data roll back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
\ir ../20261023090000_employee_push.sql
\ir ../20261025090000_employee_self_service.sql
\ir ../20261025100000_employee_cases_documents_notifications.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();
create function pg_temp.pid(label text) returns uuid language sql immutable as
 $$select md5('employee-cases-isolated-rollback-v1:'||label)::uuid$$;
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
values(pg_temp.pid('tenant'),'Synthetic push rollback','employee-cases-isolated-rollback',pg_temp.pid('employee-a'));
insert into core.legal_entities(id,tenant_id,name,code,created_by)
values(pg_temp.pid('entity'),pg_temp.pid('tenant'),'Synthetic entity','PUSHQA',pg_temp.pid('employee-a'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
select pg_temp.pid(label),pg_temp.pid('tenant'),pg_temp.pid('entity'),'Synthetic '||label,
 case when label='branch' then 'PUSH1' else 'PUSH2' end,pg_temp.pid('employee-a')
from unnest(array['branch','other-branch']) label;
insert into billing.plans(code,name) values('employee_cases_isolated','Synthetic push plan');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled)
values('employee_cases_isolated','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.pid('tenant'),'employee_cases_isolated','trialing',5,now()+interval '2 days');
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


-- Authority fixture adds one scoped HR owner; employees keep only view/self.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
values(pg_temp.pid('hr-owner'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','hr@employee-cases.rollback.invalid','',now(),now(),now());
insert into auth.sessions(id,user_id,created_at,updated_at) values(pg_temp.pid('hr-owner.session'),pg_temp.pid('hr-owner'),now(),now());
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.pid('hr-owner.membership'),pg_temp.pid('tenant'),pg_temp.pid('hr-owner'),'active');
insert into core.roles(id,tenant_id,code,name,requires_mfa) values(pg_temp.pid('hr-role'),pg_temp.pid('tenant'),'cases.hr','Synthetic HR',true);
insert into core.role_permissions(tenant_id,role_id,permission_code) select pg_temp.pid('tenant'),pg_temp.pid('hr-role'),cap
from unnest(array['people.view','people.cases.manage','people.hr.documents.manage','people.hr.documents.view','people.hr.documents.publish']) cap;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.pid('tenant'),pg_temp.pid('hr-owner.membership'),pg_temp.pid('hr-role'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('hr-owner'));
insert into core.memberships(id,tenant_id,user_id,status) values(pg_temp.pid('outsider.membership'),pg_temp.pid('tenant'),pg_temp.pid('outsider'),'active');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.pid('tenant'),pg_temp.pid('outsider.membership'),pg_temp.pid('hr-role'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('hr-owner'));
insert into people_private.policies(id,tenant_id,legal_entity_id,purpose,created_by)
values(pg_temp.pid('policy'),pg_temp.pid('tenant'),pg_temp.pid('entity'),'Synthetic case/doc policy',pg_temp.pid('hr-owner'));
insert into people_private.worker_readiness(contract,artifact_digest,storage_probe_digest)
values('w4-private-hr-v1',repeat('a',64),repeat('b',64));
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.pid('tenant'),pg_temp.pid('employee-role'),cap from unnest(array[
 'people.payroll.payslip.self','people.hr.cases.self.manage','people.hr.documents.self.view'])cap;
insert into finance.accounts(id,tenant_id,legal_entity_id,code,name,account_type,normal_balance,created_by,updated_by)
values(pg_temp.pid('net-account'),pg_temp.pid('tenant'),pg_temp.pid('entity'),'CASE_NET','Synthetic net payable','liability','credit',pg_temp.pid('hr-owner'),pg_temp.pid('hr-owner'));
insert into people_payroll.settings_versions(id,tenant_id,legal_entity_id,version,net_account_id,reason,published_by)
values(pg_temp.pid('pay-settings'),pg_temp.pid('tenant'),pg_temp.pid('entity'),1,pg_temp.pid('net-account'),'Synthetic rollback',pg_temp.pid('hr-owner'));
insert into people_payroll.runs(id,tenant_id,legal_entity_id,branch_id,name,start_date,end_date_exclusive,posting_date,currency_code,status,created_by)
values(pg_temp.pid('pay-run'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),'Synthetic rollback',current_date-10,current_date,current_date,'LKR','posted',pg_temp.pid('hr-owner'));
insert into people_payroll.run_revisions(id,tenant_id,legal_entity_id,run_id,version,settings_version_id,digest,employee_count,prepared_by)
select pg_temp.pid('pay-revision-'||n),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('pay-run'),n,pg_temp.pid('pay-settings'),repeat('d',64),2,pg_temp.pid('hr-owner')
from generate_series(1,2)n;
insert into people_payroll.run_employees(tenant_id,legal_entity_id,branch_id,run_id,employee_id)
select pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('pay-run'),pg_temp.pid(label||'.employee')
from unnest(array['employee-a','employee-b'])label;
insert into people_payroll.employee_calculations(id,tenant_id,legal_entity_id,run_id,revision_id,employee_id,inputs,input_digest,calculation,gross,deductions,employer_cost,net)
select pg_temp.pid(label||'.calculation'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('pay-run'),pg_temp.pid('pay-revision-1'),pg_temp.pid(label||'.employee'),
 '{}',repeat('e',64),'{}',1,0,0,1 from unnest(array['employee-a','employee-b'])label;
insert into people_payroll.payslips(id,tenant_id,legal_entity_id,branch_id,run_id,employee_id,calculation_id,revision_digest)
select pg_temp.pid(label||'.payslip'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('pay-run'),pg_temp.pid(label||'.employee'),pg_temp.pid(label||'.calculation'),repeat('d',64)
from unnest(array['employee-a','employee-b'])label;
create function pg_temp.create_case(label text,command text,changes jsonb default '{}') returns jsonb language sql as $$
 select api.employee_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid(command),'create',
 jsonb_build_object('id',pg_temp.pid(label),'category','general','subject','Synthetic subject','body','SYNTHETIC_PRIVATE_CASE_BODY')||changes)
$$;
create function pg_temp.staff_case(action text,expected bigint,body text default null) returns jsonb language sql as $$
 select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('case-a'),
 pg_temp.pid('hr-'||action),expected,action,body)
$$;
create function pg_temp.publish(visible boolean,expected bigint) returns jsonb language sql as $$
 select api.employee_hr_document_publish(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('doc-a'),
 pg_temp.pid('publish-'||expected::text||'-'||visible::text),1,expected,visible,
 case when visible then 'Reviewed employee copy' end)
$$;
create function pg_temp.doc_ticket(publication bigint default 1) returns jsonb language sql as $$
 select api.employee_document_access_ticket(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('doc-a'),1,publication)
$$;
insert into people_private.documents(id,tenant_id,legal_entity_id,branch_id,employee_id,policy_id,classification,purpose,mime,byte_size,checksum,object_path,status,created_by)
values(pg_temp.pid('doc-a'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-a.employee'),pg_temp.pid('policy'),
 'review-evidence','PRIVATE_STAFF_PURPOSE','text/plain',10,repeat('c',64),'PRIVATE_OBJECT_PATH','active',pg_temp.pid('hr-owner'));

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='employee_self' and relkind='r'),'all additive self-service tables force RLS');
select ok(not has_table_privilege('authenticated','employee_self.case_messages','SELECT'),'employee cannot bypass own case projection');
select ok(not has_function_privilege('authenticated','employee_self.notify_employee(uuid,uuid,uuid,uuid,text,uuid,bigint)','EXECUTE'),'employee cannot manufacture notices');
select ok(not has_function_privilege('service_role','api.people_hr_service_document_staff_v1(uuid,uuid)','EXECUTE'),'legacy staff service path remains internal');
select ok(not has_function_privilege('anon','api.employee_case_command(uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE'),'anonymous case commands denied');

select pg_temp.push_actor('employee-a');set local role authenticated;
select throws_ok($$select pg_temp.create_case('case-a','create-case')$$,'42501',null,'case creation requires MFA');
reset role;select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
insert into push_results values('case-created',pg_temp.create_case('case-a','create-case'));
select is((select value->>'employee_id' from push_results where name='case-created'),pg_temp.pid('employee-a.employee')::text,'case subject derives from accepted account');
select is(pg_temp.create_case('case-a','create-case'),(select value from push_results where name='case-created'),'same command returns exact original acknowledgement');
select is(api.employee_case_receipt(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('create-case'),pg_temp.pid('case-a'),'employee_case_command')->'receipt',
 (select value from push_results where name='case-created'),'receipt-only recovery returns original metadata acknowledgement without private body');
select throws_ok($$select api.employee_case_receipt(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('create-case'),pg_temp.pid('foreign-case'),'employee_case_command')$$,
 '42501','EMPLOYEE_RECEIPT_DENIED','receipt-only recovery rejects a substituted subject');
select is(api.employee_case_receipt(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('not-applied-command'),pg_temp.pid('not-applied-case'),'employee_case_command')->>'abandoned',
 'true','missing receipt is atomically fenced before private pending body can be removed');
select throws_ok($$select pg_temp.create_case('not-applied-case','not-applied-command')$$,'55000','EMPLOYEE_COMMAND_ABANDONED','a delayed original cannot commit after missing-receipt recovery fence');
select throws_ok($$select pg_temp.create_case('case-a','create-case','{"body":"changed"}')$$,'22023','EMPLOYEE_COMMAND_REUSED','changed retry cannot alter original private case');
select throws_ok($$select pg_temp.create_case('forged','forged','{"employee_id":"00000000-0000-4000-8000-000000000099"}')$$,'22023',null,'employee selector is rejected');
select throws_ok($$select pg_temp.create_case('bad-pay','bad-pay',jsonb_build_object('category','payroll','payslip_id',pg_temp.pid('foreign-payslip'),'payslip_revision_id',pg_temp.pid('foreign-revision')))$$,
 '42501',null,'payroll query cannot bind an unowned or nonexistent revision');
select throws_ok($$select pg_temp.create_case('bad-pay-owner','bad-pay-owner',jsonb_build_object('category','payroll','payslip_id',pg_temp.pid('employee-b.payslip'),'payslip_revision_id',pg_temp.pid('pay-revision-1')))$$,
 '42501','EMPLOYEE_PAYSLIP_DENIED','a real foreign payslip cannot be attached to own case');
select throws_ok($$select pg_temp.create_case('bad-pay-revision','bad-pay-revision',jsonb_build_object('category','payroll','payslip_id',pg_temp.pid('employee-a.payslip'),'payslip_revision_id',pg_temp.pid('pay-revision-2')))$$,
 '42501','EMPLOYEE_PAYSLIP_DENIED','a real different revision cannot be substituted for own payslip');
select is(jsonb_array_length(api.employee_cases_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),1,'own case appears once');
select throws_ok($$select api.employee_cases_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('foreign-cursor'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','case cursor must remain in current accepted subject');
select is(pg_temp.create_case('pay-case-a','pay-case-a',jsonb_build_object('category','payroll','payslip_id',pg_temp.pid('employee-a.payslip'),'payslip_revision_id',pg_temp.pid('pay-revision-1')))->>'status',
 'open','own issued payslip can create a revision-bound payroll question');
select is(api.employee_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('case-a'))#>>'{case,messages,0,body}',
 'SYNTHETIC_PRIVATE_CASE_BODY','own detail includes private message');
select throws_ok($$select api.employee_hr_cases_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))$$,'42501',null,'ordinary employee cannot use staff queue');
select is(jsonb_array_length(api.employee_documents_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),0,'active staff document is invisible by default');
select throws_ok($$select pg_temp.doc_ticket()$$,'42501','HR_DOCUMENT_DENIED','unpublished document cannot be ticketed');
select throws_ok($$select pg_temp.publish(true,0)$$,'42501',null,'employee cannot publish staff documents');
select pg_temp.push_register('device-a','register-a');
reset role;select pg_temp.push_actor('employee-b','aal2');set local role authenticated;
select is(jsonb_array_length(api.employee_cases_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),0,'foreign employee case list is empty');
select is(api.employee_case_receipt(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('create-case'),pg_temp.pid('case-a'),'employee_case_command')->'receipt',
 'null'::jsonb,'foreign actor receipt is not disclosed by recovery lookup');
select throws_ok($$select api.employee_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('case-a'))$$,
 '42501','EMPLOYEE_CASE_DENIED','guessed foreign case detail denied');
select throws_ok($$select api.employee_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('foreign-reply'),'reply',jsonb_build_object('id',pg_temp.pid('case-a'),'expected_version',1,'body','foreign'))$$,
 '42501','EMPLOYEE_CASE_DENIED','foreign employee cannot reply');
reset role;select pg_temp.push_actor('hr-owner');set local role authenticated;
select throws_ok($$select pg_temp.staff_case('claim',1)$$,'42501',null,'HR ownership requires MFA');
reset role;select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select is(pg_temp.staff_case('claim',1)->>'status','in_progress','HR actor claims accountable ownership');
reset role;select pg_temp.push_actor('outsider','aal2');set local role authenticated;
select throws_ok($$select pg_temp.staff_case('reply',2,'unowned')$$,'42501','EMPLOYEE_CASE_OWNER_REQUIRED','another authorized HR actor must not silently reply as owner');
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('case-a'),pg_temp.pid('unowned-reassignment'),2,'assign',null,pg_temp.pid('outsider'))$$,
 '42501','EMPLOYEE_CASE_OWNER_REQUIRED','unowned HR staff cannot bypass ownership by reassigning the case to themselves');
reset role;select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select is(pg_temp.staff_case('reply',2,'SYNTHETIC_PRIVATE_HR_REPLY')->>'version','3','owner reply advances exact case version');
select is(pg_temp.staff_case('resolve',3)->>'status','resolved','owner resolves with immutable history');
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('case-a'),pg_temp.pid('stale-reply'),2,'reply','stale')$$,
 '40001','VERSION_CONFLICT','stale staff version does not create a reply');
reset role;
delete from core.role_permissions where role_id=pg_temp.pid('hr-role') and permission_code='people.hr.documents.publish';
select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select throws_ok($$select pg_temp.publish(true,0)$$,'42501',null,'existing upload/view staff cannot publish without the new privileged capability');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.pid('tenant'),pg_temp.pid('hr-role'),'people.hr.documents.publish');
select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select is(pg_temp.publish(true,0)->>'visible','true','authorized staff explicitly publishes one reviewed copy');
select is(pg_temp.publish(true,0)->>'version','1','exact publication retry recovers original acknowledgement');
select is(api.employee_hr_document_publication(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('doc-a'))->>'publication_version',
 '1','authorized publication metadata supplies the optimistic version without manual entry');
select throws_ok($$select api.employee_hr_document_publish(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('doc-a'),
 pg_temp.pid('publish-0-true'),1,0,true,'Changed label')$$,'22023','EMPLOYEE_COMMAND_REUSED','publication command cannot be replayed with altered content');
select throws_ok($$select api.employee_hr_document_publication(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('other-branch'),pg_temp.pid('doc-a'))$$,
 '42501',null,'publication metadata does not reveal a document in a foreign branch');
reset role;
select throws_ok($$update employee_self.case_history set status='closed' where case_id=pg_temp.pid('case-a')$$,
 '55000','EMPLOYEE_CASE_HISTORY_IMMUTABLE','committed lifecycle history cannot be rewritten');
select throws_ok($$update employee_self.case_messages set body='rewritten' where case_id=pg_temp.pid('case-a')$$,
 '55000','EMPLOYEE_CASE_HISTORY_IMMUTABLE','case messages cannot be silently edited');
select throws_ok($$delete from employee_self.case_receipts where actor_id=pg_temp.pid('employee-a')$$,
 '55000','EMPLOYEE_CASE_HISTORY_IMMUTABLE','command receipts cannot be deleted to unlock redispatch');
select is((select count(*) from workflow.notifications where notification_type='people.employee.cases'),2::bigint,'only actual HR reply and resolution create notices');
select ok((select bool_and(title='Jentra Employee' and body='You have an update. Open the app to view it.' and source_context::text not like '%PRIVATE%')
 from workflow.notifications where notification_type like 'people.employee.%'),'notification title/body/context contain no case/document private text');
select is((select count(*) from employee_push.deliveries),3::bigint,'existing push mirror observes exactly one notice per transition');
select is(employee_self.notify_employee(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-a.employee'),'cases',pg_temp.pid('case-a'),3),null::uuid,'source retry is deduplicated before push insertion');
select is((select count(*) from employee_self.case_history where case_id=pg_temp.pid('case-a')),4::bigint,'create ownership reply and resolve are auditable');
select is((select payslip_revision_id from employee_self.cases where id=pg_temp.pid('pay-case-a')),pg_temp.pid('pay-revision-1'),'pay question retains exact immutable revision binding');

select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
select throws_ok($$select api.employee_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('resolved-reply'),'reply',jsonb_build_object('id',pg_temp.pid('case-a'),'expected_version',4,'body','reply'))$$,
 '22023','EMPLOYEE_CASE_CLOSED','resolved case cannot silently reopen');
select is(jsonb_array_length(api.employee_documents_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),1,'only explicitly published document appears');
select ok(not ((api.employee_documents_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'->0) ?| array['object_path','purpose','created_by']),
 'employee list excludes private path and staff purpose');
select is(api.employee_documents_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))#>>'{items,0,publication_version}',
 '1','employee list exposes the exact publication revision needed for a bound download');
select throws_ok($$select api.employee_documents_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('foreign-cursor'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','document cursor cannot escape the current published subject');
insert into push_results values('ticket-a',pg_temp.doc_ticket());
select ok(not ((select value from push_results where name='ticket-a') ? 'object_path'),'employee ticket never contains storage path');
reset role;select pg_temp.push_actor('employee-b','aal2');set local role authenticated;
select throws_ok($$select pg_temp.doc_ticket()$$,'42501','HR_DOCUMENT_DENIED','published copy stays bound to its employee');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
insert into push_results values('consumed',api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-a'),pg_temp.pid('employee-a')));
select is((select value->>'object_path' from push_results where name='consumed'),'PRIVATE_OBJECT_PATH','private worker receives exact published object after independent recheck');
select throws_ok($$select api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-a'),pg_temp.pid('employee-a'))$$,
 '42501','HR_DOCUMENT_DENIED','employee ticket is one-use');
reset role;select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
insert into push_results values('ticket-revoke',pg_temp.doc_ticket());
reset role;select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select pg_temp.publish(false,1);
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-revoke'),pg_temp.pid('employee-a'))$$,
 '42501','HR_DOCUMENT_DENIED','withdrawn publication invalidates an already-issued ticket');
reset role;
select is((select count(*) from workflow.notifications where notification_type='people.employee.documents'),0::bigint,'publication withdrawal removes stale inbox row and mirrored delivery');
select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;select pg_temp.publish(true,2);
reset role;select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
select throws_ok($$select pg_temp.doc_ticket(1)$$,'42501','HR_DOCUMENT_DENIED','withdrawal and republication invalidate an old employee publication revision');
insert into push_results values('ticket-link-revoke',pg_temp.doc_ticket(3));
reset role;update people_private.account_links set status='revoked',version=version+1 where id=pg_temp.pid('employee-a.link');
select is((select count(*) from workflow.notifications where notification_type like 'people.employee.%'),0::bigint,'link revocation removes all previous generic employee notices');
select is((select count(*) from employee_push.deliveries),0::bigint,'revocation removes pending push mirrors with their notice');
select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
select throws_ok($$select pg_temp.create_case('case-a','create-case')$$,'42501',null,'receipt replay rechecks revoked subject authority');
select throws_ok($$select api.employee_case_receipt(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('create-case'),pg_temp.pid('case-a'),'employee_case_command')$$,
 '42501',null,'receipt-only recovery rechecks revoked accepted link before inspecting saved receipt');
reset role;select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-link-revoke'),pg_temp.pid('employee-a'))$$,
 '42501','HR_DOCUMENT_DENIED','revoked accepted link invalidates private consumption');
reset role;
update people_private.account_links set status='accepted',version=version+1 where id=pg_temp.pid('employee-a.link');
select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
insert into push_results values('ticket-session-expired',pg_temp.doc_ticket(3));
reset role;update auth.sessions set not_after=statement_timestamp()-interval '1 minute' where id=pg_temp.pid('employee-a.session');
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-session-expired'),pg_temp.pid('employee-a'))$$,
 '42501','HR_DOCUMENT_DENIED','retained expired session cannot consume document');
reset role;update auth.sessions set not_after=null where id=pg_temp.pid('employee-a.session');
select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
insert into push_results values('ticket-cap-revoked',pg_temp.doc_ticket(3));
reset role;
delete from core.role_permissions where role_id=pg_temp.pid('employee-role') and permission_code='people.hr.documents.self.view';
select set_config('request.jwt.claims','{"role":"service_role"}',true);set local role service_role;
select throws_ok($$select api.people_hr_service_document((select (value->>'ticket_id')::uuid from push_results where name='ticket-cap-revoked'),pg_temp.pid('employee-a'))$$,
 '42501','HR_DOCUMENT_DENIED','published document capability revocation is checked again on consume');
reset role;
insert into core.role_permissions(tenant_id,role_id,permission_code) values(pg_temp.pid('tenant'),pg_temp.pid('employee-role'),'people.hr.documents.self.view');

-- Ownership recovery is based on durable scoped authorization, never whether
-- the original owner happens to be signed in. Case managers need no unrelated
-- account-link permission to select another eligible case owner.
select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
select throws_ok($$select api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))$$,
 '42501',null,'employee self access cannot enumerate HR case owners');
select pg_temp.create_case('orphan-case','orphan-create');
reset role;select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select is(jsonb_array_length(api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),2,
 'case manager can select eligible staff without account-link management');
select ok(not (api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'->0 ? 'email'),
 'owner picker excludes login email and private personnel fields');
select throws_ok($$select api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('other-branch'))$$,
 '42501',null,'owner picker cannot enumerate a foreign branch');
select throws_ok($$select api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('employee-a.membership'))$$,
 '22023','EMPLOYEE_CURSOR_INVALID','owner cursor must itself be an eligible scoped owner');
select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-initial-claim'),1,'claim');
reset role;select pg_temp.push_actor('outsider','aal2');set local role authenticated;
select is(api.employee_hr_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'))->>'owner_available',
 'true','active scoped case owner remains protected');
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-active-takeover'),2,'claim')$$,'42501','EMPLOYEE_CASE_OWNER_REQUIRED','another case manager cannot take over an active owner');
reset role;update auth.sessions set not_after=statement_timestamp()-interval '1 minute' where id=pg_temp.pid('hr-owner.session');
set local role authenticated;
select is(api.employee_hr_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'))->>'owner_available',
 'true','owner session expiry does not make an enquiry orphaned');
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-expired-session-takeover'),2,'claim')$$,'42501','EMPLOYEE_CASE_OWNER_REQUIRED','temporary owner session loss cannot bypass ownership');
reset role;
update auth.sessions set not_after=null where id=pg_temp.pid('hr-owner.session');
delete from core.role_assignments where membership_id=pg_temp.pid('hr-owner.membership') and role_id=pg_temp.pid('hr-role');
set local role authenticated;
select is(api.employee_hr_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'))->>'owner_available',
 'false','permanent scoped role revocation exposes recoverable ownership');
select is(jsonb_array_length(api.employee_hr_case_owners(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),1,
 'revoked owner is no longer offered as an assignee');
reset role;update core.memberships set status='suspended' where id=pg_temp.pid('outsider.membership');
set local role authenticated;
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-inactive-claim'),2,'claim')$$,'42501',null,'an inactive claimant cannot recover orphan ownership');
reset role;update core.memberships set status='active' where id=pg_temp.pid('outsider.membership');
set local role authenticated;
insert into push_results values('orphan-reclaimed',api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-reclaim'),2,'claim'));
select is(api.employee_hr_case_detail(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'))->>'owner_user_id',
 pg_temp.pid('outsider')::text,'eligible replacement takes accountable ownership');
select is(api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-reclaim'),2,'claim'),(select value from push_results where name='orphan-reclaimed'),'recovery retry returns the original receipt');
select throws_ok($$select api.employee_hr_case_command(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('orphan-case'),
 pg_temp.pid('orphan-reclaim'),2,'claim','changed')$$,'22023','EMPLOYEE_COMMAND_REUSED','recovery receipt cannot be reused with altered input');
reset role;
select is((select count(*) from employee_self.case_history where case_id=pg_temp.pid('orphan-case')),3::bigint,
 'recovery adds one immutable owner transition without repeating on retry');
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
values(pg_temp.pid('tenant'),pg_temp.pid('hr-owner.membership'),pg_temp.pid('hr-role'),pg_temp.pid('entity'),pg_temp.pid('branch'),pg_temp.pid('hr-owner'));
delete from core.role_permissions where role_id=pg_temp.pid('employee-role') and permission_code='people.hr.cases.self.manage';
select pg_temp.push_actor('employee-a','aal2');set local role authenticated;
select throws_ok($$select pg_temp.create_case('case-cap-missing','case-cap-missing')$$,'42501',null,'generic employee self view does not grant case creation');
reset role;
update people_private.policies set closed_at=now()-interval '31 days' where id=pg_temp.pid('policy');
select pg_temp.push_actor('hr-owner','aal2');set local role authenticated;
select is(jsonb_array_length(api.employee_hr_cases_list(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('branch'))->'items'),0,'expired policy hides private case subjects from staff queue');
reset role;
insert into people_private.purge_jobs(id,tenant_id,legal_entity_id,employee_id)
values(pg_temp.pid('purge-job'),pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('employee-a.employee'));
insert into people_private.erasure_events(tenant_id,legal_entity_id,employee_id,job_id,contract,profile_revisions,review_revisions,documents)
values(pg_temp.pid('tenant'),pg_temp.pid('entity'),pg_temp.pid('employee-a.employee'),pg_temp.pid('purge-job'),'w4-private-hr-v1',0,0,1);
select ok((select subject is null and erased_at is not null from employee_self.cases where id=pg_temp.pid('case-a')),'existing HR erasure also removes case subject');
select ok((select bool_and(body is null) from employee_self.case_messages where case_id=pg_temp.pid('case-a')),'existing HR erasure clears all employee/HR case messages');
select ok((select not visible and label is null from employee_self.document_publications where document_id=pg_temp.pid('doc-a')),'erasure removes employee publication labels and visibility');
select * from finish();
rollback;
