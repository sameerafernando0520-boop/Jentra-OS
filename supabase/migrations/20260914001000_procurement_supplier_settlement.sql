-- AC-312 candidate. Recorded settlement only; no external payment integration.
create function finance.payable_read_allowed(p_tenant uuid,p_entity uuid,p_branch uuid) returns boolean language sql stable security definer set search_path='' as $$
 select core.is_tenant_member(p_tenant) and (procurement.bill_read_allowed(p_tenant,p_entity,p_branch)
 or core.has_permission(p_tenant,'finance.payments.manage',p_entity,p_branch) or core.has_permission(p_tenant,'finance.payments.post',p_entity,p_branch))$$;
revoke all on function finance.payable_read_allowed(uuid,uuid,uuid) from public,anon;
grant execute on function finance.payable_read_allowed(uuid,uuid,uuid) to authenticated;
alter policy permitted_read on finance.open_items using(core.is_tenant_member(tenant_id) and
 ((kind='AR' and core.has_permission(tenant_id,'finance.receivables.view',legal_entity_id,branch_id))
 or (kind='AP' and finance.payable_read_allowed(tenant_id,legal_entity_id,branch_id))));
alter policy permitted_read on finance.open_item_allocations using(core.is_tenant_member(tenant_id) and exists(select 1 from finance.open_items o
 where o.id=source_open_item_id and o.tenant_id=open_item_allocations.tenant_id and
 ((o.kind='AR' and core.has_permission(o.tenant_id,'finance.receivables.view',o.legal_entity_id,o.branch_id))
 or (o.kind='AP' and finance.payable_read_allowed(o.tenant_id,o.legal_entity_id,o.branch_id)))));
create table procurement.payment_proposals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,supplier_id uuid not null,cash_bank_account_id uuid not null,
 document_date date not null,document_number text,currency_code text not null,base_currency_code text not null,exchange_rate_id uuid,exchange_rate numeric(20,10) not null,
 total numeric(20,6) not null check(total>0),base_total numeric(20,6) not null check(base_total>0),lines jsonb not null,
 status text not null default 'draft' check(status in('draft','pending_approval','approved','rejected','cancelled','posted')),
 version bigint not null default 1,workflow_snapshot jsonb,submitted_by uuid references auth.users(id),submitted_at timestamptz,
 created_by uuid not null references auth.users(id),prepared_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,legal_entity_id,branch_id,document_number),
 foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id),foreign key(tenant_id,cash_bank_account_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id) references finance.exchange_rates(tenant_id,legal_entity_id,id)
);
create table procurement.payment_proposal_history(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 proposal_id uuid not null,version bigint not null,snapshot jsonb not null,actor_id uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(proposal_id,version),foreign key(tenant_id,proposal_id) references procurement.payment_proposals(tenant_id,id)
);
create table procurement.payment_claims(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 proposal_id uuid not null,open_item_id uuid not null,amount numeric(20,6) not null check(amount>0),active boolean not null default true,
 created_at timestamptz not null default now(),released_at timestamptz,
 foreign key(tenant_id,proposal_id) references procurement.payment_proposals(tenant_id,id),foreign key(tenant_id,open_item_id) references finance.open_items(tenant_id,id)
);
create unique index payment_claim_exclusive on procurement.payment_claims(tenant_id,open_item_id) where active;
create index payment_claim_proposal on procurement.payment_claims(tenant_id,proposal_id,active,open_item_id);
create table procurement.supplier_payments(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,proposal_id uuid not null unique,supplier_id uuid not null,
 cash_bank_account_id uuid not null,document_date date not null,document_number text not null,reference text not null,
 currency_code text not null,base_currency_code text not null,exchange_rate numeric(20,10) not null,amount numeric(20,6) not null,base_amount numeric(20,6) not null,
 journal_entry_id uuid not null,open_item_id uuid not null,allocations jsonb not null,source_snapshot jsonb not null,
 request_id uuid not null,command_id uuid not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),foreign key(tenant_id,proposal_id) references procurement.payment_proposals(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),foreign key(tenant_id,open_item_id) references finance.open_items(tenant_id,id),
 foreign key(tenant_id,cash_bank_account_id) references finance.cash_bank_accounts(tenant_id,id),foreign key(tenant_id,supplier_id) references crm.parties(tenant_id,id)
);
create index payment_proposals_scope on procurement.payment_proposals(tenant_id,legal_entity_id,branch_id,status,document_date,id);
create index supplier_payments_scope on procurement.supplier_payments(tenant_id,legal_entity_id,branch_id,document_date,id);
do $$declare t text;begin
 foreach t in array array['payment_proposals','payment_proposal_history','payment_claims','supplier_payments'] loop
 execute format('alter table procurement.%I enable row level security',t);execute format('alter table procurement.%I force row level security',t);
 execute format('create policy payment_read on procurement.%I for select to authenticated using(finance.payable_read_allowed(tenant_id,legal_entity_id,branch_id))',t);
 execute format('revoke all on procurement.%I from public,anon,authenticated',t);execute format('grant select on procurement.%I to authenticated',t);
 if t in('payment_proposal_history','supplier_payments') then execute format('create trigger immutable before update or delete on procurement.%I for each row execute function workflow.reject_history_mutation()',t);end if;
 end loop;
end $$;
create trigger proposal_posted_immutable before update or delete on procurement.payment_proposals for each row execute function sales.flow_protect_document();
create view api.payment_proposals with(security_invoker=true) as select p.tenant_id,p.legal_entity_id,p.branch_id,p.id,p.status,sales.flow_exact_json(to_jsonb(p)) detail from procurement.payment_proposals p;
create view api.supplier_payments with(security_invoker=true) as select p.tenant_id,p.legal_entity_id,p.branch_id,p.id,
 sales.flow_exact_json(to_jsonb(p))||jsonb_build_object('status','posted','reconciliation_status','pending') detail from procurement.supplier_payments p;
grant select on api.payment_proposals,api.supplier_payments to authenticated;
create function finance.payable_residual(p_tenant uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_o finance.open_items%rowtype;begin select * into v_o from finance.open_items where tenant_id=p_tenant and id=p_id and kind='AP';
 if not found or not finance.payable_read_allowed(p_tenant,v_o.legal_entity_id,v_o.branch_id) then return null;end if;
 return finance.flow_residual(p_tenant,p_id);end $$;
revoke all on function finance.payable_residual(uuid,uuid) from public,anon;
grant execute on function finance.payable_residual(uuid,uuid) to authenticated;
create view api.payable_balances with(security_invoker=true) as select o.id,o.tenant_id,o.legal_entity_id,o.branch_id,o.party_id,o.currency_code,o.posting_date,o.due_date,
 sales.flow_exact_json(to_jsonb(o))||finance.payable_residual(o.tenant_id,o.id) detail from finance.open_items o where kind='AP';
grant select on api.payable_balances to authenticated;

create function procurement.normalize_payment_proposal(p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_lock boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_bank finance.cash_bank_accounts%rowtype;v_o finance.open_items%rowtype;v_line jsonb;v_lines jsonb:='[]';v_id uuid;v_seen uuid[]:='{}';
 v_amount numeric;v_total numeric:=0;v_residual jsonb;v_rate jsonb;v_scale integer;v_date date:=(p_payload->>'document_date')::date;
begin
 if jsonb_typeof(p_payload->'lines') is distinct from 'array' or jsonb_array_length(p_payload->'lines') not between 1 and 500 or v_date is null then raise exception using errcode='22023',message='PROPOSAL_INPUT_INVALID';end if;
 select * into v_bank from finance.cash_bank_accounts where id=(p_payload->>'cash_bank_account_id')::uuid and tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and status='active';
 if not found then raise exception using errcode='22023',message='PAYMENT_BANK_INVALID';end if;
 perform finance.flow_account(p_tenant,p_entity,v_bank.account_id,'asset',v_bank.currency_code);
 if not exists(select 1 from crm.parties where id=(p_payload->>'supplier_id')::uuid and tenant_id=p_tenant and status='active' and kind in('supplier','both')) then raise exception using errcode='22023',message='SUPPLIER_INVALID';end if;
 v_rate:=finance.flow_rate(p_tenant,p_entity,v_bank.currency_code,v_date,(p_payload->>'exchange_rate_id')::uuid);
 select rounding_scale into v_scale from core.legal_entities where tenant_id=p_tenant and id=p_entity;
 for v_line in select value from jsonb_array_elements(p_payload->'lines') order by value->>'open_item_id' loop
  v_id:=(v_line->>'open_item_id')::uuid;
  if v_id is null or v_id=any(v_seen) then raise exception using errcode='22023',message='PROPOSAL_ITEM_DUPLICATE';end if;
  v_seen:=array_append(v_seen,v_id);
  if p_lock then perform 1 from finance.open_items where id=v_id and tenant_id=p_tenant for update;end if;
  select * into v_o from finance.open_items where id=v_id and tenant_id=p_tenant and legal_entity_id=p_entity and branch_id=p_branch and kind='AP'
   and party_id=(p_payload->>'supplier_id')::uuid and currency_code=v_bank.currency_code and posting_date<=v_date and (original_amount<0 or due_date<=v_date);
  if not found then raise exception using errcode='22023',message='PAYABLE_ITEM_INELIGIBLE';end if;
  if exists(select 1 from procurement.payment_claims where tenant_id=p_tenant and open_item_id=v_id and active and proposal_id<>(p_payload->>'id')::uuid) then raise exception using errcode='55000',message='PAYABLE_ITEM_ALREADY_SELECTED';end if;
  if exists(select 1 from finance.open_item_allocations where tenant_id=p_tenant and (source_open_item_id=v_id or target_open_item_id=v_id) and posting_date>v_date) then raise exception using errcode='22023',message='ALLOCATION_DATE_BEFORE_LATEST';end if;
  v_amount:=sales.wave3_decimal_string(v_line->'amount','amount',6,true,0,null);v_residual:=finance.flow_residual(p_tenant,v_id);
  if v_amount<=0 or round(v_amount,v_scale)<>v_amount or v_amount>abs((v_residual->>'amount')::numeric) then raise exception using errcode='22023',message='PROPOSAL_AMOUNT_EXCEEDED';end if;
  v_total:=v_total+case when v_o.original_amount>0 then v_amount else -v_amount end;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('open_item_id',v_id,'document_number',v_o.document_number,'kind',case when v_o.original_amount>0 then 'bill' else 'credit' end,
   'amount',v_amount::text,'residual',v_residual,'due_date',v_o.due_date,'currency_code',v_o.currency_code));
 end loop;
 if v_total<=0 then raise exception using errcode='22023',message='POSITIVE_PAYMENT_REQUIRED';end if;
 return jsonb_build_object('lines',v_lines,'currency_code',v_bank.currency_code,'rate',v_rate,'total',v_total::text,'base_total',round(v_total*(v_rate->>'exchange_rate')::numeric,v_scale)::text);
end $$;
revoke all on function procurement.normalize_payment_proposal(uuid,uuid,uuid,jsonb,boolean) from public,anon,authenticated;
create function procurement.record_payment_proposal_history(p_result jsonb) returns void language sql security definer set search_path='' as $$
 insert into procurement.payment_proposal_history(tenant_id,legal_entity_id,branch_id,proposal_id,version,snapshot,actor_id)
 select (e->>'tenant_id')::uuid,(e->>'legal_entity_id')::uuid,(e->>'branch_id')::uuid,(e->>'id')::uuid,(e->>'version')::bigint,e,auth.uid()
 from(select p_result->'entity' e)x on conflict(proposal_id,version) do nothing$$;
revoke all on function procurement.record_payment_proposal_history(jsonb) from public,anon,authenticated;
create function api.upsert_payment_proposal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'id')::uuid;v_command text:='procurement.payment_proposal.upsert';v_hash text;v_result jsonb;v_before jsonb;v_n jsonb;v_line jsonb;v_old procurement.payment_proposals%rowtype;
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.manage',p_legal_entity_id,p_branch_id);
 if v_id is null or p_legal_entity_id is null or p_branch_id is null or p_client_timestamp is null then raise exception using errcode='22023',message='INVALID_COMMAND';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 perform pg_advisory_xact_lock(hashtextextended('payment.proposal:'||v_id::text,0));
 select * into v_old from procurement.payment_proposals where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if found then
  if v_old.status<>'draft' then raise exception using errcode='55000',message='PROPOSAL_NOT_EDITABLE';end if;
  select detail into v_before from api.payment_proposals where id=v_id;perform core.wave3_assert_expected_version(v_old.version,p_expected_entity_version,v_before);
 elsif p_expected_entity_version is not null then raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
 v_n:=procurement.normalize_payment_proposal(p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,true);
 insert into procurement.payment_proposals(id,tenant_id,legal_entity_id,branch_id,supplier_id,cash_bank_account_id,document_date,currency_code,base_currency_code,exchange_rate_id,exchange_rate,total,base_total,lines,created_by,prepared_by,updated_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,(p_payload->>'supplier_id')::uuid,(p_payload->>'cash_bank_account_id')::uuid,(p_payload->>'document_date')::date,
 v_n->>'currency_code',v_n#>>'{rate,base_currency_code}',(p_payload->>'exchange_rate_id')::uuid,(v_n#>>'{rate,exchange_rate}')::numeric,(v_n->>'total')::numeric,(v_n->>'base_total')::numeric,v_n->'lines',auth.uid(),auth.uid(),auth.uid())
 on conflict(id) do update set supplier_id=excluded.supplier_id,cash_bank_account_id=excluded.cash_bank_account_id,document_date=excluded.document_date,currency_code=excluded.currency_code,
 base_currency_code=excluded.base_currency_code,exchange_rate_id=excluded.exchange_rate_id,exchange_rate=excluded.exchange_rate,total=excluded.total,base_total=excluded.base_total,
 lines=excluded.lines,version=procurement.payment_proposals.version+1,prepared_by=auth.uid(),updated_by=auth.uid(),updated_at=clock_timestamp()
 where procurement.payment_proposals.tenant_id=p_tenant_id and procurement.payment_proposals.legal_entity_id=p_legal_entity_id and procurement.payment_proposals.branch_id=p_branch_id;
 if not found then raise exception using errcode='42501',message='PROPOSAL_SCOPE_INVALID';end if;
 update procurement.payment_claims set active=false,released_at=clock_timestamp() where proposal_id=v_id and active;
 for v_line in select value from jsonb_array_elements(v_n->'lines') loop
  insert into procurement.payment_claims(tenant_id,legal_entity_id,branch_id,proposal_id,open_item_id,amount)
  values(p_tenant_id,p_legal_entity_id,p_branch_id,v_id,(v_line->>'open_item_id')::uuid,(v_line->>'amount')::numeric);
 end loop;
 select detail into v_result from api.payment_proposals where id=v_id;
 v_result:=core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'payment_proposal',v_id,p_idempotency_key,v_hash,v_before,v_result,p_legal_entity_id,p_branch_id);
 perform procurement.record_payment_proposal_history(v_result);return v_result;
end $$;
revoke all on function api.upsert_payment_proposal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.upsert_payment_proposal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function finance.allocate_payable(p_source uuid,p_target uuid,p_tenant uuid,p_entity uuid,p_branch uuid,p_payload jsonb,p_date date,p_request uuid,p_command uuid,p_proposal uuid default null)
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
 v_prior:=(v_sr->>'amount')::numeric-v_s.original_amount;
 v_sb:=round((-v_s.original_base_amount)*(v_prior+v_source)/(-v_s.original_amount),v_scale)-round((-v_s.original_base_amount)*v_prior/(-v_s.original_amount),v_scale);
 v_prior:=v_t.original_amount-(v_tr->>'amount')::numeric;
 v_tb:=round(v_t.original_base_amount*(v_prior+v_target)/v_t.original_amount,v_scale)-round(v_t.original_base_amount*v_prior/v_t.original_amount,v_scale);
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

create function api.post_supplier_payment(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid:=(p_payload->>'document_id')::uuid;v_command text:='procurement.supplier_payment.post';v_hash text;v_result jsonb;v_before jsonb;v_n jsonb;
 v_p procurement.payment_proposals%rowtype;v_bank finance.cash_bank_accounts%rowtype;v_control uuid;v_request uuid:=gen_random_uuid();v_open uuid:=gen_random_uuid();
 v_journal uuid;v_number text;v_line jsonb;v_target jsonb;v_sources jsonb:='[]';v_targets jsonb:='[]';v_remaining numeric;v_take numeric;v_target_remaining numeric;
 v_allocations jsonb:='[]';v_i integer;v_source uuid;v_ref text:=trim(p_payload->>'reference');
begin
 perform core.wave3_require_scope(p_tenant_id,'finance.payments.post',p_legal_entity_id,p_branch_id);
 if v_id is null or p_client_timestamp is null or p_legal_entity_id is null or p_branch_id is null or coalesce(length(v_ref),0) not between 1 and 140 then raise exception using errcode='22023',message='PAYMENT_REFERENCE_REQUIRED';end if;
 v_hash:=core.wave3_request_hash(v_command,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
 v_result:=core.wave3_replay(p_tenant_id,v_command,p_command_id,p_idempotency_key,v_hash);if v_result is not null then return v_result;end if;
 select * into v_p from procurement.payment_proposals where id=v_id and tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id for update;
 if not found then raise exception using errcode='P0002',message='PROPOSAL_NOT_FOUND';end if;
 select detail into v_before from api.payment_proposals where id=v_id;perform core.wave3_assert_expected_version(v_p.version,p_expected_entity_version,v_before);
 if v_p.status<>'approved' then raise exception using errcode='55000',message='PAYMENT_APPROVAL_REQUIRED';end if;
 perform sales.flow_assert_transition(v_p.workflow_snapshot->'lifecycle','approved','posted');
 v_n:=procurement.normalize_payment_proposal(p_tenant_id,p_legal_entity_id,p_branch_id,v_before,true);
 if (v_n->>'total')::numeric<>v_p.total or (v_n->>'base_total')::numeric<>v_p.base_total then raise exception using errcode='40001',message='PAYMENT_REAPPROVAL_REQUIRED';end if;
 for v_line in select value from jsonb_array_elements(v_p.lines) loop
  if not exists(select 1 from procurement.payment_claims where tenant_id=p_tenant_id and proposal_id=v_id and open_item_id=(v_line->>'open_item_id')::uuid
   and active and amount=(v_line->>'amount')::numeric) then raise exception using errcode='55000',message='PAYMENT_CLAIM_REQUIRED';end if;
 end loop;
 perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,v_p.document_date);
 select * into v_bank from finance.cash_bank_accounts where id=v_p.cash_bank_account_id and tenant_id=p_tenant_id for share;
 select payable_account_id into v_control from procurement.supplier_bill_controls where legal_entity_id=p_legal_entity_id and tenant_id=p_tenant_id for share;
 v_control:=finance.flow_account(p_tenant_id,p_legal_entity_id,v_control,'liability',v_p.currency_code);
 v_journal:=finance.flow_post_journal(to_jsonb(v_p)||jsonb_build_object('customer_id',v_p.supplier_id),
  jsonb_build_array(finance.flow_jline(v_control,v_p.total,v_p.base_total),finance.flow_jline(v_bank.account_id,-v_p.total,-v_p.base_total)),
  'supplier_payment',v_id,v_request,p_command_id);
 v_number:=sales.wave3_reserve_document_number(p_tenant_id,p_legal_entity_id,p_branch_id,'supplier_payment',v_p.document_date,auth.uid());
 insert into finance.open_items(id,tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,document_number,currency_code,base_currency_code,exchange_rate,
  original_amount,original_base_amount,posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
 values(v_open,p_tenant_id,p_legal_entity_id,p_branch_id,'AP',v_p.supplier_id,'supplier_payment',v_id,v_number,v_p.currency_code,v_p.base_currency_code,v_p.exchange_rate,
  -v_p.total,-v_p.base_total,v_p.document_date,v_p.document_date,v_journal,v_request,p_command_id,v_request,auth.uid());
 for v_line in select value from jsonb_array_elements(v_p.lines) loop
  if v_line->>'kind'='credit' then v_sources:=v_sources||jsonb_build_array(v_line);else v_targets:=v_targets||jsonb_build_array(v_line);end if;
 end loop;
 v_sources:=v_sources||jsonb_build_array(jsonb_build_object('open_item_id',v_open,'amount',v_p.total::text));
 for v_line in select value from jsonb_array_elements(v_sources) loop
  v_source:=(v_line->>'open_item_id')::uuid;v_remaining:=(v_line->>'amount')::numeric;
  for v_i in 0..jsonb_array_length(v_targets)-1 loop
   exit when v_remaining=0;v_target:=v_targets->v_i;v_target_remaining:=(v_target->>'amount')::numeric;v_take:=least(v_remaining,v_target_remaining);
   if v_take=0 then continue;end if;
   v_allocations:=v_allocations||jsonb_build_array(finance.allocate_payable(v_source,(v_target->>'open_item_id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,
    jsonb_build_object('source_amount',v_take::text,'transaction_amount',v_take::text,'reason','Approved supplier payment'),v_p.document_date,v_request,p_command_id,v_id));
   v_remaining:=v_remaining-v_take;v_targets:=jsonb_set(v_targets,array[v_i::text,'amount'],to_jsonb((v_target_remaining-v_take)::text));
  end loop;
  if v_remaining<>0 then raise exception using errcode='23514',message='PAYMENT_ALLOCATION_UNBALANCED';end if;
 end loop;
 insert into procurement.supplier_payments(id,tenant_id,legal_entity_id,branch_id,proposal_id,supplier_id,cash_bank_account_id,document_date,document_number,reference,
  currency_code,base_currency_code,exchange_rate,amount,base_amount,journal_entry_id,open_item_id,allocations,source_snapshot,request_id,command_id,created_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_id,v_p.supplier_id,v_p.cash_bank_account_id,v_p.document_date,v_number,v_ref,v_p.currency_code,v_p.base_currency_code,
  v_p.exchange_rate,v_p.total,v_p.base_total,v_journal,v_open,v_allocations,v_before,v_request,p_command_id,auth.uid());
 update procurement.payment_claims set active=false,released_at=clock_timestamp() where proposal_id=v_id and active;
 update procurement.payment_proposals set status='posted',version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=v_id;
 perform procurement.record_payment_proposal_history(jsonb_build_object('entity',(select detail from api.payment_proposals where id=v_id)));
 select detail into v_result from api.supplier_payments where id=v_id;
 return core.wave3_finish_command(p_tenant_id,v_command,p_command_id,'supplier_payment',v_id,p_idempotency_key,v_hash,v_before,v_result,p_legal_entity_id,p_branch_id,'{}',
  jsonb_build_object('from_status','approved','to_status','posted'),jsonb_build_array(jsonb_build_object('topic','procurement.supplier_payment.recorded','payload',jsonb_build_object('payment_id',v_id))),'[]',v_request,v_request);
end $$;
revoke all on function api.post_supplier_payment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon;
grant execute on function api.post_supplier_payment(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;
