-- ISOLATED LOCAL/CI DATABASE ONLY. Never run against hosted/production projects.
-- Existing Supabase migrations must already be installed. The uninstalled VAT
-- workpaper candidate and every synthetic fixture are transaction-local and rolled back.
begin;
set local lock_timeout='3s';
set local statement_timeout='90s';
-- The local-only runner inlines this candidate before staging the suite.
\ir ../20261121090000_lk_vat_workpaper.sql
create extension if not exists pgtap with schema extensions;
set local search_path=extensions,public,pg_catalog;
select no_plan();

create function pg_temp.wid(p text) returns uuid language sql immutable as
  $$select md5('lk-vat-rollback-20261121:'||p)::uuid$$;
create function pg_temp.wactor(p text,p_aal text default 'aal2') returns void language plpgsql as $$begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',pg_temp.wid(p),'role','authenticated','aal',p_aal)::text,true);
  perform set_config('request.jwt.claim.sub',pg_temp.wid(p)::text,true);
end $$;
create function pg_temp.vrow(p_type text,p_doc text,p_line text,p_value text,p_tax text,
  p_verified boolean default true,p_definition boolean default true) returns jsonb language sql immutable as $$
  select jsonb_build_object('source_type',p_type,'document_number',p_doc,'posting_date','2026-05-10','tax_code','VAT18',
   'tax_definition_id',case when p_definition then '00000000-0000-4000-8000-000000000018' end,'vat_line',p_line,
   'value_base',p_value,'tax_base',p_tax,'base_verified',p_verified,'has_journal',true,
   'counterparty_name','Lanka Traders (Pvt) Ltd','counterparty_tin','114567890')
$$;

-- Worked month: Rs 1,000,000 standard-rated at 18% (less a Rs 100,000 return),
-- an export, an exempt supply, claimable and non-claimable input tax, and four
-- rows that must become blockers rather than silently counting.
create temporary table v as select finance.lk_vat_compute(jsonb_build_array(
  pg_temp.vrow('sales_invoice','INV-1','standard_rated_supply','1000000','180000'),
  pg_temp.vrow('sales_invoice','INV-2','zero_rated_supply','500000','0'),
  pg_temp.vrow('sales_invoice','INV-3','exempt_supply','200000','0'),
  pg_temp.vrow('sales_return','SR-1','standard_rated_supply','100000','18000'),
  pg_temp.vrow('supplier_bill','BILL-1','input_claimable','400000','72000'),
  pg_temp.vrow('purchase_return','PR-1','input_claimable','50000','9000'),
  pg_temp.vrow('supplier_bill','BILL-2','input_not_claimable','100000','18000'),
  pg_temp.vrow('purchase_return','PR-2','input_claimable','10000','1800',false),
  pg_temp.vrow('supplier_bill','BILL-3',null,'300000','54000'),
  pg_temp.vrow('sales_invoice','INV-4','input_claimable','1000','180'),
  pg_temp.vrow('manual_journal','MJ-1',null,'0','500',true,false))) body;
create function pg_temp.vline(p_line text,p_field text) returns text language sql stable as $$
  select l->>p_field from v,jsonb_array_elements(body->'lines') l where l->>'line'=p_line
$$;
select is(pg_temp.vline('standard_rated_supply','value'),'900000.000000','standard-rated supplies net of returns');
select is(pg_temp.vline('standard_rated_supply','tax'),'162000.000000','output tax at 18% net of returns');
select is(pg_temp.vline('zero_rated_supply','value'),'500000.000000','exports land on the zero-rated line');
select is(pg_temp.vline('exempt_supply','value'),'200000.000000','exempt supplies land on their own line');
select is(pg_temp.vline('input_claimable','tax'),'61200.000000','claimable input tax net of purchase returns');
select is(pg_temp.vline('input_not_claimable','tax'),'18000.000000','non-claimable input tax is kept apart');
select is((select body->>'net_payable' from v),'100800.000000','net VAT payable is output tax less claimable input tax');
select is((select jsonb_agg(b->>'reason' order by b->>'reason') from v,jsonb_array_elements(body->'blockers') b),
  '["VAT_MAPPING_DIRECTION_MISMATCH","VAT_MAPPING_REQUIRED","VAT_RETURN_BASE_UNVERIFIED","VAT_TAX_CODE_MISSING"]'::jsonb,
  'unmapped, mis-mapped, unverified and uncoded lines are listed as blockers');
select is((select jsonb_array_length(body->'output_schedule') from v),4,'the output schedule lists every supply');
select is((select jsonb_array_length(body->'input_schedule') from v),4,'the input schedule lists every purchase');
select is((select s->>'value' from v,jsonb_array_elements(body->'output_schedule') s where s->>'document_number'='SR-1'),
  '-100000.000000','returns appear as negative lines in the schedule');
select is((select s->>'counterparty_tin' from v,jsonb_array_elements(body->'output_schedule') s where s->>'document_number'='INV-1'),
  '114567890','schedules carry the counterparty TIN');
select ok(not finance.lk_vat_line_valid('standard_rated_supply','output',0),'a standard-rated line needs a positive rate');
select ok(finance.lk_vat_line_valid('zero_rated_supply','zero',0),'zero-rated codes map to the zero-rated line');
select ok(not finance.lk_vat_line_valid('input_claimable','output',18),'output codes cannot be input tax');
select ok(not finance.lk_vat_line_valid('exempt_supply','input',0),'input codes cannot be exempt supplies');

-- Tenant fixture: creator and reviewer hold every finance permission; reader none.
insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,created_at,updated_at)
select pg_temp.wid(x),'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
  x||'@lk-vat.rollback.jentra.test','',now(),now(),now()
from unnest(array['creator','reviewer','reader','outsider']) x;
insert into core.tenants(id,name,slug,created_by) values
  (pg_temp.wid('tenant'),'LK VAT Rollback','lk-vat-rollback',pg_temp.wid('creator'));
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by,tax_identifier) values
  (pg_temp.wid('entity'),pg_temp.wid('tenant'),'Synthetic Lanka','LKVAT','LKR','Asia/Colombo',2,pg_temp.wid('creator'),'114000001');
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by) values
  (pg_temp.wid('branch'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'Head Office','HQ',pg_temp.wid('creator'));
insert into billing.plans(code,name) values('lk_vat_rollback','LK VAT rollback');
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled) values('lk_vat_rollback','module.finance',true);
insert into billing.tenant_subscriptions(tenant_id,plan_code,status,seats,trial_ends_at)
values(pg_temp.wid('tenant'),'lk_vat_rollback','trialing',10,now()+interval '30 days');
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
insert into finance.tax_definitions(id,tenant_id,legal_entity_id,code,name,rate,kind,inclusive,valid_from,created_by,updated_by) values
  (pg_temp.wid('vat18'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'VAT18','VAT 18 percent',18,'output',false,'2024-01-01',
   pg_temp.wid('creator'),pg_temp.wid('creator')),
  (pg_temp.wid('in18'),pg_temp.wid('tenant'),pg_temp.wid('entity'),'IN18','Input VAT 18 percent',18,'input',false,'2024-01-01',
   pg_temp.wid('creator'),pg_temp.wid('creator'));

-- Mapping lifecycle.
select pg_temp.wactor('creator');set local role authenticated;
select is((api.lk_vat_mapping_propose(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),pg_temp.wid('map-1'),
  pg_temp.wid('vat18'),'standard_rated_supply','Standard rate'))->>'status','pending','a proposed VAT mapping starts pending');
select throws_ok($q$select api.lk_vat_mapping_propose(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-bad'),pg_temp.wid('vat18'),'input_claimable','Wrong direction')$q$,'22023','TAX_VAT_MAPPING_INVALID',
  'an output code cannot be mapped to input tax');
select throws_ok($q$select api.lk_vat_mapping_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-1'),'approve')$q$,'42501','TAX_SEPARATE_APPROVER_REQUIRED','the proposer cannot approve');
reset role;select pg_temp.wactor('reviewer','aal1');set local role authenticated;
select throws_ok($q$select api.lk_vat_mapping_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-1'),'approve')$q$,'42501',null,'approval requires MFA');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select is((api.lk_vat_mapping_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-1'),'approve'))->>'status','approved','a second person with MFA approves the mapping');
reset role;select pg_temp.wactor('creator');set local role authenticated;
select lives_ok($q$select api.lk_vat_mapping_propose(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-2'),pg_temp.wid('vat18'),'outside_vat','Reclassified')$q$,'a replacement mapping can be proposed');
reset role;select pg_temp.wactor('reviewer');set local role authenticated;
select lives_ok($q$select api.lk_vat_mapping_decide(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid('map-2'),'approve')$q$,'approving a replacement succeeds');
reset role;
select is((select status from finance.lk_vat_mappings where id=pg_temp.wid('map-1')),'retired',
  'approving a replacement retires the earlier approved mapping');
select throws_ok($q$update finance.lk_vat_mappings set vat_line='exempt_supply' where id=pg_temp.wid('map-2')$q$,
  '55000','TAX_HISTORY_IMMUTABLE','approved mappings are immutable');
select throws_ok($q$delete from finance.lk_vat_mappings where id=pg_temp.wid('map-1')$q$,'55000','TAX_HISTORY_IMMUTABLE',
  'mappings cannot be deleted');
select pg_temp.wactor('creator');set local role authenticated;
select is((select x->'approved'->>'vat_line' from jsonb_array_elements(api.lk_vat_mappings(pg_temp.wid('tenant'),
  pg_temp.wid('entity'),pg_temp.wid('branch'))) x where x->>'code'='VAT18'),'outside_vat','the mapping list shows the approved line');

-- The workpaper API.
select is((api.lk_vat_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-05-01','2026-06-01'))
  ->>'net_payable','0.000000','an empty month nets to zero');
select is((api.lk_vat_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),'2026-04-01','2026-07-01'))
  ->>'entity_tin','114000001','a quarterly workpaper carries the entity TIN');
select throws_ok($q$select api.lk_vat_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01','2026-07-01')$q$,'22023','TAX_VAT_PERIOD_INVALID','a workpaper is one month or one quarter');
reset role;select pg_temp.wactor('creator','aal1');set local role authenticated;
select throws_ok($q$select api.lk_vat_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01','2026-06-01')$q$,'42501',null,'the workpaper with TINs needs MFA');
reset role;select pg_temp.wactor('reader');set local role authenticated;
select throws_ok($q$select api.lk_vat_return(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  '2026-05-01','2026-06-01')$q$,'42501',null,'users without tax access cannot prepare the workpaper');
select throws_ok($q$select api.lk_vat_mappings(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
  '42501',null,'users without tax access cannot list mappings');
reset role;select pg_temp.wactor('outsider');set local role authenticated;
select throws_ok($q$select api.lk_vat_mappings(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'))$q$,
  '42501',null,'another tenant cannot list mappings');
reset role;

select * from finish(true);
rollback;
