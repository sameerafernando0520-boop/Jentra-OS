-- ISOLATED LOCAL/CI DATABASE ONLY. Never run against hosted/production projects.
-- Existing Supabase migrations must already be installed. The uninstalled statutory
-- payroll candidate and every synthetic fixture are transaction-local and rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- The local-only runner inlines this candidate before staging the suite.
\ir ../20261120090000_lk_statutory_payroll.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
-- The runner replaces the next line with the shared worked cases
-- (packages/jentra_domain/test/fixtures/lk_statutory_payroll_cases.json).
-- LK_STATUTORY_CASES
select no_plan();

create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('lk-statutory-rollback-20261120:'||p)::uuid$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;

-- Worked cases: build frozen inputs and rules, then compare exact amounts or the blocker.
create function pg_temp.lk_actual(c jsonb) returns jsonb language plpgsql as $$
declare doc jsonb:=(select body from lk_doc);s date:=coalesce((c->>'start_date')::date,'2026-05-01'::date);
 x date:=coalesce((c->>'end_date_exclusive')::date,'2026-06-01'::date);rules jsonb:='[]';comps jsonb:='{}';
 e jsonb;code text;emp jsonb;rs jsonb;input jsonb;result jsonb;lines jsonb:='{}';l jsonb;msg text;detail text;begin
 for e in select value from jsonb_array_elements(c->'earnings') loop
  rules:=rules||jsonb_build_array(jsonb_build_object('id',md5((c->>'name')||(e->>'code'))::uuid,
   'component_id',md5('component'||(e->>'code'))::uuid,'code',e->>'code','classification','earning','basis','fixed',
   'proration','none','rounding','half_away','precision',2,'amount',e->>'amount','ratio_numerator',1,'ratio_denominator',1,
   'cap',null,'start_date','2025-04-01','end_date_exclusive','2027-04-01','currency_code','LKR'));
  if coalesce((e->>'classified')::boolean,true) then
   comps:=comps||jsonb_build_object(e->>'code',jsonb_build_object('epf',(e->>'epf')::boolean,'etf',(e->>'etf')::boolean,
    'apit',(e->>'apit')::boolean));
  end if;
 end loop;
 for code in select jsonb_array_elements_text(coalesce(c->'statutory_codes','["EPF_EE","EPF_ER","ETF_ER","APIT"]'::jsonb)) loop
  rules:=rules||jsonb_build_array(jsonb_build_object('id',md5((c->>'name')||code)::uuid,'component_id',md5('component'||code)::uuid,
   'code',code,'classification',case when code in('EPF_EE','APIT') then 'deduction' else 'employer_cost' end,
   'basis','statutory','proration','none','rounding','half_away','precision',2,'amount','0','ratio_numerator',1,
   'ratio_denominator',1,'cap',null,'start_date','2025-04-01','end_date_exclusive','2027-04-01','currency_code','LKR'));
 end loop;
 rs:=case when c ? 'rule_set' then c->'rule_set' else doc->'rule_set' end;
 emp:=case when c ? 'employee' then c->'employee' else (doc->'employee')||coalesce(c->'employee_overrides','{}'::jsonb) end;
 input:=jsonb_build_object('start_date',s,'end_date_exclusive',x,'period_days',x-s,'eligible_days',x-s,
  'paid_seconds','0','planned_seconds','0','statutory',jsonb_build_object('rule_set',rs,'employee',emp,'components',comps,
   'cumulative_regular_profits_before',coalesce(c->>'cumulative_regular_profits_before','0')));
 begin
  result:=people_payroll.calculate(input,rules,'LKR');
 exception when others then
  get stacked diagnostics msg=message_text,detail=pg_exception_detail;
  return jsonb_build_object('blocked',case when msg='PAYROLL_STATUTORY_BLOCKED' then detail else msg end);
 end;
 for l in select value from jsonb_array_elements(result->'lines') where value->>'basis'='statutory' loop
  lines:=lines||jsonb_build_object(l->>'code',(l->>'amount')::numeric);
 end loop;
 return jsonb_build_object('lines',lines,'gross',(result->>'gross')::numeric,'deductions',(result->>'deductions')::numeric,
  'employer_cost',(result->>'employer_cost')::numeric,'net',(result->>'net')::numeric);
end $$;
create function pg_temp.lk_expected(c jsonb) returns jsonb language sql immutable as $$
 select case when c->'expect' ? 'blocked' then c->'expect' else jsonb_build_object(
  'lines',(select jsonb_object_agg(k,v::numeric) from jsonb_each_text(c->'expect'->'lines') t(k,v)),
  'gross',(c->'expect'->>'gross')::numeric,'deductions',(c->'expect'->>'deductions')::numeric,
  'employer_cost',(c->'expect'->>'employer_cost')::numeric,'net',(c->'expect'->>'net')::numeric) end
$$;
select is(pg_temp.lk_actual(c),pg_temp.lk_expected(c),c->>'name')
 from lk_doc,jsonb_array_elements(body->'cases') c;

select is(
 people_payroll.calculate('{"start_date":"2026-05-01","end_date_exclusive":"2026-06-01","period_days":31,"eligible_days":31,
  "paid_seconds":"0","planned_seconds":"0"}'::jsonb,
  '[{"id":"00000000-0000-4000-8000-000000000001","code":"BASIC","classification":"earning","basis":"fixed","proration":"none",
   "rounding":"half_away","precision":2,"amount":"200000","ratio_numerator":1,"ratio_denominator":1,"cap":null,
   "start_date":"2025-04-01","end_date_exclusive":"2027-04-01","currency_code":"LKR"}]'::jsonb,'LKR'),
 people_payroll.calculate_core('{"start_date":"2026-05-01","end_date_exclusive":"2026-06-01","period_days":31,"eligible_days":31,
  "paid_seconds":"0","planned_seconds":"0"}'::jsonb,
  '[{"id":"00000000-0000-4000-8000-000000000001","code":"BASIC","classification":"earning","basis":"fixed","proration":"none",
   "rounding":"half_away","precision":2,"amount":"200000","ratio_numerator":1,"ratio_denominator":1,"cap":null,
   "start_date":"2025-04-01","end_date_exclusive":"2027-04-01","currency_code":"LKR"}]'::jsonb,'LKR'),
 'runs without statutory rules calculate exactly as before');

-- Tenant fixture: creator and reviewer hold every people permission; reader holds none for payroll.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@lk-statutory.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'LK Statutory Rollback','lk-statutory-rollback',pg_temp.wid('creator')),
  (pg_temp.wid('other-tenant'),'Other Rollback','lk-statutory-other-rollback',pg_temp.wid('outsider'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Lanka','LKSYN','LKR','Asia/Colombo',2,pg_temp.wid('creator'));
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('lk_statutory_rollback','LK statutory rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('lk_statutory_rollback','module.people',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'lk_statutory_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active' from unnest(array['creator','reviewer','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true from unnest(array['creator','reviewer','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code
from unnest(array['creator','reviewer']) x cross join core.permissions p where p.module='people';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code from unnest(array['people.view','people.employees.view']) p(code)
join core.permissions c on c.code=p.code;
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),
  case when x='reader' then pg_temp.wid('branch') end,pg_temp.wid('creator')
from unnest(array['creator','reviewer','reader']) x;
insert into people_payroll.components(id,tenant_id,legal_entity_id,code,name,classification) values
  (pg_temp.wid('basic'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'BASIC','Basic salary','earning'),
  (pg_temp.wid('epf-ee'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'EPF_EE','EPF employee','deduction');

select throws_ok($q$insert into people_payroll.rule_versions(id,tenant_id,legal_entity_id,component_id,version,start_date,
  end_date_exclusive,currency_code,basis,proration,rounding,precision,amount,ratio_numerator,ratio_denominator,reason,published_by)
  values(pg_temp.wid('bad-rule'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('basic'),1,'2025-04-01','2027-04-01',
  'LKR','statutory','none','half_away',2,0,1,1,'Wrong component',pg_temp.wid('creator'))$q$,
  '22023','PAYROLL_STATUTORY_RULE_INVALID','only EPF_EE, EPF_ER, ETF_ER and APIT components take the statutory basis');
select lives_ok($q$insert into people_payroll.rule_versions(id,tenant_id,legal_entity_id,component_id,version,start_date,
  end_date_exclusive,currency_code,basis,proration,rounding,precision,amount,ratio_numerator,ratio_denominator,reason,published_by)
  values(pg_temp.wid('epf-rule'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('epf-ee'),1,'2025-04-01','2027-04-01',
  'LKR','statutory','none','half_away',2,0,1,1,'EPF employee contribution',pg_temp.wid('creator'))$q$,
  'an EPF_EE deduction takes the statutory basis');

create function pg_temp.wemployee(p text) returns jsonb language sql as $$
  select api.people_employee_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
    pg_temp.wid(p||'.create'),pg_temp.wid(p||'.create'),now(),jsonb_build_object('action','create',
      'id',pg_temp.wid(p),'code',upper(p),'display_name','Synthetic '||p,'work_email',null,
      'start_date',(now() at time zone 'Asia/Colombo')::date-10,'job_title','Synthetic role','employment_type','permanent'),0)
$$;
select pg_temp.wactor('creator');
select pg_temp.wemployee('employee');

-- Rule set lifecycle.
select pg_temp.wactor('creator');set local role authenticated;
select is((api.people_payroll_statutory_propose_lk(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'2025-04-01','2027-04-01'))->>'status','pending','a proposed rule set starts pending');
select is((api.people_payroll_statutory_propose_lk(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'2025-04-01','2027-04-01'))->>'id',pg_temp.wid('set-1')::text,'proposing again with the same id is idempotent');
select throws_ok($q$select api.people_payroll_statutory_propose_lk(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('set-late'),'2027-04-01','2028-04-01')$q$,'22023','PAYROLL_STATUTORY_PERIOD_INVALID',
  'shipped values cannot be proposed beyond their checked years of assessment');
select throws_ok($q$select api.people_payroll_statutory_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('set-1'),'approve')$q$,'42501','PAYROLL_STATUTORY_SEPARATE_APPROVER_REQUIRED',
  'the proposer cannot approve their own rule set');
reset role;select pg_temp.wactor('reviewer','aal1');set local role authenticated;
select throws_ok($q$select api.people_payroll_statutory_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('set-1'),'approve')$q$,'42501','PAYROLL_MFA_REQUIRED','approval requires MFA');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select is((api.people_payroll_statutory_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'approve'))->>'status','approved','a second person with MFA approves the rule set');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select lives_ok($q$select api.people_payroll_statutory_propose_lk(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('set-2'),'2026-04-01','2027-04-01')$q$,'an overlapping set can be proposed');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($q$select api.people_payroll_statutory_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('set-2'),'approve')$q$,'55000','PAYROLL_STATUTORY_OVERLAP',
  'two approved rule sets cannot cover the same day');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.people_payroll_statutory_rule_sets(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
  '42501',null,'a user without payroll access cannot list rule sets');
reset role;select pg_temp.wactor('outsider');set local role authenticated;
select throws_ok($q$select api.people_payroll_statutory_rule_sets(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
  '42501',null,'another tenant cannot list rule sets');
reset role;
select throws_ok($q$update people_payroll.statutory_rule_sets set epf_employee_percent=9 where id=pg_temp.wid('set-1')$q$,
  '55000','PAYROLL_HISTORY_IMMUTABLE','approved rule set values are immutable');
select throws_ok($q$delete from people_payroll.statutory_rule_sets where id=pg_temp.wid('set-2')$q$,
  '55000','PAYROLL_HISTORY_IMMUTABLE','rule sets cannot be deleted');

-- Classification, employee details and employer registration.
select pg_temp.wactor('creator');set local role authenticated;
select lives_ok($q$select api.people_payroll_component_statutory_set(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('basic-class'),pg_temp.wid('basic'),true,true,true,'Basic salary is liable')$q$,
  'an earning component is classified');
select throws_ok($q$select api.people_payroll_component_statutory_set(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('epf-class'),pg_temp.wid('epf-ee'),true,true,true,'Not an earning')$q$,
  '22023','PAYROLL_STATUTORY_CLASSIFICATION_INVALID','only earnings are classified');
select is((select x->>'epf_liable' from jsonb_array_elements(api.people_payroll_component_statutory(pg_temp.wid('tenant'),
  pg_temp.wid('entity'),pg_temp.wid('branch'))) x where x->>'code'='BASIC'),'true','the latest classifications are listed');
select lives_ok($q$select api.people_payroll_employee_statutory_set(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('employee-statutory'),pg_temp.wid('employee'),
  '{"nic":"199012345678","epf_member_number":"1234","coverage":"standard","apit_case":"regular_primary",
    "resident_or_citizen":true,"primary_employment_declared":true,"joined_or_left_in_year":false,"reason":"Onboarding"}'::jsonb)$q$,
  'employee statutory details are recorded');
select throws_ok($q$select api.people_payroll_employee_statutory_set(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('employee-bad-nic'),pg_temp.wid('employee'),
  '{"nic":"12345","coverage":"standard","apit_case":"regular_primary","resident_or_citizen":true,
    "primary_employment_declared":true,"joined_or_left_in_year":false,"reason":"Typo"}'::jsonb)$q$,
  '23514',null,'an invalid NIC is rejected');
select is((api.people_payroll_employee_statutory(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employee')))->>'nic','199012345678','payroll configurers read the NIC');
select is((api.people_payroll_employer_registration_set(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('employer-1'),'a/12345','b/67890','EPF and ETF registration'))->>'version','1','employer numbers are recorded');
select is((api.people_payroll_employer_registration(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch')))
  ->>'epf_employer_number','A/12345','employer numbers are normalized');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.people_payroll_employee_statutory(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('branch'),pg_temp.wid('employee'))$q$,'42501',null,'users without payroll configuration cannot read the NIC');

-- Frozen inputs: identifiers never enter run inputs.
reset role;
create temporary table lk_inputs as select people_payroll.statutory_inputs(pg_temp.wid('tenant'),pg_temp.wid('entity'),
  pg_temp.wid('employee'),'2026-05-01','2026-06-01',jsonb_build_array(
   jsonb_build_object('component_id',pg_temp.wid('basic'),'code','BASIC','classification','earning','basis','fixed'),
   jsonb_build_object('component_id',pg_temp.wid('epf-ee'),'code','EPF_EE','classification','deduction','basis','statutory'))) body;
select is((select body->'rule_set'->>'id' from lk_inputs),pg_temp.wid('set-1')::text,'the approved set covering the period is frozen');
select is((select body->'employee'->>'has_nic' from lk_inputs),'true','the employee facts are frozen');
select ok((select not (body->'employee' ? 'nic') and not (body->'employee' ? 'epf_member_number') and body::text !~ '199012345678'
  from lk_inputs),'the NIC and member number never enter run inputs');
select is((select body->'components'->'BASIC'->>'epf' from lk_inputs),'true','component classification is frozen');
select is(people_payroll.statutory_inputs(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('employee'),
  '2026-05-01','2026-06-01','[{"code":"BASIC","classification":"earning","basis":"fixed"}]'::jsonb),null,
  'employees without statutory rules get no statutory inputs');
select pg_temp.wactor('reviewer');set local role authenticated;
select is((api.people_payroll_statutory_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'retire'))->>'status','retired','an approved set can be retired');
reset role;
select is((people_payroll.statutory_inputs(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('employee'),
  '2026-05-01','2026-06-01',(select jsonb_build_array(jsonb_build_object('component_id',pg_temp.wid('epf-ee'),
   'code','EPF_EE','classification','deduction','basis','statutory')))))->'rule_set','null'::jsonb,
  'a retired set is no longer frozen into runs');

select * from finish(true);
rollback;
