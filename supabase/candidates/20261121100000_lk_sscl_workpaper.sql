-- Candidate only. Not installed on any hosted database.
-- Sri Lanka Social Security Contribution Levy (SSCL) quarterly workpaper.
-- Requires 20261121090000_lk_vat_workpaper.sql. Contract:
-- docs/blueprint/71_LK_TAX_SCHEDULES_CONTRACT.md (part B).
--
-- SSCL is due on turnover, including sales without any tax code. Turnover comes
-- from every posted sales invoice and return line, net of VAT. Approved SSCL
-- settings decide the rate, the liable portion of turnover for the entity's
-- activity (for example a wholesale or retail portion) and whether zero-rated and
-- exempt supplies count. The workpaper is not certified.

create table finance.lk_sscl_settings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 effective_from date not null,effective_to_exclusive date not null,
 rate_percent numeric(9,6) not null check(rate_percent between 0 and 100),
 liable_portion_percent numeric(9,6) not null check(liable_portion_percent between 0 and 100),
 include_zero_rated boolean not null,include_exempt boolean not null,
 activity text not null check(length(btrim(activity)) between 1 and 300),
 sources jsonb not null check(jsonb_typeof(sources)='object'),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 status text not null default 'pending' check(status in('pending','approved','retired')),
 proposed_by uuid not null references auth.users(id),proposed_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 retired_by uuid references auth.users(id),retired_at timestamptz,
 check(effective_to_exclusive>effective_from and effective_to_exclusive-effective_from<=1830),
 check((approved_by is null)=(approved_at is null) and (retired_by is null)=(retired_at is null)),
 check(status<>'approved' or approved_by is not null),
 check((status='retired')=(retired_by is not null)),
 check(approved_by is null or approved_by<>proposed_by),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 exclude using gist(tenant_id extensions.gist_uuid_ops with =,legal_entity_id extensions.gist_uuid_ops with =,
  daterange(effective_from,effective_to_exclusive,'[)') with &&) where (status='approved')
);
create index lk_sscl_settings_scope_idx on finance.lk_sscl_settings(tenant_id,legal_entity_id,effective_from);
create index lk_sscl_settings_proposer_idx on finance.lk_sscl_settings(proposed_by);
create index lk_sscl_settings_approver_idx on finance.lk_sscl_settings(approved_by);
create index lk_sscl_settings_retirer_idx on finance.lk_sscl_settings(retired_by);
alter table finance.lk_sscl_settings enable row level security;
alter table finance.lk_sscl_settings force row level security;
revoke all on finance.lk_sscl_settings from public,anon,authenticated;

create function finance.lk_sscl_settings_guard() returns trigger language plpgsql set search_path='' as $$
declare state text[]:=array['status','approved_by','approved_at','retired_by','retired_at'];begin
 if tg_op='DELETE' or to_jsonb(old)-state<>to_jsonb(new)-state
  or not((old.status='pending' and new.status in('approved','retired')) or (old.status='approved' and new.status='retired'))
  or (old.status='approved' and (new.approved_by,new.approved_at) is distinct from (old.approved_by,old.approved_at)) then
  raise exception using errcode='55000',message='TAX_HISTORY_IMMUTABLE';end if;
 return new;
end $$;
create trigger lk_sscl_settings_guard before update or delete on finance.lk_sscl_settings
 for each row execute function finance.lk_sscl_settings_guard();

-- Pure aggregation. Rows: source_type, document_number, value_base,
-- has_definition, vat_line (approved line or null). Settings: the approved
-- settings object or null. Returns reduce turnover.
create function finance.lk_sscl_compute(p_rows jsonb,p_settings jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare r jsonb;value numeric;line text;standard numeric:=0;zero numeric:=0;exempt numeric:=0;untaxed numeric:=0;
 outside numeric:=0;blockers jsonb:='[]';included numeric;liable numeric;due numeric;begin
 if coalesce(jsonb_typeof(p_rows),'null')<>'array' then
  raise exception using errcode='22023',message='TAX_SSCL_ROWS_INVALID';end if;
 for r in select v from jsonb_array_elements(p_rows) v loop
  value:=coalesce((r->>'value_base')::numeric,0)*case when r->>'source_type'='sales_return' then -1 else 1 end;
  line:=r->>'vat_line';
  if not coalesce((r->>'has_definition')::boolean,false) then untaxed:=untaxed+value;
  elsif line is null then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','SSCL_VAT_MAPPING_REQUIRED',
    'source_type',r->>'source_type','document_number',r->>'document_number','tax_code',r->>'tax_code'));
  elsif line='standard_rated_supply' then standard:=standard+value;
  elsif line='zero_rated_supply' then zero:=zero+value;
  elsif line='exempt_supply' then exempt:=exempt+value;
  elsif line='outside_vat' then outside:=outside+value;
  else
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','SSCL_VAT_MAPPING_DIRECTION_MISMATCH',
    'source_type',r->>'source_type','document_number',r->>'document_number','tax_code',r->>'tax_code'));
  end if;
 end loop;
 -- Sales without a tax code and sales outside VAT are still business turnover.
 included:=standard+untaxed+outside
  +case when coalesce((p_settings->>'include_zero_rated')::boolean,false) then zero else 0 end
  +case when coalesce((p_settings->>'include_exempt')::boolean,false) then exempt else 0 end;
 if coalesce(jsonb_typeof(p_settings),'null')<>'object' then
  blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','SSCL_SETTINGS_REQUIRED'));
  liable:=null;due:=null;
 else
  liable:=round(included*(p_settings->>'liable_portion_percent')::numeric/100,2);
  due:=round(liable*(p_settings->>'rate_percent')::numeric/100,2);
 end if;
 return jsonb_build_object('turnover',jsonb_build_object('standard_rated',round(standard,6)::text,
   'zero_rated',round(zero,6)::text,'exempt',round(exempt,6)::text,'untaxed',round(untaxed,6)::text,
   'outside_vat',round(outside,6)::text),
  'included_turnover',round(included,6)::text,'liable_turnover',round(liable,6)::text,'sscl_due',round(due,6)::text,
  'blockers',blockers);
end $$;
revoke all on function finance.lk_sscl_compute(jsonb,jsonb) from public,anon,authenticated;

create function finance.lk_sscl_settings_payload(s finance.lk_sscl_settings) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',s.id,'effective_from',s.effective_from,'effective_to_exclusive',s.effective_to_exclusive,
  'rate_percent',s.rate_percent::text,'liable_portion_percent',s.liable_portion_percent::text,
  'include_zero_rated',s.include_zero_rated,'include_exempt',s.include_exempt,'activity',s.activity,'sources',s.sources,
  'reason',s.reason,'status',s.status,'proposed_by',s.proposed_by,'proposed_at',s.proposed_at,
  'approved_by',s.approved_by,'approved_at',s.approved_at,'retired_by',s.retired_by,'retired_at',s.retired_at)
$$;
revoke all on function finance.lk_sscl_settings_payload(finance.lk_sscl_settings) from public,anon,authenticated;

create function api.lk_sscl_settings(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 return coalesce((select jsonb_agg(finance.lk_sscl_settings_payload(s) order by s.effective_from desc,s.proposed_at desc)
  from finance.lk_sscl_settings s where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id),'[]'::jsonb);
end $$;

-- Proposes settings. The rate and portion are entered by the proposer and checked
-- by the approver against the SSCL Act and IRD guidance recorded in sources.
create function api.lk_sscl_settings_propose(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s finance.lk_sscl_settings%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_id is null or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k not in('effective_from','effective_to_exclusive',
   'rate_percent','liable_portion_percent','include_zero_rated','include_exempt','activity','reason'))
  or coalesce(p_payload->>'effective_from','') !~ '^[0-9]{4}-[0-9]{2}-01$'
  or coalesce(p_payload->>'effective_to_exclusive','') !~ '^[0-9]{4}-[0-9]{2}-01$'
  or coalesce(p_payload->>'rate_percent','') !~ '^(0|[1-9][0-9]?|100)(\.[0-9]{1,6})?$'
  or coalesce(p_payload->>'liable_portion_percent','') !~ '^(0|[1-9][0-9]?|100)(\.[0-9]{1,6})?$'
  or jsonb_typeof(p_payload->'include_zero_rated') is distinct from 'boolean'
  or jsonb_typeof(p_payload->'include_exempt') is distinct from 'boolean' then
  raise exception using errcode='22023',message='TAX_SSCL_SETTINGS_INVALID';end if;
 select * into s from finance.lk_sscl_settings where id=p_id;
 if s.id is not null then
  if s.tenant_id<>p_tenant_id or s.legal_entity_id<>p_legal_entity_id then
   raise exception using errcode='55000',message='TAX_SSCL_ID_CONFLICT';end if;
  return finance.lk_sscl_settings_payload(s);
 end if;
 insert into finance.lk_sscl_settings(id,tenant_id,legal_entity_id,effective_from,effective_to_exclusive,rate_percent,
  liable_portion_percent,include_zero_rated,include_exempt,activity,sources,reason,proposed_by)
 values(p_id,p_tenant_id,p_legal_entity_id,(p_payload->>'effective_from')::date,(p_payload->>'effective_to_exclusive')::date,
  (p_payload->>'rate_percent')::numeric,(p_payload->>'liable_portion_percent')::numeric,
  (p_payload->>'include_zero_rated')::boolean,(p_payload->>'include_exempt')::boolean,btrim(p_payload->>'activity'),
  jsonb_build_object('checked_on','2026-11-21',
   'act','Social Security Contribution Levy Act No. 25 of 2022, as amended',
   'ird','https://www.ird.gov.lk',
   'note','Rate 2.5% of liable turnover at the check date. An amendment effective 1 July 2026 (reported as Act No. 10 of 2026) changed the thresholds; confirm it. Confirm the rate, the liable portion for this activity and the treatment of exports and exempt supplies against the Act and IRD guidance before approving.'),
  btrim(p_payload->>'reason'),auth.uid())
 returning * into s;
 return finance.lk_sscl_settings_payload(s);
end $$;

create function api.lk_sscl_settings_decide(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s finance.lk_sscl_settings%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.classifications.approve',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_action is null or p_action not in('approve','retire') then
  raise exception using errcode='22023',message='TAX_SSCL_ACTION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('finance.lk_sscl:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into s from finance.lk_sscl_settings where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_id for update;
 if s.id is null then raise exception using errcode='42501',message='TAX_SCOPE_DENIED';end if;
 if p_action='approve' then
  if s.status<>'pending' then raise exception using errcode='55000',message='TAX_SSCL_STATE_INVALID';end if;
  if s.proposed_by=auth.uid() then raise exception using errcode='42501',message='TAX_SEPARATE_APPROVER_REQUIRED';end if;
  if exists(select 1 from finance.lk_sscl_settings o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
   and o.status='approved' and daterange(o.effective_from,o.effective_to_exclusive,'[)') && daterange(s.effective_from,s.effective_to_exclusive,'[)')) then
   raise exception using errcode='55000',message='TAX_SSCL_OVERLAP';end if;
  update finance.lk_sscl_settings set status='approved',approved_by=auth.uid(),approved_at=clock_timestamp()
   where id=p_id returning * into s;
 else
  if s.status='retired' then raise exception using errcode='55000',message='TAX_SSCL_STATE_INVALID';end if;
  update finance.lk_sscl_settings set status='retired',retired_by=auth.uid(),retired_at=clock_timestamp()
   where id=p_id returning * into s;
 end if;
 return finance.lk_sscl_settings_payload(s);
end $$;

-- One calendar quarter (January, April, July or October start) by document date.
create function api.lk_sscl_return(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_quarter_start date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare entity core.legal_entities%rowtype;q_end date;settings jsonb;v_rows jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.reports.export',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_quarter_start is null or extract(day from p_quarter_start)<>1 or extract(month from p_quarter_start)::integer not in(1,4,7,10) then
  raise exception using errcode='22023',message='TAX_SSCL_PERIOD_INVALID';end if;
 q_end:=(p_quarter_start+interval '3 months')::date;
 select * into entity from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 if entity.currency_code<>'LKR' then
  return jsonb_build_object('quarter_start',p_quarter_start,'quarter_end_exclusive',q_end,
   'blockers',jsonb_build_array(jsonb_build_object('reason','SSCL_BASE_CURRENCY_LKR_REQUIRED')));
 end if;
 select finance.lk_sscl_settings_payload(s) into settings from finance.lk_sscl_settings s
  where s.tenant_id=p_tenant_id and s.legal_entity_id=p_legal_entity_id and s.status='approved'
   and daterange(s.effective_from,s.effective_to_exclusive,'[)') @> daterange(p_quarter_start,q_end,'[)');
 with lines as (
  select 'sales_invoice' source_type,doc.document_number,doc.exchange_rate,l.taxable_amount,l.snapshot
  from sales.sales_invoice_lines l join sales.sales_invoices doc on doc.tenant_id=l.tenant_id and doc.id=l.document_id
  where doc.tenant_id=p_tenant_id and doc.legal_entity_id=p_legal_entity_id and doc.status='posted'
   and doc.document_date>=p_quarter_start and doc.document_date<q_end
  union all
  select 'sales_return',doc.document_number,doc.exchange_rate,l.taxable_amount,l.snapshot
  from sales.sales_return_lines l join sales.sales_returns doc on doc.tenant_id=l.tenant_id and doc.id=l.document_id
  where doc.tenant_id=p_tenant_id and doc.legal_entity_id=p_legal_entity_id and doc.status='posted'
   and doc.document_date>=p_quarter_start and doc.document_date<q_end)
 select coalesce(jsonb_agg(jsonb_build_object('source_type',x.source_type,'document_number',x.document_number,
  'value_base',round(x.taxable_amount*x.exchange_rate,entity.rounding_scale)::text,
  'has_definition',x.snapshot->>'tax_definition_id' is not null,'tax_code',x.snapshot->>'tax_code','vat_line',m.vat_line)),'[]'::jsonb)
 into v_rows from lines x
 left join finance.lk_vat_mappings m on m.tenant_id=p_tenant_id and m.legal_entity_id=p_legal_entity_id and m.status='approved'
  and m.tax_definition_id::text=x.snapshot->>'tax_definition_id';
 return finance.lk_sscl_compute(v_rows,settings)||jsonb_build_object('quarter_start',p_quarter_start,
  'quarter_end_exclusive',q_end,'entity_tin',entity.tax_identifier,'settings',settings);
end $$;

do $$declare f text;begin
 foreach f in array array[
  'api.lk_sscl_settings(uuid,uuid,uuid)',
  'api.lk_sscl_settings_propose(uuid,uuid,uuid,uuid,jsonb)',
  'api.lk_sscl_settings_decide(uuid,uuid,uuid,uuid,text)',
  'api.lk_sscl_return(uuid,uuid,uuid,date)'] loop
  execute format('revoke all on function %s from public,anon',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;

do $$begin
 if to_regprocedure('organization_lifecycle.install_write_guards()') is not null then
  perform organization_lifecycle.install_write_guards();
 end if;
end $$;

notify pgrst,'reload schema';
