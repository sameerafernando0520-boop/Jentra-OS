-- ISOLATED LOCAL/CI DATABASE ONLY. Never run against hosted/production projects.
-- Existing Supabase migrations must already be installed. The uninstalled VAT and
-- WHT candidates and every synthetic fixture are transaction-local and rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- The local-only runner inlines these candidates before staging the suite.
\ir ../20261121090000_lk_vat_workpaper.sql
\ir ../20261121110000_lk_wht_schedule.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();

create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('lk-wht-rollback-20261121:'||p)::uuid$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
create function pg_temp.wrow(p_doc text,p_rate text,p_sign integer,p_wht text,p_register jsonb) returns jsonb
language sql immutable as $$
  select jsonb_build_object('manual_journal_id','j-'||p_doc,'line_id','l-'||p_doc,'document_number',p_doc,
   'posting_date','2026-05-10','tax_code','WHT'||p_rate,'rate',p_rate,'sign',p_sign,'wht_base',p_wht,
   'taxable_base','50000.00','has_journal',true,'register',p_register)
$$;
create function pg_temp.wreg(p_supplier text,p_tin text,p_type text,p_gross text) returns jsonb language sql immutable as $$
  select jsonb_build_object('supplier_id',p_supplier,'supplier_name',p_supplier,'supplier_tin',p_tin,
   'payment_type',p_type,'gross',p_gross)
$$;

-- Worked month: a Rs 200,000 service fee at 5%, Rs 150,000 rent at 10% to a supplier
-- without a TIN, Rs 100,000 interest with Rs 4,000 deducted where 5% is Rs 5,000,
-- an unregistered line, and a reversed Rs 20,000 service fee.
create temporary table w as select finance.lk_wht_compute(jsonb_build_array(
  pg_temp.wrow('MJ-1','5',1,'10000',pg_temp.wreg('Alpha','100200300','service_fee','200000')),
  pg_temp.wrow('MJ-2','10',1,'15000',pg_temp.wreg('Beta',null,'rent','150000')),
  pg_temp.wrow('MJ-3','5',1,'4000',pg_temp.wreg('Alpha','100200300','interest','100000')),
  pg_temp.wrow('MJ-4','5',1,'2500',null),
  pg_temp.wrow('MJ-5R','5',-1,'1000',pg_temp.wreg('Alpha','100200300','service_fee','20000')))) body;
create function pg_temp.wline(p_type text,p_field text) returns text language sql stable as $$
  select l->>p_field from w,jsonb_array_elements(body->'lines') l where l->>'payment_type'=p_type
$$;
select is(pg_temp.wline('service_fee','gross'),'180000.000000','service fees net of the reversal');
select is(pg_temp.wline('service_fee','wht'),'9000.000000','WHT on service fees net of the reversal');
select is(pg_temp.wline('rent','wht'),'15000.000000','rent is its own payment type');
select is(pg_temp.wline('interest','wht'),'4000.000000','the deducted amount is reported as posted');
select is((select body->>'total_gross' from w),'430000.000000','total gross of registered lines');
select is((select body->>'total_wht' from w),'28000.000000','total WHT deducted');
select is((select jsonb_agg(b->>'reason'||':'||(b->>'document_number') order by b->>'document_number') from w,
  jsonb_array_elements(body->'blockers') b),
  '["WHT_SUPPLIER_TIN_MISSING:MJ-2","WHT_AMOUNT_MISMATCH:MJ-3","WHT_REGISTER_REQUIRED:MJ-4"]'::jsonb,
  'missing TINs, rate mismatches and unregistered lines are blockers');
select is((select c->>'wht' from w,jsonb_array_elements(body->'certificates') c where c->>'supplier_id'='Alpha'),
  '13000.000000','a supplier certificate totals every payment to that supplier');
select is((select jsonb_array_length(c->'payments') from w,jsonb_array_elements(body->'certificates') c
  where c->>'supplier_id'='Alpha'),3,'the certificate lists each payment');
select is((select jsonb_array_length(body->'schedule') from w),4,'unregistered lines stay out of the schedule');
select is((select b->>'taxable_base' from w,jsonb_array_elements(body->'blockers') b where b->>'reason'='WHT_REGISTER_REQUIRED'),
  '50000.00','an unregistered line carries its taxable base for the register form');

-- Tenant fixture: creator holds every finance permission; reader only finance.view.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@lk-wht.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'LK WHT Rollback','lk-wht-rollback',pg_temp.wid('creator'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by,tax_identifier) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Lanka','LKWHT','LKR','Asia/Colombo',2,pg_temp.wid('creator'),'114000002');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('lk_wht_rollback','LK WHT rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('lk_wht_rollback','module.finance',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'lk_wht_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active' from unnest(array['creator','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true from unnest(array['creator','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('creator.role'),p.code from core.permissions p where p.module='finance';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code from core.permissions p where p.code='finance.view';
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),null,pg_temp.wid('creator')
from unnest(array['creator','reader']) x;
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,inclusive,valid_from,created_by,updated_by) values
  (pg_temp.wid('wht5'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'WHT5','WHT 5 percent',5,'withholding',false,'2024-01-01',
   pg_temp.wid('creator'),pg_temp.wid('creator'));
insert into crm.parties(id,tenant_id,code,legal_name,display_name,kind,tax_identifier,created_by,updated_by) values
  (pg_temp.wid('alpha'),pg_temp.wid('tenant'),'ALPHA','Alpha Services (Pvt) Ltd','Alpha','supplier','100200300',
   pg_temp.wid('creator'),pg_temp.wid('creator')),
  (pg_temp.wid('buyer'),pg_temp.wid('tenant'),'BUYER','Buyer Lanka (Pvt) Ltd','Buyer','customer','100200400',
   pg_temp.wid('creator'),pg_temp.wid('creator'));

-- Posted manual journals: a WHT deduction in May, another left unregistered, and the
-- reversal of the first in June. A reversal keeps the original line ids.
create function pg_temp.wjournal(p_doc text,p_date date,p_line text,p_direction integer,p_reversal text default null)
returns void language sql as $$
  insert into finance.manual_journals(id,tenant_id,legal_entity_id,branch_id,document_number,document_date,reason,description,
   currency_code,grand_total,snapshot,reversal_of_id,status,prepared_by,posted_by,posted_at,request_id,command_id,correlation_id,
   client_timestamp,created_by,updated_by)
  values(pg_temp.wid(p_doc),pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),p_doc,p_date,'Consultancy fee',
   'Consultancy fee','LKR',200000,jsonb_build_object('base_currency_code','LKR','exchange_rate','1','lines',jsonb_build_array(
    jsonb_build_object('line_id',pg_temp.wid(p_line),'tax_definition_id',pg_temp.wid('wht5'),'tax_definition_version',1,
     'tax_code','WHT5','tax_kind','withholding','tax_rate',5,'tax_inclusive',false,'tax_direction',p_direction,
     'taxable_amount',200000,'amount',-p_direction*10000,'expected_tax_base',10000,'tax_basis_date',p_date))),
   case when p_reversal is not null then pg_temp.wid(p_reversal) end,'posted',pg_temp.wid('creator'),pg_temp.wid('creator'),now(),
   pg_temp.wid(p_doc||'.request'),pg_temp.wid(p_doc||'.command'),pg_temp.wid(p_doc||'.correlation'),now(),
   pg_temp.wid('creator'),pg_temp.wid('creator'))
$$;
select pg_temp.wjournal('MJ-1','2026-05-05','line-1',-1);
select pg_temp.wjournal('MJ-2','2026-05-20','line-2',-1);
select pg_temp.wjournal('MJ-1R','2026-06-03','line-1',1,'MJ-1');
create function pg_temp.wpayload(p_doc text,p_line text,p_supplier text,p_gross text) returns jsonb language sql immutable as $$
  select jsonb_build_object('manual_journal_id',pg_temp.wid(p_doc),'line_id',pg_temp.wid(p_line),
   'supplier_id',pg_temp.wid(p_supplier),'payment_type','service_fee','gross_amount',p_gross,'note','Consultancy invoice A-17')
$$;

-- Register lifecycle.
select pg_temp.wactor('creator');set local role authenticated;
select is((api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('reg-1'),
  pg_temp.wpayload('MJ-1','line-1','alpha','200000')))->>'status','active','a posted WHT line is registered');
select is((api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('reg-1'),
  pg_temp.wpayload('MJ-1','line-1','alpha','200000')))->>'id',pg_temp.wid('reg-1')::text,'recording is idempotent');
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-1'),pg_temp.wpayload('MJ-1','line-1','alpha','210000'))$q$,'55000','TAX_REGISTER_ID_CONFLICT',
  'a reused id with other values is refused');
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-dup'),pg_temp.wpayload('MJ-1','line-1','alpha','200000'))$q$,'23505','TAX_WHT_ALREADY_REGISTERED',
  'a line has one active entry');
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-rev'),pg_temp.wpayload('MJ-1R','line-1','alpha','200000'))$q$,'22023','TAX_WHT_REGISTER_INVALID',
  'reversals reuse the original entry and are not registered');
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-cust'),pg_temp.wpayload('MJ-2','line-2','buyer','200000'))$q$,'22023','TAX_WHT_REGISTER_INVALID',
  'only suppliers can be registered');
reset role;select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-2'),pg_temp.wpayload('MJ-2','line-2','alpha','200000'))$q$,'42501',null,'recording requires MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.lk_wht_register_record(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-2'),pg_temp.wpayload('MJ-2','line-2','alpha','200000'))$q$,'42501',null,
  'finance viewers cannot record entries');
reset role;
select throws_ok($q$update finance.lk_wht_register set gross_amount=1 where id=pg_temp.wid('reg-1')$q$,
  '55000','TAX_HISTORY_IMMUTABLE','register values are immutable');
select throws_ok($q$delete from finance.lk_wht_register where id=pg_temp.wid('reg-1')$q$,'55000','TAX_HISTORY_IMMUTABLE',
  'register entries cannot be deleted');

-- The schedule API.
select pg_temp.wactor('creator');set local role authenticated;
create temporary table may as select api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01') body;
select is((select body->>'total_wht' from may),'10000.000000','registered WHT is totalled for the month');
select is((select body->>'entity_tin' from may),'114000002','the schedule carries the entity TIN');
select is((select c->>'supplier_tin' from may,jsonb_array_elements(body->'certificates') c),'100200300',
  'certificates carry the supplier TIN');
select ok((select body->'blockers' @> jsonb_build_array(jsonb_build_object('reason','WHT_REGISTER_REQUIRED',
  'document_number','MJ-2','line_id',pg_temp.wid('line-2'))) from may),'an unregistered line is a blocker with its ids');
select ok((select body->'suppliers' @> jsonb_build_array(jsonb_build_object('supplier_id',pg_temp.wid('alpha')))
  and not body->'suppliers' @> jsonb_build_array(jsonb_build_object('supplier_id',pg_temp.wid('buyer'))) from may),
  'the supplier list leaves out customers');
select is((api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-06-01'))
  ->>'total_gross','-200000.000000','a reversal uses the original entry with the amounts negated');
select throws_ok($q$select api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-02')$q$,'22023','TAX_WHT_PERIOD_INVALID','a schedule covers one calendar month');
select is((api.lk_wht_register_retire(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('reg-1')))
  ->>'status','retired','an entry can be retired for correction');
select throws_ok($q$select api.lk_wht_register_retire(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('reg-1'))$q$,'55000','TAX_REGISTER_STATE_INVALID','a retired entry cannot be retired again');
select is((api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-05-01'))
  ->>'total_wht','0.000000','a retired entry no longer counts');
reset role;select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($q$select api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01')$q$,'42501',null,'the schedule with TINs needs MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01')$q$,'42501',null,'finance viewers without export access cannot prepare the schedule');
reset role;select pg_temp.wactor('outsider');set local role authenticated;
select throws_ok($q$select api.lk_wht_schedule(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01')$q$,'42501',null,'another tenant cannot prepare the schedule');
reset role;

select * from finish(true);
rollback;
