-- UNAPPLIED additive governed financial dimensions. No historical backfill.
insert into core.permissions(code,module,description,privileged) values
 ('finance.dimensions.manage','finance','Manage scoped financial cost centres and project tags.',true)
 on conflict(code) do nothing;
create table finance.dimensions (
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 kind text not null check(kind in('cost_centre','project')),code text not null check(code~'^[A-Z0-9][A-Z0-9._-]{0,39}$'),
 name text not null check(length(trim(name)) between 2 and 160),status text not null check(status in('active','retired')),
 version bigint not null check(version>0),reason text not null check(length(trim(reason)) between 3 and 1000),
 created_by uuid not null references auth.users(id),updated_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,kind,code),
 foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),
 foreign key(tenant_id,branch_id) references core.branches(tenant_id,id)
);
create index dimensions_scope on finance.dimensions(tenant_id,legal_entity_id,kind,status,id);
create index dimensions_branch on finance.dimensions(tenant_id,branch_id);
create index dimensions_creator on finance.dimensions(created_by);
create index dimensions_updater on finance.dimensions(updated_by);
alter table finance.dimensions enable row level security;
alter table finance.dimensions force row level security;
revoke all on finance.dimensions from public,anon,authenticated;
create function finance.guard_dimension() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' or new.id is distinct from old.id or new.tenant_id is distinct from old.tenant_id
  or new.legal_entity_id is distinct from old.legal_entity_id or new.branch_id is distinct from old.branch_id
  or new.kind is distinct from old.kind or new.code is distinct from old.code
  or new.version<>old.version+1 or new.created_by is distinct from old.created_by then
  raise exception using errcode='55000',message='DIMENSION_IDENTITY_IMMUTABLE';end if;
 return new;
end$$;
create trigger dimension_guard before update or delete on finance.dimensions for each row execute function finance.guard_dimension();
create table finance.dimension_events (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 dimension_id uuid not null,version bigint not null,actor_id uuid not null references auth.users(id),snapshot jsonb not null,
 created_at timestamptz not null default now(),unique(tenant_id,legal_entity_id,dimension_id,version),
 foreign key(tenant_id,legal_entity_id,dimension_id) references finance.dimensions(tenant_id,legal_entity_id,id)
);
create index dimension_events_actor on finance.dimension_events(actor_id);
alter table finance.dimension_events enable row level security;
alter table finance.dimension_events force row level security;
revoke all on finance.dimension_events from public,anon,authenticated;
create trigger immutable before update or delete on finance.dimension_events for each row execute function workflow.reject_history_mutation();

create function api.financial_dimension_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_entity_version bigint default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;p jsonb:=p_payload;
 v_id uuid:=(p->>'id')::uuid;target_branch uuid:=(p->>'dimension_branch_id')::uuid;
 oldrow finance.dimensions%rowtype;d finance.dimensions%rowtype;h text;r jsonb;req uuid:=gen_random_uuid();result jsonb;begin
 perform core.wave3_require_scope(t,'finance.dimensions.manage',e,null);
 perform core.wave3_require_scope(t,'finance.dimensions.manage',e,b);
 if v_id is null or p_client_timestamp is null or p->>'kind' not in('cost_centre','project') or p->>'kind' is null
  or coalesce(p->>'code','')!~'^[A-Z0-9][A-Z0-9._-]{0,39}$'
  or length(trim(coalesce(p->>'name',''))) not between 2 and 160
  or p->>'status' not in('active','retired') or p->>'status' is null
  or length(trim(coalesce(p->>'reason',''))) not between 3 and 1000 then
  raise exception using errcode='22023',message='DIMENSION_INPUT_INVALID';end if;
 if target_branch is not null and (target_branch<>b or not exists(select 1 from core.branches
  where tenant_id=t and legal_entity_id=e and id=target_branch and status='active')) then
  raise exception using errcode='42501',message='DIMENSION_BRANCH_SCOPE_REQUIRED';end if;
 h:=core.wave3_request_hash('finance.dimension.save',p_command_id,t,e,b,p,p_expected_entity_version);
 r:=core.wave3_replay(t,'finance.dimension.save',p_command_id,p_idempotency_key,h);if r is not null then return r;end if;
 perform pg_advisory_xact_lock(hashtextextended(t::text||':dimension:'||v_id::text,0));
 select * into oldrow from finance.dimensions where tenant_id=t and legal_entity_id=e and dimensions.id=v_id for update;
 if not found then
  perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
  insert into finance.dimensions(id,tenant_id,legal_entity_id,branch_id,kind,code,name,status,version,reason,created_by,updated_by)
  values(v_id,t,e,target_branch,p->>'kind',p->>'code',trim(p->>'name'),p->>'status',1,trim(p->>'reason'),auth.uid(),auth.uid());
 else
  if oldrow.branch_id is not null and oldrow.branch_id<>b then raise exception using errcode='42501',message='DIMENSION_BRANCH_SCOPE_REQUIRED';end if;
  perform core.wave3_assert_expected_version(oldrow.version,p_expected_entity_version,to_jsonb(oldrow));
  if oldrow.branch_id is distinct from target_branch or oldrow.kind<>p->>'kind' or oldrow.code<>p->>'code' then
   raise exception using errcode='22023',message='DIMENSION_IDENTITY_IMMUTABLE';end if;
  update finance.dimensions set name=trim(p->>'name'),status=p->>'status',reason=trim(p->>'reason'),
   version=version+1,updated_by=auth.uid(),updated_at=now() where tenant_id=t and dimensions.id=v_id;
 end if;
 select * into d from finance.dimensions where tenant_id=t and dimensions.id=v_id;
 result:=to_jsonb(d)||jsonb_build_object('dimension_branch_id',d.branch_id,'branch_id',b);
 insert into finance.dimension_events(tenant_id,legal_entity_id,dimension_id,version,actor_id,snapshot)
  values(t,e,v_id,d.version,auth.uid(),to_jsonb(d));
 return core.wave3_finish_command(t,'finance.dimension.save',p_command_id,'financial_dimension',v_id,p_idempotency_key,h,
  case when oldrow.id is not null then to_jsonb(oldrow) end,result,e,b,'{}',
  jsonb_build_object('to_status',d.status,'reason',d.reason),
  jsonb_build_array(jsonb_build_object('topic','finance.dimension.saved','payload',result)),'[]',req,req);
end$$;

create function api.financial_dimensions(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_kind text,p_after uuid default null,p_search text default '',p_active_only boolean default true) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;n integer;begin
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,null);
 perform core.wave3_require_scope(p_tenant_id,'finance.view',p_legal_entity_id,p_branch_id);
 if p_kind not in('cost_centre','project') or p_kind is null or length(coalesce(p_search,''))>100 or p_active_only is null then
  raise exception using errcode='22023',message='DIMENSION_PAGE_INVALID';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by id),'[]') into rows from(
  select id,tenant_id,legal_entity_id,branch_id dimension_branch_id,kind,code,name,status,version,reason
  from finance.dimensions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
   and kind=p_kind and (branch_id is null or branch_id=p_branch_id)
   and (not p_active_only or status='active') and (p_after is null or id>p_after)
   and (coalesce(p_search,'')='' or position(lower(p_search) in lower(code||' '||name))>0)
  order by id limit 51)q;
 n:=jsonb_array_length(rows);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'kind',p_kind,'items',case when n>50 then rows-50 else rows end,'next_cursor',case when n>50 then rows->49->>'id' end);
end$$;

create function finance.dimension_basis(t uuid,e uuid,b uuid,i uuid,k text) returns jsonb
language plpgsql security definer set search_path='' as $$declare d finance.dimensions%rowtype;begin
 if i is null then return null;end if;
 select * into d from finance.dimensions where tenant_id=t and legal_entity_id=e and id=i and kind=k and status='active'
  and (branch_id is null or branch_id=b) for share;
 if not found then raise exception using errcode='22023',message='BUDGET_DIMENSION_UNAVAILABLE';end if;
 return jsonb_build_object('id',d.id,'tenant_id',t,'legal_entity_id',e,'branch_id',d.branch_id,
  'kind',d.kind,'version',d.version,'code',d.code,'name',d.name);
end$$;

alter function finance.manual_normalize(uuid,uuid,uuid,jsonb) rename to manual_normalize_before_dimensions;
create function finance.manual_normalize(t uuid,e uuid,b uuid,p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare normalized jsonb;rawlines jsonb;line jsonb;raw jsonb;lines jsonb:='[]';dims jsonb;basis jsonb;
 reversal uuid:=(p->>'reversal_of_id')::uuid;k text;id_key text;begin
 normalized:=finance.manual_normalize_before_dimensions(t,e,b,p);
 if reversal is null then rawlines:=p->'lines';else select snapshot->'lines' into rawlines from finance.manual_journals
  where tenant_id=t and legal_entity_id=e and branch_id=b and id=reversal and status='posted';end if;
 for line in select value from jsonb_array_elements(normalized->'lines') loop
  select value into raw from jsonb_array_elements(rawlines) where value->>'line_id'=line->>'line_id';
  dims:='{}';
  foreach k in array array['cost_centre','project'] loop
   id_key:=k||'_id';
   if raw->>id_key is not null then
    if reversal is null then basis:=finance.dimension_basis(t,e,b,(raw->>id_key)::uuid,k);
    else
     basis:=raw#>array['dimension_snapshot',k];
     if basis->>'id' is distinct from raw->>id_key or basis->>'tenant_id' is distinct from t::text
      or basis->>'legal_entity_id' is distinct from e::text then raise exception using errcode='55000',message='DIMENSION_REVERSAL_BASIS_INVALID';end if;
    end if;
    dims:=dims||jsonb_build_object(k,basis);
    line:=line||jsonb_build_object(id_key,raw->>id_key,
     case k when 'cost_centre' then 'cost_center' else 'project' end,(basis->>'code')||' · '||(basis->>'name'));
   end if;
  end loop;
  if dims<>'{}' then line:=line||jsonb_build_object('dimension_snapshot',dims);end if;
  lines:=lines||jsonb_build_array(line);
 end loop;
 return normalized||jsonb_build_object('lines',lines);
end$$;

alter table finance.journal_lines
 add column cost_centre_id uuid,add column project_id uuid,add column dimension_snapshot jsonb,
 add foreign key(tenant_id,legal_entity_id,cost_centre_id) references finance.dimensions(tenant_id,legal_entity_id,id),
 add foreign key(tenant_id,legal_entity_id,project_id) references finance.dimensions(tenant_id,legal_entity_id,id);
create index journal_cost_centre on finance.journal_lines(tenant_id,legal_entity_id,cost_centre_id,posting_date);
create index journal_project on finance.journal_lines(tenant_id,legal_entity_id,project_id,posting_date);
create function finance.capture_manual_dimensions() returns trigger language plpgsql security definer set search_path='' as $$
declare j finance.journal_entries%rowtype;line jsonb;begin
 if new.cost_centre_id is not null or new.project_id is not null or new.dimension_snapshot is not null then
  raise exception using errcode='22023',message='DIMENSION_SOURCE_REQUIRED';end if;
 select * into j from finance.journal_entries where tenant_id=new.tenant_id and id=new.journal_entry_id;
 if j.source_type='manual_journal' then
  select x into line from finance.manual_journals d cross join lateral jsonb_array_elements(d.snapshot->'lines')x
   where d.tenant_id=j.tenant_id and d.legal_entity_id=j.legal_entity_id and d.branch_id=j.branch_id
    and d.id=j.source_id and d.status='approved' and x->>'line_id'=new.source_line_id::text;
  if line is null then raise exception using errcode='55000',message='DIMENSION_MANUAL_SOURCE_INVALID';end if;
  new.cost_centre_id:=(line->>'cost_centre_id')::uuid;new.project_id:=(line->>'project_id')::uuid;
  new.dimension_snapshot:=line->'dimension_snapshot';
 end if;
 return new;
end$$;
create trigger capture_manual_dimensions before insert on finance.journal_lines for each row execute function finance.capture_manual_dimensions();

create function finance.validate_dimension_budget_lines(t uuid,e uuid,b uuid,lines jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare x jsonb;y jsonb;out_rows jsonb:='[]';ids uuid[]:='{}';i uuid;a uuid;cost uuid;project uuid;amount text;dims jsonb;basis jsonb;k text;begin
 if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) not between 1 and 500 then
  raise exception using errcode='22023',message='BUDGET_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(lines) loop
  if jsonb_typeof(x) is distinct from 'object' then raise exception using errcode='22023',message='BUDGET_LINE_INVALID';end if;
  i:=(x->>'id')::uuid;a:=(x->>'account_id')::uuid;cost:=(x->>'cost_centre_id')::uuid;project:=(x->>'project_id')::uuid;amount:=x->>'amount';
  if i is null or a is null or i=any(ids) or jsonb_typeof(x->'amount') is distinct from 'string' or amount is null
   or amount !~ '^\d+(\.\d{1,6})?$' or length(amount)>35 or amount::numeric>99999999999999 then
   raise exception using errcode='22023',message='BUDGET_LINE_INVALID';end if;
  if not exists(select 1 from finance.accounts where tenant_id=t and legal_entity_id=e and id=a and status='active' and is_posting) then
   raise exception using errcode='22023',message='BUDGET_ACCOUNT_INVALID';end if;
  for y in select value from jsonb_array_elements(out_rows) where value->>'account_id'=a::text loop
   if (cost is null or y->>'cost_centre_id' is null or y->>'cost_centre_id'=cost::text)
    and (project is null or y->>'project_id' is null or y->>'project_id'=project::text) then
    raise exception using errcode='22023',message='BUDGET_DIMENSION_OVERLAP';end if;
  end loop;
  dims:='{}';
  foreach k in array array['cost_centre','project'] loop
   basis:=finance.dimension_basis(t,e,b,(x->>(k||'_id'))::uuid,k);
   if basis is not null then dims:=dims||jsonb_build_object(k,basis);end if;
  end loop;
  ids:=array_append(ids,i);
  out_rows:=out_rows||jsonb_build_array(jsonb_build_object('id',i,'account_id',a,'amount',(amount::numeric(20,6))::text,
   'cost_centre_id',cost,'project_id',project)||case when dims='{}' then '{}'::jsonb else jsonb_build_object('dimension_snapshot',dims) end);
 end loop;
 return out_rows;
end$$;

-- API budget/variance replacements below preserve shared engines and old unassigned budgets.
revoke all on function finance.guard_dimension(),finance.dimension_basis(uuid,uuid,uuid,uuid,text),
 finance.manual_normalize_before_dimensions(uuid,uuid,uuid,jsonb),finance.manual_normalize(uuid,uuid,uuid,jsonb),
 finance.capture_manual_dimensions(),finance.validate_dimension_budget_lines(uuid,uuid,uuid,jsonb),
 api.financial_dimension_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.financial_dimensions(uuid,uuid,uuid,text,uuid,text,boolean) from public,anon,authenticated;
grant execute on function api.financial_dimension_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.financial_dimensions(uuid,uuid,uuid,text,uuid,text,boolean) to authenticated;

create or replace function api.budget_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_payload jsonb,p_expected_entity_version bigint default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare t uuid:=p_tenant_id;e uuid:=p_legal_entity_id;b uuid:=p_branch_id;
 act text:=p_payload->>'action';v_id uuid:=(p_payload->>'id')::uuid;
 source_id uuid:=(p_payload->>'source_id')::uuid;
 budget finance.budget_versions%rowtype;source_budget finance.budget_versions%rowtype;
 period finance.fiscal_periods%rowtype;year_value integer;budget_branch uuid;
 currency text;reason text:=trim(p_payload->>'reason');v_lines jsonb;
 before_row jsonb;result jsonb;h text;r jsonb;req uuid:=gen_random_uuid();begin
 perform core.wave3_require_scope(t,case when act in('approve','reject') then
  'finance.budgets.approve' else 'finance.budgets.manage' end,e,null);
 perform core.wave3_require_scope(t,case when act in('approve','reject') then
  'finance.budgets.approve' else 'finance.budgets.manage' end,e,b);
 if act not in('create','save','submit','approve','reject','revise') or act is null
  or v_id is null or p_client_timestamp is null or reason is null
  or length(reason) not between 3 and 1000 then
  raise exception using errcode='22023',message='BUDGET_COMMAND_INVALID';end if;
 h:=core.wave3_request_hash('finance.budgets.'||act,p_command_id,t,e,b,p_payload,p_expected_entity_version);
 r:=core.wave3_replay(t,'finance.budgets.'||act,p_command_id,p_idempotency_key,h);
 if r is not null then return r;end if;
 if act in('create','revise') then
  if act='revise' then
   select * into source_budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
    and id=source_id and status='approved' for update;
   if not found then raise exception using errcode='55000',message='BUDGET_APPROVED_SOURCE_REQUIRED';end if;
   if source_budget.branch_id is not null and source_budget.branch_id<>b then
    raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
   perform core.wave3_assert_expected_version(source_budget.version,
    p_expected_entity_version,to_jsonb(source_budget));
   if exists(select 1 from finance.budget_versions where tenant_id=t and root_id=source_budget.root_id
    and revision>source_budget.revision) then
    raise exception using errcode='40001',message='VERSION_CONFLICT';end if;
   v_lines:=source_budget.lines;budget_branch:=source_budget.branch_id;
   year_value:=source_budget.budget_year;currency:=source_budget.currency_code;
   budget.period_id:=source_budget.period_id;
  else
   perform core.wave3_assert_expected_version(0,p_expected_entity_version,'{}');
   budget.period_id:=(p_payload->>'period_id')::uuid;
   year_value:=(p_payload->>'budget_year')::integer;
   budget_branch:=(p_payload->>'branch_id')::uuid;
   currency:=p_payload->>'currency_code';
   if budget_branch is not null and budget_branch<>b then
    raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
   if budget_branch is not null and not exists(select 1 from core.branches
    where tenant_id=t and legal_entity_id=e and id=budget_branch and status='active') then
    raise exception using errcode='22023',message='BUDGET_BRANCH_INVALID';end if;
   if year_value not between 2000 and 2100 or year_value is null
    or currency is null or not exists(select 1 from core.currencies where code=currency) then
    raise exception using errcode='22023',message='BUDGET_BASIS_INVALID';end if;
   if budget.period_id is not null then
    select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
     and id=budget.period_id and status='active';
    if not found or extract(year from period.start_date)::integer<>year_value then
     raise exception using errcode='22023',message='BUDGET_PERIOD_INVALID';end if;
   end if;
   v_lines:=finance.validate_dimension_budget_lines(t,e,budget_branch,p_payload->'lines');
  end if;
  insert into finance.budget_versions(id,tenant_id,legal_entity_id,root_id,revision,
   period_id,budget_year,branch_id,currency_code,lines,status,version,reason,created_by)
  values(v_id,t,e,case when act='create' then v_id else source_budget.root_id end,
   case when act='create' then 1 else source_budget.revision+1 end,budget.period_id,
   year_value,budget_branch,currency,v_lines,'draft',1,reason,auth.uid());
 else
  select * into budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
   and id=v_id for update;
  if not found then raise exception using errcode='42501',message='BUDGET_SCOPE_REQUIRED';end if;
  if budget.branch_id is not null and budget.branch_id<>b then
   raise exception using errcode='42501',message='BUDGET_BRANCH_SCOPE_REQUIRED';end if;
  perform core.wave3_assert_expected_version(budget.version,p_expected_entity_version,to_jsonb(budget));
  before_row:=to_jsonb(budget);
  if act in('save','submit') and budget.status<>'draft' or
   act in('approve','reject') and budget.status<>'submitted' then
   raise exception using errcode='55000',message='BUDGET_STATE_INVALID';end if;
  if act in('approve','reject') and auth.uid() in(budget.created_by,budget.submitted_by) then
   raise exception using errcode='42501',message='SEGREGATION_OF_DUTIES_VIOLATION';end if;
  if act in('submit','approve') and finance.validate_dimension_budget_lines(t,e,budget.branch_id,budget.lines) is distinct from budget.lines then
   raise exception using errcode='55000',message='BUDGET_DIMENSION_REAPPROVAL_REQUIRED';end if;
  if act='save' then
   v_lines:=finance.validate_dimension_budget_lines(t,e,budget.branch_id,p_payload->'lines');
   update finance.budget_versions set lines=v_lines,version=version+1,updated_at=now()
    where tenant_id=t and id=budget.id;
  else
   update finance.budget_versions set status=case act when 'submit' then 'submitted'
    when 'approve' then 'approved' else 'rejected' end,version=version+1,
    submitted_by=case when act='submit' then auth.uid() else submitted_by end,
    decided_by=case when act in('approve','reject') then auth.uid() else decided_by end,
    decided_at=case when act in('approve','reject') then now() else decided_at end,
    updated_at=now() where tenant_id=t and id=budget.id;
  end if;
 end if;
 select * into budget from finance.budget_versions v where v.tenant_id=t and v.id=v_id;
 insert into finance.budget_events(tenant_id,legal_entity_id,budget_id,version,action,reason,snapshot,actor_id)
 values(t,e,budget.id,budget.version,act,reason,to_jsonb(budget),auth.uid());
 result:=jsonb_build_object('id',budget.id,'tenant_id',t,'legal_entity_id',e,
  'branch_id',b,'budget_branch_id',budget.branch_id,'root_id',budget.root_id,
  'revision',budget.revision,'period_id',budget.period_id,'budget_year',budget.budget_year,
  'currency_code',budget.currency_code,'line_count',jsonb_array_length(budget.lines),
  'lines',budget.lines,'status',budget.status,'version',budget.version,
  'reason',budget.reason,'created_by',budget.created_by);
 return core.wave3_finish_command(t,'finance.budgets.'||act,p_command_id,'budget',v_id,
  p_idempotency_key,h,before_row,result,e,b,
  jsonb_build_object('period_id',budget.period_id,'root_id',budget.root_id),
  jsonb_build_object('to_status',budget.status,'revision',budget.revision,'reason',reason),
  jsonb_build_array(jsonb_build_object('topic','finance.budgets.'||act,'payload',result)),
  '[]',req,req);
end$$;


create or replace function finance.build_budget_variance(t uuid,e uuid,b uuid,budget_id uuid,d date,report_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare budget finance.budget_versions%rowtype;period finance.fiscal_periods%rowtype;
 start_date date;end_date date;base_currency text;x jsonb;a finance.accounts%rowtype;
 actual numeric;planned numeric;total_budget numeric:=0;total_actual numeric:=0;
 rows jsonb:='[]';journals jsonb:='[]';source_rows jsonb;source_count integer;
 summary jsonb;result jsonb;begin
 perform core.wave3_require_scope(t,'finance.view',e,null);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 select * into budget from finance.budget_versions where tenant_id=t and legal_entity_id=e
  and id=budget_id and status='approved' and (branch_id is null or branch_id=b);
 if not found then raise exception using errcode='42501',message='APPROVED_BUDGET_REQUIRED';end if;
 if budget.period_id is not null then
  select * into period from finance.fiscal_periods where tenant_id=t and legal_entity_id=e
   and id=budget.period_id;
  start_date:=period.start_date;end_date:=period.end_date;
 else start_date:=make_date(budget.budget_year,1,1);
  end_date:=make_date(budget.budget_year,12,31);end if;
 if d is null or d<start_date or d>end_date or d>(clock_timestamp() at time zone 'UTC')::date then
  raise exception using errcode='22023',message='BUDGET_VARIANCE_DATE_INVALID';end if;
 select currency_code into base_currency from core.legal_entities
  where tenant_id=t and id=e;
 for x in select value from jsonb_array_elements(budget.lines) loop
  select * into a from finance.accounts where tenant_id=t and legal_entity_id=e
   and id=(x->>'account_id')::uuid;
  select coalesce(sum(case when a.normal_balance='debit' then
    case when budget.currency_code=base_currency then l.base_debit-l.base_credit
     else l.transaction_debit-l.transaction_credit end
   else case when budget.currency_code=base_currency then l.base_credit-l.base_debit
     else l.transaction_credit-l.transaction_debit end end),0),
   coalesce(jsonb_agg(jsonb_build_object('id',l.id,'budget_line_id',x->>'id',
    'journal_entry_id',j.id,'posting_date',j.posting_date,'document_number',j.document_number,
    'account_id',a.id,'branch_id',j.branch_id,'currency_code',j.currency_code,
    'base_debit',l.base_debit::text,'base_credit',l.base_credit::text,
    'transaction_debit',l.transaction_debit::text,
    'transaction_credit',l.transaction_credit::text,'source_type',j.source_type,
    'source_id',j.source_id,'cost_centre_id',l.cost_centre_id,'project_id',l.project_id,
    'dimension_snapshot',l.dimension_snapshot) order by j.posting_date,j.id,l.id),'[]')
   into actual,source_rows
  from finance.journal_lines l join finance.journal_entries j
   on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where l.tenant_id=t and l.legal_entity_id=e and l.account_id=a.id
   and j.status='posted' and j.posting_date between start_date and d
   and (budget.branch_id is null or j.branch_id=budget.branch_id)
   and (budget.currency_code=base_currency or j.currency_code=budget.currency_code)
   and (x->>'cost_centre_id' is null or l.cost_centre_id=(x->>'cost_centre_id')::uuid)
   and (x->>'project_id' is null or l.project_id=(x->>'project_id')::uuid);
  planned:=(x->>'amount')::numeric;total_budget:=total_budget+planned;
  total_actual:=total_actual+actual;
  rows:=rows||jsonb_build_array(jsonb_build_object('id',x->>'id','account_id',a.id,
   'code',a.code,'name',a.name,'normal_balance',a.normal_balance,
   'cost_centre_id',x->'cost_centre_id','project_id',x->'project_id',
   'dimension_snapshot',x->'dimension_snapshot',
   'budget_amount',planned::text,'actual_amount',actual::text,
   'variance',(actual-planned)::text,
   'variance_percent',case when planned=0 then null else round((actual-planned)*100/planned,6)::text end,
   'source_count',jsonb_array_length(source_rows)));
  journals:=journals||source_rows;
  if jsonb_array_length(journals)>10000 then
   raise exception using errcode='54000',message='BUDGET_VARIANCE_SOURCE_LIMIT';end if;
 end loop;
 source_count:=jsonb_array_length(journals);
 summary:=jsonb_build_object('id',report_id,'tenant_id',t,'legal_entity_id',e,
  'branch_id',b,'budget_id',budget_id,'budget_root_id',budget.root_id,
  'budget_revision',budget.revision,'period_id',budget.period_id,
  'budget_year',budget.budget_year,'budget_branch_id',budget.branch_id,
  'as_of',d,'period_start',start_date,'period_end',end_date,
  'currency_code',budget.currency_code,'base_currency_code',base_currency,
  'currency_basis',case when budget.currency_code=base_currency then 'base_all_posted'
   else 'matching_transaction_only' end,'generated_at',now(),
  'status','generated','version',1,'line_count',jsonb_array_length(rows),
  'journal_count',source_count,'budget_total',total_budget::text,
  'actual_total',total_actual::text,'variance_total',(total_actual-total_budget)::text,
  'variance_percent',case when total_budget=0 then null
   else round((total_actual-total_budget)*100/total_budget,6)::text end);
 result:=jsonb_build_object('summary',summary,'lines',rows,'journals',journals);
 if octet_length(result::text)>16777216 then
  raise exception using errcode='54000',message='BUDGET_VARIANCE_EVIDENCE_LIMIT';end if;
 return result;
end$$;


notify pgrst,'reload schema';
