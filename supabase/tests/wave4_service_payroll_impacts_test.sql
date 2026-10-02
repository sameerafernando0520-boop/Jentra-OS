reset role;
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,status,created_by,updated_by)
values(pg_temp.wid('customer'),pg_temp.wid('tenant'),'W4SERVICE','Synthetic Service Customer','Synthetic Customer','customer','active',pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('w4_integrated_rollback','module.service',true) on conflict do nothing;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code from unnest(array['creator','reviewer']) x cross join core.permissions p
where p.module='service' or p.code='people.payroll.post' on conflict do nothing;
create temporary table service_impact_samples(name text primary key,body jsonb);
grant select,insert on service_impact_samples to authenticated;
create function pg_temp.sic(p jsonb,v bigint,key text) returns jsonb language sql as $$
 select api.service_command(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(key),pg_temp.wid(key),now(),p,v) $$;
create function pg_temp.siu(minute integer) returns text language sql as $$
 select to_char((pg_temp.wdate()::timestamp+make_interval(mins=>minute)) at time zone 'Asia/Colombo' at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.sic(jsonb_build_object('action','equipment','id',pg_temp.wid('si.eq'),'code','SI-EQ','name','Synthetic linked service pump',
 'identity','SI-EQUIPMENT','kind','customer','customer_id',pg_temp.wid('customer'),'provider_id',null,'reason','Synthetic linked service fixture'),0,'si.eq.create');
select pg_temp.sic(jsonb_build_object('action','policy','id',pg_temp.wid('si.policy'),'name','Synthetic linked service policy',
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+30,
 'response_seconds',3600,'resolution_seconds',28800,'independent_closure',true,'offsets','[]'::jsonb,'reason','Synthetic policy'),0,'si.policy.create');
select pg_temp.sic(jsonb_build_object('action','ticket','id',pg_temp.wid('si.ticket'),'code','SI-TICKET','name','Synthetic allocation repair',
 'classification','repair','customer_id',pg_temp.wid('customer'),'contact_id',null,'equipment_id',pg_temp.wid('si.eq'),
 'coverage_id',null,'policy_id',pg_temp.wid('si.policy'),'priority','normal','owner_id',null,'observed_utc',pg_temp.siu(540),'reason','Synthetic repair'),0,'si.ticket.create');
select pg_temp.sic(jsonb_build_object('action','order','id',pg_temp.wid('si.order'),'ticket_id',pg_temp.wid('si.ticket'),'reason','Synthetic order'),0,'si.order.create');
select pg_temp.sic(jsonb_build_object('action','dispatch','id',pg_temp.wid('si.order'),'employee_id',pg_temp.wid('manager'),
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.siu(540),'end_utc',pg_temp.siu(600),
 'booking_id',pg_temp.wid('si.booking'),'reason','Synthetic eligible dispatch'),1,'si.order.dispatch');
select pg_temp.sic(jsonb_build_object('action','accept','id',pg_temp.wid('si.order'),'observed_utc',pg_temp.siu(540),'reason','Synthetic acceptance'),2,'si.order.accept');
reset role;
insert into service_impact_samples values('labor_create',jsonb_build_object('action','labor','id',pg_temp.wid('si.labor'),
 'order_id',pg_temp.wid('si.order'),'employee_id',pg_temp.wid('manager'),'calendar_version_id',pg_temp.wid('calendar-version'),
 'start_utc',pg_temp.siu(540),'end_utc',pg_temp.siu(585),'breaks',jsonb_build_array(jsonb_build_object('start_utc',pg_temp.siu(555),'end_utc',pg_temp.siu(570))),
 'claim_id',(select active_claim_id from people.attendance_entries where id=pg_temp.wid('corr.attendance')),
 'hourly_cost','18.00','currency_code','LKR','precision',2,'billing_kind','nonbillable','hourly_billing','0','billing_reference','Synthetic internal service','reason','Synthetic break separated labor'));
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.sic((select body from service_impact_samples where name='labor_create'),0,'si.labor.create');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
reset role;insert into service_impact_samples values('before_claims',jsonb_build_object('count',(select count(*) from people.work_claims where employee_id=pg_temp.wid('manager') and active)));set local role authenticated;
select pg_temp.sic(jsonb_build_object('action','approve_labor','id',pg_temp.wid('si.labor'),'reason','Independent approval'),1,'si.labor.approve');
reset role;
select is((select cardinality(allocation_ids) from service.labor where id=pg_temp.wid('si.labor')),2,'two payable service segments belong to one labor entry');
select is((select count(*)::integer from people.work_claims where employee_id=pg_temp.wid('manager') and active),(select (body->>'count')::integer from service_impact_samples where name='before_claims'),'service allocation adds no payable claim');
select is(service.payroll_allocation_impact(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('manager'),
 (select allocation_ids[1] from service.labor where id=pg_temp.wid('si.labor')),pg_temp.wid('si.read'),'{}','read')->>'entry_id',
 pg_temp.wid('si.labor')::text,'named correction source returns stable labor entry identity');
create function pg_temp.si_correction(key text,minute integer,change_mode text default 'retain') returns jsonb
language sql security definer set search_path='' as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid(key),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+1,
 'reason','Synthetic linked service correction','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
 'before_revision_id',state->>'revision_id','expected_version',(state->>'version')::bigint,'paid_seconds',(minute-540)*60,
 'impact',jsonb_build_object('mode','geometry','expected_source_version',a.version,
 'start_local',to_char(pg_temp.wdate()::timestamp+interval '9 hours','YYYY-MM-DD"T"HH24:MI:SS'),
 'end_local',to_char(pg_temp.wdate()::timestamp+make_interval(mins=>minute),'YYYY-MM-DD"T"HH24:MI:SS'),
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb,
 'allocation_changes',case when change_mode='retain' then '[]'::jsonb else jsonb_build_array(
 jsonb_build_object('entry_id',pg_temp.wid('si.labor'),'mode',change_mode)||
 case when change_mode='geometry' then jsonb_build_object('start_local',pg_temp.wdate()::text||'T09:00:00',
 'end_local',pg_temp.wdate()::text||'T09:40:00','start_offset_seconds',19800,'end_offset_seconds',19800,
 'breaks',jsonb_build_array(jsonb_build_object('start_utc',pg_temp.siu(555),'end_utc',pg_temp.siu(570)))) else '{}'::jsonb end) end))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 cross join lateral(select people_payroll.correction_source_state(s.id) state) v
 join people.attendance_entries a on a.active_claim_id=(state->>'claim_id')::uuid
 where c.run_id=pg_temp.wid('corr.original') and s.claim_id=(c.inputs->'sources'->0->>'claim_id')::uuid $$;
select pg_temp.wactor('creator');set local role authenticated;
select throws_ok($q$select pg_temp.cc(pg_temp.si_correction('si.invalid',550),0,'si.invalid.prepare')$q$,'55000',
 'SERVICE_ALLOCATION_GEOMETRY_IMPACT_REQUIRED','attendance cannot silently truncate grouped service labor');
select pg_temp.cc(pg_temp.si_correction('si.retain',590),0,'si.retain.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','si.retain'),1,'si.retain.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','si.retain'),2,'si.retain.post');
reset role;
select is((select count(*)::integer from service.labor_revisions where labor_id=pg_temp.wid('si.labor')),1,'two callbacks append exactly one service revision');
select is((select cardinality(allocation_ids) from service.labor where id=pg_temp.wid('si.labor')),2,'grouped replacement preserves both payable segments');
select is((select count(*)::integer from service.payroll_labor_impacts),1,'grouped replacement has one immutable module impact');
select is((select sum(extract(epoch from end_utc-start_utc))::bigint from people.work_allocations where employee_id=pg_temp.wid('manager') and active),1800::bigint,'retained service seconds conserved');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','si.retain'),3,'si.retain.reverse');
reset role;
select is((select count(*)::integer from service.labor_revisions where labor_id=pg_temp.wid('si.labor')),2,'reverse through inactive original IDs appends once');
select is((select cardinality(allocation_ids) from service.labor where id=pg_temp.wid('si.labor')),2,'reversal restores all original segments');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.si_correction('si.geometry',580,'geometry'),0,'si.geometry.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','si.geometry'),1,'si.geometry.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','si.geometry'),2,'si.geometry.post');
reset role;
select is(service.snapshot('labor',pg_temp.wid('si.labor'))->>'seconds','1500','explicit service geometry recomputes payable seconds');
select is(service.snapshot('labor',pg_temp.wid('si.labor'))->>'amount','7.500000','explicit service geometry recomputes independent cost');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','si.geometry'),3,'si.geometry.reverse');
reset role;
select is(service.snapshot('labor',pg_temp.wid('si.labor'))->>'seconds','1800','geometry reverse retains original basis');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.si_correction('si.remove',550,'remove'),0,'si.remove.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','si.remove'),1,'si.remove.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','si.remove'),2,'si.remove.post');
reset role;
select is(service.snapshot('labor',pg_temp.wid('si.labor'))->>'seconds','0','governed removal has zero current labor seconds');
select is((select status from service.labor where id=pg_temp.wid('si.labor')),'cancelled','removed service entry is visibly cancelled');
select is((select count(*)::integer from people.work_allocations where employee_id=pg_temp.wid('manager') and active),0,'removal releases every service segment');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','si.remove'),3,'si.remove.reverse');
reset role;
select is((select cardinality(allocation_ids) from service.labor where id=pg_temp.wid('si.labor')),2,'removed source reverses using immutable lineage');
select is((select status from service.labor where id=pg_temp.wid('si.labor')),'approved','removed source reversal appends approved labor');
select ok(not has_table_privilege('authenticated','service.labor_allocations','SELECT') and not has_table_privilege('authenticated','service.payroll_labor_impacts','SELECT'),'module allocation lineage remains API-only');
select throws_ok($q$update service.labor_allocations set revision_id=gen_random_uuid()$q$,'55000','SERVICE_HISTORY_IMMUTABLE','allocation lineage is immutable');
select is((select start_utc from service.labor where id=pg_temp.wid('si.labor')),pg_temp.siu(540)::timestamptz,'original labor geometry remains immutable');

-- Direct service claim: a separate synthetic employee has no previously consumed period.
insert into people.organization_assignments(id,tenant_id,legal_entity_id,branch_id,employee_id,spell_id,department_id,calendar_version_id,role_title,start_date,end_date_exclusive,reason,recorded_by)
select pg_temp.wid('sd.organization'),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('third'),s.id,pg_temp.wid('department'),pg_temp.wid('calendar-version'),'Synthetic direct service engineer',pg_temp.wdate()-10,pg_temp.wdate()+400,'Synthetic direct fixture',pg_temp.wid('creator') from people.employment_spells s where s.employee_id=pg_temp.wid('third');
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pc(jsonb_build_object('action','assign','id',pg_temp.wid('sd.salary'),'employee_id',pg_temp.wid('third'),'component_id',pg_temp.wid('component.CORRHOURS'),'start_date',pg_temp.wdate()-10,'end_date_exclusive',pg_temp.wdate()+400,'reason','Synthetic direct hourly basis'),0,'sd.salary');
reset role;
create function pg_temp.sidu(minute integer) returns text language sql as $$
 select to_char((pg_temp.wdate()::timestamp+make_interval(mins=>minute)) at time zone 'Asia/Colombo' at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.sic(jsonb_build_object('action','policy','id',pg_temp.wid('sd.policy'),'name','Synthetic direct policy',
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+30,
 'response_seconds',3600,'resolution_seconds',28800,'independent_closure',true,'offsets','[]'::jsonb,'reason','Synthetic historic policy'),0,'sd.policy.create');
select pg_temp.sic(jsonb_build_object('action','ticket','id',pg_temp.wid('sd.ticket'),'code','SD-TICKET','name','Synthetic direct labor repair',
 'classification','repair','customer_id',pg_temp.wid('customer'),'contact_id',null,'equipment_id',pg_temp.wid('si.eq'),'coverage_id',null,
 'policy_id',pg_temp.wid('sd.policy'),'priority','normal','owner_id',null,'observed_utc',pg_temp.sidu(540),'reason','Synthetic direct repair'),0,'sd.ticket.create');
select pg_temp.sic(jsonb_build_object('action','order','id',pg_temp.wid('sd.order'),'ticket_id',pg_temp.wid('sd.ticket'),'reason','Synthetic direct order'),0,'sd.order.create');
select pg_temp.sic(jsonb_build_object('action','dispatch','id',pg_temp.wid('sd.order'),'employee_id',pg_temp.wid('third'),
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.sidu(540),'end_utc',pg_temp.sidu(600),
 'booking_id',pg_temp.wid('sd.booking'),'reason','Synthetic direct dispatch'),1,'sd.order.dispatch');
select pg_temp.sic(jsonb_build_object('action','accept','id',pg_temp.wid('sd.order'),'observed_utc',pg_temp.sidu(540),'reason','Synthetic direct acceptance'),2,'sd.order.accept');
select pg_temp.sic(jsonb_build_object('action','labor','id',pg_temp.wid('sd.labor'),'order_id',pg_temp.wid('sd.order'),'employee_id',pg_temp.wid('third'),
 'calendar_version_id',pg_temp.wid('calendar-version'),'start_utc',pg_temp.sidu(540),'end_utc',pg_temp.sidu(600),'breaks','[]'::jsonb,'claim_id',null,
 'hourly_cost','18.00','currency_code','LKR','precision',2,'billing_kind','billable','hourly_billing','54.00','billing_reference','Synthetic independent rate',
 'reason','Synthetic direct owned labor'),0,'sd.labor.create');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.sic(jsonb_build_object('action','approve_labor','id',pg_temp.wid('sd.labor'),'reason','Independent direct approval'),1,'sd.labor.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_create('sd.original')||jsonb_build_object('employee_ids',jsonb_build_array(pg_temp.wid('third')),
 'start_date',pg_temp.wdate(),'end_date_exclusive',pg_temp.wdate()+1,'posting_date',pg_temp.wdate()),0,'sd.original.create');
select pg_temp.pcmd(jsonb_build_object('action','prepare','id',pg_temp.wid('sd.original'),'reason','Synthetic direct freeze'),1,'sd.original.prepare');
select pg_temp.pcmd(pg_temp.run_action('submit','sd.original'),2,'sd.original.submit');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('approve','sd.original'),3,'sd.original.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.pcmd(pg_temp.run_action('post','sd.original'),4,'sd.original.post');
reset role;
create function pg_temp.sd_correction() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('action','prepare','id',pg_temp.wid('sd.correction'),'original_calculation_id',c.id,'posting_date',pg_temp.wdate()+1,
 'reason','Synthetic direct sealed service correction','replacements',jsonb_build_array(jsonb_build_object('seal_id',s.id,
 'before_revision_id',state->>'revision_id','expected_version',(state->>'version')::bigint,'paid_seconds',2700,
 'impact',jsonb_build_object('mode','geometry','expected_source_version',l.version,
 'start_local',pg_temp.wdate()::text||'T09:00:00','end_local',pg_temp.wdate()::text||'T09:45:00',
 'start_offset_seconds',19800,'end_offset_seconds',19800,'breaks','[]'::jsonb))))
 from people_payroll.employee_calculations c join people.work_input_seals s on s.run_id=c.run_id and s.employee_id=c.employee_id
 cross join lateral(select people_payroll.correction_source_state(s.id) state) v
 join service.labor l on l.claim_id=(state->>'claim_id')::uuid where c.run_id=pg_temp.wid('sd.original') $$;
select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.sd_correction(),0,'sd.correction.prepare');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('approve','sd.correction'),1,'sd.correction.approve');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('post','sd.correction'),2,'sd.correction.post');
reset role;
select is(service.snapshot('labor',pg_temp.wid('sd.labor'))->>'seconds','2700','direct owned correction appends exact service seconds');
select is(service.snapshot('labor',pg_temp.wid('sd.labor'))->>'billable_amount','40.500000','direct correction recomputes separate billing amount');
select is(service.payroll_source(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('third'),
 (select claim_id from service.labor where id=pg_temp.wid('sd.labor')))->>'paid_seconds','2700','payroll reads effective service claim revision');
select throws_ok($q$select pg_temp.sic(jsonb_build_object('action','cancel_labor','id',pg_temp.wid('sd.labor'),'reason','Synthetic ordinary cancellation'),3,'sd.cancel.sealed')$q$,'55000','PAYROLL_INPUT_SEALED','ordinary service cancellation still sealed');
select pg_temp.wactor('reviewer');set local role authenticated;
select pg_temp.cc(pg_temp.correction_action('reverse','sd.correction'),3,'sd.correction.reverse');
reset role;
select is(service.snapshot('labor',pg_temp.wid('sd.labor'))->>'seconds','3600','direct reversal appends original service basis');
select is((select count(*)::integer from service.labor_revisions where labor_id=pg_temp.wid('sd.labor')),2,'direct original and both immutable correction revisions retained');
select is((select count(*)::integer from people.work_claims where source_kind='service' and employee_id=pg_temp.wid('third') and active),1,'direct reversal has exactly one active payable service owner');
