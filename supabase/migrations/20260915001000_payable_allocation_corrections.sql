-- Candidate only. Shared residual compatibility must be reviewed before application.
insert into core.permissions(code,module,description,privileged) values
 ('finance.payments.allocate','finance','Allocate existing supplier credits and payments.',true),
 ('finance.payments.reverse','finance','Reverse supplier allocations with retained history.',true)
on conflict(code) do nothing;
create or replace function finance.payable_read_allowed(p_tenant uuid,p_entity uuid,p_branch uuid) returns boolean language sql stable security definer set search_path='' as $$
 select core.is_tenant_member(p_tenant) and (procurement.bill_read_allowed(p_tenant,p_entity,p_branch)
 or core.has_permission(p_tenant,'finance.payments.manage',p_entity,p_branch) or core.has_permission(p_tenant,'finance.payments.post',p_entity,p_branch)
 or core.has_permission(p_tenant,'finance.payments.allocate',p_entity,p_branch) or core.has_permission(p_tenant,'finance.payments.reverse',p_entity,p_branch))$$;
create table finance.allocation_reversals(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 allocation_id uuid not null unique,posting_date date not null,reason text not null check(length(trim(reason)) between 1 and 1000),
 journal_entry_id uuid,source_snapshot jsonb not null,request_id uuid not null,command_id uuid not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),unique(tenant_id,id),
 foreign key(tenant_id,allocation_id) references finance.open_item_allocations(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
create index allocation_reversal_scope on finance.allocation_reversals(tenant_id,legal_entity_id,branch_id,posting_date,id);
create index allocation_reversal_journal on finance.allocation_reversals(tenant_id,journal_entry_id);
create trigger immutable before update or delete on finance.allocation_reversals for each row execute function workflow.reject_history_mutation();
alter table finance.allocation_reversals enable row level security;
alter table finance.allocation_reversals force row level security;
revoke all on finance.allocation_reversals from public,anon,authenticated;
grant select on finance.allocation_reversals to authenticated;
create policy ap_read on finance.allocation_reversals for select to authenticated using(finance.payable_read_allowed(tenant_id,legal_entity_id,branch_id));

create or replace function finance.flow_residual(p_tenant uuid,p_id uuid,p_as_of date default null)
returns jsonb language sql stable security definer set search_path='' as $$
 with active_allocations as (
  select a.* from finance.open_item_allocations a where a.tenant_id=p_tenant
   and (a.source_open_item_id=p_id or a.target_open_item_id=p_id)
   and (p_as_of is null or a.posting_date<=p_as_of)
   and not exists(select 1 from finance.allocation_reversals r where r.tenant_id=a.tenant_id and r.allocation_id=a.id
    and (p_as_of is null or r.posting_date<=p_as_of))
 ) select jsonb_build_object('amount',(o.original_amount+
  coalesce((select sum(source_amount) from active_allocations where source_open_item_id=o.id),0)-
  coalesce((select sum(transaction_amount+write_off+discount_amount) from active_allocations where target_open_item_id=o.id),0))::text,
 'base_amount',(o.original_base_amount+
  coalesce((select sum(source_base_amount) from active_allocations where source_open_item_id=o.id),0)-
  coalesce((select sum(target_base_amount+adjustment_base_amount) from active_allocations where target_open_item_id=o.id),0))::text)
 from finance.open_items o where o.tenant_id=p_tenant and o.id=p_id and (p_as_of is null or o.posting_date<=p_as_of) $$;

create function api.allocate_supplier_credit(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='finance.supplier_credit.allocate';v_hash text;v_result jsonb;v_source finance.open_items%rowtype;
 v_line jsonb;v_results jsonb:='[]';v_request uuid:=gen_random_uuid();v_date date:=(p_payload->>'posting_date')::date;v_reason text:=trim(p_payload->>'reason');
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.allocate',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_date is null or coalesce(length(v_reason),0) not between 1 and 1000
  or jsonb_typeof(p_payload->'allocations') is distinct from 'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 500
  or p_expected_entity_version is not null then raise exception using errcode='22023',message='ALLOCATION_PAYLOAD_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 if v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='FUTURE_POSTING_DATE';end if;
 perform 1 from finance.open_items where tenant_id=p_tenant_id and (id=(p_payload->>'source_open_item_id')::uuid or id in
  (select (x->>'target_open_item_id')::uuid from jsonb_array_elements(p_payload->'allocations')x)) order by id for update;
 select * into v_source from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and id=(p_payload->>'source_open_item_id')::uuid and kind='AP' and original_amount<0;
 if not found then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 for v_line in select value from jsonb_array_elements(p_payload->'allocations') loop
  v_results:=v_results||jsonb_build_array(finance.allocate_payable(v_source.id,(v_line->>'target_open_item_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,
   v_line||jsonb_build_object('reason',v_reason),v_date,v_request,p_command_id));
 end loop;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_allocation',p_command_id,p_idempotency_key,v_hash,null,
  jsonb_build_object('id',p_command_id,'source_open_item_id',v_source.id,'allocations',v_results,'source_residual',finance.flow_residual(p_tenant_id,v_source.id)),
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','open','to_status','allocated','reason',v_reason),
  jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('source_open_item_id',v_source.id))),'[]',v_request,v_request);
end $$;

create function api.reverse_supplier_allocation(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='finance.supplier_allocation.reverse';v_hash text;v_result jsonb;v_a finance.open_item_allocations%rowtype;v_source finance.open_items%rowtype;
 v_id uuid:=gen_random_uuid();v_request uuid:=gen_random_uuid();v_date date:=(p_payload->>'posting_date')::date;v_reason text:=trim(p_payload->>'reason');
 v_journal uuid;v_original finance.journal_entries%rowtype;v_lines jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.reverse',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_date is null or coalesce(length(v_reason),0) not between 1 and 1000
  or p_expected_entity_version is not null then raise exception using errcode='22023',message='ALLOCATION_REVERSAL_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_a from finance.open_item_allocations where id=(p_payload->>'allocation_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id;
 if not found then raise exception using errcode='P0002',message='ALLOCATION_NOT_FOUND';end if;
 perform 1 from finance.open_items where tenant_id=p_tenant_id and id in(v_a.source_open_item_id,v_a.target_open_item_id) order by id for update;
 select * into v_source from finance.open_items where id=v_a.source_open_item_id and tenant_id=p_tenant_id;
 if v_source.kind<>'AP' then raise exception using errcode='22023',message='AP_ALLOCATION_REQUIRED';end if;
 if exists(select 1 from finance.allocation_reversals where allocation_id=v_a.id) then raise exception using errcode='55000',message='ALLOCATION_ALREADY_REVERSED';end if;
 if v_date<v_a.posting_date or v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='ALLOCATION_REVERSAL_DATE_INVALID';end if;
 if exists(select 1 from procurement.payment_claims where tenant_id=p_tenant_id and open_item_id in(v_a.source_open_item_id,v_a.target_open_item_id) and active)
  then raise exception using errcode='55000',message='PAYABLE_ITEM_ALREADY_SELECTED';end if;
 if exists(select 1 from finance.open_item_allocations a where a.tenant_id=p_tenant_id and (a.source_open_item_id in(v_a.source_open_item_id,v_a.target_open_item_id)
  or a.target_open_item_id in(v_a.source_open_item_id,v_a.target_open_item_id)) and a.posting_date>v_date)
  or exists(select 1 from finance.allocation_reversals r join finance.open_item_allocations a on a.id=r.allocation_id where r.tenant_id=p_tenant_id
   and (a.source_open_item_id in(v_a.source_open_item_id,v_a.target_open_item_id) or a.target_open_item_id in(v_a.source_open_item_id,v_a.target_open_item_id)) and r.posting_date>v_date)
  then raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 if v_a.journal_entry_id is not null then
  select * into v_original from finance.journal_entries where id=v_a.journal_entry_id and tenant_id=p_tenant_id;
  select jsonb_agg(finance.flow_jline(account_id,transaction_credit-transaction_debit,base_credit-base_debit) order by line_number) into v_lines
   from finance.journal_lines where journal_entry_id=v_original.id and tenant_id=p_tenant_id;
  v_journal:=finance.flow_post_journal(to_jsonb(v_original)||jsonb_build_object('document_date',v_date,'customer_id',v_source.party_id),v_lines,
   'supplier_allocation_reversal',v_id,v_request,p_command_id);
 end if;
 insert into finance.allocation_reversals(id,tenant_id,legal_entity_id,branch_id,allocation_id,posting_date,reason,journal_entry_id,source_snapshot,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_a.id,v_date,v_reason,v_journal,sales.flow_exact_json(to_jsonb(v_a)),v_request,p_command_id,auth.uid());
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_allocation_reversal',v_id,p_idempotency_key,v_hash,sales.flow_exact_json(to_jsonb(v_a)),
  jsonb_build_object('id',v_id,'allocation_id',v_a.id,'journal_entry_id',v_journal,'posting_date',v_date,'reason',v_reason,
   'source_residual',finance.flow_residual(p_tenant_id,v_a.source_open_item_id),'target_residual',finance.flow_residual(p_tenant_id,v_a.target_open_item_id)),
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','allocated','to_status','reversed','reason',v_reason),
  jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('allocation_id',v_a.id))),'[]',v_request,v_request);
end $$;
revoke all on function api.allocate_supplier_credit(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.reverse_supplier_allocation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.allocate_supplier_credit(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.reverse_supplier_allocation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
create or replace function finance.allocate_payable(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_date date,p_request uuid,p_command uuid,p_proposal uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_s finance.open_items%rowtype;v_t finance.open_items%rowtype;v_sr jsonb;v_tr jsonb;v_rate finance.exchange_rates%rowtype;v_scale integer;
 v_source numeric;v_target numeric;v_sb numeric;v_tb numeric;v_prior numeric;v_fx numeric;v_conversion numeric:=1;v_id uuid:=gen_random_uuid();v_journal uuid;v_control uuid;v_doc jsonb;
begin
 perform 1 from finance.open_items where tenant_id=p_tenant and id in(p_source,p_target) order by id for update;
 select * into v_s from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_source;
 select * into v_t from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_target;
 if v_s.id is null or v_t.id is null or v_s.party_id<>v_t.party_id or v_s.kind<>'AP' or v_t.kind<>'AP' or v_s.original_amount>=0 or v_t.original_amount<=0
  or v_s.base_currency_code<>v_t.base_currency_code or p_date<greatest(v_s.posting_date,v_t.posting_date) then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 if exists(select 1 from procurement.payment_claims where tenant_id=p_tenant and open_item_id in(p_source,p_target) and active and proposal_id is distinct from p_proposal)
 then raise exception using errcode='55000',message='PAYABLE_ITEM_ALREADY_SELECTED';end if;
 if exists(select 1 from finance.open_item_allocations where tenant_id=p_tenant and (source_open_item_id in(p_source,p_target) or target_open_item_id in(p_source,p_target)) and posting_date>p_date)
 then raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 if exists(select 1 from finance.allocation_reversals r join finance.open_item_allocations a on a.id=r.allocation_id where r.tenant_id=p_tenant
  and (a.source_open_item_id in(p_source,p_target) or a.target_open_item_id in(p_source,p_target)) and r.posting_date>p_date)
 then raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 select rounding_scale into v_scale from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 v_source:=sales.wave3_decimal_string(p_payload->'source_amount','source_amount',6,true,0,null);v_target:=sales.wave3_decimal_string(p_payload->'transaction_amount','transaction_amount',6,true,0,null);
 if v_source<=0 or v_target<=0 or round(v_source,v_scale)<>v_source or round(v_target,v_scale)<>v_target then raise exception using errcode='22023',message='ALLOCATION_AMOUNT_INVALID';end if;
 if v_s.currency_code<>v_t.currency_code then
  select * into v_rate from finance.exchange_rates where id=(p_payload->>'exchange_rate_id')::uuid and tenant_id=p_tenant and legal_entity_id=p_entity
   and source_currency_code=v_s.currency_code and target_currency_code=v_t.currency_code and effective_date<=p_date and status='active';
  if not found then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_REQUIRED';end if;v_conversion:=v_rate.rate;
 elsif p_payload->>'exchange_rate_id' is not null then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_INVALID';end if;
 if round(v_source*v_conversion,v_scale)<>v_target then raise exception using errcode='22023',message='ALLOCATION_CURRENCY_MISMATCH';end if;
 v_sr:=finance.flow_residual(p_tenant,p_source);v_tr:=finance.flow_residual(p_tenant,p_target);
 if v_source>-(v_sr->>'amount')::numeric or v_target>(v_tr->>'amount')::numeric then raise exception using errcode='22023',message='ALLOCATION_EXCEEDED';end if;
 -- Allocate from remaining carrying value: reversal can restore a different cent distribution.
 v_sb:=round(-(v_sr->>'base_amount')::numeric*v_source/(-(v_sr->>'amount')::numeric),v_scale);
 v_tb:=round((v_tr->>'base_amount')::numeric*v_target/(v_tr->>'amount')::numeric,v_scale);
 if v_sb<=0 or v_tb<=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
 v_fx:=v_sb-v_tb;
 if v_fx<>0 then
  select payable_account_id into v_control from procurement.supplier_bill_controls where tenant_id=p_tenant and legal_entity_id=p_entity;
  v_control:=finance.flow_account(p_tenant,p_entity,v_control,'liability',v_s.base_currency_code);
  v_doc:=jsonb_build_object('tenant_id',p_tenant,'legal_entity_id',p_entity,'branch_id',p_branch,'document_date',p_date,'customer_id',v_s.party_id,
   'currency_code',v_s.base_currency_code,'base_currency_code',v_s.base_currency_code,'exchange_rate','1');
  v_journal:=finance.flow_post_journal(v_doc,jsonb_build_array(finance.flow_jline(v_control,-v_fx,-v_fx),
   finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,case when v_fx>0 then 'exchange_loss' else 'exchange_gain' end,v_s.base_currency_code),v_fx,v_fx)),
   'supplier_allocation',v_id,p_request,p_command);
 end if;
 insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,
  source_base_amount,target_base_amount,exchange_difference,exchange_rate_id,conversion_rate,posting_date,reason,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_id,p_tenant,p_entity,p_branch,p_source,p_target,v_source,v_target,v_sb,v_tb,v_fx,v_rate.id,v_conversion,p_date,p_payload->>'reason',v_journal,p_request,p_command,p_request,auth.uid());
 return jsonb_build_object('allocation_id',v_id,'source_open_item_id',p_source,'target_open_item_id',p_target,'source_amount',v_source::text,'transaction_amount',v_target::text,
  'exchange_difference',v_fx::text,'journal_entry_id',v_journal,'source_residual',finance.flow_residual(p_tenant,p_source),'target_residual',finance.flow_residual(p_tenant,p_target));
end $$;
revoke all on function finance.allocate_payable(uuid,uuid,uuid,uuid,uuid,jsonb,date,uuid,uuid,uuid) from public,anon,authenticated;



create function api.payable_item_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_item_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_item finance.open_items%rowtype;v_rows jsonb;v_next uuid;begin
 if p_legal_entity_id is null or p_branch_id is null or not finance.payable_read_allowed(p_tenant_id,p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 select * into v_item from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and kind='AP' and id=p_item_id;
 if not found then raise exception using errcode='P0002',message='PAYABLE_ITEM_NOT_FOUND';end if;
 select jsonb_agg(detail order by id) into v_rows from (
  select a.id,sales.flow_exact_json(to_jsonb(a))||jsonb_build_object('source_document_number',s.document_number,'target_document_number',t.document_number,
   'reversal',(select sales.flow_exact_json(to_jsonb(r)) from finance.allocation_reversals r where r.allocation_id=a.id)) detail
  from finance.open_item_allocations a join finance.open_items s on s.id=a.source_open_item_id join finance.open_items t on t.id=a.target_open_item_id
  where a.tenant_id=p_tenant_id and (a.source_open_item_id=p_item_id or a.target_open_item_id=p_item_id) and (p_after is null or a.id>p_after) order by a.id limit 51)x;
 v_rows:=coalesce(v_rows,'[]');if jsonb_array_length(v_rows)>50 then v_next:=(v_rows->49->>'id')::uuid;v_rows:=v_rows-50;end if;
 return jsonb_build_object('item',sales.flow_exact_json(to_jsonb(v_item))||finance.flow_residual(p_tenant_id,p_item_id),'allocations',v_rows,'next_cursor',v_next);
end $$;
revoke all on function api.payable_item_detail(uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.payable_item_detail(uuid,uuid,uuid,uuid,uuid) to authenticated;

create function api.payable_allocation_targets(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_source_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_source finance.open_items%rowtype;v_items jsonb;v_next uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.allocate',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null then raise exception using errcode='22023',message='SCOPE_REQUIRED';end if;
 select * into v_source from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_source_id and kind='AP' and original_amount<0;
 if not found then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 select jsonb_agg(detail order by id) into v_items from (
  select o.id,sales.flow_exact_json(to_jsonb(o))||finance.flow_residual(p_tenant_id,o.id) detail from finance.open_items o
  where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.party_id=v_source.party_id
   and o.kind='AP' and o.original_amount>0 and (p_after is null or o.id>p_after)
   and (finance.flow_residual(p_tenant_id,o.id)->>'amount')::numeric>0
   and not exists(select 1 from procurement.payment_claims c where c.tenant_id=p_tenant_id and c.open_item_id=o.id and c.active)
  order by o.id limit 51)x;
 v_items:=coalesce(v_items,'[]');if jsonb_array_length(v_items)>50 then v_next:=(v_items->49->>'id')::uuid;v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',v_next);
end $$;
revoke all on function api.payable_allocation_targets(uuid,uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.payable_allocation_targets(uuid,uuid,uuid,uuid,uuid) to authenticated;
create or replace function api.supplier_statement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_supplier_id uuid,
 p_currency_code text,p_as_of date,p_buckets integer[] default array[30,60,90])
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_rows jsonb;v_amount numeric;v_base numeric;v_bucket jsonb;v_count integer;begin
 if not finance.payable_read_allowed(p_tenant_id,p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if p_branch_id is null or p_supplier_id is null or p_as_of is null or p_as_of>(now() at time zone 'UTC')::date
 or p_currency_code is null or p_currency_code!~'^[A-Z]{3}$'
 or p_buckets is null or cardinality(p_buckets) not between 1 and 12 or exists(select 1 from unnest(p_buckets) x where x is null or x<=0)
 or p_buckets<>(select array_agg(distinct x order by x) from unnest(p_buckets) x) then
 raise exception using errcode='22023',message='STATEMENT_FILTER_INVALID';end if;
 select count(*) into v_count from (select id from finance.open_items where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
 and branch_id=p_branch_id and party_id=p_supplier_id and kind='AP' and currency_code=p_currency_code and posting_date<=p_as_of limit 10001) bounded;
 if v_count>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 with items as (select o.*,finance.flow_residual(p_tenant_id,o.id,p_as_of) residual from finance.open_items o
 where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.party_id=p_supplier_id
 and o.kind='AP' and o.currency_code=p_currency_code and o.posting_date<=p_as_of), rows as (
 select id,source_type,source_id,document_number,currency_code,posting_date,due_date,original_amount::text,original_base_amount::text,
 residual->>'amount' as open_amount,residual->>'base_amount' as open_base_amount,
 case when original_amount<0 then -1 when due_date>=p_as_of then 0 else
 1+(select count(*) from unnest(p_buckets) b where p_as_of-due_date>b) end bucket from items)
 select coalesce(jsonb_agg(to_jsonb(rows) order by posting_date,id),'[]'),coalesce(sum(open_amount::numeric),0),coalesce(sum(open_base_amount::numeric),0)
 into v_rows,v_amount,v_base from rows;
 select coalesce(jsonb_agg(jsonb_build_object('bucket',bucket,'amount',amount::text,'base_amount',base_amount::text) order by bucket),'[]') into v_bucket
 from (select (x->>'bucket')::integer bucket,sum((x->>'open_amount')::numeric) amount,sum((x->>'open_base_amount')::numeric) base_amount
 from jsonb_array_elements(v_rows) x group by (x->>'bucket')::integer) b;
 return jsonb_build_object('supplier_id',p_supplier_id,'currency_code',p_currency_code,'as_of',p_as_of,
 'rows',v_rows,'aging',v_bucket,'bucket_days',p_buckets,'open_amount',v_amount::text,'open_base_amount',v_base::text,
 'basis','posting_date','unapplied_credits_separate',true);end $$;

revoke all on function api.supplier_statement(uuid,uuid,uuid,uuid,text,date,integer[]) from public,anon;
grant execute on function api.supplier_statement(uuid,uuid,uuid,uuid,text,date,integer[]) to authenticated;


create function api.payable_allocation_rates(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_source_currency text,p_target_currency text,p_date date,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;v_next uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.allocate',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_date is null then raise exception using errcode='22023',message='RATE_FILTER_INVALID';end if;
 select jsonb_agg(jsonb_build_object('id',id,'rate',rate::text,'date',effective_date) order by id) into v_items from (
  select id,rate,effective_date from finance.exchange_rates where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active'
   and source_currency_code=p_source_currency and target_currency_code=p_target_currency and effective_date<=p_date and (p_after is null or id>p_after) order by id limit 51)x;
 v_items:=coalesce(v_items,'[]');if jsonb_array_length(v_items)>50 then v_next:=(v_items->49->>'id')::uuid;v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',v_next);
end $$;
revoke all on function api.payable_allocation_rates(uuid,uuid,uuid,text,text,date,uuid) from public,anon;
grant execute on function api.payable_allocation_rates(uuid,uuid,uuid,text,text,date,uuid) to authenticated;
create or replace function api.supplier_payment_reference_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null,p_search text default '',
 p_supplier_id uuid default null,p_cash_bank_account_id uuid default null,p_date date default null,p_proposal_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;v_next uuid;v_base text;v_search text:=lower(trim(coalesce(p_search,'')));begin
 if p_resource='payment_suppliers' then
  if not finance.payable_read_allowed(p_tenant_id,p_legal_entity_id,p_branch_id) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 else perform core.wave3_require_scope(p_tenant_id,'finance.payments.manage',p_legal_entity_id,p_branch_id);end if;
 if p_legal_entity_id is null or p_branch_id is null or length(v_search)>100 then raise exception using errcode='22023',message='REFERENCE_SCOPE_INVALID';end if;
 select currency_code into v_base from core.legal_entities where id=p_legal_entity_id and tenant_id=p_tenant_id;
 if p_resource='payment_items' then
  if p_supplier_id is null or p_cash_bank_account_id is null or p_date is null then raise exception using errcode='22023',message='PAYMENT_FILTER_REQUIRED';end if;
  select jsonb_agg(sales.flow_exact_json(to_jsonb(x)) order by id) into v_items from (
   select o.id,o.document_number,o.source_id,o.source_type,o.due_date,o.currency_code,
    case when o.original_amount<0 then 'credit' else 'bill' end kind,finance.flow_residual(p_tenant_id,o.id) residual,
    exists(select 1 from procurement.payment_claims c where c.tenant_id=p_tenant_id and c.open_item_id=o.id and c.active and c.proposal_id is distinct from p_proposal_id) claimed
   from finance.open_items o join finance.cash_bank_accounts b on b.id=p_cash_bank_account_id and b.tenant_id=o.tenant_id and b.legal_entity_id=o.legal_entity_id and b.branch_id=o.branch_id
   where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and o.branch_id=p_branch_id and o.kind='AP' and o.party_id=p_supplier_id
    and o.currency_code=b.currency_code and b.status='active' and o.posting_date<=p_date and (o.original_amount<0 or o.due_date<=p_date)
    and (p_after is null or o.id>p_after) and (v_search='' or position(v_search in lower(o.document_number))>0)
    and (finance.flow_residual(p_tenant_id,o.id)->>'amount')::numeric<>0
   order by o.id limit 51) x;
 elsif p_resource='payment_suppliers' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',display_name) order by id) into v_items from (
   select * from crm.parties where tenant_id=p_tenant_id and status='active' and kind in('supplier','both') and (p_after is null or id>p_after)
    and (v_search='' or position(v_search in lower(code||' '||display_name))>0) order by id limit 51)x;
 elsif p_resource='payment_banks' then
  select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name||' · '||currency_code,'currency_code',currency_code) order by id) into v_items from (
   select * from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and status='active'
    and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(code||' '||name))>0) order by id limit 51)x;
 elsif p_resource='payment_rates' then
  select jsonb_agg(jsonb_build_object('id',id,'code',source_currency_code,'name',effective_date::text||' · '||rate::text,'currency_code',source_currency_code,'exchange_rate',rate::text) order by id) into v_items from (
   select * from finance.exchange_rates where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active' and target_currency_code=v_base
    and (p_after is null or id>p_after) and (v_search='' or position(v_search in lower(source_currency_code))>0) order by id limit 51)x;
 else raise exception using errcode='22023',message='REFERENCE_RESOURCE_INVALID';end if;
 v_items:=coalesce(v_items,'[]');if jsonb_array_length(v_items)>50 then v_next:=(v_items->49->>'id')::uuid;v_items:=v_items-50;end if;
 return jsonb_build_object('items',v_items,'next_cursor',v_next,'base_currency',v_base);
end $$;
revoke all on function api.supplier_payment_reference_options(uuid,uuid,uuid,text,uuid,text,uuid,uuid,date,uuid) from public,anon;
grant execute on function api.supplier_payment_reference_options(uuid,uuid,uuid,text,uuid,text,uuid,uuid,date,uuid) to authenticated;

