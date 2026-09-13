-- AC-309 / FR-337. Unapplied candidate. Invitations record intent; no external messages.
create table procurement.rfqs (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 requisition_id uuid not null,requisition_version bigint not null,
 invited_supplier_ids uuid[] not null check(cardinality(invited_supplier_ids) between 1 and 100),
 invited_suppliers jsonb not null,
 title text not null check(length(trim(title)) between 1 and 160),
 document_date date not null,close_date date not null,document_number text not null,
 status text not null default 'issued' check(status in('issued','selected','ordered','cancelled')),
 selected_quote_id uuid,selection_reason text,version bigint not null default 1,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,legal_entity_id,requisition_id) references procurement.requisitions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),check(close_date>=document_date)
);
create table procurement.rfq_lines (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 rfq_id uuid not null,source_line_id uuid not null,source_snapshot jsonb not null,
 unique(rfq_id,source_line_id),
 foreign key(tenant_id,legal_entity_id,rfq_id) references procurement.rfqs(tenant_id,legal_entity_id,id)
);
create index rfq_scope_page on procurement.rfqs(tenant_id,legal_entity_id,branch_id,id);
create index rfq_scope_status on procurement.rfqs(tenant_id,legal_entity_id,branch_id,status,id);
create table procurement.supplier_quotes (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,rfq_id uuid not null,
 supplier_id uuid not null,quote_date date not null,valid_until date not null,
 currency_code text not null references core.currencies(code),exchange_rate_id uuid,
 exchange_rate numeric(20,10) not null,rate_date date not null,
 payment_terms text not null,delivery_terms text not null,
 subtotal numeric(20,6) not null,tax_total numeric(20,6) not null,total numeric(20,6) not null,base_total numeric(20,6) not null,
 complete boolean not null,version bigint not null default 1,
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,legal_entity_id,id),unique(rfq_id,supplier_id),
 foreign key(tenant_id,legal_entity_id,rfq_id) references procurement.rfqs(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id),
 check(valid_until>=quote_date),check(exchange_rate>0),check(subtotal>=0 and tax_total>=0 and total>=0 and base_total>=0),
 check(length(trim(payment_terms)) between 1 and 1000 and length(trim(delivery_terms)) between 1 and 1000)
);
alter table procurement.rfqs add constraint rfq_selected_quote_fk foreign key(tenant_id,legal_entity_id,selected_quote_id)
 references procurement.supplier_quotes(tenant_id,legal_entity_id,id);
create table procurement.supplier_quote_lines (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 quote_id uuid not null,source_line_id uuid not null,detail jsonb not null,
 unique(quote_id,source_line_id),foreign key(tenant_id,legal_entity_id,quote_id) references procurement.supplier_quotes(tenant_id,legal_entity_id,id)
);
create table procurement.rfq_history (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 rfq_id uuid not null,version bigint not null,snapshot jsonb not null,actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),unique(rfq_id,version),
 foreign key(tenant_id,legal_entity_id,rfq_id) references procurement.rfqs(tenant_id,legal_entity_id,id)
);
create function procurement.rfq_read_allowed(p_tenant uuid,p_entity uuid,p_rfq uuid) returns boolean
language sql stable security definer set search_path='' as $$select exists(select 1 from procurement.rfqs r
 where r.id=p_rfq and r.tenant_id=p_tenant and r.legal_entity_id=p_entity
 and (core.has_permission(r.tenant_id,'procurement.rfq.manage',r.legal_entity_id,r.branch_id)
 or core.has_permission(r.tenant_id,'procurement.orders.manage',r.legal_entity_id,r.branch_id)))$$;
alter table procurement.rfqs enable row level security;alter table procurement.rfqs force row level security;
create policy rfq_read on procurement.rfqs for select to authenticated using(procurement.rfq_read_allowed(tenant_id,legal_entity_id,id));
do $$declare t text;begin
 foreach t in array array['rfq_lines','supplier_quotes','rfq_history'] loop
  execute format('alter table procurement.%I enable row level security',t);
  execute format('alter table procurement.%I force row level security',t);
  execute format('create policy rfq_read on procurement.%I for select to authenticated using(procurement.rfq_read_allowed(tenant_id,legal_entity_id,rfq_id))',t);
 end loop;
end $$;
alter table procurement.supplier_quote_lines enable row level security;alter table procurement.supplier_quote_lines force row level security;
create policy quote_lines_read on procurement.supplier_quote_lines for select to authenticated
using(exists(select 1 from procurement.supplier_quotes q where q.id=quote_id and q.tenant_id=supplier_quote_lines.tenant_id));
create trigger rfq_history_immutable before update or delete on procurement.rfq_history for each row execute function workflow.reject_history_mutation();
create trigger rfq_sources_immutable before update or delete on procurement.rfq_lines for each row execute function workflow.reject_history_mutation();
revoke all on procurement.rfqs,procurement.rfq_lines,procurement.supplier_quotes,procurement.supplier_quote_lines,procurement.rfq_history from public,anon,authenticated;
grant select on procurement.rfqs,procurement.rfq_lines,procurement.supplier_quotes,procurement.supplier_quote_lines,procurement.rfq_history to authenticated;
revoke all on function procurement.rfq_read_allowed(uuid,uuid,uuid) from public,anon;
grant execute on function procurement.rfq_read_allowed(uuid,uuid,uuid) to authenticated;

create view api.request_for_quotes with(security_invoker=true) as
select r.tenant_id,r.legal_entity_id,r.branch_id,r.id,r.status,
 sales.flow_exact_json(to_jsonb(r))||jsonb_build_object(
 'lines',coalesce((select jsonb_agg(l.source_snapshot||jsonb_build_object('source_line_id',l.source_line_id) order by l.id)
  from procurement.rfq_lines l where l.rfq_id=r.id),'[]'),
 'quotes',coalesce((select jsonb_agg(sales.flow_exact_json(to_jsonb(q))||jsonb_build_object(
  'supplier_name',(select x->>'name' from jsonb_array_elements(r.invited_suppliers) x where x->>'id'=q.supplier_id::text),
  'lines',coalesce((select jsonb_agg(l.detail order by l.id) from procurement.supplier_quote_lines l where l.quote_id=q.id),'[]'))
  order by q.base_total,q.id) from procurement.supplier_quotes q where q.rfq_id=r.id),'[]')) detail
from procurement.rfqs r;
grant select on api.request_for_quotes to authenticated;

create function api.upsert_request_for_quote(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_id uuid:=(p_payload->>'id')::uuid;v_operation text:=p_payload->>'operation';v_hash text;v_result jsonb;v_before jsonb;v_entity jsonb;
 v_rfq procurement.rfqs%rowtype;v_req procurement.requisitions%rowtype;v_quote procurement.supplier_quotes%rowtype;
 v_supplier uuid;v_invites uuid[];v_sources uuid[];v_quote_id uuid;v_line jsonb;v_source jsonb;v_tax finance.tax_definitions%rowtype;
 v_lines jsonb:='[]';v_unit jsonb;v_seen uuid[]:='{}';v_line_id uuid;v_q numeric;v_price numeric;v_discount numeric;v_gross numeric;
 v_net numeric;v_tax_amount numeric;v_total numeric:=0;v_subtotal numeric:=0;v_tax_total numeric:=0;v_rate numeric;
 v_date date;v_valid date;v_rate_date date;v_currency text;v_base text;v_scale integer;v_rate_id uuid;v_complete boolean:=true;
begin
 perform core.wave3_require_scope(p_tenant_id,'procurement.rfq.manage',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_id is null
 or jsonb_typeof(p_payload) is distinct from 'object' or v_operation is null then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash('procurement.rfq.upsert',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,'procurement.rfq.upsert',p_command_id,p_idempotency_key,v_hash);
 if v_result is not null then return v_result;end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('procurement.rfq:'||v_id::text,0));
 select * into v_rfq from procurement.rfqs where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if found then
  select detail into v_before from api.request_for_quotes where id=v_id;
  perform core.wave3_assert_expected_version(v_rfq.version,p_expected_entity_version,v_before);
  if v_rfq.status<>'issued' then raise exception using errcode='55000',message='RFQ_NOT_EDITABLE';end if;
 elsif v_operation<>'issue' or p_expected_entity_version is not null then
  raise exception using errcode='40001',message='VERSION_CONFLICT';
 end if;
 select currency_code,rounding_scale into v_base,v_scale from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 if v_operation='issue' then
  if v_rfq.id is not null then raise exception using errcode='55000',message='RFQ_ALREADY_ISSUED';end if;
  select * into v_req from procurement.requisitions where id=(p_payload->>'requisition_id')::uuid and tenant_id=p_tenant_id
   and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for share;
  if not found or v_req.status<>'approved' then raise exception using errcode='55000',message='APPROVED_REQUISITION_REQUIRED';end if;
  perform core.wave3_assert_expected_version(v_req.version,(p_payload->>'requisition_version')::bigint,'{}');
  if p_payload ? 'source_line_ids' then
   if jsonb_typeof(p_payload->'source_line_ids') is distinct from 'array' then raise exception using errcode='22023',message='RFQ_SOURCE_LINES_INVALID';end if;
   select array_agg(value::uuid) into v_sources from jsonb_array_elements_text(p_payload->'source_line_ids');
  else select array_agg(id) into v_sources from procurement.requisition_lines where requisition_id=v_req.id;end if;
  if coalesce(cardinality(v_sources),0) not between 1 and 500 or cardinality(v_sources)<>(select count(distinct x) from unnest(v_sources) x)
   or cardinality(v_sources)<>(select count(*) from procurement.requisition_lines where requisition_id=v_req.id and id=any(v_sources)) then
   raise exception using errcode='22023',message='RFQ_SOURCE_LINES_INVALID';end if;
  if jsonb_typeof(p_payload->'invited_supplier_ids') is distinct from 'array' then raise exception using errcode='22023',message='SUPPLIERS_REQUIRED';end if;
  select array_agg(value::uuid) into v_invites from jsonb_array_elements_text(p_payload->'invited_supplier_ids');
  if coalesce(cardinality(v_invites),0) not between 1 and 100 or
   cardinality(v_invites)<>(select count(distinct x) from unnest(v_invites) x) then raise exception using errcode='22023',message='SUPPLIERS_INVALID';end if;
  foreach v_supplier in array v_invites loop
   if not exists(select 1 from crm.parties where id=v_supplier and tenant_id=p_tenant_id and status='active' and kind in('supplier','both')) then
    raise exception using errcode='22023',message='SUPPLIER_INVALID';end if;
  end loop;
  v_date:=(p_payload->>'document_date')::date;
  insert into procurement.rfqs(id,tenant_id,legal_entity_id,branch_id,requisition_id,requisition_version,invited_supplier_ids,invited_suppliers,
   title,document_date,close_date,document_number,created_by,updated_by)
  values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_req.id,v_req.version,v_invites,
   (select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',display_name) order by id) from crm.parties where id=any(v_invites)),trim(p_payload->>'title'),
   v_date,(p_payload->>'close_date')::date,sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,'request_for_quote',v_date,auth.uid()),auth.uid(),auth.uid());
  insert into procurement.rfq_lines(tenant_id,legal_entity_id,rfq_id,source_line_id,source_snapshot)
  select p_tenant_id,p_legal_entity_id,v_id,l.id,sales.flow_exact_json(to_jsonb(l)) from procurement.requisition_lines l where l.requisition_id=v_req.id and l.id=any(v_sources);
 elsif v_operation='record_quote' then
  v_supplier:=(p_payload->>'supplier_id')::uuid;v_quote_id:=(p_payload->>'quote_id')::uuid;
  if v_quote_id is null or v_supplier is null or not(v_supplier=any(v_rfq.invited_supplier_ids))
   or not exists(select 1 from crm.parties where id=v_supplier and tenant_id=p_tenant_id and status='active' and kind in('supplier','both')) then
    raise exception using errcode='22023',message='INVITED_SUPPLIER_REQUIRED';end if;
  select * into v_quote from procurement.supplier_quotes where rfq_id=v_id and supplier_id=v_supplier;
  if found and v_quote.id<>v_quote_id then raise exception using errcode='22023',message='QUOTE_ID_MISMATCH';end if;
  v_date:=(p_payload->>'quote_date')::date;v_valid:=(p_payload->>'valid_until')::date;v_currency:=p_payload->>'currency_code';
  v_rate_date:=(p_payload->>'rate_date')::date;v_rate_id:=(p_payload->>'exchange_rate_id')::uuid;
  v_rate:=sales.wave3_decimal_string(p_payload->'exchange_rate','exchange_rate',10,true,0,null);
  if v_rate<=0 or not exists(select 1 from core.currencies where code=v_currency and active) then raise exception using errcode='22023',message='CURRENCY_INVALID';end if;
  if v_currency=v_base then
   if v_rate<>1 or v_rate_id is not null then raise exception using errcode='22023',message='BASE_RATE_MUST_BE_ONE';end if;
  elsif not exists(select 1 from finance.exchange_rates where id=v_rate_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and status='active' and source_currency_code=v_currency and target_currency_code=v_base and rate=v_rate and effective_date=v_rate_date) then
   raise exception using errcode='22023',message='RATE_SNAPSHOT_INVALID';end if;
  if jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500 then
   raise exception using errcode='22023',message='QUOTE_LINES_REQUIRED';end if;
  for v_line in select value from jsonb_array_elements(p_payload->'lines') loop
   v_line_id:=(v_line->>'source_line_id')::uuid;
   if v_line_id is null or v_line_id=any(v_seen) then raise exception using errcode='22023',message='QUOTE_SOURCE_INVALID';end if;
   v_seen:=array_append(v_seen,v_line_id);
   select source_snapshot into v_source from procurement.rfq_lines where rfq_id=v_id and source_line_id=v_line_id;
   if not found then raise exception using errcode='22023',message='QUOTE_SOURCE_INVALID';end if;
   v_q:=sales.wave3_decimal_string(v_line->'quantity','quantity',6,true,0,null);
   v_price:=sales.wave3_decimal_string(v_line->'unit_price','unit_price',6,true,0,null);
   v_discount:=sales.wave3_decimal_string(coalesce(v_line->'discount_percent','"0"'),'discount_percent',6,true,0,100);
   if v_q<=0 then raise exception using errcode='22023',message='QUANTITY_INVALID';end if;
   v_unit:=inventory.resolve_product_unit(p_tenant_id,p_legal_entity_id,(v_source->>'product_id')::uuid,(v_source->>'unit_id')::uuid,
    v_line->'quantity',v_source->'conversion_numerator',v_source->'conversion_denominator');
   if v_q<>(v_source->>'quantity')::numeric then v_complete:=false;end if;
   v_gross:=round(v_q*v_price,v_scale);v_discount:=round(v_gross*v_discount/100,v_scale);v_net:=v_gross-v_discount;
   v_tax:=null;v_tax_amount:=0;
   if v_line->>'tax_definition_id' is not null then
    select * into v_tax from finance.tax_definitions where id=(v_line->>'tax_definition_id')::uuid and tenant_id=p_tenant_id
     and legal_entity_id=p_legal_entity_id and status='active' and kind in('input','zero','exempt')
     and v_date>=valid_from and (valid_to is null or v_date<=valid_to);
    if not found then raise exception using errcode='22023',message='INPUT_TAX_INVALID';end if;
    v_tax_amount:=round(v_net*v_tax.rate/(case when v_tax.inclusive then 100+v_tax.rate else 100 end),v_scale);
    if v_tax.inclusive then v_net:=v_net-v_tax_amount;end if;
   end if;
   v_subtotal:=v_subtotal+v_net;v_tax_total:=v_tax_total+v_tax_amount;v_total:=v_total+v_net+v_tax_amount;
   v_lines:=v_lines||jsonb_build_array(jsonb_build_object('source_line_id',v_line_id,'product_id',v_source->>'product_id',
    'description',v_source->>'description','unit_id',v_source->>'unit_id','quantity',v_q::text,'unit_price',v_price::text,
    'discount_percent',coalesce(v_line->>'discount_percent','0'),'discount_amount',v_discount::text,
    'tax_definition_id',v_tax.id,'tax_rate',coalesce(v_tax.rate,0)::text,'tax_inclusive',coalesce(v_tax.inclusive,false),
    'tax_definition_version',v_tax.version,'net_amount',v_net::text,'tax_amount',v_tax_amount::text,'line_total',(v_net+v_tax_amount)::text)||v_unit);
  end loop;
  v_complete:=v_complete and cardinality(v_seen)=(select count(*) from procurement.rfq_lines where rfq_id=v_id);
  insert into procurement.supplier_quotes(id,tenant_id,legal_entity_id,rfq_id,supplier_id,quote_date,valid_until,currency_code,
   exchange_rate_id,exchange_rate,rate_date,payment_terms,delivery_terms,subtotal,tax_total,total,base_total,complete,created_by,updated_by)
  values(v_quote_id,p_tenant_id,p_legal_entity_id,v_id,v_supplier,v_date,v_valid,v_currency,v_rate_id,v_rate,v_rate_date,
   trim(p_payload->>'payment_terms'),trim(p_payload->>'delivery_terms'),v_subtotal,v_tax_total,v_total,round(v_total*v_rate,v_scale),v_complete,auth.uid(),auth.uid())
  on conflict(id) do update set quote_date=excluded.quote_date,valid_until=excluded.valid_until,currency_code=excluded.currency_code,
   exchange_rate_id=excluded.exchange_rate_id,exchange_rate=excluded.exchange_rate,rate_date=excluded.rate_date,
   payment_terms=excluded.payment_terms,delivery_terms=excluded.delivery_terms,subtotal=excluded.subtotal,tax_total=excluded.tax_total,
   total=excluded.total,base_total=excluded.base_total,complete=excluded.complete,version=procurement.supplier_quotes.version+1,
   updated_by=auth.uid(),updated_at=clock_timestamp()
  where procurement.supplier_quotes.rfq_id=v_id and procurement.supplier_quotes.supplier_id=v_supplier and procurement.supplier_quotes.tenant_id=p_tenant_id;
  if not found then raise exception using errcode='22023',message='QUOTE_ID_MISMATCH';end if;
  delete from procurement.supplier_quote_lines where quote_id=v_quote_id;
  insert into procurement.supplier_quote_lines(tenant_id,legal_entity_id,quote_id,source_line_id,detail)
   select p_tenant_id,p_legal_entity_id,v_quote_id,(x->>'source_line_id')::uuid,x from jsonb_array_elements(v_lines) x;
  update procurement.rfqs set version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_id;
 elsif v_operation='select' then
  select * into v_quote from procurement.supplier_quotes where id=(p_payload->>'quote_id')::uuid and rfq_id=v_id;
  if not found or not v_quote.complete or v_quote.valid_until<current_date then raise exception using errcode='55000',message='COMPLETE_VALID_QUOTE_REQUIRED';end if;
  if not exists(select 1 from crm.parties where id=v_quote.supplier_id and tenant_id=p_tenant_id and status='active' and kind in('supplier','both')) then
   raise exception using errcode='22023',message='SUPPLIER_INACTIVE';end if;
  if length(trim(coalesce(p_payload->>'selection_reason',''))) not between 1 and 1000 then raise exception using errcode='22023',message='SELECTION_REASON_REQUIRED';end if;
  update procurement.rfqs set status='selected',selected_quote_id=v_quote.id,selection_reason=trim(p_payload->>'selection_reason'),
   version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_id;
 else raise exception using errcode='22023',message='RFQ_OPERATION_INVALID';end if;
 select detail into v_entity from api.request_for_quotes where id=v_id;
 v_result:=core.wave3_finish_command(p_tenant_id,'procurement.rfq.upsert',p_command_id,'request_for_quote',v_id,
  p_idempotency_key,v_hash,v_before,v_entity,p_legal_entity_id,p_branch_id,'{}',
  case when v_operation='record_quote' then null else jsonb_build_object('from_status',v_rfq.status,'to_status',v_entity->>'status') end,
  jsonb_build_array(jsonb_build_object('topic','procurement.rfq.updated','payload',jsonb_build_object('operation',v_operation))));
 insert into procurement.rfq_history(tenant_id,legal_entity_id,rfq_id,version,snapshot,actor_id)
 values(p_tenant_id,p_legal_entity_id,v_id,(v_entity->>'version')::bigint,v_entity,auth.uid());
 return v_result;
end $$;
revoke all on function api.upsert_request_for_quote(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_request_for_quote(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
-- Index every reference without changing indexes on shared tables.
do $$declare c record;begin
 for c in select con.conrelid::regclass tbl,con.conname,
  (select string_agg(quote_ident(a.attname),',' order by k.n) from unnest(con.conkey) with ordinality k(att,n)
   join pg_attribute a on a.attrelid=con.conrelid and a.attnum=k.att) cols
  from pg_constraint con join pg_class t on t.oid=con.conrelid join pg_namespace n on n.oid=t.relnamespace
  where con.contype='f' and n.nspname='procurement' and t.relname in('rfqs','rfq_lines','supplier_quotes','supplier_quote_lines','rfq_history')
 loop execute format('create index %I on %s(%s)',c.conname||'_idx',c.tbl,c.cols);end loop;
end $$;
