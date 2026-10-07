-- Uninstalled additive milestone candidate. Requires projects/time and finance.
-- Existing permission codes are used; no role, plan, entitlement or provider activation.
create table projects.milestones(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 version bigint not null default 1 check(version between 1 and 9007199254740990),current_revision_id uuid not null,
 status text not null default 'draft' check(status in('draft','submitted','approved','rejected','cancelled')),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),submitted_by uuid references auth.users(id),
 unique(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id) references projects.register(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create table projects.milestone_revisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,project_id uuid not null,milestone_id uuid not null,version bigint not null,
 plan_id uuid not null,task_id uuid not null,task_name text not null,owner_id uuid not null,owner_name text not null,
 customer_id uuid not null,customer_name text not null,currency_code text not null references core.currencies(code),precision integer not null check(precision between 0 and 6),
 name text not null,due_date date not null,amount numeric(20,6) not null check(amount>=0),commercial_terms text not null,
 payment_terms text not null,payment_due_days integer not null check(payment_due_days between 0 and 365),evidence_reference text not null,
 digest text not null check(digest~'^[a-f0-9]{64}$'),reason text not null,supersedes_id uuid references projects.milestone_revisions(id),
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,project_id,milestone_id,id),unique(milestone_id,version),
 foreign key(tenant_id,legal_entity_id,project_id,milestone_id) references projects.milestones(tenant_id,legal_entity_id,project_id,id),
 foreign key(tenant_id,legal_entity_id,project_id,plan_id,task_id) references projects.tasks(tenant_id,legal_entity_id,project_id,plan_id,id),
 foreign key(tenant_id,legal_entity_id,owner_id) references people.employees(tenant_id,legal_entity_id,id),foreign key(tenant_id,customer_id) references crm.parties(tenant_id,id)
);
alter table projects.milestones add constraint milestone_current_revision foreign key(tenant_id,legal_entity_id,project_id,id,current_revision_id)
 references projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id) deferrable initially deferred;
create table projects.milestone_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,project_id uuid not null,
 milestone_id uuid not null,revision_id uuid not null,version bigint not null,action text not null,digest text not null,reason text not null,
 eligibility jsonb not null default '{}',actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(milestone_id,version),foreign key(tenant_id,legal_entity_id,project_id,milestone_id,revision_id)
 references projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id)
);
create index milestone_scope_idx on projects.milestones(tenant_id,legal_entity_id,branch_id,project_id,id);
create index milestone_revision_scope_idx on projects.milestone_revisions(tenant_id,legal_entity_id,project_id,milestone_id,id);
create index milestone_event_scope_idx on projects.milestone_events(tenant_id,legal_entity_id,branch_id,project_id,milestone_id,id);
do $$declare n text;begin foreach n in array array['milestones','milestone_revisions','milestone_events'] loop
 execute format('alter table projects.%I enable row level security',n);execute format('alter table projects.%I force row level security',n);
 execute format('revoke all on projects.%I from public,anon,authenticated,service_role',n);
 if n<>'milestones' then execute format('create trigger immutable before update or delete on projects.%I for each row execute function projects.immutable()',n);end if;
end loop;end $$;
create function projects.milestone_cap(a text) returns text language sql immutable set search_path='' as $$
 select case when a in('create','correct','submit','cancel') then 'projects.manage' when a in('approve','reject') then 'projects.approve' end $$;
create function projects.milestone_summary(p uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',m.id,'tenant_id',m.tenant_id,'legal_entity_id',m.legal_entity_id,'branch_id',m.branch_id,'project_id',m.project_id,
 'version',m.version,'status',m.status,'revision_id',r.id,'plan_id',r.plan_id,'task_id',r.task_id,'task_name',r.task_name,'owner_id',r.owner_id,'owner_name',r.owner_name,
 'customer_id',r.customer_id,'customer_name',r.customer_name,'currency_code',r.currency_code,'precision',r.precision,'name',r.name,'due_date',r.due_date,
 'amount',r.amount::text,'commercial_terms',r.commercial_terms,'payment_terms',r.payment_terms,'payment_due_days',r.payment_due_days,
 'evidence_reference',r.evidence_reference,'digest',r.digest,'recorded_by',r.recorded_by,'reason',r.reason,'unit_status',u.status)
 from projects.milestones m join projects.milestone_revisions r on r.id=m.current_revision_id
 left join projects.billable_units u on u.source_kind='milestone' and u.source_id=r.id where m.id=p $$;
create function projects.milestone_owner(t uuid,e uuid,b uuid,employee uuid,d date) returns text language plpgsql security definer set search_path='' as $$
declare answer text;begin
 select x.display_name into answer from people.employees x where x.tenant_id=t and x.legal_entity_id=e and x.id=employee
 and exists(select 1 from people.employment_assignments a join people.employment_spells s on s.id=a.spell_id
  where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=x.id
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> d and daterange(s.start_date,s.end_date_exclusive,'[)') @> d);
 if answer is null then raise exception using errcode='55000',message='MILESTONE_OWNER_COVERAGE_REQUIRED';end if;return answer;end $$;
create function api.project_milestone_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_idempotency_key uuid,
 p_issued_at timestamptz,p_payload jsonb,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare act text:=p_payload->>'action';id uuid;project uuid;cap text;hash text;replay jsonb;reason text;allowed text[];
 pr projects.register%rowtype;m projects.milestones%rowtype;r projects.milestone_revisions%rowtype;task projects.tasks%rowtype;
 new_revision uuid:=gen_random_uuid();owner uuid;owner_name text;customer_name text;amount numeric;due date;digest text;version bigint;
 before_state jsonb:='{}';after_state jsonb;progress projects.task_progress%rowtype;eligibility jsonb:='{}';begin
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>65536 or p_command_id is null or p_idempotency_key is null
  or p_issued_at is null or p_issued_at>clock_timestamp()+interval '5 minutes' or p_expected_version is null or p_expected_version not between 0 and 9007199254740990 then
  raise exception using errcode='22023',message='MILESTONE_COMMAND_INVALID';end if;
 cap:=projects.milestone_cap(act);perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 id:=(p_payload->>'id')::uuid;project:=(p_payload->>'project_id')::uuid;reason:=projects.text(p_payload->'reason',1000);
 if id is null or project is null then raise exception using errcode='22023',message='MILESTONE_ID_REQUIRED';end if;
 allowed:=case when act in('create','correct') then array['action','id','project_id','plan_id','task_id','owner_id','name','due_date','amount','commercial_terms','payment_terms','payment_due_days','evidence_reference','reason'] else array['action','id','project_id','digest','reason'] end;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(allowed)) then raise exception using errcode='22023',message='MILESTONE_FIELDS_INVALID';end if;
 hash:=core.wave3_request_hash('projects.milestone.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'projects.milestone.'||act,p_command_id,p_idempotency_key,hash);if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 select x.* into m from projects.milestones x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.project_id=project and x.id=id;
 select x.* into r from projects.milestone_revisions x where x.id=m.current_revision_id;
 owner:=case when act in('create','correct') then(p_payload->>'owner_id')::uuid else r.owner_id end;
 perform x.id from people.employees x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.id=owner for update;
 select x.* into pr from projects.register x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.branch_id=p_branch_id and x.id=project for update;
 if pr.id is null then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 if pr.status<>'open' then raise exception using errcode='55000',message='PROJECT_CLOSED';end if;
 select x.* into m from projects.milestones x where x.id=id and x.project_id=project for update;
 if act='create' then
  if m.id is not null or p_expected_version<>0 then raise exception using errcode='40001',message='MILESTONE_VERSION_CONFLICT';end if;version:=1;
 else
  if m.id is null then raise exception using errcode='P0002',message='MILESTONE_NOT_FOUND';end if;
  before_state:=jsonb_build_object('id',m.id,'version',m.version,'status',m.status,'revision_id',m.current_revision_id);
  perform core.wave3_assert_expected_version(m.version,p_expected_version,before_state);version:=m.version+1;
 end if;
 if act in('create','correct') then
  if act='correct' then
   if m.status not in('draft','rejected','approved') then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if exists(select 1 from projects.billable_units where source_kind='milestone' and source_id=m.current_revision_id and status not in('available','cancelled')) then
    raise exception using errcode='55000',message='MILESTONE_BILLING_IMPACT_REQUIRED';end if;
   update projects.billable_units set status='cancelled' where source_kind='milestone' and source_id=m.current_revision_id and status='available';
  end if;
  if pr.customer_id is null or pr.current_plan_id is distinct from(p_payload->>'plan_id')::uuid or not exists(select 1 from projects.plans x where x.id=pr.current_plan_id and x.status='approved') then
   raise exception using errcode='55000',message='MILESTONE_APPROVED_PLAN_REQUIRED';end if;
  select x.* into task from projects.tasks x where x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id and x.project_id=project and x.plan_id=pr.current_plan_id and x.id=(p_payload->>'task_id')::uuid;
  if coalesce(p_payload->>'due_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception using errcode='22023',message='MILESTONE_DUE_TASK_INVALID';end if;
  due:=(p_payload->>'due_date')::date;
  if task.id is null or due is null or due<task.start_date or due>=task.end_date_exclusive or due<pr.start_date or due>=pr.end_date_exclusive then
   raise exception using errcode='22023',message='MILESTONE_DUE_TASK_INVALID';end if;
  owner_name:=projects.milestone_owner(p_tenant_id,p_legal_entity_id,p_branch_id,owner,due);
  select x.display_name into customer_name from crm.parties x where x.tenant_id=p_tenant_id and x.id=pr.customer_id and x.status='active' and x.kind in('customer','both');
  if customer_name is null then raise exception using errcode='55000',message='MILESTONE_ACTIVE_CUSTOMER_REQUIRED';end if;
  amount:=projects.amount(p_payload->'amount');if amount<>projects.ratio(amount*1000000,1,pr.precision) then raise exception using errcode='22023',message='PROJECT_AMOUNT_PRECISION';end if;
  if jsonb_typeof(p_payload->'payment_due_days') is distinct from 'number' or coalesce(p_payload->>'payment_due_days','') !~ '^(0|[1-9][0-9]{0,2})$'
   or(p_payload->>'payment_due_days')::integer>365 then raise exception using errcode='22023',message='MILESTONE_PAYMENT_DAYS_INVALID';end if;
  digest:=encode(extensions.digest((p_payload||jsonb_build_object('customer_id',pr.customer_id,'currency_code',pr.currency_code,'precision',pr.precision,'plan_terms',(select terms from projects.plans where id=pr.current_plan_id)))::text,'sha256'),'hex');
  if act='create' then insert into projects.milestones(id,tenant_id,legal_entity_id,branch_id,project_id,current_revision_id,created_by)
   values(id,p_tenant_id,p_legal_entity_id,p_branch_id,project,new_revision,auth.uid());end if;
  insert into projects.milestone_revisions(id,tenant_id,legal_entity_id,project_id,milestone_id,version,plan_id,task_id,task_name,owner_id,owner_name,customer_id,customer_name,
   currency_code,precision,name,due_date,amount,commercial_terms,payment_terms,payment_due_days,evidence_reference,digest,reason,supersedes_id,recorded_by)
  values(new_revision,p_tenant_id,p_legal_entity_id,project,id,version,pr.current_plan_id,task.id,task.name,owner,owner_name,pr.customer_id,customer_name,pr.currency_code,pr.precision,
   projects.text(p_payload->'name',160),due,amount,projects.text(p_payload->'commercial_terms',2000),projects.text(p_payload->'payment_terms',1000),
   (p_payload->>'payment_due_days')::integer,projects.text(p_payload->'evidence_reference',160),digest,reason,m.current_revision_id,auth.uid());
  if act='correct' then update projects.milestones set current_revision_id=new_revision,version=version,status='draft',submitted_by=null where milestones.id=id;end if;
 else
  if r.digest is distinct from p_payload->>'digest' then raise exception using errcode='40001',message='MILESTONE_VERSION_CONFLICT';end if;
  if act='submit' then
   if m.status<>'draft' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   update projects.milestones set status='submitted',submitted_by=auth.uid(),version=version where milestones.id=id;
  elsif act in('approve','reject') then
   if m.status<>'submitted' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if auth.uid() in(r.recorded_by,m.submitted_by) then raise exception using errcode='42501',message='MILESTONE_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if act='approve' then
    if pr.current_plan_id is distinct from r.plan_id or not exists(select 1 from projects.plans where plans.id=r.plan_id and status='approved') then raise exception using errcode='55000',message='MILESTONE_APPROVED_PLAN_REQUIRED';end if;
    select x.* into progress from projects.task_progress x where x.project_id=project and x.plan_id=r.plan_id and x.task_id=r.task_id order by x.project_version desc limit 1;
    if progress.id is null or progress.progress<>10000 then raise exception using errcode='55000',message='MILESTONE_TASK_INCOMPLETE';end if;
    perform projects.milestone_owner(p_tenant_id,p_legal_entity_id,p_branch_id,r.owner_id,r.due_date);
    if not exists(select 1 from crm.parties x where x.tenant_id=p_tenant_id and x.id=r.customer_id and x.status='active' and x.kind in('customer','both')) then
     raise exception using errcode='55000',message='MILESTONE_ACTIVE_CUSTOMER_REQUIRED';end if;
    eligibility:=jsonb_build_object('plan_id',r.plan_id,'task_id',r.task_id,'progress_event_id',progress.id,'project_version',pr.version,'progress',10000,'completion_evidence',r.evidence_reference);
    insert into projects.billable_units(id,tenant_id,legal_entity_id,project_id,branch_id,source_kind,source_id,source_version,source_digest,amount)
     values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,project,p_branch_id,'milestone',r.id,version,r.digest,r.amount);
   end if;
   update projects.milestones set status=case act when 'approve' then 'approved' else 'rejected' end,version=version where milestones.id=id;
  elsif act='cancel' then
   if m.status='cancelled' then raise exception using errcode='55000',message='MILESTONE_STATE_CONFLICT';end if;
   if exists(select 1 from projects.billable_units where source_kind='milestone' and source_id=r.id and status not in('available','cancelled')) then raise exception using errcode='55000',message='MILESTONE_BILLING_IMPACT_REQUIRED';end if;
   update projects.billable_units set status='cancelled' where source_kind='milestone' and source_id=r.id and status='available';
   update projects.milestones set status='cancelled',version=version where milestones.id=id;
  end if;
  new_revision:=r.id;digest:=r.digest;
 end if;
 insert into projects.milestone_events(tenant_id,legal_entity_id,branch_id,project_id,milestone_id,revision_id,version,action,digest,reason,eligibility,actor_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,project,id,new_revision,version,act,digest,reason,eligibility,auth.uid());
 select jsonb_build_object('id',x.id,'tenant_id',x.tenant_id,'legal_entity_id',x.legal_entity_id,'branch_id',x.branch_id,'project_id',x.project_id,
 'version',x.version,'status',x.status,'revision_id',x.current_revision_id) into after_state from projects.milestones x where x.id=id;
 return core.wave3_finish_command(p_tenant_id,'projects.milestone.'||act,p_command_id,'projects.milestone',id,p_idempotency_key,hash,before_state,after_state,p_legal_entity_id,p_branch_id);
end $$;
create function api.project_milestones(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if not exists(select 1 from projects.register where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_project_id) then raise exception using errcode='P0002',message='PROJECT_NOT_FOUND';end if;
 select coalesce(jsonb_agg(projects.milestone_summary(x.id) order by x.id),'[]') into items from(select id from projects.milestones where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and(p_after is null or id>p_after) order by id limit 50) x;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'project_id',p_project_id,'items',items,'next_after',case when jsonb_array_length(items)=50 then items->49->>'id' end);end $$;
create function api.project_milestone_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_id uuid,p_after uuid default null,p_kind text default 'events')
returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;events jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'projects.view');
 if not exists(select 1 from projects.milestones where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and project_id=p_project_id and id=p_id) then raise exception using errcode='P0002',message='MILESTONE_NOT_FOUND';end if;
 body:=projects.milestone_summary(p_id);
 if p_kind='events' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into events from(select * from projects.milestone_events where milestone_id=p_id and(p_after is null or id>p_after) order by id limit 50) x;
 elsif p_kind='revisions' then
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('amount',x.amount::text) order by x.id),'[]') into events from(select * from projects.milestone_revisions where milestone_id=p_id and(p_after is null or id>p_after) order by id limit 50) x;
 else raise exception using errcode='22023',message='MILESTONE_DETAIL_KIND_INVALID';end if;
 return jsonb_build_object('record',body,'kind',p_kind,'rows',events,'next_after',case when jsonb_array_length(events)=50 then events->49->>'id' end);end $$;
create function api.project_milestone_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_project_id uuid,p_idempotency_key uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;begin
 perform projects.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,projects.milestone_cap(p_action),true);
 select response into body from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
 and actor_id=auth.uid() and command_name='projects.milestone.'||p_action and idempotency_key=p_idempotency_key and(response#>>'{entity,project_id}')::uuid=p_project_id;
 return body;end $$;
create function projects.milestone_billing_terms(t uuid,e uuid,b uuid,source uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare body jsonb;begin
 select jsonb_build_object('customer_id',r.customer_id,'currency_code',r.currency_code,'amount',r.amount::text,'source_version',u.source_version,'digest',r.digest,
 'payment_due_days',r.payment_due_days,'payment_terms',r.payment_terms) into body
 from projects.milestone_revisions r join projects.milestones m on m.id=r.milestone_id join projects.billable_units u on u.source_id=r.id and u.source_kind='milestone'
 where m.tenant_id=t and m.legal_entity_id=e and m.branch_id=b and r.id=source
 and u.tenant_id=t and u.legal_entity_id=e and u.branch_id=b and u.project_id=m.project_id and u.source_digest=r.digest and u.amount=r.amount
 and exists(select 1 from projects.milestone_events a where a.milestone_id=m.id and a.revision_id=r.id and a.version=u.source_version and a.action='approve' and a.digest=r.digest);
 if body is null then raise exception using errcode='55000',message='MILESTONE_BILLING_SOURCE_CHANGED';end if;return body;end $$;
create function projects.milestone_closure_guard(t uuid,e uuid,project uuid) returns void language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from projects.milestones where tenant_id=t and legal_entity_id=e and project_id=project and status in('draft','submitted','rejected'))
 or exists(select 1 from projects.billable_units where tenant_id=t and legal_entity_id=e and project_id=project and source_kind='milestone' and status in('available','reserved')) then
  raise exception using errcode='55000',message='MILESTONE_CLOSURE_IMPACT_REQUIRED';end if;end $$;
revoke all on function projects.milestone_cap(text),projects.milestone_summary(uuid),projects.milestone_owner(uuid,uuid,uuid,uuid,date),
 projects.milestone_billing_terms(uuid,uuid,uuid,uuid),projects.milestone_closure_guard(uuid,uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function api.project_milestone_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.project_milestones(uuid,uuid,uuid,uuid,uuid),
 api.project_milestone_detail(uuid,uuid,uuid,uuid,uuid,uuid,text),api.project_milestone_own_receipt(uuid,uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function api.project_milestone_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),api.project_milestones(uuid,uuid,uuid,uuid,uuid),
 api.project_milestone_detail(uuid,uuid,uuid,uuid,uuid,uuid,text),api.project_milestone_own_receipt(uuid,uuid,uuid,uuid,uuid,text) to authenticated;
