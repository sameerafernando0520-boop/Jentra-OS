-- Candidate only. Not installed on any hosted database.
-- Sri Lanka WHT monthly schedule and supplier certificate data. Contract:
-- docs/blueprint/71_LK_TAX_SCHEDULES_CONTRACT.md (part C).
-- Requires 20261121090000_lk_vat_workpaper.sql (finance.lk_tax_require_mfa).
--
-- Withholding is posted on manual journal tax lines. A register links each posted
-- WHT line to a supplier, an IRD payment type and the gross amount paid. The
-- schedule is computed from finance.tax_posted_sources; lines without a register
-- entry are blockers. Posting is unchanged. The output is not certified: an
-- accountant reviews it before filing or issuing certificates.

create table finance.lk_wht_register(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,
 manual_journal_id uuid not null,line_id uuid not null,supplier_id uuid not null,
 payment_type text not null check(payment_type in('service_fee','rent','interest','dividend','royalty','other')),
 gross_amount numeric(20,6) not null check(gross_amount>0),
 note text not null check(length(btrim(note)) between 1 and 1000),
 status text not null default 'active' check(status in('active','retired')),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 retired_by uuid references auth.users(id),retired_at timestamptz,
 check((retired_by is null)=(retired_at is null) and (status='retired')=(retired_by is not null)),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,manual_journal_id) references finance.manual_journals(tenant_id,id),
 foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id)
);
create unique index lk_wht_register_one_active on finance.lk_wht_register(tenant_id,manual_journal_id,line_id)
 where status='active';
create index lk_wht_register_entity_idx on finance.lk_wht_register(tenant_id,legal_entity_id,recorded_at);
create index lk_wht_register_supplier_idx on finance.lk_wht_register(tenant_id,supplier_id);
create index lk_wht_register_recorder_idx on finance.lk_wht_register(recorded_by);
create index lk_wht_register_retirer_idx on finance.lk_wht_register(retired_by);
alter table finance.lk_wht_register enable row level security;
alter table finance.lk_wht_register force row level security;
revoke all on finance.lk_wht_register from public,anon,authenticated;

-- Values never change. The only transition is active -> retired; a correction is
-- a retirement followed by a new entry.
create function finance.lk_wht_register_guard() returns trigger language plpgsql set search_path='' as $$
declare state text[]:=array['status','retired_by','retired_at'];begin
 if tg_op='DELETE' or to_jsonb(old)-state<>to_jsonb(new)-state
  or not(old.status='active' and new.status='retired') then
  raise exception using errcode='55000',message='TAX_HISTORY_IMMUTABLE';end if;
 return new;
end $$;
create trigger lk_wht_register_guard before update or delete on finance.lk_wht_register
 for each row execute function finance.lk_wht_register_guard();

-- Pure aggregation over prepared rows, so it can be tested without documents.
-- Each row: manual_journal_id, line_id, document_number, posting_date, tax_code,
-- rate, sign (1, or -1 for a reversal), wht_base (positive LKR), taxable_base,
-- has_journal, and register (supplier_id, supplier_name, supplier_tin,
-- payment_type, gross) or null.
create function finance.lk_wht_compute(p_rows jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare r jsonb;reg jsonb;dir integer;gross numeric;wht numeric;types text[]:=array['service_fee','rent',
 'interest','dividend','royalty','other'];totals jsonb:='{}';suppliers jsonb:='{}';schedule jsonb:='[]';
 blockers jsonb:='[]';total_gross numeric:=0;total_wht numeric:=0;t text;s text;begin
 -- Alias the element: a bare "value" would clash in plpgsql.
 for r in select e from jsonb_array_elements(coalesce(p_rows,'[]')) e loop
  reg:=r->'register';dir:=coalesce((r->>'sign')::integer,1);
  if reg is null or jsonb_typeof(reg)<>'object' then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','WHT_REGISTER_REQUIRED',
    'manual_journal_id',r->>'manual_journal_id','line_id',r->>'line_id','document_number',r->>'document_number',
    'posting_date',r->>'posting_date','tax_code',r->>'tax_code','wht',round(dir*coalesce((r->>'wht_base')::numeric,0),6)::text,
    'taxable_base',r->>'taxable_base'));
   continue;
  end if;
  gross:=dir*(reg->>'gross')::numeric;wht:=dir*coalesce((r->>'wht_base')::numeric,0);
  t:=reg->>'payment_type';s:=reg->>'supplier_id';
  if round((reg->>'gross')::numeric*(r->>'rate')::numeric/100,2)<>round(coalesce((r->>'wht_base')::numeric,0),2) then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','WHT_AMOUNT_MISMATCH',
    'document_number',r->>'document_number','tax_code',r->>'tax_code','rate',r->>'rate',
    'gross',round(gross,6)::text,'wht',round(wht,6)::text));
  end if;
  if coalesce(btrim(reg->>'supplier_tin'),'')='' then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','WHT_SUPPLIER_TIN_MISSING',
    'document_number',r->>'document_number','supplier_name',reg->>'supplier_name'));
  end if;
  if not coalesce((r->>'has_journal')::boolean,false) then
   blockers:=blockers||jsonb_build_array(jsonb_build_object('reason','WHT_JOURNAL_MISSING',
    'document_number',r->>'document_number','tax_code',r->>'tax_code'));
  end if;
  total_gross:=total_gross+gross;total_wht:=total_wht+wht;
  totals:=jsonb_set(totals,array[t],jsonb_build_object(
   'gross',coalesce((totals->t->>'gross')::numeric,0)+gross,'wht',coalesce((totals->t->>'wht')::numeric,0)+wht));
  suppliers:=jsonb_set(suppliers,array[s],jsonb_build_object('supplier_id',s,'supplier_name',reg->>'supplier_name',
   'supplier_tin',reg->>'supplier_tin','gross',coalesce((suppliers->s->>'gross')::numeric,0)+gross,
   'wht',coalesce((suppliers->s->>'wht')::numeric,0)+wht,
   'payments',coalesce(suppliers->s->'payments','[]')||jsonb_build_array(jsonb_build_object('posting_date',r->>'posting_date',
    'document_number',r->>'document_number','payment_type',t,'rate',r->>'rate','gross',round(gross,6)::text,'wht',round(wht,6)::text))));
  schedule:=schedule||jsonb_build_array(jsonb_build_object('posting_date',r->>'posting_date',
   'document_number',r->>'document_number','supplier_id',s,'supplier_name',reg->>'supplier_name',
   'supplier_tin',reg->>'supplier_tin','payment_type',t,'tax_code',r->>'tax_code','rate',r->>'rate',
   'gross',round(gross,6)::text,'wht',round(wht,6)::text));
 end loop;
 return jsonb_build_object(
  'lines',(select jsonb_agg(jsonb_build_object('payment_type',x,'gross',round(coalesce((totals->x->>'gross')::numeric,0),6)::text,
   'wht',round(coalesce((totals->x->>'wht')::numeric,0),6)::text) order by o) from unnest(types) with ordinality u(x,o)),
  'total_gross',round(total_gross,6)::text,'total_wht',round(total_wht,6)::text,'schedule',schedule,
  'certificates',coalesce((select jsonb_agg(jsonb_build_object('supplier_id',v->>'supplier_id','supplier_name',v->>'supplier_name',
   'supplier_tin',v->>'supplier_tin','gross',round((v->>'gross')::numeric,6)::text,'wht',round((v->>'wht')::numeric,6)::text,
   'payments',v->'payments') order by v->>'supplier_name',v->>'supplier_id') from jsonb_each(suppliers) j(k,v)),'[]'::jsonb),
  'blockers',blockers);
end $$;
revoke all on function finance.lk_wht_compute(jsonb) from public,anon,authenticated;

create function finance.lk_wht_register_payload(g finance.lk_wht_register) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',g.id,'manual_journal_id',g.manual_journal_id,'line_id',g.line_id,
  'supplier_id',g.supplier_id,'payment_type',g.payment_type,'gross_amount',g.gross_amount::text,'note',g.note,
  'status',g.status,'recorded_by',g.recorded_by,'recorded_at',g.recorded_at,'retired_by',g.retired_by,'retired_at',g.retired_at)
$$;
revoke all on function finance.lk_wht_register_payload(finance.lk_wht_register) from public,anon,authenticated;

-- Records one posted WHT line. Reversal journals reuse the original line's entry.
create function api.lk_wht_register_record(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g finance.lk_wht_register%rowtype;j finance.manual_journals%rowtype;
 v_journal uuid;v_line uuid;v_supplier uuid;v_gross numeric;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.journals.post',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_id is null or jsonb_typeof(p_payload)<>'object' or exists(select 1 from jsonb_object_keys(p_payload) k
   where k not in('manual_journal_id','line_id','supplier_id','payment_type','gross_amount','note'))
  or coalesce(p_payload->>'manual_journal_id','')!~*'^[0-9a-f-]{36}$' or coalesce(p_payload->>'line_id','')!~*'^[0-9a-f-]{36}$'
  or coalesce(p_payload->>'supplier_id','')!~*'^[0-9a-f-]{36}$'
  or coalesce(p_payload->>'gross_amount','')!~'^[0-9]{1,14}(\.[0-9]{1,6})?$' then
  raise exception using errcode='22023',message='TAX_WHT_REGISTER_INVALID';end if;
 v_journal:=(p_payload->>'manual_journal_id')::uuid;v_line:=(p_payload->>'line_id')::uuid;
 v_supplier:=(p_payload->>'supplier_id')::uuid;v_gross:=(p_payload->>'gross_amount')::numeric;
 select * into g from finance.lk_wht_register where id=p_id;
 if g.id is not null then
  if g.tenant_id<>p_tenant_id or g.legal_entity_id<>p_legal_entity_id or g.manual_journal_id<>v_journal
   or g.line_id<>v_line or g.supplier_id<>v_supplier or g.payment_type<>p_payload->>'payment_type'
   or g.gross_amount<>v_gross then raise exception using errcode='55000',message='TAX_REGISTER_ID_CONFLICT';end if;
  return finance.lk_wht_register_payload(g);
 end if;
 select * into j from finance.manual_journals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_journal and status='posted';
 if j.id is null or j.reversal_of_id is not null or v_gross<=0
  or coalesce(p_payload->>'payment_type','') not in('service_fee','rent','interest','dividend','royalty','other')
  or length(btrim(coalesce(p_payload->>'note',''))) not between 1 and 1000
  or not exists(select 1 from jsonb_array_elements(j.snapshot->'lines') x where x->>'line_id'=v_line::text
   and x->>'tax_kind'='withholding')
  or not exists(select 1 from crm.parties p where p.tenant_id=p_tenant_id and p.id=v_supplier
   and p.kind in('supplier','both')) then
  raise exception using errcode='22023',message='TAX_WHT_REGISTER_INVALID';end if;
 if exists(select 1 from finance.lk_wht_register r where r.tenant_id=p_tenant_id and r.manual_journal_id=v_journal
   and r.line_id=v_line and r.status='active') then
  raise exception using errcode='23505',message='TAX_WHT_ALREADY_REGISTERED';end if;
 insert into finance.lk_wht_register(id,tenant_id,legal_entity_id,manual_journal_id,line_id,supplier_id,payment_type,
  gross_amount,note,recorded_by)
 values(p_id,p_tenant_id,p_legal_entity_id,v_journal,v_line,v_supplier,p_payload->>'payment_type',v_gross,
  btrim(p_payload->>'note'),auth.uid()) returning * into g;
 return finance.lk_wht_register_payload(g);
end $$;

create function api.lk_wht_register_retire(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare g finance.lk_wht_register%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.journals.post',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 update finance.lk_wht_register set status='retired',retired_by=auth.uid(),retired_at=clock_timestamp()
 where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=p_id and status='active' returning * into g;
 if g.id is null then raise exception using errcode='55000',message='TAX_REGISTER_STATE_INVALID';end if;
 return finance.lk_wht_register_payload(g);
end $$;

-- Monthly schedule with supplier certificate data. It carries supplier TINs, so it
-- needs report export and MFA.
create function api.lk_wht_schedule(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_month date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare entity core.legal_entities%rowtype;month_end date;v_rows jsonb;suppliers jsonb;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.reports.export',p_legal_entity_id,null);
 perform finance.lk_tax_require_mfa();
 if p_month is null or extract(day from p_month)<>1 then
  raise exception using errcode='22023',message='TAX_WHT_PERIOD_INVALID';end if;
 month_end:=(p_month+interval '1 month')::date;
 select * into entity from core.legal_entities where tenant_id=p_tenant_id and id=p_legal_entity_id;
 if entity.currency_code<>'LKR' then
  return jsonb_build_object('month',p_month,'entity_tin',entity.tax_identifier,
   'blockers',jsonb_build_array(jsonb_build_object('reason','WHT_BASE_CURRENCY_LKR_REQUIRED')));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('manual_journal_id',s.source_id,'line_id',s.source_line_id,
  'document_number',s.document_number,'posting_date',s.posting_date,'tax_code',s.source_snapshot->>'tax_code',
  'rate',s.source_snapshot->>'tax_rate','sign',-coalesce((s.source_snapshot->>'tax_direction')::integer,-1),
  'wht_base',s.expected_tax_base::text,'taxable_base',round(s.taxable_amount*s.exchange_rate,entity.rounding_scale)::text,
  'has_journal',s.journal_entry_id is not null,
  'register',case when g.id is not null then jsonb_build_object('supplier_id',g.supplier_id,'supplier_name',p.legal_name,
   'supplier_tin',p.tax_identifier,'payment_type',g.payment_type,'gross',g.gross_amount::text) end)
  order by s.posting_date,s.document_number,s.source_line_id),'[]'::jsonb)
 into v_rows
 from finance.tax_posted_sources(p_tenant_id,p_legal_entity_id,month_end-1) s
 left join finance.lk_wht_register g on g.tenant_id=p_tenant_id and g.status='active' and g.line_id=s.source_line_id
  and g.manual_journal_id=coalesce((s.source_snapshot->>'reversal_of_id')::uuid,s.source_id)
 left join crm.parties p on p.tenant_id=p_tenant_id and p.id=g.supplier_id
 where s.source_type='manual_journal' and s.source_snapshot->>'tax_kind'='withholding'
  and s.posting_date>=p_month and s.posting_date<month_end;
 select coalesce(jsonb_agg(jsonb_build_object('supplier_id',x.id,'supplier_name',x.legal_name,'supplier_tin',x.tax_identifier)
  order by x.legal_name,x.id),'[]'::jsonb) into suppliers
 from (select p.id,p.legal_name,p.tax_identifier from crm.parties p where p.tenant_id=p_tenant_id
  and p.kind in('supplier','both') and p.status='active' order by p.legal_name,p.id limit 1000) x;
 return finance.lk_wht_compute(v_rows)||jsonb_build_object('month',p_month,'entity_tin',entity.tax_identifier,
  'base_currency',entity.currency_code,'suppliers',suppliers,
  'register',coalesce((select jsonb_agg(finance.lk_wht_register_payload(g) order by g.recorded_at)
   from finance.lk_wht_register g join finance.manual_journals j on j.tenant_id=g.tenant_id and j.id=g.manual_journal_id
   where g.tenant_id=p_tenant_id and g.legal_entity_id=p_legal_entity_id and g.status='active'
    and j.document_date>=p_month and j.document_date<month_end),'[]'::jsonb));
end $$;

do $$declare f text;begin
 foreach f in array array[
  'api.lk_wht_register_record(uuid,uuid,uuid,uuid,jsonb)',
  'api.lk_wht_register_retire(uuid,uuid,uuid,uuid)',
  'api.lk_wht_schedule(uuid,uuid,uuid,date)'] loop
  execute format('revoke all on function %s from public,anon',f);
  execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;

-- Organization lifecycle guards cover every tenant-scoped table.
do $$begin
 if to_regprocedure('organization_lifecycle.install_write_guards()') is not null then
  perform organization_lifecycle.install_write_guards();
 end if;
end $$;

notify pgrst,'reload schema';
