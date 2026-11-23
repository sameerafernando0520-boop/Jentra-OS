-- ISOLATED LOCAL/CI DATABASE ONLY. Never run against hosted/production projects.
-- Existing Supabase migrations must already be installed. The uninstalled VAT and
-- SSCL workpaper candidates and every fixture are transaction-local and rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- The local-only runner inlines both candidates before staging the suite.
\ir ../20261121090000_lk_vat_workpaper.sql
\ir ../20261121100000_lk_sscl_workpaper.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();

create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('lk-sscl-rollback-20261121:'||p)::uuid$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
create function pg_temp.srow(p_type text,p_doc text,p_line text,p_value text,p_definition boolean default true)
returns jsonb language sql immutable as $$
  select jsonb_build_object('source_type',p_type,'document_number',p_doc,'value_base',p_value,
   'has_definition',p_definition,'tax_code',case when p_definition then 'VAT18' end,'vat_line',p_line)
$$;
create function pg_temp.settings(p_portion text,p_zero boolean,p_exempt boolean) returns jsonb language sql immutable as $$
  select jsonb_build_object('rate_percent','2.5','liable_portion_percent',p_portion,'include_zero_rated',p_zero,
   'include_exempt',p_exempt)
$$;
create temporary table quarter_rows as select jsonb_build_array(
  pg_temp.srow('sales_invoice','INV-1','standard_rated_supply','4000000'),
  pg_temp.srow('sales_return','SR-1','standard_rated_supply','400000'),
  pg_temp.srow('sales_invoice','INV-2','zero_rated_supply','1000000'),
  pg_temp.srow('sales_invoice','INV-3','exempt_supply','500000'),
  pg_temp.srow('sales_invoice','INV-4',null,'2000000',false),
  pg_temp.srow('sales_invoice','INV-5',null,'300000'),
  pg_temp.srow('sales_invoice','INV-6','input_claimable','100')) body;

-- Rs 4,000,000 standard-rated less a Rs 400,000 return, plus Rs 2,000,000 with
-- no tax code: Rs 5,600,000 turnover. At a full portion and 2.5%: Rs 140,000.
create temporary table full_portion as select finance.lk_sscl_compute(body,pg_temp.settings('100',false,false)) body from quarter_rows;
select is((select body->>'included_turnover' from full_portion),'5600000.000000','returns reduce turnover and untaxed sales count');
select is((select body->>'sscl_due' from full_portion),'140000.000000','SSCL is 2.5% of liable turnover');
select is((select body->'turnover'->>'untaxed' from full_portion),'2000000.000000','sales without a tax code are reported separately');
select is((select jsonb_agg(b->>'reason' order by b->>'reason') from full_portion,jsonb_array_elements(body->'blockers') b),
  '["SSCL_VAT_MAPPING_DIRECTION_MISMATCH","SSCL_VAT_MAPPING_REQUIRED"]'::jsonb,'unmapped and mis-mapped taxed sales are blockers');
-- A wholesale or retail portion of 50%, counting exports and exempt supplies.
create temporary table half_portion as select finance.lk_sscl_compute(body,pg_temp.settings('50',true,true)) body from quarter_rows;
select is((select body->>'included_turnover' from half_portion),'7100000.000000','included exports and exempt supplies add to turnover');
select is((select body->>'liable_turnover' from half_portion),'3550000.000000','the liable portion applies to turnover');
select is((select body->>'sscl_due' from half_portion),'88750.000000','SSCL on the liable portion');
create temporary table no_settings as select finance.lk_sscl_compute(body,null) body from quarter_rows;
select is((select body->>'sscl_due' from no_settings),null,'no SSCL is computed without approved settings');
select ok((select body->'blockers' @> '[{"reason":"SSCL_SETTINGS_REQUIRED"}]'::jsonb from no_settings),
  'missing settings are a blocker');

-- Tenant fixture.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@lk-sscl.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'LK SSCL Rollback','lk-sscl-rollback',pg_temp.wid('creator'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by,tax_identifier) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Lanka','LKSSCL','LKR','Asia/Colombo',2,pg_temp.wid('creator'),'114000002');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('lk_sscl_rollback','LK SSCL rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('lk_sscl_rollback','module.finance',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'lk_sscl_rollback','trialing',10,now()+interval '30 days');
insert into core.memberships(id,tenant_id,user_id,status)
select pg_temp.wid(x||'.membership'),pg_temp.wid('tenant'),pg_temp.wid(x),'active' from unnest(array['creator','reviewer','reader']) x;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
select pg_temp.wid(x||'.role'),pg_temp.wid('tenant'),x,x,true from unnest(array['creator','reviewer','reader']) x;
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.role'),p.code
from unnest(array['creator','reviewer']) x cross join core.permissions p where p.module='finance';
insert into core.role_permissions(tenant_id,role_id,permission_code)
select pg_temp.wid('tenant'),pg_temp.wid('reader.role'),p.code from core.permissions p where p.code='finance.view';
insert into core.role_assignments(tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
select pg_temp.wid('tenant'),pg_temp.wid(x||'.membership'),pg_temp.wid(x||'.role'),pg_temp.wid('entity'),null,pg_temp.wid('creator')
from unnest(array['creator','reviewer','reader']) x;

create function pg_temp.propose(p_key text,p_from text,p_to text) returns jsonb language sql as $$
  select api.lk_sscl_settings_propose(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid(p_key),
   jsonb_build_object('effective_from',p_from,'effective_to_exclusive',p_to,'rate_percent','2.5',
    'liable_portion_percent','100','include_zero_rated',false,'include_exempt',false,
    'activity','Manufacturing and services','reason','SSCL at 2.5%'))
$$;
select pg_temp.wactor('creator');set local role authenticated;
select is((pg_temp.propose('set-1','2026-04-01','2027-04-01'))->>'status','pending','proposed SSCL settings start pending');
select is((pg_temp.propose('set-1','2026-04-01','2027-04-01'))->'sources'->>'ird','https://www.ird.gov.lk',
  'settings record their sources');
select throws_ok($q$select api.lk_sscl_settings_propose(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-bad'),'{"effective_from":"2026-04-01","effective_to_exclusive":"2027-04-01","rate_percent":"250",
  "liable_portion_percent":"100","include_zero_rated":false,"include_exempt":false,"activity":"x","reason":"x"}'::jsonb)$q$,
  '22023','TAX_SSCL_SETTINGS_INVALID','rates above 100% are refused');
select throws_ok($q$select api.lk_sscl_settings_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'approve')$q$,'42501','TAX_SEPARATE_APPROVER_REQUIRED','the proposer cannot approve');
select is((api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01'))
  ->'blockers'->0->>'reason','SSCL_SETTINGS_REQUIRED','pending settings do not count');
reset role;select pg_temp.wactor('reviewer','aal1');set local role authenticated;
select throws_ok($q$select api.lk_sscl_settings_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'approve')$q$,'42501',null,'approval requires MFA');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select is((api.lk_sscl_settings_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-1'),'approve'))->>'status','approved','a second person with MFA approves the settings');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select lives_ok($q$select pg_temp.propose('set-2','2026-10-01','2027-04-01')$q$,'overlapping settings can be proposed');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select throws_ok($q$select api.lk_sscl_settings_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('set-2'),'approve')$q$,'55000','TAX_SSCL_OVERLAP','two approved settings cannot cover the same day');
reset role;
select throws_ok($q$update finance.lk_sscl_settings set rate_percent=3 where id=pg_temp.wid('set-1')$q$,
  '55000','TAX_HISTORY_IMMUTABLE','approved settings are immutable');

select pg_temp.wactor('creator');set local role authenticated;
select is((api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01'))
  ->>'sscl_due','0.000000','an approved quarter without sales owes nothing');
select is((api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01'))
  ->'settings'->>'rate_percent','2.500000','the workpaper shows the approved settings');
select throws_ok($q$select api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-05-01')$q$,
  '22023','TAX_SSCL_PERIOD_INVALID','a workpaper starts a calendar quarter');
reset role;select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($q$select api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01')$q$,
  '42501',null,'the workpaper needs MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select lives_ok($q$select api.lk_sscl_settings(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
  'finance viewers can list settings');
select throws_ok($q$select api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01')$q$,
  '42501',null,'finance viewers without export access cannot prepare the workpaper');
reset role;select pg_temp.wactor('outsider');set local role authenticated;
select throws_ok($q$select api.lk_sscl_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01')$q$,
  '42501',null,'another tenant cannot prepare the workpaper');
reset role;

select * from finish(true);
rollback;
