-- Candidate only. Not installed on any hosted database.
-- Sri Lanka VAT return workpaper from posted tax lines. Contract:
-- docs/blueprint/71_LK_TAX_SCHEDULES_CONTRACT.md (part A).
--
-- Each tax definition is mapped to an IRD VAT return line. A mapping is pending
-- until a second person approves it with MFA. The workpaper is computed from
-- finance.tax_posted_sources and is not certified: an accountant reviews it
-- before filing.

create function finance.lk_vat_line_valid(p_line text,p_kind text,p_rate numeric) returns boolean
language sql immutable set search_path='' as $$
 select case p_line
  when 'standard_rated_supply' then p_kind='output' and p_rate>0
  when 'zero_rated_supply' then p_kind in('zero','output') and p_rate=0
  when 'exempt_supply' then p_kind='exempt'
  when 'input_claimable' then p_kind='input'
  when 'input_not_claimable' then p_kind='input'
  when 'outside_vat' then true
  else false end
$$;

create table finance.lk_vat_mappings(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,tax_definition_id uuid not null,
 vat_line text not null check(vat_line in('standard_rated_supply','zero_rated_supply','exempt_supply',
  'input_claimable','input_not_claimable','outside_vat')),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 status text not null default 'pending' check(status in('pending','approved','retired')),
 proposed_by uuid not null references auth.users(id),proposed_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 retired_by uuid references auth.users(id),retired_at timestamptz,
 check((approved_by is null)=(approved_at is null) and (retired_by is null)=(retired_at is null)),
 check(status<>'approved' or approved_by is not null),
 check((status='retired')=(retired_by is not null)),
 check(approved_by is null or approved_by<>proposed_by),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,tax_definition_id) references finance.tax_definitions(tenant_id,legal_entity_id,id)
);
create unique index lk_vat_mappings_one_approved on finance.lk_vat_mappings(tenant_id,legal_entity_id,tax_definition_id)
 where status='approved';
create index lk_vat_mappings_definition_idx on finance.lk_vat_mappings(tenant_id,legal_entity_id,tax_definition_id,proposed_at);
create index lk_vat_mappings_proposer_idx on finance.lk_vat_mappings(proposed_by);
create index lk_vat_mappings_approver_idx on finance.lk_vat_mappings(approved_by);
create index lk_vat_mappings_retirer_idx on finance.lk_vat_mappings(retired_by);
alter table finance.lk_vat_mappings enable row level security;
alter table finance.lk_vat_mappings force row level security;
revoke all on finance.lk_vat_mappings from public,anon,authenticated;

-- Values never change. Allowed transitions: pending -> approved, pending -> retired
-- (withdrawn) and approved -> retired.
create function finance.lk_vat_mapping_guard() returns trigger language plpgsql set search_path='' as $$
declare state text[]:=array['status','approved_by','approved_at','retired_by','retired_at'];begin
 if tg_op='DELETE' or to_jsonb(old)-state<>to_jsonb(new)-state
  or not((old.status='pending' and new.status in('approved','retired')) or (old.status='approved' and new.status='retired'))
  or (old.status='approved' and (new.approved_by,new.approved_at) is distinct from (old.approved_by,old.approved_at)) then
  raise exception using errcode='55000',message='TAX_HISTORY_IMMUTABLE';end if;
 return new;
end $$;
create trigger lk_vat_mapping_guard before update or delete on finance.lk_vat_mappings
 for each row execute function finance.lk_vat_mapping_guard();

-- Pure aggregation over prepared rows, so it can be tested without documents.
-- Each row: source_type, document_number, posting_date, tax_code, tax_definition_id,
-- vat_line (null when unmapped), value_base, tax_base, base_verified, has_journal,
-- counterparty_name, counterparty_tin. Return documents reduce their line.
create function finance.lk_vat_compute(p_rows jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare r jsonb;sign numeric;line text;sale boolean;value numeric;tax numeric;
 totals jsonb:='{}';blockers jsonb:='[]';outputs jsonb:='[]';inputs jsonb:='[]';
 lines text[]:=array['standard_rated_supply','zero_rated_supply','exempt_supply','input_claimable','input_not_claimable','outside_vat'];
 output_tax numeric;input_tax numeric;begin
 if coalesce(jsonb_typeof(p_rows),'null')<>'array' then
  raise exception using errcode='22023',message='TAX_VAT_ROWS_INVALID';end if;
 -- Alias the element: a bare "value" would clash with the value variable.
 for r in select e from jsonb_array_elements(p_rows) e loop
  sale:=r->>'source_type' in('sales_invoice','sales_return');
  sign:=case when r->>'source_type' in('sales_return','purchase_return') then -1 else 1 end;
  line:=r->>'vat_line';value:=coalesce((r->>'value_base')::numeric,0)*sign;tax:=coalesce((r->>'tax_base')::numeric,0)*sign;
  if r->>'tax_definition_id' is null then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','VAT_TAX_CODE_MISSING','source_type',r->>'source_type',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
   continue;
  end if;
  if line is null then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','VAT_MAPPING_REQUIRED','source_type',r->>'source_type',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
   continue;
  end if;
  if line<>'outside_vat' and r->>'source_type'<>'manual_journal'
   and sale<>(line in('standard_rated_supply','zero_rated_supply','exempt_supply')) then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','VAT_MAPPING_DIRECTION_MISMATCH','source_type',r->>'source_type',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
   continue;
  end if;
  if not coalesce((r->>'base_verified')::boolean,false) then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','VAT_RETURN_BASE_UNVERIFIED','source_type',r->>'source_type',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
  end if;
  if not coalesce((r->>'has_journal')::boolean,false) then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','VAT_JOURNAL_MISSING','source_type',r->>'source_type',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
  end if;
  totals:=jsonb_set(totals,array[line],jsonb_build_object(
   'value',coalesce((totals->line->>'value')::numeric,0)+value,'tax',coalesce((totals->line->>'tax')::numeric,0)+tax));
  if line in('standard_rated_supply','zero_rated_supply','exempt_supply') then
   outputs:=outputs||jsonb_build_array(jsonb_build_object('line',line,'source_type',r->>'source_type',
    'posting_date',r->>'posting_date','document_number',r->>'document_number','counterparty_name',r->>'counterparty_name',
    'counterparty_tin',r->>'counterparty_tin','tax_code',r->>'tax_code','value',round(value,6)::text,'tax',round(tax,6)::text));
  elsif line in('input_claimable','input_not_claimable') then
   inputs:=inputs||jsonb_build_array(jsonb_build_object('line',line,'source_type',r->>'source_type',
    'posting_date',r->>'posting_date','document_number',r->>'document_number','counterparty_name',r->>'counterparty_name',
    'counterparty_tin',r->>'counterparty_tin','tax_code',r->>'tax_code','value',round(value,6)::text,'tax',round(tax,6)::text));
  end if;
 end loop;
 output_tax:=coalesce((totals->'standard_rated_supply'->>'tax')::numeric,0);
 input_tax:=coalesce((totals->'input_claimable'->>'tax')::numeric,0);
 return jsonb_build_object(
  'lines',(select jsonb_agg(jsonb_build_object('line',l,'value',round(coalesce((totals->l->>'value')::numeric,0),6)::text,
   'tax',round(coalesce((totals->l->>'tax')::numeric,0),6)::text) order by o) from unnest(lines) with ordinality u(l,o)),
  'output_tax',round(output_tax,6)::text,'input_tax_claimable',round(input_tax,6)::text,
  'net_payable',round(output_tax-input_tax,6)::text,'blockers',blockers,
  'output_schedule',outputs,'input_schedule',inputs);
end $$;
revoke all on function finance.lk_vat_compute(jsonb) from public,anon,authenticated;

create function finance.lk_vat_mapping_payload(m finance.lk_vat_mappings) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',m.id,'tax_definition_id',m.tax_definition_id,'vat_line',m.vat_line,'reason',m.reason,
  'status',m.status,'proposed_by',m.proposed_by,'proposed_at',m.proposed_at,'approved_by',m.approved_by,
  'approved_at',m.approved_at,'retired_by',m.retired_by,'retired_at',m.retired_at)
$$;
revoke all on function finance.lk_vat_mapping_payload(finance.lk_vat_mappings) from public,anon,authenticated;

create function finance.lk_tax_require_mfa() returns void language plpgsql stable set search_path='' as $$begin
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='TAX_MFA_REQUIRED';end if;
end $$;
revoke all on function finance.lk_tax_require_mfa() from public,anon,authenticated;

-- Tax definitions with their approved and pending VAT mappings.
create function api.lk_vat_mappings(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 return coalesce((select jsonb_agg(jsonb_build_object('tax_definition_id',d.id,'code',d.code,'name',d.name,'kind',d.kind,
  'rate',d.rate::text,'status',d.status,
  'approved',(select finance.lk_vat_mapping_payload(m) from finance.lk_vat_mappings m where m.tenant_id=d.tenant_id
   and m.legal_entity_id=d.legal_entity_id and m.tax_definition_id=d.id and m.status='approved'),
  'pending',coalesce((select jsonb_agg(finance.lk_vat_mapping_payload(m) order by m.proposed_at) from finance.lk_vat_mappings m
   where m.tenant_id=d.tenant_id and m.legal_entity_id=d.legal_entity_id and m.tax_definition_id=d.id and m.status='pending'),'[]'::jsonb))
  order by d.code) from finance.tax_definitions d where d.tenant_id=p_tenant_id and d.legal_entity_id=p_legal_entity_id),'[]'::jsonb);
end $$;

create function api.lk_vat_mapping_propose(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_tax_definition_id uuid,p_vat_line text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d finance.tax_definitions%rowtype;m finance.lk_vat_mappings%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 select * into m from finance.lk_vat_mappings where id=p_id;
 if m.id is not null then
  if m.tenant_id<>p_tenant_id or m.legal_entity_id<>p_legal_entity_id or m.tax_definition_id<>p_tax_definition_id
   or m.vat_line<>p_vat_line then raise exception using errcode='55000',message='TAX_MAPPING_ID_CONFLICT';end if;
  return finance.lk_vat_mapping_payload(m);
 end if;
 select * into d from finance.tax_definitions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_tax_definition_id;
 if p_id is null or d.id is null or length(btrim(coalesce(p_reason,''))) not between 1 and 1000
  or not coalesce(finance.lk_vat_line_valid(p_vat_line,d.kind,d.rate),false) then
  raise exception using errcode='22023',message='TAX_VAT_MAPPING_INVALID';end if;
 insert into finance.lk_vat_mappings(id,tenant_id,legal_entity_id,tax_definition_id,vat_line,reason,proposed_by)
 values(p_id,p_tenant_id,p_legal_entity_id,p_tax_definition_id,p_vat_line,btrim(p_reason),auth.uid()) returning * into m;
 return finance.lk_vat_mapping_payload(m);
end $$;

create function api.lk_vat_mapping_decide(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m finance.lk_vat_mappings%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.classifications.approve',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_action is null or p_action not in('approve','retire') then
  raise exception using errcode='22023',message='TAX_MAPPING_ACTION_INVALID';end if;
 perform pg_advisory_xact_lock(hashtextextended('finance.lk_vat:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into m from finance.lk_vat_mappings where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_id for update;
 if m.id is null then raise exception using errcode='42501',message='TAX_SCOPE_DENIED';end if;
 if p_action='approve' then
  if m.status<>'pending' then raise exception using errcode='55000',message='TAX_MAPPING_STATE_INVALID';end if;
  if m.proposed_by=auth.uid() then raise exception using errcode='42501',message='TAX_SEPARATE_APPROVER_REQUIRED';end if;
  -- The newly approved mapping replaces the previous one for the same code.
  update finance.lk_vat_mappings set status='retired',retired_by=auth.uid(),retired_at=clock_timestamp()
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and tax_definition_id=m.tax_definition_id and status='approved';
  update finance.lk_vat_mappings set status='approved',approved_by=auth.uid(),approved_at=clock_timestamp()
   where id=p_id returning * into m;
 else
  if m.status='retired' then raise exception using errcode='55000',message='TAX_MAPPING_STATE_INVALID';end if;
  update finance.lk_vat_mappings set status='retired',retired_by=auth.uid(),retired_at=clock_timestamp()
   where id=p_id returning * into m;
 end if;
 return finance.lk_vat_mapping_payload(m);
end $$;

-- The workpaper for one month or quarter, by posting date. Counterparty TINs are
-- business identifiers, so it needs report export and MFA.
create function api.lk_vat_return(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_from date,p_to_exclusive date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare entity core.legal_entities%rowtype;months integer;v_rows jsonb;result jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.tax_summary',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.reports.export',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 months:=(extract(year from p_to_exclusive)::integer-extract(year from p_from)::integer)*12
  +extract(month from p_to_exclusive)::integer-extract(month from p_from)::integer;
 if p_from is null or p_to_exclusive is null or extract(day from p_from)<>1 or extract(day from p_to_exclusive)<>1
  or months not in(1,3) then
  raise exception using errcode='22023',message='TAX_VAT_PERIOD_INVALID';end if;
 select * into entity from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 if entity.currency_code<>'LKR' then
  return jsonb_build_object('from',p_from,'to_exclusive',p_to_exclusive,'entity_tin',entity.tax_identifier,
   'blockers',jsonb_build_array(jsonb_build_object('reason','VAT_BASE_CURRENCY_LKR_REQUIRED')));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('source_type',s.source_type,'document_number',s.document_number,
  'posting_date',s.posting_date,'tax_code',s.source_snapshot->>'tax_code','tax_definition_id',s.source_snapshot->>'tax_definition_id',
  'vat_line',m.vat_line,'value_base',round(s.taxable_amount*s.exchange_rate,entity.rounding_scale)::text,
  'tax_base',s.expected_tax_base::text,'base_verified',s.expected_base_verified,'has_journal',s.journal_entry_id is not null,
  'counterparty_name',p.legal_name,'counterparty_tin',p.tax_identifier) order by s.posting_date,s.document_number,s.source_line_id),'[]'::jsonb)
 into v_rows
 from finance.tax_posted_sources(p_tenant_id,p_legal_entity_id,p_to_exclusive-1) s
 left join finance.lk_vat_mappings m on m.tenant_id=p_tenant_id and m.legal_entity_id=p_legal_entity_id and m.status='approved'
  and m.tax_definition_id::text=s.source_snapshot->>'tax_definition_id'
 left join lateral(select case s.source_type
   when 'sales_invoice' then (select x.customer_id from sales.sales_invoices x where x.tenant_id=p_tenant_id and x.id=s.source_id)
   when 'sales_return' then (select x.customer_id from sales.sales_returns x where x.tenant_id=p_tenant_id and x.id=s.source_id)
   when 'supplier_bill' then (select x.supplier_id from procurement.supplier_bills x where x.tenant_id=p_tenant_id and x.id=s.source_id)
   when 'purchase_return' then (select x.supplier_id from procurement.purchase_returns x where x.tenant_id=p_tenant_id and x.id=s.source_id)
  end party_id) c on true
 left join crm.parties p on p.tenant_id=p_tenant_id and p.id=c.party_id
 where s.posting_date>=p_from and s.posting_date<p_to_exclusive;
 result:=finance.lk_vat_compute(v_rows);
 return result||jsonb_build_object('from',p_from,'to_exclusive',p_to_exclusive,'entity_tin',entity.tax_identifier,
  'base_currency',entity.currency_code);
end $$;

do $$declare f text;begin
 foreach f in array array[
  'api.lk_vat_mappings(uuid,uuid,uuid)',
  'api.lk_vat_mapping_propose(uuid,uuid,uuid,uuid,uuid,text,text)',
  'api.lk_vat_mapping_decide(uuid,uuid,uuid,uuid,text)',
  'api.lk_vat_return(uuid,uuid,uuid,date,date)'] loop
  execute format('revoke all on function %s from public,anon',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
revoke all on function finance.lk_vat_line_valid(text,text,numeric) from public,anon,authenticated;

-- Organization lifecycle guards cover every tenant-scoped table.
do $$begin
 if to_regprocedure('organization_lifecycle.install_write_guards()') is not null then
  perform organization_lifecycle.install_write_guards();
 end if;
end $$;

notify pgrst,'reload schema';
