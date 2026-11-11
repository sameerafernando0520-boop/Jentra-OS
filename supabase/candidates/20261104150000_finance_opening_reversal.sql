-- Additive follow-on to 20261104090000_finance_opening_import.sql.
-- Original posted sources and their permanent duplicate identities are retained.
insert into core.permissions(code,module,description,privileged) values
  ('finance.openings.reverse','finance','Post independently approved opening reversals.',true);

create table finance.opening_reversals (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  batch_id uuid not null,
  status text not null check(status in ('pending_approval','approved','posted','rejected','cancelled')),
  version bigint not null check(version>0),
  posting_date date not null,
  reason text not null check(length(btrim(reason)) between 3 and 1000),
  snapshot jsonb not null,
  content_hash text not null check(content_hash ~ '^[0-9a-f]{64}$'),
  approved_content_hash text,
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  posted_by uuid references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  approved_at timestamptz,
  posted_at timestamptz,
  decision_reason text,
  unique(tenant_id,legal_entity_id,branch_id,id),
  foreign key(tenant_id,legal_entity_id,branch_id,batch_id)
    references finance.opening_batches(tenant_id,legal_entity_id,branch_id,id),
  check(status not in ('approved','posted') or
    (approved_by is not null and approved_at is not null and approved_content_hash=content_hash)),
  check((status='posted')=(posted_at is not null and posted_by is not null))
);
create unique index opening_reversal_active_batch on finance.opening_reversals(batch_id)
  where status in ('pending_approval','approved','posted');
create index opening_reversal_batch_history on finance.opening_reversals(batch_id,id);

create table finance.opening_reversal_lines (
  id uuid primary key,
  tenant_id uuid not null,
  legal_entity_id uuid not null,
  branch_id uuid not null,
  reversal_id uuid not null,
  source_line_id uuid not null references finance.opening_lines(id),
  original_open_item_id uuid not null unique,
  reversal_open_item_id uuid not null unique,
  journal_entry_id uuid not null,
  allocation_id uuid not null unique,
  unique(reversal_id,source_line_id),
  foreign key(tenant_id,legal_entity_id,branch_id,reversal_id)
    references finance.opening_reversals(tenant_id,legal_entity_id,branch_id,id),
  foreign key(tenant_id,original_open_item_id) references finance.open_items(tenant_id,id),
  foreign key(tenant_id,reversal_open_item_id) references finance.open_items(tenant_id,id),
  foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
  foreign key(tenant_id,allocation_id) references finance.open_item_allocations(tenant_id,id)
);
alter table finance.opening_reversals enable row level security;
alter table finance.opening_reversals force row level security;
alter table finance.opening_reversal_lines enable row level security;
alter table finance.opening_reversal_lines force row level security;
revoke all on finance.opening_reversals,finance.opening_reversal_lines from public,anon,authenticated,service_role;

create function finance.opening_reversal_protect() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='opening_reversal_lines' then
    raise exception using errcode='55000',message='OPENING_REVERSAL_IMMUTABLE';
  elsif old.status='posted' then
    raise exception using errcode='55000',message='OPENING_REVERSAL_IMMUTABLE';
  end if;
  if tg_op='DELETE' then return old;end if;
  return new;
end $$;
create trigger immutable before update or delete on finance.opening_reversals
  for each row execute function finance.opening_reversal_protect();
create trigger immutable before update or delete on finance.opening_reversal_lines
  for each row execute function finance.opening_reversal_protect();

-- Existing generic allocation reversal APIs must never reopen this system pair.
create function finance.opening_reversal_guard_allocation() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if exists(select 1 from finance.opening_reversal_lines where allocation_id=new.allocation_id) then
    raise exception using errcode='55000',message='OPENING_REVERSAL_ALLOCATION_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger opening_reversal_allocation_guard before insert on finance.allocation_reversals
  for each row execute function finance.opening_reversal_guard_allocation();

-- Serialize FX snapshots with reversal posting and reject a later backdated run.
-- This runs inside the ordinary FX command transaction, so prior journals roll back.
create function finance.opening_reversal_guard_fx() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  perform 1 from finance.open_items item
  where item.tenant_id=new.tenant_id and item.id in
    (select (value->>'id')::uuid from jsonb_array_elements(new.snapshot))
    and item.source_type in ('opening_receivable','opening_payable',
      'opening_receivable_reversal','opening_payable_reversal')
  order by item.id for update nowait;
  if exists(select 1 from finance.opening_reversal_lines line
    where line.tenant_id=new.tenant_id and
      (line.original_open_item_id in (select (value->>'id')::uuid from jsonb_array_elements(new.snapshot))
       or line.reversal_open_item_id in (select (value->>'id')::uuid from jsonb_array_elements(new.snapshot)))) then
    raise exception using errcode='55000',message='OPENING_REVERSED_SOURCE_FX';
  end if;
  return new;
exception when lock_not_available then
  raise exception using errcode='55P03',message='OPENING_REVERSAL_BUSY';
end $$;
create trigger opening_reversal_fx_guard before insert on finance.fx_revaluation_runs
  for each row execute function finance.opening_reversal_guard_fx();

create function finance.opening_reversal_lock_sources(batch finance.opening_batches,d date)
returns void language plpgsql security definer set search_path='' as $$
begin
  perform 1 from crm.parties party where party.tenant_id=batch.tenant_id and party.id in
    (select line.party_id from finance.opening_lines line where line.batch_id=batch.id)
  order by party.id for update nowait;
  perform 1 from finance.fiscal_periods period where period.tenant_id=batch.tenant_id
    and period.legal_entity_id=batch.legal_entity_id and period.status='active'
    and d between period.start_date and period.end_date for update nowait;
  perform finance.wave3_lock_open_period(batch.tenant_id,batch.legal_entity_id,d);
  perform 1 from finance.open_items item where item.tenant_id=batch.tenant_id and item.id in
    (select line.open_item_id from finance.opening_lines line where line.batch_id=batch.id)
  order by item.id for update nowait;
  perform 1 from core.legal_entities entity where entity.tenant_id=batch.tenant_id and entity.id=batch.legal_entity_id for share nowait;
  perform 1 from finance.accounts account where account.tenant_id=batch.tenant_id and account.legal_entity_id=batch.legal_entity_id
    and account.id in ((batch.snapshot->>'control_account_id')::uuid,(batch.snapshot->>'clearing_account_id')::uuid)
  order by account.id for share nowait;
exception when lock_not_available then
  raise exception using errcode='55P03',message='OPENING_REVERSAL_BUSY';
end $$;

create function finance.opening_reversal_snapshot(batch finance.opening_batches,d date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  source_ids uuid[];
  sources jsonb;
  period finance.fiscal_periods%rowtype;
  control finance.accounts%rowtype;
  clearing finance.accounts%rowtype;
  entity core.legal_entities%rowtype;
begin
  if batch.status<>'posted' or d is null or d<(batch.snapshot->>'cutoff_date')::date
      or d>(clock_timestamp() at time zone 'UTC')::date then
    raise exception using errcode='22023',message='OPENING_REVERSAL_INPUT_INVALID';
  end if;
  select array_agg(line.open_item_id order by line.open_item_id) into source_ids
    from finance.opening_lines line where line.batch_id=batch.id;
  if exists(select 1 from finance.open_item_allocations allocation where allocation.tenant_id=batch.tenant_id
      and (allocation.source_open_item_id=any(source_ids) or allocation.target_open_item_id=any(source_ids))) then
    raise exception using errcode='55000',message='OPENING_REVERSAL_SETTLEMENT_HISTORY';
  end if;
  if exists(select 1 from finance.fx_revaluation_runs run cross join lateral jsonb_array_elements(run.snapshot) item
      where run.tenant_id=batch.tenant_id and run.legal_entity_id=batch.legal_entity_id
        and run.branch_id=batch.branch_id and run.currency_code=batch.snapshot->>'currency_code'
        and (item->>'id')::uuid=any(source_ids)) then
    raise exception using errcode='55000',message='OPENING_REVERSAL_FX_HISTORY';
  end if;
  if exists(select 1 from procurement.payment_claims claim where claim.tenant_id=batch.tenant_id
      and claim.open_item_id=any(source_ids) and claim.active) then
    raise exception using errcode='55000',message='PAYABLE_ITEM_ALREADY_SELECTED';
  end if;
  select * into entity from core.legal_entities where tenant_id=batch.tenant_id and id=batch.legal_entity_id;
  select * into period from finance.fiscal_periods where tenant_id=batch.tenant_id and legal_entity_id=batch.legal_entity_id
    and status='active' and state='open' and d between start_date and end_date;
  if period.id is null then raise exception using errcode='55000',message='PERIOD_CLOSED';end if;
  -- Later-period FX would require a historical revaluation of an item that
  -- the correction has since closed. Keep foreign reversals in the source period.
  if batch.snapshot->>'currency_code'<>batch.snapshot->>'base_currency_code'
      and period.id is distinct from (batch.snapshot->>'period_id')::uuid then
    raise exception using errcode='55000',message='OPENING_REVERSAL_FX_PERIOD';
  end if;
  select * into control from finance.accounts where tenant_id=batch.tenant_id and legal_entity_id=batch.legal_entity_id
    and id=(batch.snapshot->>'control_account_id')::uuid and is_posting and status='active'
    and account_type=case batch.snapshot->>'kind' when 'AR' then 'asset' else 'liability' end
    and (currency_code is null or currency_code=batch.snapshot->>'currency_code');
  select * into clearing from finance.accounts where tenant_id=batch.tenant_id and legal_entity_id=batch.legal_entity_id
    and id=(batch.snapshot->>'clearing_account_id')::uuid and is_posting and status='active' and account_type='equity'
    and (currency_code is null or currency_code=batch.snapshot->>'currency_code');
  if control.id is null or clearing.id is null or entity.currency_code is distinct from batch.snapshot->>'base_currency_code' then
    raise exception using errcode='55000',message='OPENING_REVERSAL_ACCOUNT_INVALID';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'source_line_id',line.id,'row_number',line.row_number,'party_id',line.party_id,'party_code',party.code,'party_version',party.version,
      'original_open_item_id',item.id,'original_journal_entry_id',item.journal_entry_id,
      'source_type',item.source_type,'document_number',item.document_number,
      'document_date',line.data->'document_date','due_date',item.due_date,
      'currency_code',item.currency_code,'base_currency_code',item.base_currency_code,'exchange_rate',item.exchange_rate::text,
      'original_amount',item.original_amount::text,'original_base_amount',item.original_base_amount::text)
      order by line.row_number),'[]') into sources
  from finance.opening_lines line join finance.open_items item on item.tenant_id=line.tenant_id and item.id=line.open_item_id
  join crm.parties party on party.tenant_id=line.tenant_id and party.id=line.party_id
  join finance.journal_entries journal on journal.tenant_id=item.tenant_id and journal.id=item.journal_entry_id and journal.status='posted'
  where line.batch_id=batch.id and item.legal_entity_id=batch.legal_entity_id and item.branch_id=batch.branch_id
    and item.party_id=line.party_id and item.kind=line.kind and item.source_id=line.id
    and item.original_amount=(line.data->>'outstanding_amount')::numeric
    and item.original_base_amount=(line.data->>'carrying_base_amount')::numeric
    and item.original_amount=round(item.original_amount,entity.rounding_scale)
    and item.original_base_amount=round(item.original_base_amount,entity.rounding_scale)
    and finance.open_item_control(batch.tenant_id,item.id)=control.id;
  if jsonb_array_length(sources) is distinct from (batch.snapshot->>'row_count')::integer then
    raise exception using errcode='55000',message='OPENING_REVERSAL_SOURCE_INVALID';
  end if;
  return jsonb_build_object('batch_id',batch.id,'batch_version',batch.version,'batch_content_hash',batch.content_hash,
    'posting_date',d,'period_id',period.id,'period_version',period.version,
    'kind',batch.snapshot->'kind','currency_code',batch.snapshot->'currency_code','base_currency_code',entity.currency_code,
    'entity_version',entity.version,'entity_rounding_scale',entity.rounding_scale,
    'control_account_id',control.id,'control_account_version',control.version,
    'clearing_account_id',clearing.id,'clearing_account_version',clearing.version,
    'preparer_ids',to_jsonb(batch.preparer_ids),'row_count',jsonb_array_length(sources),'lines',sources);
end $$;

create function finance.opening_reversal_entity(reversal finance.opening_reversals,include_lines boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  result:=to_jsonb(reversal)-'snapshot'-'approved_content_hash';
  if include_lines then
    result:=result||jsonb_build_object('source',reversal.snapshot-'lines','lines',
      (select coalesce(jsonb_agg(source||jsonb_build_object('currency',source->'currency_code',
        'outstanding_amount',(-(source->>'original_amount')::numeric)::text,
        'carrying_base_amount',(-(source->>'original_base_amount')::numeric)::text)
        ||coalesce(to_jsonb(link)-'tenant_id'-'legal_entity_id'-'branch_id','{}')
        order by (source->>'row_number')::integer),'[]')
       from jsonb_array_elements(reversal.snapshot->'lines') source
       left join finance.opening_reversal_lines link on link.reversal_id=reversal.id
         and link.source_line_id=(source->>'source_line_id')::uuid));
  end if;
  return result;
end $$;

create or replace function finance.opening_batch_entity(batch finance.opening_batches,include_lines boolean) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;lines jsonb;reversal jsonb;
begin
  result:=(batch.snapshot-'lines')||(to_jsonb(batch)-'input'-'snapshot'-'approved_content_hash');
  select finance.opening_reversal_entity(row,false) into reversal from finance.opening_reversals row
    where row.batch_id=batch.id order by case when row.status in ('pending_approval','approved','posted') then 0 else 1 end,
      row.created_at desc,row.id desc limit 1;
  result:=result||jsonb_build_object('reversal_supported',true,'reversal',reversal,'current_reversal',reversal);
  if include_lines then
    select coalesce(jsonb_agg(line.data||jsonb_build_object('id',line.id,'open_item_id',line.open_item_id,
      'journal_entry_id',line.journal_entry_id) order by line.row_number),'[]') into lines
      from finance.opening_lines line where line.batch_id=batch.id;
    result:=result||jsonb_build_object('lines',lines);
    if batch.status='posted' then
      result:=result||jsonb_build_object('open_item_ids',(select jsonb_agg(value->'open_item_id' order by ordinality)
        from jsonb_array_elements(lines) with ordinality),'journal_entry_ids',
        (select jsonb_agg(value->'journal_entry_id' order by ordinality) from jsonb_array_elements(lines) with ordinality));
    end if;
  end if;
  return result;
end $$;

create function api.finance_opening_reversal(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare reversal finance.opening_reversals%rowtype;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  select * into reversal from finance.opening_reversals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and id=p_id;
  if not found then raise exception using errcode='P0002',message='OPENING_REVERSAL_NOT_FOUND';end if;
  return finance.opening_reversal_entity(reversal,true);
end $$;

create function api.finance_opening_reversals(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
  p_batch_id uuid,p_after uuid default null,p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;cursor uuid;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  if p_limit is null or p_limit not between 1 and 50 then
    raise exception using errcode='22023',message='OPENING_PAGE_INVALID';
  end if;
  if not exists(select 1 from finance.opening_batches where id=p_batch_id and tenant_id=p_tenant_id
      and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id) then
    raise exception using errcode='P0002',message='OPENING_BATCH_NOT_FOUND';
  end if;
  select coalesce(jsonb_agg(finance.opening_reversal_entity(q.row,false) order by q.id),'[]') into items
    from (select row.id,row from finance.opening_reversals row where row.tenant_id=p_tenant_id
      and row.legal_entity_id=p_legal_entity_id and row.branch_id=p_branch_id and row.batch_id=p_batch_id
      and (p_after is null or row.id>p_after) order by row.id limit p_limit+1) q;
  if jsonb_array_length(items)>p_limit then items:=items-p_limit;cursor:=(items->(p_limit-1)->>'id')::uuid;end if;
  return jsonb_build_object('batch_id',p_batch_id,'items',items,'next_cursor',cursor);
end $$;

create function api.prepare_finance_opening_reversal(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
  p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  command_name text:='finance.opening_reversal.prepare';
  batch finance.opening_batches%rowtype;
  reversal finance.opening_reversals%rowtype;
  reversal_id uuid:=(p_payload->>'id')::uuid;
  v_batch_id uuid:=(p_payload->>'document_id')::uuid;
  posting_date date:=finance.opening_date(p_payload->'posting_date');
  v_reason text:=btrim(p_payload->>'reason');
  snapshot jsonb;
  request_hash text;
  replay jsonb;
  request_id uuid:=gen_random_uuid();
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare',true);
  if reversal_id is null or v_batch_id is null or p_command_id is null or p_idempotency_key is null
      or p_client_timestamp is null or p_expected_entity_version is distinct from 0
      or coalesce(length(v_reason),0) not between 3 and 1000 then
    raise exception using errcode='22023',message='OPENING_REVERSAL_INPUT_INVALID';
  end if;
  batch:=finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,v_batch_id,p_idempotency_key);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare',true);
  request_hash:=core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  replay:=core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then return replay;end if;
  if batch.id is null then raise exception using errcode='P0002',message='OPENING_BATCH_NOT_FOUND';end if;
  if exists(select 1 from finance.opening_reversals where finance.opening_reversals.batch_id=batch.id
      and status in ('pending_approval','approved','posted')) then
    raise exception using errcode='55000',message='OPENING_REVERSAL_ALREADY_REQUESTED';
  end if;
  perform finance.opening_reversal_lock_sources(batch,posting_date);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.prepare',true);
  snapshot:=finance.opening_reversal_snapshot(batch,posting_date)||jsonb_build_object('reason',v_reason);
  insert into finance.opening_reversals(id,tenant_id,legal_entity_id,branch_id,batch_id,status,version,
    posting_date,reason,snapshot,content_hash,created_by)
  values(reversal_id,p_tenant_id,p_legal_entity_id,p_branch_id,batch.id,'pending_approval',1,
    posting_date,v_reason,snapshot,encode(extensions.digest(snapshot::text,'sha256'),'hex'),auth.uid())
  returning * into reversal;
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening_reversal',reversal.id,
    p_idempotency_key,request_hash,null,finance.opening_reversal_entity(reversal,true),p_legal_entity_id,p_branch_id,
    '{}',jsonb_build_object('to_status','pending_approval','reason',v_reason),'[]','[]',request_id,request_id);
end $$;

create function api.transition_finance_opening_reversal(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
  p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  command_name text:='finance.opening_reversal.transition';
  batch finance.opening_batches%rowtype;
  reversal finance.opening_reversals%rowtype;
  reversal_id uuid:=(p_payload->>'document_id')::uuid;
  v_batch_id uuid:=(p_payload->>'batch_id')::uuid;
  action text:=p_payload->>'action';
  v_reason text:=btrim(p_payload->>'reason');
  required_permission text;
  previous jsonb;
  request_hash text;
  replay jsonb;
  request_id uuid:=gen_random_uuid();
begin
  required_permission:=case when action in ('approve','reject') then 'finance.openings.approve' else 'finance.openings.prepare' end;
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,required_permission,true);
  if reversal_id is null or v_batch_id is null or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
      or action is null or action not in ('approve','reject','cancel')
      or (action in ('reject','cancel') and coalesce(length(v_reason),0) not between 3 and 1000) then
    raise exception using errcode='22023',message='OPENING_REVERSAL_INPUT_INVALID';
  end if;
  batch:=finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,v_batch_id,p_idempotency_key);
  select * into reversal from finance.opening_reversals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and id=reversal_id and finance.opening_reversals.batch_id=v_batch_id for update;
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,required_permission,true);
  request_hash:=core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  replay:=core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then return replay;end if;
  if reversal.id is null or batch.id is null then raise exception using errcode='P0002',message='OPENING_REVERSAL_NOT_FOUND';end if;
  perform core.wave3_assert_expected_version(reversal.version,p_expected_entity_version,finance.opening_reversal_entity(reversal,false));
  if (action in ('approve','reject') and reversal.status<>'pending_approval')
      or (action='cancel' and reversal.status not in ('pending_approval','approved')) then
    raise exception using errcode='55000',message='OPENING_REVERSAL_TRANSITION_INVALID';
  end if;
  if action in ('approve','reject') and (auth.uid()=reversal.created_by
      or auth.uid()=batch.submitted_by or auth.uid()=any(batch.preparer_ids)) then
    raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';
  end if;
  if action='approve' then
    perform finance.opening_reversal_lock_sources(batch,reversal.posting_date);
    perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,required_permission,true);
    if finance.opening_reversal_snapshot(batch,reversal.posting_date)||jsonb_build_object('reason',reversal.reason)
        is distinct from reversal.snapshot then
      raise exception using errcode='55000',message='OPENING_REVERSAL_STALE';
    end if;
  end if;
  previous:=finance.opening_reversal_entity(reversal,false);
  update finance.opening_reversals row set status=case action when 'approve' then 'approved' when 'reject' then 'rejected' else 'cancelled' end,
    version=row.version+1,updated_at=clock_timestamp(),decision_reason=v_reason,
    approved_by=case when action='approve' then auth.uid() end,
    approved_at=case when action='approve' then clock_timestamp() end,
    approved_content_hash=case when action='approve' then content_hash end
  where row.id=reversal.id returning * into reversal;
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening_reversal',reversal.id,
    p_idempotency_key,request_hash,previous,finance.opening_reversal_entity(reversal,true),p_legal_entity_id,p_branch_id,
    '{}',jsonb_build_object('from_status',previous->>'status','to_status',reversal.status),'[]','[]',request_id,request_id);
end $$;

create function api.post_finance_opening_reversal(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
  p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  command_name text:='finance.opening_reversal.post';
  batch finance.opening_batches%rowtype;
  reversal finance.opening_reversals%rowtype;
  reversal_id uuid:=(p_payload->>'document_id')::uuid;
  v_batch_id uuid:=(p_payload->>'batch_id')::uuid;
  source jsonb;
  previous jsonb;
  request_hash text;
  replay jsonb;
  request_id uuid:=gen_random_uuid();
  reversal_line_id uuid;
  counter_item_id uuid;
  journal_id uuid;
  original_item_id uuid;
  allocation jsonb;
  source_type text;
  transaction_amount numeric;
  base_amount numeric;
  direction integer;
  party_id uuid;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.reverse',true);
  if reversal_id is null or v_batch_id is null or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null then
    raise exception using errcode='22023',message='OPENING_REVERSAL_INPUT_INVALID';
  end if;
  batch:=finance.opening_lock_batch(p_tenant_id,p_legal_entity_id,p_branch_id,v_batch_id,p_idempotency_key);
  select * into reversal from finance.opening_reversals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and branch_id=p_branch_id and id=reversal_id and finance.opening_reversals.batch_id=v_batch_id for update;
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.reverse',true);
  request_hash:=core.wave3_request_hash(command_name,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_entity_version);
  replay:=core.wave3_replay(p_tenant_id,command_name,p_command_id,p_idempotency_key,request_hash);
  if replay is not null then return replay;end if;
  if reversal.id is null or batch.id is null then raise exception using errcode='P0002',message='OPENING_REVERSAL_NOT_FOUND';end if;
  perform core.wave3_assert_expected_version(reversal.version,p_expected_entity_version,finance.opening_reversal_entity(reversal,false));
  if reversal.status<>'approved' or reversal.approved_content_hash is distinct from reversal.content_hash then
    raise exception using errcode='55000',message='OPENING_REVERSAL_APPROVAL_REQUIRED';
  end if;
  perform finance.opening_reversal_lock_sources(batch,reversal.posting_date);
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.reverse',true);
  if finance.opening_reversal_snapshot(batch,reversal.posting_date)||jsonb_build_object('reason',reversal.reason)
      is distinct from reversal.snapshot then
    raise exception using errcode='55000',message='OPENING_REVERSAL_STALE';
  end if;
  previous:=finance.opening_reversal_entity(reversal,false);
  direction:=case reversal.snapshot->>'kind' when 'AR' then 1 else -1 end;
  source_type:=case direction when 1 then 'opening_receivable_reversal' else 'opening_payable_reversal' end;
  for source in select value from jsonb_array_elements(reversal.snapshot->'lines') order by (value->>'row_number')::integer loop
    reversal_line_id:=gen_random_uuid();
    original_item_id:=(source->>'original_open_item_id')::uuid;
    transaction_amount:=(source->>'original_amount')::numeric;
    base_amount:=(source->>'original_base_amount')::numeric;
    journal_id:=finance.flow_post_journal(jsonb_build_object(
      'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
      'document_date',reversal.posting_date,'customer_id',source->'party_id',
      'currency_code',source->'currency_code','base_currency_code',source->'base_currency_code',
      'exchange_rate',source->'exchange_rate'),jsonb_build_array(
        finance.flow_jline((reversal.snapshot->>'control_account_id')::uuid,-direction*transaction_amount,-direction*base_amount,reversal_line_id),
        finance.flow_jline((reversal.snapshot->>'clearing_account_id')::uuid,direction*transaction_amount,direction*base_amount,reversal_line_id)
      ),source_type,reversal_line_id,request_id,p_command_id);
    insert into finance.open_items(tenant_id,legal_entity_id,branch_id,kind,party_id,source_type,source_id,
      document_number,currency_code,base_currency_code,exchange_rate,original_amount,original_base_amount,
      posting_date,due_date,journal_entry_id,request_id,command_id,correlation_id,created_by)
    values(p_tenant_id,p_legal_entity_id,p_branch_id,reversal.snapshot->>'kind',(source->>'party_id')::uuid,
      source_type,reversal_line_id,'Reversal '||(source->>'document_number'),source->>'currency_code',source->>'base_currency_code',
      (source->>'exchange_rate')::numeric,-transaction_amount,-base_amount,reversal.posting_date,reversal.posting_date,
      journal_id,request_id,p_command_id,request_id,auth.uid()) returning id into counter_item_id;
    if direction=1 then
      allocation:=finance.flow_allocate(case when transaction_amount>0 then counter_item_id else original_item_id end,
        case when transaction_amount>0 then original_item_id else counter_item_id end,p_tenant_id,p_legal_entity_id,p_branch_id,
        jsonb_build_object('source_amount',abs(transaction_amount)::text,'transaction_amount',abs(transaction_amount)::text,
          'reason',reversal.reason),reversal.posting_date,request_id,p_command_id);
    else
      allocation:=finance.allocate_payable(case when transaction_amount>0 then counter_item_id else original_item_id end,
        case when transaction_amount>0 then original_item_id else counter_item_id end,p_tenant_id,p_legal_entity_id,p_branch_id,
        jsonb_build_object('source_amount',abs(transaction_amount)::text,'transaction_amount',abs(transaction_amount)::text,
          'reason',reversal.reason),reversal.posting_date,request_id,p_command_id);
    end if;
    if (allocation->>'exchange_difference')::numeric<>0
        or (finance.flow_residual(p_tenant_id,original_item_id)->>'amount')::numeric<>0
        or (finance.flow_residual(p_tenant_id,original_item_id)->>'base_amount')::numeric<>0
        or (finance.flow_residual(p_tenant_id,counter_item_id)->>'amount')::numeric<>0
        or (finance.flow_residual(p_tenant_id,counter_item_id)->>'base_amount')::numeric<>0 then
      raise exception using errcode='23514',message='OPENING_REVERSAL_RESIDUAL_MISMATCH';
    end if;
    insert into finance.opening_reversal_lines(id,tenant_id,legal_entity_id,branch_id,reversal_id,source_line_id,
      original_open_item_id,reversal_open_item_id,journal_entry_id,allocation_id)
    values(reversal_line_id,p_tenant_id,p_legal_entity_id,p_branch_id,reversal.id,(source->>'source_line_id')::uuid,
      original_item_id,counter_item_id,journal_id,(allocation->>'allocation_id')::uuid);
  end loop;
  if direction=1 then
    for party_id in select distinct (value->>'party_id')::uuid from jsonb_array_elements(reversal.snapshot->'lines') loop
      perform finance.flow_refresh_credit(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
        'branch_id',p_branch_id,'customer_id',party_id));
    end loop;
  end if;
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.reverse',true);
  update finance.opening_reversals row set status='posted',version=row.version+1,posted_by=auth.uid(),
    posted_at=clock_timestamp(),updated_at=clock_timestamp() where row.id=reversal.id returning * into reversal;
  return core.wave3_finish_command(p_tenant_id,command_name,p_command_id,'finance_opening_reversal',reversal.id,
    p_idempotency_key,request_hash,previous,finance.opening_reversal_entity(reversal,true),p_legal_entity_id,p_branch_id,
    '{}',jsonb_build_object('from_status','approved','to_status','posted'),'[]','[]',request_id,request_id);
end $$;

create or replace function api.finance_opening_source(
  p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare source jsonb;
begin
  perform finance.opening_require_scope(p_tenant_id,p_legal_entity_id,p_branch_id,'finance.openings.view');
  select line.data||jsonb_build_object('id',line.id,'batch_id',batch.id,'kind',line.kind,
    'cutoff_date',batch.snapshot->'cutoff_date','source_system',batch.snapshot->'source_system',
    'base_currency_code',batch.snapshot->'base_currency_code','file_sha256',batch.snapshot->'file_sha256',
    'posted_at',batch.posted_at,'journal_entry_id',line.journal_entry_id,'open_item_id',line.open_item_id,
    'reversal_id',link.reversal_id,'reversal_source_id',link.id)
  into source from finance.opening_lines line join finance.opening_batches batch on batch.id=line.batch_id
  left join finance.opening_reversal_lines link on link.source_line_id=line.id
  where line.tenant_id=p_tenant_id and line.legal_entity_id=p_legal_entity_id and line.branch_id=p_branch_id
    and line.id=p_source_id and batch.status='posted';
  if found then return source;end if;
  select original.data||jsonb_build_object('id',line.id,'batch_id',batch.id,'kind',original.kind,
    'cutoff_date',reversal.posting_date,'source_system',batch.snapshot->'source_system',
    'base_currency_code',batch.snapshot->'base_currency_code','file_sha256',batch.snapshot->'file_sha256',
    'posted_at',reversal.posted_at,'journal_entry_id',line.journal_entry_id,'open_item_id',line.reversal_open_item_id,
    'source_type',counter.source_type,'outstanding_amount',counter.original_amount::text,
    'carrying_base_amount',counter.original_base_amount::text,'document_number',counter.document_number,
    'document_date',counter.posting_date,'due_date',counter.due_date,
    'original_document_date',original.data->'document_date','original_due_date',original.data->'due_date',
    'reversal_id',reversal.id,'reversal_reason',reversal.reason,'reversal_posting_date',reversal.posting_date,
    'reversal_of_source_id',original.id,'original_open_item_id',line.original_open_item_id,'allocation_id',line.allocation_id)
  into source from finance.opening_reversal_lines line
  join finance.opening_reversals reversal on reversal.id=line.reversal_id and reversal.status='posted'
  join finance.opening_lines original on original.id=line.source_line_id
  join finance.opening_batches batch on batch.id=original.batch_id
  join finance.open_items counter on counter.id=line.reversal_open_item_id and counter.tenant_id=line.tenant_id
  where line.tenant_id=p_tenant_id and line.legal_entity_id=p_legal_entity_id and line.branch_id=p_branch_id and line.id=p_source_id;
  if not found then raise exception using errcode='P0002',message='OPENING_SOURCE_NOT_FOUND';end if;
  return source;
end $$;

revoke all on function finance.opening_reversal_protect(),finance.opening_reversal_guard_allocation(),
  finance.opening_reversal_guard_fx(),finance.opening_reversal_lock_sources(finance.opening_batches,date),
  finance.opening_reversal_snapshot(finance.opening_batches,date),finance.opening_reversal_entity(finance.opening_reversals,boolean)
from public,anon,authenticated,service_role;
revoke all on function api.prepare_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.transition_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.post_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.finance_opening_reversal(uuid,uuid,uuid,uuid),api.finance_opening_reversals(uuid,uuid,uuid,uuid,uuid,integer)
from public,anon,authenticated,service_role;
grant execute on function api.prepare_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.transition_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.post_finance_opening_reversal(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
  api.finance_opening_reversal(uuid,uuid,uuid,uuid),api.finance_opening_reversals(uuid,uuid,uuid,uuid,uuid,integer)
to authenticated;
