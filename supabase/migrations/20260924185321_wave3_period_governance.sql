-- UNAPPLIED AC-319 period-governance candidate. Verification must ROLLBACK.
-- This migration is additive; prior immutable migration files are untouched.
create table finance.period_reopen_requests (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,period_id uuid not null,
 period_version bigint not null,reason text not null check(length(btrim(reason)) between 3 and 1000),
 requested_by uuid not null references auth.users(id),requested_at timestamptz not null default now(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id,period_id)
 references finance.fiscal_periods(tenant_id,legal_entity_id,id)
);
create table finance.period_events (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,period_id uuid not null,
 action text not null check(action in('soft_lock','hard_lock','close_blocked','reopen_requested','reopened')),
 from_state text not null,to_state text not null,period_version bigint not null,
 reason text not null,exceptions jsonb not null default '[]'::jsonb,
 reopen_request_id uuid,actor_id uuid not null references auth.users(id),
 transaction_id bigint not null,created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,reopen_request_id),
 foreign key(tenant_id,legal_entity_id,period_id) references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,reopen_request_id) references finance.period_reopen_requests(tenant_id,id),
 check(jsonb_typeof(exceptions)='array')
);
create index period_requests_scope on finance.period_reopen_requests(tenant_id,legal_entity_id,period_id,id);
create index period_requests_actor on finance.period_reopen_requests(requested_by);
create index period_events_scope on finance.period_events(tenant_id,legal_entity_id,period_id,id);
create index period_events_actor on finance.period_events(actor_id);
alter table finance.period_reopen_requests enable row level security;
alter table finance.period_reopen_requests force row level security;
alter table finance.period_events enable row level security;
alter table finance.period_events force row level security;
revoke all on finance.period_reopen_requests,finance.period_events from public,anon,authenticated;
create trigger immutable before update or delete on finance.period_reopen_requests
 for each row execute function workflow.reject_history_mutation();
create trigger immutable before update or delete on finance.period_events
 for each row execute function workflow.reject_history_mutation();

-- Setup's pre-existing fiscal-period API can no longer bypass the period command.
-- The event must be created by the same actor in the same transaction before the
-- state update. Private event tables are never writable by client roles.
create or replace function finance.enforce_fiscal_period_lifecycle() returns trigger
language plpgsql set search_path='' as $$begin
 if tg_op='INSERT' then
  if new.state<>'open' then raise exception using errcode='55000',message='PERIOD_MUST_START_OPEN';end if;
  return new;
 end if;
 if new.state is distinct from old.state then
  if old.state='open' and new.state not in('soft_locked')
   or old.state='soft_locked' and new.state not in('hard_locked')
   or old.state='hard_locked' and new.state not in('open') then
   raise exception using errcode='55000',message='PERIOD_TRANSITION_INVALID';end if;
  if not exists(select 1 from finance.period_events ev where ev.tenant_id=old.tenant_id
   and ev.legal_entity_id=old.legal_entity_id and ev.period_id=old.id
   and ev.period_version=old.version and ev.from_state=old.state and ev.to_state=new.state
   and ev.actor_id=auth.uid() and ev.transaction_id=txid_current()
   and ev.action=case new.state when 'soft_locked' then 'soft_lock'
    when 'hard_locked' then 'hard_lock' else 'reopened' end) then
   raise exception using errcode='55000',message='PERIOD_TRANSITION_COMMAND_REQUIRED';end if;
 end if;
 return new;
end$$;

-- AAL2 alone does not prove recency: use the timestamp of a verified second
-- method in Supabase's signed amr claim. Missing or stale claims fail closed.
create function finance.period_require_recent_mfa() returns void language plpgsql
security definer set search_path='' as $$declare ts bigint;now_epoch bigint;begin
 if auth.jwt()->>'aal' is distinct from 'aal2' then
  raise exception using errcode='42501',message='RECENT_MFA_REQUIRED';end if;
 select max((x->>'timestamp')::bigint) into ts
 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) x
 where x->>'method' in('totp','otp') and x->>'timestamp' ~ '^[0-9]{10,12}$';
 now_epoch:=extract(epoch from clock_timestamp())::bigint;
 if ts is null or ts<now_epoch-900 or ts>now_epoch+60 then
  raise exception using errcode='42501',message='RECENT_MFA_REQUIRED';end if;
end$$;

-- Only this explicitly permitted closing source may post in a soft lock.
-- Every ordinary source continues through the original open-only helper.
create function finance.wave3_lock_posting_period(t uuid,e uuid,d date,source_type text)
returns uuid language plpgsql security definer set search_path='' as $$declare pid uuid;begin
 if source_type not in('exchange_revaluation','exchange_revaluation_reversal') then
  return finance.wave3_lock_open_period(t,e,d);end if;
 perform core.require_permission(t,'finance.fx.post',e,null);
 select fp.id into pid from finance.fiscal_periods fp where fp.tenant_id=t and fp.legal_entity_id=e
  and fp.status='active' and fp.state in('open','soft_locked') and d between fp.start_date and fp.end_date for update;
 if pid is null then raise exception using errcode='55000',message='PERIOD_CLOSED';end if;
 return pid;
end$$;

-- Preserve the existing exact, immutable journal engine; change only the
-- period selector so configured FX closing entries can post in a soft lock.
create or replace function finance.flow_post_journal(p_doc jsonb,p_lines jsonb,p_source_type text,p_source_id uuid,p_request uuid,p_command uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid:=gen_random_uuid();v_t uuid:=(p_doc->>'tenant_id')::uuid;v_e uuid:=(p_doc->>'legal_entity_id')::uuid;
 v_b uuid:=(p_doc->>'branch_id')::uuid;v_date date:=(p_doc->>'document_date')::date;v_period uuid;v_item jsonb;
 v_diff numeric;v_transaction numeric;v_base numeric;v_ord integer:=0;v_account finance.accounts%rowtype;begin
 if jsonb_array_length(p_lines)=0 then return null;end if;
 select sum((x->>'base_amount')::numeric) into v_diff from jsonb_array_elements(p_lines) x;
 if v_diff<>0 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 v_period:=finance.wave3_lock_posting_period(v_t,v_e,v_date,p_source_type);
 insert into finance.journal_entries(id,tenant_id,legal_entity_id,branch_id,fiscal_period_id,document_number,
 posting_date,source_type,source_id,currency_code,base_currency_code,exchange_rate,request_id,command_id,correlation_id,created_by)
 values(v_id,v_t,v_e,v_b,v_period,sales.wave3_reserve_document_number(v_t,v_e,v_b,'journal_entry',v_date,auth.uid()),
 v_date,p_source_type,p_source_id,p_doc->>'currency_code',p_doc->>'base_currency_code',(p_doc->>'exchange_rate')::numeric,
 p_request,p_command,p_request,auth.uid());
 for v_item in select value from jsonb_array_elements(p_lines) loop
 v_base:=(v_item->>'base_amount')::numeric;v_transaction:=(v_item->>'amount')::numeric;
 if v_base=0 then
 if v_transaction<>0 then raise exception using errcode='22023',message='AMOUNT_BELOW_BASE_PRECISION';end if;continue;end if;
 select * into v_account from finance.accounts where tenant_id=v_t and legal_entity_id=v_e
 and id=(v_item->>'account_id')::uuid and is_posting and status='active'
 and (currency_code is null or currency_code=p_doc->>'currency_code');
 if not found then raise exception using errcode='55000',message='ACCOUNT_MAPPING_INVALID';end if;
 v_ord:=v_ord+1;
 insert into finance.journal_lines(tenant_id,legal_entity_id,branch_id,journal_entry_id,line_number,account_id,party_id,
 source_line_id,currency_code,transaction_debit,transaction_credit,base_debit,base_credit,posting_date,created_by)
 values(v_t,v_e,v_b,v_id,v_ord,v_account.id,(p_doc->>'customer_id')::uuid,(v_item->>'source_line_id')::uuid,
 p_doc->>'currency_code',greatest(v_transaction,0),greatest(-v_transaction,0),greatest(v_base,0),greatest(-v_base,0),v_date,auth.uid());
 end loop;
 if v_ord<2 then raise exception using errcode='23514',message='UNBALANCED_JOURNAL';end if;
 update finance.journal_entries set status='posted' where id=v_id;return v_id;end $$;

create table finance.fx_revaluation_runs (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 period_id uuid not null,as_of date not null,currency_code text not null,base_currency_code text not null,
 exchange_rate_id uuid not null,exchange_rate numeric(20,10) not null check(exchange_rate>0),
 snapshot_hash text not null check(snapshot_hash ~ '^[0-9a-f]{64}$'),
 snapshot jsonb not null,item_count integer not null check(item_count between 0 and 1000),
 control_delta_base numeric(20,6) not null,journal_entry_id uuid,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id,period_id)
 references finance.fiscal_periods(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,exchange_rate_id)
 references finance.exchange_rates(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id),
 check(jsonb_typeof(snapshot)='array' and jsonb_array_length(snapshot)=item_count
  and octet_length(snapshot::text)<=4194304)
);
create table finance.fx_revaluation_reversals (
 id uuid primary key,tenant_id uuid not null,run_id uuid not null unique,
 replacement_run_id uuid,posting_date date not null,journal_entry_id uuid,
 reason text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 unique(tenant_id,id),unique(tenant_id,run_id),
 foreign key(tenant_id,run_id) references finance.fx_revaluation_runs(tenant_id,id),
 foreign key(tenant_id,replacement_run_id) references finance.fx_revaluation_runs(tenant_id,id),
 foreign key(tenant_id,journal_entry_id) references finance.journal_entries(tenant_id,id)
);
create index fx_reval_scope on finance.fx_revaluation_runs(tenant_id,legal_entity_id,branch_id,currency_code,as_of,id);
create index fx_reval_period on finance.fx_revaluation_runs(tenant_id,period_id,branch_id,id);
create index fx_reval_actor on finance.fx_revaluation_runs(created_by);
create index fx_reval_reversal_actor on finance.fx_revaluation_reversals(created_by);
create index fx_reval_replacement on finance.fx_revaluation_reversals(tenant_id,replacement_run_id);
alter table finance.fx_revaluation_runs enable row level security;
alter table finance.fx_revaluation_runs force row level security;
alter table finance.fx_revaluation_reversals enable row level security;
alter table finance.fx_revaluation_reversals force row level security;
revoke all on finance.fx_revaluation_runs,finance.fx_revaluation_reversals from public,anon,authenticated;
create trigger immutable before update or delete on finance.fx_revaluation_runs
 for each row execute function workflow.reject_history_mutation();
create trigger immutable before update or delete on finance.fx_revaluation_reversals
 for each row execute function workflow.reject_history_mutation();

create function finance.fx_open_snapshot(t uuid,e uuid,b uuid,c text,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into items from (
  select o.id,o.kind,o.party_id,o.source_type,o.source_id,o.document_number,
   finance.open_item_control(t,o.id) control_account_id,
   r->>'amount' open_amount,r->>'base_amount' open_base_amount
  from finance.open_items o
  cross join lateral (select finance.flow_residual(t,o.id,d) r) residual
  where o.tenant_id=t and o.legal_entity_id=e and o.branch_id=b and o.currency_code=c
   and o.base_currency_code<>c and o.posting_date<=d
   and ((r->>'amount')::numeric<>0 or (r->>'base_amount')::numeric<>0)
  order by o.id limit 1001)q;
 if jsonb_array_length(items)>1000 then raise exception using errcode='54000',message='FX_SNAPSHOT_LIMIT';end if;
 return jsonb_build_object('items',items,'hash',encode(extensions.digest(items::text,'sha256'),'hex'));
end$$;

create function finance.fx_reverse_run(t uuid,e uuid,b uuid,old_run finance.fx_revaluation_runs,
 reversal_id uuid,d date,reason text,req uuid,cmd uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare j finance.journal_entries%rowtype;doc jsonb;lines jsonb;reverse_journal uuid;begin
 if old_run.journal_entry_id is not null then
  select * into j from finance.journal_entries where tenant_id=t and id=old_run.journal_entry_id;
  doc:=jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,'document_date',d,
   'currency_code',j.currency_code,'base_currency_code',j.base_currency_code,'exchange_rate',j.exchange_rate::text);
  select jsonb_agg(finance.flow_jline(l.account_id,l.transaction_credit-l.transaction_debit,
   l.base_credit-l.base_debit,l.source_line_id) order by l.line_number) into lines
  from finance.journal_lines l where l.tenant_id=t and l.journal_entry_id=j.id;
  reverse_journal:=finance.flow_post_journal(doc,lines,'exchange_revaluation_reversal',reversal_id,req,cmd);
 end if;
 return reverse_journal;
end$$;

create function api.post_exchange_revaluation(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;
 act text:=p_payload->>'action';v_id uuid:=(p_payload->>'id')::uuid;d date:=(p_payload->>'as_of')::date;
 reason text:=btrim(p_payload->>'reason');period finance.fiscal_periods%rowtype;
 old_run finance.fx_revaluation_runs%rowtype;rate finance.exchange_rates%rowtype;
 base text;currency text:=p_payload->>'currency_code';snap jsonb;item jsonb;lines jsonb:='[]'::jsonb;
 delta numeric;signed_delta numeric;total numeric:=0;offset_account uuid;new_journal uuid;reverse_journal uuid;
 reversal_id uuid;request_id uuid:=gen_random_uuid();h text;r jsonb;result jsonb;begin
 perform core.wave3_require_scope(t,'finance.fx.post',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if act not in('post','reverse') or act is null or v_id is null or d is null
  or p_client_timestamp is null or d>(clock_timestamp() at time zone 'UTC')::date
  or coalesce(length(reason),0) not between 3 and 1000 then
  raise exception using errcode='22023',message='FX_REVALUATION_INPUT_INVALID';end if;
 h:=core.wave3_request_hash('finance.fx.'||act,p_command_id,t,e,b,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(t,'finance.fx.'||act,p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 select fp.* into period from finance.fiscal_periods fp where fp.tenant_id=t and fp.legal_entity_id=e
  and fp.id=(p_payload->>'period_id')::uuid and fp.status='active' and d between fp.start_date and fp.end_date for update;
 if not found or period.state='hard_locked' then raise exception using errcode='55000',message='PERIOD_CLOSED';end if;
 if act='reverse' then
  perform core.wave3_assert_expected_version(1,p_expected_entity_version,'{}');
  select rr.* into old_run from finance.fx_revaluation_runs rr where rr.tenant_id=t and rr.legal_entity_id=e
   and rr.branch_id=b and rr.id=(p_payload->>'run_id')::uuid and rr.as_of<=d;
  if not found or exists(select 1 from finance.fx_revaluation_reversals x where x.tenant_id=t and x.run_id=old_run.id) then
   raise exception using errcode='55000',message='FX_RUN_NOT_ACTIVE';end if;
  reverse_journal:=finance.fx_reverse_run(t,e,b,old_run,v_id,d,reason,request_id,p_command_id);
  insert into finance.fx_revaluation_reversals values(v_id,t,old_run.id,null,d,reverse_journal,reason,auth.uid(),now());
  result:=jsonb_build_object('id',v_id,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'period_id',period.id,
   'run_id',old_run.id,'version',1,'status','reversed','journal_entry_id',reverse_journal);
 else
  perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
  select currency_code into base from core.legal_entities where tenant_id=t and id=e;
  if currency is null or currency=base then raise exception using errcode='22023',message='FX_CURRENCY_INVALID';end if;
  select er.* into rate from finance.exchange_rates er where er.tenant_id=t and er.legal_entity_id=e
   and er.id=(p_payload->>'exchange_rate_id')::uuid and er.source_currency_code=currency
   and er.target_currency_code=base and er.rate_type='closing' and er.status='active' and er.effective_date<=d;
  if not found then raise exception using errcode='22023',message='FX_CLOSING_RATE_REQUIRED';end if;
  if exists(select 1 from finance.fx_revaluation_runs rr where rr.tenant_id=t and rr.legal_entity_id=e
   and rr.branch_id=b and rr.currency_code=currency and rr.as_of>d) then
   raise exception using errcode='22023',message='FX_DATE_BEFORE_ACTIVE_RUN';end if;
  snap:=finance.fx_open_snapshot(t,e,b,currency,d);
  select rr.* into old_run from finance.fx_revaluation_runs rr where rr.tenant_id=t and rr.legal_entity_id=e
   and rr.branch_id=b and rr.currency_code=currency and rr.as_of<=d
   and not exists(select 1 from finance.fx_revaluation_reversals x where x.tenant_id=t and x.run_id=rr.id)
   order by rr.as_of desc,rr.created_at desc limit 1;
  if found then
   reversal_id:=gen_random_uuid();
   reverse_journal:=finance.fx_reverse_run(t,e,b,old_run,reversal_id,d,reason,request_id,p_command_id);
  end if;
  for item in select value from jsonb_array_elements(snap->'items') loop
   delta:=round((item->>'open_amount')::numeric*rate.rate,6)-(item->>'open_base_amount')::numeric;
   signed_delta:=case when item->>'kind'='AR' then delta else -delta end;
   total:=total+signed_delta;
   if signed_delta<>0 then
    offset_account:=finance.flow_mapping(t,e,case when signed_delta>0 then 'exchange_gain' else 'exchange_loss' end,currency);
    lines:=lines||jsonb_build_array(finance.flow_jline((item->>'control_account_id')::uuid,0,signed_delta,(item->>'id')::uuid),
      finance.flow_jline(offset_account,0,-signed_delta,(item->>'id')::uuid));
   end if;
  end loop;
  if jsonb_array_length(lines)>0 then
   new_journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',t,'legal_entity_id',e,'branch_id',b,
    'document_date',d,'currency_code',currency,'base_currency_code',base,'exchange_rate',rate.rate::text),
    lines,'exchange_revaluation',v_id,request_id,p_command_id);
  end if;
  insert into finance.fx_revaluation_runs values(v_id,t,e,b,period.id,d,currency,base,rate.id,rate.rate,
   snap->>'hash',snap->'items',jsonb_array_length(snap->'items'),total,new_journal,reason,auth.uid(),now());
  if reversal_id is not null then
   insert into finance.fx_revaluation_reversals values(reversal_id,t,old_run.id,v_id,d,reverse_journal,reason,auth.uid(),now());
  end if;
  result:=jsonb_build_object('id',v_id,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'period_id',period.id,
   'version',1,'status','posted','as_of',d,'currency_code',currency,'exchange_rate',rate.rate::text,
   'item_count',jsonb_array_length(snap->'items'),'control_delta_base',total::text,
   'journal_entry_id',new_journal,'reversed_run_id',old_run.id);
 end if;
 return core.wave3_finish_command(t,'finance.fx.'||act,p_command_id,'fx_revaluation',v_id,
  p_idempotency_key,h,null,result,e,b,'{}',jsonb_build_object('to_status',result->>'status'),
  jsonb_build_array(jsonb_build_object('topic','finance.fx.'||act,'payload',jsonb_build_object('id',v_id))),
  '[]',request_id,request_id);
end$$;

create function api.exchange_revaluation_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_resource text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_resource not in('rates','runs') or p_resource is null then
  raise exception using errcode='22023',message='FX_RESOURCE_INVALID';end if;
 if p_resource='rates' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from
   (select id,source_currency_code,target_currency_code,rate::text rate,effective_date,rate_type
    from finance.exchange_rates where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and rate_type='closing' and status='active' and (p_after is null or id>p_after)
    order by id limit 51)q;
 else
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from
   (select rr.id,rr.period_id,rr.as_of,rr.currency_code,rr.base_currency_code,
    rr.exchange_rate_id,rr.exchange_rate::text exchange_rate,rr.snapshot_hash,rr.item_count,
    rr.control_delta_base::text control_delta_base,rr.journal_entry_id,rr.reason,rr.created_by,rr.created_at,
    to_jsonb(x) reversal from finance.fx_revaluation_runs rr
    left join finance.fx_revaluation_reversals x on x.tenant_id=rr.tenant_id and x.run_id=rr.id
    where rr.tenant_id=p_tenant_id and rr.legal_entity_id=p_legal_entity_id and rr.branch_id=p_branch_id
     and (p_after is null or rr.id>p_after) order by rr.id limit 51)q;
 end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'resource',p_resource,'items',rows,'next_cursor',cursor);
end$$;

create function api.exchange_revaluation_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_run_id uuid,p_offset integer default 0) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare run finance.fx_revaluation_runs%rowtype;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_offset is null or p_offset<0 or p_offset>1000 then raise exception using errcode='22023',message='FX_PAGE_INVALID';end if;
 select * into run from finance.fx_revaluation_runs where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and id=p_run_id;
 if not found then raise exception using errcode='42501',message='FX_RUN_SCOPE_REQUIRED';end if;
 return jsonb_build_object('id',run.id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'snapshot_hash',run.snapshot_hash,'item_count',run.item_count,
  'offset',p_offset,'items',(select coalesce(jsonb_agg(value order by ord),'[]') from
   jsonb_array_elements(run.snapshot) with ordinality a(value,ord) where ord>p_offset and ord<=p_offset+50),
  'next_offset',case when p_offset+50<run.item_count then p_offset+50 else null end);
end$$;

-- A revaluation does not mutate an open item. Reconcile its independently
-- recomputed snapshot delta to the report's account-and-command difference;
-- a non-FX difference therefore remains a close blocker.
create function finance.period_control_fx_variance(t uuid,e uuid,b uuid,k text,d date,report jsonb)
returns jsonb language sql stable security definer set search_path='' as $$
 with fx_events as (
  select rr.snapshot,rr.exchange_rate,j.command_id,1 direction
  from finance.fx_revaluation_runs rr join finance.journal_entries j
   on j.tenant_id=rr.tenant_id and j.id=rr.journal_entry_id
  where rr.tenant_id=t and rr.legal_entity_id=e and rr.branch_id=b and rr.as_of<=d
  union all
  select rr.snapshot,rr.exchange_rate,j.command_id,-1 direction
  from finance.fx_revaluation_reversals reversal
  join finance.fx_revaluation_runs rr on rr.tenant_id=reversal.tenant_id and rr.id=reversal.run_id
  join finance.journal_entries j on j.tenant_id=reversal.tenant_id and j.id=reversal.journal_entry_id
  where rr.tenant_id=t and rr.legal_entity_id=e and rr.branch_id=b and reversal.posting_date<=d
 ), fx_expected as (
  select item->>'control_account_id' evidence_key,command_id::text command_id,
   sum(direction*(round((item->>'open_amount')::numeric*exchange_rate,6)
    -(item->>'open_base_amount')::numeric)) value
  from fx_events cross join lateral jsonb_array_elements(snapshot) item
  where item->>'kind'=k group by item->>'control_account_id',command_id
 ), actual as (
  select x->>'evidence_key' evidence_key,x->>'command_id' command_id,
   (x->>'difference')::numeric difference from jsonb_array_elements(report->'differences') x
 )
 select coalesce(jsonb_agg(jsonb_build_object(
  'evidence_key',coalesce(a.evidence_key,f.evidence_key),
  'command_id',coalesce(a.command_id,f.command_id),
  'unexplained_difference',(coalesce(a.difference,0)+coalesce(f.value,0))::text)
  order by coalesce(a.evidence_key,f.evidence_key),coalesce(a.command_id,f.command_id))
  filter(where coalesce(a.difference,0)+coalesce(f.value,0)<>0),'[]'::jsonb)
 from actual a full join fx_expected f on f.evidence_key=a.evidence_key
  and f.command_id is not distinct from a.command_id
$$;

-- Recalculate controls at the exact cutoff. A failed check is returned and
-- recorded, never silently waived. Branch access is checked by the shared
-- report engine. Bank and draft checks use posted as-of truth.
create function finance.period_close_exceptions(t uuid,e uuid,p finance.fiscal_periods)
returns jsonb language plpgsql security definer set search_path='' as $$
declare issues jsonb:='[]'::jsonb;n bigint;branch record;k text;report jsonb;control_variance jsonb;
 fx_group record;run_hash text;current_hash text;run_rate uuid;closing_rate uuid;begin
 select count(*) into n from finance.journal_entries j where j.tenant_id=t and j.legal_entity_id=e
  and j.posting_date between p.start_date and p.end_date and j.status<>'posted';
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('code','DRAFT_JOURNALS','count',n));end if;
 for fx_group in select distinct branch_id,currency_code from (
  select o.branch_id,o.currency_code from finance.open_items o
   cross join lateral (select finance.flow_residual(t,o.id,p.end_date) r) residual
   where o.tenant_id=t and o.legal_entity_id=e and o.posting_date<=p.end_date
    and o.currency_code<>o.base_currency_code
    and ((residual.r->>'amount')::numeric<>0 or (residual.r->>'base_amount')::numeric<>0)
  union all
  select rr.branch_id,rr.currency_code from finance.fx_revaluation_runs rr
   where rr.tenant_id=t and rr.legal_entity_id=e and rr.as_of<=p.end_date
    and not exists(select 1 from finance.fx_revaluation_reversals x
     where x.tenant_id=t and x.run_id=rr.id and x.posting_date<=p.end_date)
 ) fx_groups order by branch_id,currency_code loop
  begin
   select rr.snapshot_hash,rr.exchange_rate_id into run_hash,run_rate from finance.fx_revaluation_runs rr
    where rr.tenant_id=t and rr.legal_entity_id=e and rr.branch_id=fx_group.branch_id
     and rr.currency_code=fx_group.currency_code and rr.as_of=p.end_date
     and not exists(select 1 from finance.fx_revaluation_reversals x where x.tenant_id=t
      and x.run_id=rr.id and x.posting_date<=p.end_date)
    order by rr.created_at desc limit 1;
   select er.id into closing_rate from finance.exchange_rates er where er.tenant_id=t
    and er.legal_entity_id=e and er.source_currency_code=fx_group.currency_code
    and er.target_currency_code=(select currency_code from core.legal_entities where tenant_id=t and id=e)
    and er.rate_type='closing' and er.status='active' and er.effective_date<=p.end_date
    order by er.effective_date desc,er.created_at desc,er.id desc limit 1;
   current_hash:=finance.fx_open_snapshot(t,e,fx_group.branch_id,fx_group.currency_code,p.end_date)->>'hash';
   if run_hash is distinct from current_hash or run_rate is distinct from closing_rate
    or closing_rate is null then
    issues:=issues||jsonb_build_array(jsonb_build_object('code','FX_REVALUATION_REQUIRED',
     'branch_id',fx_group.branch_id,'currency_code',fx_group.currency_code));end if;
  exception when others then
   issues:=issues||jsonb_build_array(jsonb_build_object('code','FX_REVALUATION_CHECK_FAILED',
    'branch_id',fx_group.branch_id,'currency_code',fx_group.currency_code,'sqlstate',sqlstate));
  end;
 end loop;
 if p.end_date>=(clock_timestamp() at time zone 'UTC')::date then
  issues:=issues||jsonb_build_array(jsonb_build_object('code','PERIOD_NOT_ENDED'));
 end if;
 select count(distinct l.id) into n from finance.journal_lines l
 join finance.journal_entries j on j.id=l.journal_entry_id
 join finance.cash_bank_accounts cb on cb.tenant_id=l.tenant_id and cb.legal_entity_id=l.legal_entity_id
  and cb.branch_id=l.branch_id and cb.account_id=l.account_id and cb.currency_code=l.currency_code and cb.account_kind='bank'
 left join finance.bank_match_claims c on c.tenant_id=l.tenant_id and c.kind='journal' and c.source_id=l.id
 where l.tenant_id=t and l.legal_entity_id=e and l.posting_date between p.start_date and p.end_date
  and j.status='posted' and j.source_type not in('bank_adjustment','bank_adjustment_reversal') and c.source_id is null;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('code','UNMATCHED_BANK_JOURNALS','count',n));end if;
 select count(*) into n from finance.bank_statement_lines l join finance.bank_statements s on s.id=l.statement_id
 left join finance.bank_match_claims c on c.tenant_id=l.tenant_id and c.kind='statement' and c.source_id=l.id
 where l.tenant_id=t and s.legal_entity_id=e and l.posting_date between p.start_date and p.end_date and c.source_id is null;
 if n>0 then issues:=issues||jsonb_build_array(jsonb_build_object('code','UNMATCHED_BANK_STATEMENTS','count',n));end if;
 for branch in select id from core.branches where tenant_id=t and legal_entity_id=e and status='active' order by id loop
  foreach k in array array['AR','AP'] loop
   begin
    report:=finance.build_control_report(t,e,branch.id,jsonb_build_object('id',gen_random_uuid(),'kind',k,'as_of',p.end_date));
    control_variance:=finance.period_control_fx_variance(t,e,branch.id,k,p.end_date,report);
    if jsonb_array_length(control_variance)<>0 then
     issues:=issues||jsonb_build_array(jsonb_build_object('code',k||'_CONTROL_DIFFERENCE','branch_id',branch.id,
      'difference',report#>>'{summary,difference}','difference_count',report#>>'{summary,difference_count}',
      'unexplained',control_variance));
    end if;
   exception when others then
    issues:=issues||jsonb_build_array(jsonb_build_object('code',k||'_CONTROL_CHECK_FAILED','branch_id',branch.id,'sqlstate',sqlstate));
   end;
  end loop;
 end loop;
 return issues;
end$$;

create function api.period_governance_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,
 p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;
 act text:=p_payload->>'action';v_id uuid:=(p_payload->>'id')::uuid;
 period finance.fiscal_periods%rowtype;request finance.period_reopen_requests%rowtype;
 h text;r jsonb;result jsonb;issues jsonb:='[]'::jsonb;new_state text;req uuid:=gen_random_uuid();reason text:=btrim(p_payload->>'reason');
begin
 if act not in('soft_lock','hard_lock','request_reopen','approve_reopen') or act is null
  or v_id is null or p_client_timestamp is null or coalesce(length(reason),0) not between 3 and 1000 then
  raise exception using errcode='22023',message='PERIOD_COMMAND_INVALID';end if;
 perform core.wave3_require_scope(t,case when act in('soft_lock','hard_lock') then 'finance.period.close'
  else 'finance.period.reopen' end,e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 if act in('request_reopen','approve_reopen') then perform finance.period_require_recent_mfa();end if;
 h:=core.wave3_request_hash('finance.period.'||act,p_command_id,t,e,b,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(t,'finance.period.'||act,p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 select fp.* into period from finance.fiscal_periods fp where fp.tenant_id=t and fp.legal_entity_id=e
  and fp.id=(p_payload->>'period_id')::uuid and fp.status='active' for update;
 if not found then raise exception using errcode='42501',message='PERIOD_SCOPE_REQUIRED';end if;
 perform core.wave3_assert_expected_version(period.version,p_expected_entity_version,'{}');
 if act='soft_lock' and period.state='open' then new_state:='soft_locked';
 elsif act='hard_lock' and period.state='soft_locked' then
  issues:=finance.period_close_exceptions(t,e,period);
  new_state:=case when jsonb_array_length(issues)=0 then 'hard_locked' else period.state end;
 elsif act='request_reopen' and period.state='hard_locked' then new_state:=period.state;
 elsif act='approve_reopen' and period.state='hard_locked' then
  select rr.* into request from finance.period_reopen_requests rr where rr.tenant_id=t and rr.legal_entity_id=e
   and rr.period_id=period.id and rr.id=(p_payload->>'request_id')::uuid and rr.period_version=period.version;
  if not found or request.requested_by=auth.uid() or exists(select 1 from finance.period_events
   where tenant_id=t and reopen_request_id=request.id) then
   raise exception using errcode='42501',message='PERIOD_REOPEN_APPROVAL_INVALID';end if;
  new_state:='open';
 else raise exception using errcode='55000',message='PERIOD_TRANSITION_INVALID';end if;
 if act='request_reopen' then
  insert into finance.period_reopen_requests values(v_id,t,e,period.id,period.version,reason,auth.uid(),now());
 end if;
 insert into finance.period_events(id,tenant_id,legal_entity_id,period_id,action,from_state,to_state,period_version,
  reason,exceptions,reopen_request_id,actor_id,transaction_id)
 values(case when act='request_reopen' then gen_random_uuid() else v_id end,t,e,period.id,
  case when act='hard_lock' and jsonb_array_length(issues)>0 then 'close_blocked'
   when act='request_reopen' then 'reopen_requested' when act='approve_reopen' then 'reopened' else act end,
  period.state,new_state,period.version,reason,issues,
  case when act='approve_reopen' then request.id else null end,auth.uid(),txid_current());
 if new_state<>period.state then
  update finance.fiscal_periods set state=new_state,updated_by=auth.uid() where finance.fiscal_periods.id=period.id;
 end if;
 select jsonb_build_object('id',v_id,'tenant_id',t,'legal_entity_id',e,'branch_id',b,
  'period_id',period.id,'period_version',fp.version,'version',1,
  'status',case when act='hard_lock' and jsonb_array_length(issues)>0 then 'blocked'
   when act='request_reopen' then 'pending_approval' else new_state end,
  'action',act,'exceptions',issues,'reason',reason,'reopen_request_id',
  case when act='request_reopen' then v_id when act='approve_reopen' then request.id else null end)
 into result from finance.fiscal_periods fp where fp.id=period.id;
 return core.wave3_finish_command(t,'finance.period.'||act,p_command_id,'fiscal_period_event',v_id,
  p_idempotency_key,h,null,result,e,b,'{}',jsonb_build_object('from_status',period.state,'to_status',result->>'status'),
  jsonb_build_array(jsonb_build_object('topic','finance.period.'||act,'payload',jsonb_build_object('period_id',period.id))),
  '[]',req,req);
end$$;

create function api.period_governance_options(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_resource text,p_period_id uuid default null,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;cursor uuid;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_resource not in('periods','events','reopen_requests') or p_resource is null then
  raise exception using errcode='22023',message='PERIOD_RESOURCE_INVALID';end if;
 if p_resource<>'periods' and not exists(select 1 from finance.fiscal_periods where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and id=p_period_id) then
  raise exception using errcode='42501',message='PERIOD_SCOPE_REQUIRED';end if;
 if p_resource='periods' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from
   (select id,name,start_date,end_date,state,status,version from finance.fiscal_periods
    where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and status='active'
    and (p_after is null or id>p_after) order by id limit 51)q;
 elsif p_resource='events' then
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from
   (select id,period_id,action,from_state,to_state,period_version,reason,exceptions,
    reopen_request_id,actor_id,created_at from finance.period_events
    where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and period_id=p_period_id
    and (p_after is null or id>p_after) order by id limit 51)q;
 else
  select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from
   (select id,period_id,period_version,reason,requested_by,requested_at from finance.period_reopen_requests
    where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and period_id=p_period_id
    and (p_after is null or id>p_after) order by id limit 51)q;
 end if;
 if jsonb_array_length(rows)>50 then cursor:=(rows->49->>'id')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'resource',p_resource,'period_id',p_period_id,'items',rows,'next_cursor',cursor);
end$$;
revoke all on function finance.period_require_recent_mfa(),finance.period_close_exceptions(uuid,uuid,finance.fiscal_periods),
 finance.period_control_fx_variance(uuid,uuid,uuid,text,date,jsonb),
 finance.wave3_lock_posting_period(uuid,uuid,date,text),finance.fx_open_snapshot(uuid,uuid,uuid,text,date),
 finance.fx_reverse_run(uuid,uuid,uuid,finance.fx_revaluation_runs,uuid,date,text,uuid,uuid),
 api.post_exchange_revaluation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.exchange_revaluation_options(uuid,uuid,uuid,text,uuid),
 api.exchange_revaluation_detail(uuid,uuid,uuid,uuid,integer),
 api.period_governance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.period_governance_options(uuid,uuid,uuid,text,uuid,uuid) from public,anon,authenticated;
grant execute on function api.period_governance_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.period_governance_options(uuid,uuid,uuid,text,uuid,uuid),
 api.post_exchange_revaluation(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.exchange_revaluation_options(uuid,uuid,uuid,text,uuid),
 api.exchange_revaluation_detail(uuid,uuid,uuid,uuid,integer) to authenticated;
notify pgrst,'reload schema';
