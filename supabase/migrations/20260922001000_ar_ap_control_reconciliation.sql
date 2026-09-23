-- UNAPPLIED AC-317 candidate. Existing ledger, journal and residual engines only.
insert into core.permissions(code,module,description,privileged) values
 ('finance.controls.reconcile','finance','Generate and read branch AR/AP control evidence.',true),
 ('finance.receipts.reverse','finance','Reverse customer allocations with reason and history.',true)
on conflict(code) do nothing;

-- A control is recovered from the immutable source journal, never today's mapping.
-- Ambiguous/unsupported historical sources fail explicitly rather than invent a basis.
create function finance.open_item_control(t uuid,i uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare ids uuid[];begin
 select array_agg(q.account_id) into ids from (
  select l.account_id from finance.open_items o join finance.journal_lines l on l.tenant_id=o.tenant_id and l.journal_entry_id=o.journal_entry_id
  join finance.accounts a on a.id=l.account_id and a.tenant_id=o.tenant_id
  where o.tenant_id=t and o.id=i and a.account_type=case o.kind when 'AR' then 'asset' else 'liability' end
  group by l.account_id,o.original_base_amount,o.kind
  having sum(l.base_debit-l.base_credit)=case o.kind when 'AR' then o.original_base_amount else -o.original_base_amount end
 )q;
 if coalesce(cardinality(ids),0)<>1 then raise exception using errcode='55000',message='OPEN_ITEM_CONTROL_BASIS_REQUIRED';end if;
 return ids[1];end $$;
revoke all on function finance.open_item_control(uuid,uuid) from public,anon,authenticated;

create or replace function finance.flow_allocate(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,
 p_payload jsonb,p_date date,p_request uuid,p_command uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_s finance.open_items%rowtype;v_t finance.open_items%rowtype;v_sr jsonb;v_tr jsonb;
 v_source numeric;v_target numeric;v_write numeric;v_discount numeric;v_sb numeric;v_tb numeric;v_ab numeric;
 v_fx numeric;v_rate finance.exchange_rates%rowtype;v_scale integer;v_conversion numeric:=1;v_id uuid:=gen_random_uuid();
 v_journal uuid;v_lines jsonb:='[]';v_doc jsonb;v_control uuid;v_target_control uuid;v_prior numeric;v_adjust numeric;
begin
 perform 1 from finance.open_items where tenant_id=p_tenant and id in (p_source,p_target) order by id for update;
 select * into v_s from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_source;
 select * into v_t from finance.open_items where tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and id=p_target;
 if v_s.id is null or v_t.id is null or v_s.party_id<>v_t.party_id or v_s.original_amount>=0 or v_t.original_amount<=0
 or v_s.kind<>'AR' or v_t.kind<>'AR' or v_s.base_currency_code<>v_t.base_currency_code
 or p_date<greatest(v_s.posting_date,v_t.posting_date) then raise exception using errcode='22023',message='ALLOCATION_SOURCE_INVALID';end if;
 if exists(select 1 from finance.open_item_allocations where tenant_id=p_tenant and
 (source_open_item_id in (p_source,p_target) or target_open_item_id in (p_source,p_target)) and posting_date>p_date) then
 raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 if exists(select 1 from finance.allocation_reversals r join finance.open_item_allocations a on a.id=r.allocation_id
 where r.tenant_id=p_tenant and (a.source_open_item_id in(p_source,p_target) or a.target_open_item_id in(p_source,p_target)) and r.posting_date>p_date)
 then raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
 select rounding_scale into v_scale from core.legal_entities where id=p_entity and tenant_id=p_tenant;
 v_source:=sales.wave3_decimal_string(p_payload->'source_amount','Source amount',6,true,0,null)::numeric;
 v_target:=sales.wave3_decimal_string(p_payload->'transaction_amount','Target amount',6,true,0,null)::numeric;
 v_write:=sales.wave3_decimal_string(coalesce(p_payload->'write_off','"0"'),'Write-off',6,true,0,null)::numeric;
 v_discount:=sales.wave3_decimal_string(coalesce(p_payload->'discount_amount','"0"'),'Discount',6,true,0,null)::numeric;
 if v_source<=0 or v_target<=0 or v_source<>round(v_source,v_scale) or v_target<>round(v_target,v_scale)
 or v_write<>round(v_write,v_scale) or v_discount<>round(v_discount,v_scale) then raise exception using errcode='22023',message='ALLOCATION_AMOUNT_INVALID';end if;
 if v_write+v_discount>0 then
 perform core.wave3_require_scope(p_tenant,'finance.receipts.adjust',p_entity,p_branch);
 if nullif(trim(p_payload->>'reason'),'') is null then raise exception using errcode='22023',message='REASON_REQUIRED';end if;end if;
 if v_s.currency_code<>v_t.currency_code then
 select * into v_rate from finance.exchange_rates where tenant_id=p_tenant and legal_entity_id=p_entity and status='active'
 and id=(p_payload->>'exchange_rate_id')::uuid and source_currency_code=v_s.currency_code and target_currency_code=v_t.currency_code and effective_date<=p_date;
 if not found then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_REQUIRED';end if;v_conversion:=v_rate.rate;
 elsif p_payload->>'exchange_rate_id' is not null then raise exception using errcode='22023',message='ALLOCATION_EXCHANGE_RATE_INVALID';end if;
 if round(v_source*v_conversion,v_scale)<>v_target then raise exception using errcode='22023',message='ALLOCATION_CURRENCY_MISMATCH';end if;
 v_sr:=finance.flow_residual(p_tenant,p_source);v_tr:=finance.flow_residual(p_tenant,p_target);
 if v_source>-(v_sr->>'amount')::numeric or v_target+v_write+v_discount>(v_tr->>'amount')::numeric then
 raise exception using errcode='22023',message='ALLOCATION_EXCEEDED';end if;
 v_sb:=round(-(v_sr->>'base_amount')::numeric*v_source/(-(v_sr->>'amount')::numeric),v_scale);
 v_tb:=round((v_tr->>'base_amount')::numeric*v_target/(v_tr->>'amount')::numeric,v_scale);
 v_ab:=round((v_tr->>'base_amount')::numeric*(v_target+v_write+v_discount)/(v_tr->>'amount')::numeric,v_scale)-v_tb;
 if v_sb<=0 or v_tb<=0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;
 v_fx:=v_sb-v_tb;
 v_doc:=jsonb_build_object('tenant_id',p_tenant,'legal_entity_id',p_entity,'branch_id',p_branch,'document_date',p_date,
 'customer_id',v_s.party_id,'currency_code',v_s.base_currency_code,'base_currency_code',v_s.base_currency_code,'exchange_rate','1');
 v_control:=finance.open_item_control(p_tenant,p_source);v_target_control:=finance.open_item_control(p_tenant,p_target);
 if v_fx<>0 or v_ab<>0 or v_control<>v_target_control then
 if v_control<>v_target_control then
 v_lines:=jsonb_build_array(finance.flow_jline(v_control,v_sb,v_sb),finance.flow_jline(v_target_control,-v_sb,-v_sb));end if;
 v_control:=v_target_control;
 if v_fx<>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,v_fx,v_fx),finance.flow_jline(
 finance.flow_mapping(p_tenant,p_entity,case when v_fx>0 then 'exchange_gain' else 'exchange_loss' end,v_s.base_currency_code),-v_fx,-v_fx));end if;
 if v_ab>0 then
 v_lines:=v_lines||jsonb_build_array(finance.flow_jline(v_control,-v_ab,-v_ab));
 v_adjust:=round(v_ab*v_write/(v_write+v_discount),v_scale);
 if v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'write_off',v_s.base_currency_code),v_adjust,v_adjust));end if;
 if v_ab-v_adjust>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,'settlement_discount',v_s.base_currency_code),v_ab-v_adjust,v_ab-v_adjust));end if;
 end if;
 v_journal:=finance.flow_post_journal(v_doc,v_lines,'customer_allocation',v_id,p_request,p_command);end if;
 insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,
 source_amount,transaction_amount,source_base_amount,target_base_amount,exchange_difference,write_off,discount_amount,
 adjustment_base_amount,exchange_rate_id,conversion_rate,posting_date,reason,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_id,p_tenant,p_entity,p_branch,p_source,p_target,v_source,v_target,v_sb,v_tb,v_fx,v_write,v_discount,v_ab,v_rate.id,v_conversion,
 p_date,p_payload->>'reason',v_journal,p_request,p_command,p_request,auth.uid());
 return jsonb_build_object('allocation_id',v_id,'journal_entry_id',v_journal,'source_open_item_id',p_source,'target_open_item_id',p_target,
 'source_amount',v_source::text,'transaction_amount',v_target::text,'exchange_difference',v_fx::text,
 'source_residual',finance.flow_residual(p_tenant,p_source),'target_residual',finance.flow_residual(p_tenant,p_target));end $$;

create or replace function finance.allocate_payable(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_date date,p_request uuid,p_command uuid,p_proposal uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_s finance.open_items%rowtype;v_t finance.open_items%rowtype;v_sr jsonb;v_tr jsonb;v_rate finance.exchange_rates%rowtype;v_scale integer;
 v_source numeric;v_target numeric;v_sb numeric;v_tb numeric;v_prior numeric;v_fx numeric;v_conversion numeric:=1;v_id uuid:=gen_random_uuid();v_journal uuid;v_control uuid;v_target_control uuid;v_lines jsonb;v_doc jsonb;
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
 v_control:=finance.open_item_control(p_tenant,p_source);v_target_control:=finance.open_item_control(p_tenant,p_target);
 if v_fx<>0 or v_control<>v_target_control then
 v_doc:=jsonb_build_object('tenant_id',p_tenant,'legal_entity_id',p_entity,'branch_id',p_branch,'document_date',p_date,'customer_id',v_s.party_id,
 'currency_code',v_s.base_currency_code,'base_currency_code',v_s.base_currency_code,'exchange_rate','1');
 v_lines:=jsonb_build_array(finance.flow_jline(v_control,-v_sb,-v_sb),finance.flow_jline(v_target_control,v_tb,v_tb));
 if v_fx<>0 then v_lines:=v_lines||jsonb_build_array(finance.flow_jline(finance.flow_mapping(p_tenant,p_entity,
 case when v_fx>0 then 'exchange_loss' else 'exchange_gain' end,v_s.base_currency_code),v_fx,v_fx));end if;
 v_journal:=finance.flow_post_journal(v_doc,v_lines,'supplier_allocation',v_id,p_request,p_command);
 end if;
 insert into finance.open_item_allocations(id,tenant_id,legal_entity_id,branch_id,source_open_item_id,target_open_item_id,source_amount,transaction_amount,
  source_base_amount,target_base_amount,exchange_difference,exchange_rate_id,conversion_rate,posting_date,reason,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_id,p_tenant,p_entity,p_branch,p_source,p_target,v_source,v_target,v_sb,v_tb,v_fx,v_rate.id,v_conversion,p_date,p_payload->>'reason',v_journal,p_request,p_command,p_request,auth.uid());
 return jsonb_build_object('allocation_id',v_id,'source_open_item_id',p_source,'target_open_item_id',p_target,'source_amount',v_source::text,'transaction_amount',v_target::text,
  'exchange_difference',v_fx::text,'journal_entry_id',v_journal,'source_residual',finance.flow_residual(p_tenant,p_source),'target_residual',finance.flow_residual(p_tenant,p_target));
end $$;

create or replace function api.reverse_customer_allocation(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_command text:='finance.customer_allocation.reverse';v_hash text;v_result jsonb;v_a finance.open_item_allocations%rowtype;v_source finance.open_items%rowtype;
 v_id uuid:=gen_random_uuid();v_request uuid:=gen_random_uuid();v_date date:=(p_payload->>'posting_date')::date;v_reason text:=trim(p_payload->>'reason');
 v_journal uuid;v_original finance.journal_entries%rowtype;v_lines jsonb;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.receipts.reverse',p_legal_entity_id,p_branch_id);
 if p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null or v_date is null or coalesce(length(v_reason),0) not between 1 and 1000
  or p_expected_entity_version is not null then raise exception using errcode='22023',message='ALLOCATION_REVERSAL_INVALID';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_a from finance.open_item_allocations where id=(p_payload->>'allocation_id')::uuid and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id;
 if not found then raise exception using errcode='P0002',message='ALLOCATION_NOT_FOUND';end if;
 perform 1 from crm.parties where tenant_id=p_tenant_id and id=(select party_id from finance.open_items where id=v_a.source_open_item_id) for update;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_date);
 perform 1 from finance.open_items where tenant_id=p_tenant_id and id in(v_a.source_open_item_id,v_a.target_open_item_id) order by id for update;
 select * into v_source from finance.open_items where id=v_a.source_open_item_id and tenant_id=p_tenant_id;
 if v_source.kind<>'AR' then raise exception using errcode='22023',message='AR_ALLOCATION_REQUIRED';end if;
 if exists(select 1 from finance.allocation_reversals where allocation_id=v_a.id) then raise exception using errcode='55000',message='ALLOCATION_ALREADY_REVERSED';end if;
 if v_date<v_a.posting_date or v_date>(clock_timestamp() at time zone 'UTC')::date then raise exception using errcode='22023',message='ALLOCATION_REVERSAL_DATE_INVALID';end if;
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
   'customer_allocation_reversal',v_id,v_request,p_command_id);
 end if;
 insert into finance.allocation_reversals(id,tenant_id,legal_entity_id,branch_id,allocation_id,posting_date,reason,journal_entry_id,source_snapshot,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_a.id,v_date,v_reason,v_journal,sales.flow_exact_json(to_jsonb(v_a)),v_request,p_command_id,auth.uid());
 perform finance.flow_refresh_credit(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'customer_id',v_source.party_id));
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'customer_allocation_reversal',v_id,p_idempotency_key,v_hash,sales.flow_exact_json(to_jsonb(v_a)),
  jsonb_build_object('id',v_id,'allocation_id',v_a.id,'journal_entry_id',v_journal,'posting_date',v_date,'reason',v_reason,
   'source_residual',finance.flow_residual(p_tenant_id,v_a.source_open_item_id),'target_residual',finance.flow_residual(p_tenant_id,v_a.target_open_item_id)),
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('from_status','allocated','to_status','reversed','reason',v_reason),
  jsonb_build_array(jsonb_build_object('topic',v_command,'payload',jsonb_build_object('allocation_id',v_a.id))),'[]',v_request,v_request);
end $$;
revoke all on function api.reverse_customer_allocation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.reverse_customer_allocation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
-- Kind-aware history RLS prevents payable-only readers from seeing AR corrections.
drop policy ap_read on finance.allocation_reversals;
create policy scoped_read on finance.allocation_reversals for select to authenticated using(exists(
 select 1 from finance.open_item_allocations a join finance.open_items o on o.id=a.source_open_item_id
 where a.id=allocation_id and a.tenant_id=allocation_reversals.tenant_id and
 ((o.kind='AP' and finance.payable_read_allowed(o.tenant_id,o.legal_entity_id,o.branch_id)) or
 (o.kind='AR' and core.has_permission(o.tenant_id,'finance.receivables.view',o.legal_entity_id,o.branch_id)))));

create function finance.require_control_scope(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if e is null or b is null then raise exception using errcode='42501',message='OPERATIONAL_SCOPE_REQUIRED';end if;
 perform core.wave3_require_scope(t,'finance.view',e,b);
 perform core.wave3_require_scope(t,'finance.controls.reconcile',e,b);
end $$;
revoke all on function finance.require_control_scope(uuid,uuid,uuid) from public,anon,authenticated;

create table finance.control_reports(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 as_of date not null,generated_at timestamptz not null,summary jsonb not null,evidence jsonb not null,
 created_by uuid not null references auth.users(id),unique(tenant_id,id),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),check(octet_length(evidence::text)<=16777216)
);
alter table finance.control_reports enable row level security;
alter table finance.control_reports force row level security;
revoke all on finance.control_reports from public,anon,authenticated;
create trigger immutable before update or delete on finance.control_reports for each row execute function workflow.reject_history_mutation();
create index control_reports_scope on finance.control_reports(tenant_id,legal_entity_id,branch_id,id);
create index control_reports_branch on finance.control_reports(tenant_id,branch_id);
create index control_reports_actor on finance.control_reports(created_by);

-- STABLE fixes a single MVCC snapshot for all reads, including residual/reversal helpers.
create function finance.build_control_report(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d date:=(p->>'as_of')::date;k text:=p->>'kind';sgn integer;
 items jsonb;allocations jsonb;entries jsonb;journals jsonb;accounts jsonb;differences jsonb;result jsonb;
 ids uuid[];sv numeric;gv numeric;begin
 perform finance.require_control_scope(t,e,b);
 if k is null or k not in('AR','AP') or d is null or d>(statement_timestamp() at time zone 'UTC')::date then
 raise exception using errcode='22023',message='CONTROL_REPORT_INPUT_INVALID';end if;
 sgn:=case k when 'AR' then 1 else -1 end;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into items from (
  select o.id,o.party_id,party.display_name party_name,o.source_type,o.source_id,o.document_number,o.journal_entry_id,o.command_id,
  o.posting_date,o.due_date,o.currency_code,o.base_currency_code,finance.open_item_control(t,o.id)::text evidence_key,
  o.original_amount::text original_amount,o.original_base_amount::text original_base_amount,
  r->>'amount' open_amount,r->>'base_amount' open_base_amount,
  (o.original_amount-(r->>'amount')::numeric)::text settled_amount,
  (o.original_base_amount-(r->>'base_amount')::numeric)::text settled_base_amount
  from finance.open_items o join crm.parties party on party.id=o.party_id
  cross join lateral (select finance.flow_residual(t,o.id,d) r) residual
  where o.tenant_id=t and o.legal_entity_id=e and o.branch_id=b and o.kind=k and o.posting_date<=d order by o.id limit 10001)q;
 if jsonb_array_length(items)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into allocations from (
  select a.id,a.command_id,a.source_open_item_id,a.target_open_item_id,s.document_number source_document_number,z.document_number target_document_number,
  a.posting_date,a.journal_entry_id,a.source_amount::text,a.transaction_amount::text,a.source_base_amount::text,a.target_base_amount::text,
  a.write_off::text,a.discount_amount::text,a.adjustment_base_amount::text,a.exchange_difference::text,a.reason,
  finance.open_item_control(t,s.id)::text source_control,finance.open_item_control(t,z.id)::text evidence_key,
  case when r.id is not null then sales.flow_exact_json(to_jsonb(r)) end reversal
  from finance.open_item_allocations a join finance.open_items s on s.id=a.source_open_item_id join finance.open_items z on z.id=a.target_open_item_id
  left join finance.allocation_reversals r on r.allocation_id=a.id and r.posting_date<=d
  where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and s.kind=k and a.posting_date<=d order by a.id limit 10001)q;
 if jsonb_array_length(allocations)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select array_agg(distinct id order by id) into ids from (
  select (x->>'evidence_key')::uuid id from jsonb_array_elements(items)x
  union select account_id from finance.posting_mappings where tenant_id=t and legal_entity_id=e and purpose='receivable_control' and k='AR'
  union select payable_account_id from procurement.supplier_bill_controls where tenant_id=t and legal_entity_id=e and k='AP')a where id is not null;
 if coalesce(cardinality(ids),0) not between 1 and 50 then raise exception using errcode='55000',message='CONTROL_ACCOUNT_SETUP_REQUIRED';end if;
 -- Dated subledger movements retain original command lineage, including exact reversal effects.
 with movements as (
  select 'item:'||(x->>'id') id,x->>'evidence_key' evidence_key,x->>'command_id' command_id,x->>'source_type' source_type,x->>'source_id' source_id,
   x->>'posting_date' posting_date,(x->>'original_base_amount')::numeric value from jsonb_array_elements(items)x
  union all select 'allocation-source:'||(x->>'id'),x->>'source_control',x->>'command_id','allocation',x->>'id',x->>'posting_date',(x->>'source_base_amount')::numeric from jsonb_array_elements(allocations)x
  union all select 'allocation-target:'||(x->>'id'),x->>'evidence_key',x->>'command_id','allocation',x->>'id',x->>'posting_date',-(x->>'target_base_amount')::numeric-(x->>'adjustment_base_amount')::numeric from jsonb_array_elements(allocations)x
  union all select 'reversal-source:'||(x#>>'{reversal,id}'),x->>'source_control',x#>>'{reversal,command_id}','allocation_reversal',x#>>'{reversal,id}',x#>>'{reversal,posting_date}',-(x->>'source_base_amount')::numeric from jsonb_array_elements(allocations)x where x->'reversal'<>'null'::jsonb
  union all select 'reversal-target:'||(x#>>'{reversal,id}'),x->>'evidence_key',x#>>'{reversal,command_id}','allocation_reversal',x#>>'{reversal,id}',x#>>'{reversal,posting_date}',(x->>'target_base_amount')::numeric+(x->>'adjustment_base_amount')::numeric from jsonb_array_elements(allocations)x where x->'reversal'<>'null'::jsonb)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'evidence_key',evidence_key,'command_id',command_id,'source_type',source_type,'source_id',source_id,'posting_date',posting_date,'value',value::text) order by id),'[]') into entries from movements;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into journals from (
  select l.id,l.account_id::text evidence_key,a.code account_code,j.command_id,j.id journal_id,j.document_number,j.source_type,j.source_id,l.source_line_id,l.posting_date,
   (sgn*(l.base_debit-l.base_credit))::text value,l.base_debit::text,l.base_credit::text
  from finance.journal_lines l join finance.journal_entries j on j.id=l.journal_entry_id join finance.accounts a on a.id=l.account_id
  where l.tenant_id=t and l.legal_entity_id=e and l.branch_id=b and l.account_id=any(ids) and j.status='posted' and l.posting_date<=d order by l.id limit 10001)q;
 if jsonb_array_length(journals)>10000 then raise exception using errcode='54000',message='CONTROL_REPORT_INPUT_LIMIT';end if;
 select jsonb_agg(jsonb_build_object('id',a.id,'evidence_key',a.id,'code',a.code,'name',a.name,'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a.id)
 into accounts from finance.accounts a
 cross join lateral(select coalesce(sum((x->>'open_base_amount')::numeric),0) v from jsonb_array_elements(items)x where x->>'evidence_key'=a.id::text)s
 cross join lateral(select coalesce(sum((x->>'value')::numeric),0) g from jsonb_array_elements(journals)x where x->>'evidence_key'=a.id::text)j where a.id=any(ids);
 with effects as (
  select x->>'evidence_key' a,x->>'command_id' c,(x->>'value')::numeric v,0::numeric g from jsonb_array_elements(entries)x
  union all select x->>'evidence_key',x->>'command_id',0,(x->>'value')::numeric from jsonb_array_elements(journals)x), totals as(select a,c,sum(v)v,sum(g)g from effects group by a,c)
 select coalesce(jsonb_agg(jsonb_build_object('id',a||':'||c,'evidence_key',a,'command_id',c,'subledger_value',v::text,'gl_value',g::text,'difference',(v-g)::text) order by a,c),'[]') into differences from totals where v<>g;
 if greatest(jsonb_array_length(entries),jsonb_array_length(differences))>50000 then raise exception using errcode='54000',message='CONTROL_REPORT_OUTPUT_LIMIT';end if;
 select coalesce(sum((x->>'subledger_value')::numeric),0),coalesce(sum((x->>'gl_value')::numeric),0) into sv,gv from jsonb_array_elements(accounts)x;
 if sv<>(select coalesce(sum((x->>'value')::numeric),0) from jsonb_array_elements(entries)x) then raise exception using errcode='23514',message='CONTROL_RESIDUAL_DIVERGENCE';end if;
 result:=jsonb_build_object('summary',jsonb_build_object('id',p->>'id','version',1,'status','generated','kind',k,'as_of',d,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
 'entity_name',(select name from core.legal_entities where id=e),'branch_name',(select name from core.branches where id=b),
 'currency_code',(select currency_code from core.legal_entities where id=e),'generated_at',statement_timestamp(),
 'accounts',accounts,'subledger_value',sv::text,'gl_value',gv::text,'difference',(sv-gv)::text,'item_count',jsonb_array_length(items),'difference_count',jsonb_array_length(differences)),
 'items',items,'allocations',allocations,'entries',entries,'journals',journals,'accounts',accounts,'differences',differences);
 if octet_length(result::text)>16777216 then raise exception using errcode='54000',message='CONTROL_REPORT_EVIDENCE_LIMIT';end if;
 return result;
end $$;
revoke all on function finance.build_control_report(uuid,uuid,uuid,jsonb) from public,anon,authenticated;


create function api.generate_control_reconciliation_report(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$declare h text;r jsonb;data jsonb;summary jsonb;id uuid:=(p_payload->>'id')::uuid;req uuid:=gen_random_uuid();begin
 perform finance.require_control_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if id is null or p_client_timestamp is null then raise exception using errcode='22023',message='CONTROL_REPORT_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.controls.report',p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(p_tenant_id,'finance.controls.report',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
 data:=finance.build_control_report(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload);summary:=data->'summary';
 insert into finance.control_reports values(id,p_tenant_id,p_legal_entity_id,p_branch_id,(summary->>'as_of')::date,(summary->>'generated_at')::timestamptz,summary,data,auth.uid());
 return core.wave3_finish_command(p_tenant_id,'finance.controls.report',p_command_id,'control_reconciliation_report',id,p_idempotency_key,h,null,summary,
  p_legal_entity_id,p_branch_id,'{}',jsonb_build_object('to_status','generated'),jsonb_build_array(jsonb_build_object('topic','finance.controls.report','payload',summary)),'[]',req,req);
end $$;
create function api.control_reconciliation_reports(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_resource text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;cursor uuid;begin
 perform finance.require_control_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_resource='reports' then
  select coalesce(jsonb_agg(summary order by id),'[]') into rows from(select id,summary from finance.control_reports
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and(p_after is null or id>p_after) order by id limit 51)q;
 else raise exception using errcode='22023',message='CONTROL_REPORT_RESOURCE_INVALID';end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('items',rows,'next_cursor',cursor);
end $$;
create function api.control_reconciliation_report_page(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_section text,p_after integer default 0,p_evidence_key text default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare r finance.control_reports%rowtype;rows jsonb;n integer;begin
 perform finance.require_control_scope(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_section is null or p_section not in('items','allocations','entries','journals','accounts','differences') or p_after is null or p_after<0 or p_after>50000 then raise exception using errcode='22023',message='CONTROL_REPORT_PAGE_INVALID';end if;
 select * into r from finance.control_reports where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='CONTROL_REPORT_REPORT_SCOPE_REQUIRED';end if;
 select coalesce(jsonb_agg(value order by ord),'[]') into rows from(select value,ord from jsonb_array_elements(r.evidence->p_section) with ordinality x(value,ord)
  where p_evidence_key is null or value->>'evidence_key'=p_evidence_key
   or (p_section='allocations' and value->>'source_control'=p_evidence_key) order by ord offset p_after limit 51)q;
 n:=jsonb_array_length(rows);if n>50 then rows:=rows-50;end if;
 return jsonb_build_object('summary',r.summary,'section',p_section,'evidence_key',p_evidence_key,'items',rows,'next_cursor',case when n>50 then (p_after+50)::text end);
end $$;
revoke all on function api.generate_control_reconciliation_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.control_reconciliation_reports(uuid,uuid,uuid,text,uuid),api.control_reconciliation_report_page(uuid,uuid,uuid,uuid,text,integer,text) from public,anon,authenticated;
grant execute on function api.generate_control_reconciliation_report(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.control_reconciliation_reports(uuid,uuid,uuid,text,uuid),api.control_reconciliation_report_page(uuid,uuid,uuid,uuid,text,integer,text) to authenticated;
notify pgrst,'reload schema';
