-- UNAPPLIED W5-owned date authority. W4 stores, functions and grants are unchanged.
-- Depends on W5 dated-cash/export candidates. W4 providers are optional at install.
insert into core.permissions(code,module,description,privileged) values
 ('analytics.cash_dates.prepare','analytics','Propose authoritative obligation payment dates',true),
 ('analytics.cash_dates.approve','analytics','Independently review obligation payment dates',true)
on conflict(code) do nothing;

create table analytics.cash_date_proposals(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 source_kind text not null check(source_kind in('payroll_obligation','payroll_correction','project_reimbursement')),
 source_id uuid not null,source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
 expected_version bigint not null check(expected_version between 0 and 9007199254740990),
 due_date date not null check(due_date between date '0001-01-01' and date '9999-12-31'),
 reason_code text not null check(reason_code in('payroll_calendar','payment_terms','reviewed_reschedule','correction_recovery')),
 proposal_hash text not null check(proposal_hash ~ '^[a-f0-9]{64}$'),
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index cash_date_proposal_source_idx on analytics.cash_date_proposals(tenant_id,legal_entity_id,branch_id,source_kind,source_id,prepared_at,id);
create index cash_date_proposal_actor_idx on analytics.cash_date_proposals(prepared_by);
create table analytics.cash_date_decisions(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 proposal_id uuid not null unique,source_kind text not null,source_id uuid not null,
 decision text not null check(decision in('approved','rejected')),
 approved_version bigint check(approved_version between 1 and 9007199254740991),
 actor_id uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,source_kind,source_id,approved_version),
 foreign key(tenant_id,legal_entity_id,branch_id,proposal_id) references analytics.cash_date_proposals(tenant_id,legal_entity_id,branch_id,id),
 check((decision='approved')=(approved_version is not null))
);
create index cash_date_decision_source_idx on analytics.cash_date_decisions(tenant_id,legal_entity_id,branch_id,source_kind,source_id,recorded_at);
create index cash_date_decision_actor_idx on analytics.cash_date_decisions(actor_id);
alter table analytics.cash_date_proposals enable row level security;
alter table analytics.cash_date_proposals force row level security;
alter table analytics.cash_date_decisions enable row level security;
alter table analytics.cash_date_decisions force row level security;
revoke all on analytics.cash_date_proposals,analytics.cash_date_decisions from public,anon,authenticated;
create trigger immutable before update or delete on analytics.cash_date_proposals for each row execute function analytics.immutable_evidence();
create trigger immutable before update or delete on analytics.cash_date_decisions for each row execute function analytics.immutable_evidence();

create function analytics.cash_date_access(t uuid,e uuid,b uuid,k text,act text default 'read') returns void
language plpgsql stable security definer set search_path='' as $$declare branch uuid;cap text;module_code text;begin
 perform analytics.cash_access(t,e,b);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='CASH_DATES_MFA_REQUIRED';end if;
 if k not in('payroll_obligation','payroll_correction','project_reimbursement') or k is null or act not in('read','prepare','approve') or act is null then
  raise exception using errcode='22023',message='CASH_DATE_SOURCE_INVALID';end if;
 module_code:=case k when 'project_reimbursement' then 'module.projects' else 'module.people' end;
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code=module_code and p.enabled
   and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
    or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='CASH_DATE_SOURCE_ENTITLEMENT_REQUIRED';end if;
 if k='project_reimbursement' then
  perform core.wave3_require_scope(t,'projects.view',e,b);perform core.wave3_require_scope(t,'projects.cost.view',e,b);
  if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
   where s.tenant_id=t and p.entitlement_code='module.finance' and p.enabled
    and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
     or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
   raise exception using errcode='42501',message='CASH_DATE_SOURCE_ENTITLEMENT_REQUIRED';end if;
 else
  perform core.wave3_require_scope(t,'people.view',e,b);perform core.wave3_require_scope(t,'people.payroll.view',e,b);
 end if;
 if act<>'read' then
  if b is null then raise exception using errcode='42501',message='CASH_DATE_BRANCH_REQUIRED';end if;
  perform core.wave3_require_scope(t,'analytics.cash_dates.'||act,e,b);
 end if;
 -- Entity-wide completeness is conservative: every active branch must be readable.
 for branch in select id from core.branches where tenant_id=t and legal_entity_id=e and status='active' and (b is null or id=b) loop
  if k='project_reimbursement' then
   cap:=case act when 'prepare' then 'projects.expenses.settle' when 'approve' then 'projects.expenses.approve' else 'projects.cost.view' end;
   if to_regprocedure('projects.finance_access(uuid,uuid,uuid,text,boolean)') is null then
    raise exception using errcode='55000',message='CASH_DATE_SOURCE_NOT_INSTALLED';end if;
   execute 'select projects.finance_access($1,$2,$3,$4,false)' using t,e,branch,cap;
  else
   cap:=case act when 'prepare' then 'people.payroll.settle' when 'approve' then case k when 'payroll_correction' then 'people.payroll.correction.approve' else 'people.payroll.approve' end else 'people.payroll.view' end;
   execute 'select people.require_access($1,$2,$3,$4)' using t,e,branch,cap;
   perform core.wave3_require_scope(t,'people.payroll.view',e,branch);
  end if;
 end loop;
end $$;

create function analytics.cash_source_installed(k text) returns boolean
language sql stable security definer set search_path='' as $$select case k
 when 'payroll_obligation' then to_regclass('people_payroll.obligations') is not null and to_regclass('people_payroll.obligation_effects') is not null and to_regclass('people_payroll.settlements') is not null
 when 'payroll_correction' then to_regclass('people_payroll.correction_balances') is not null and to_regclass('people_payroll.correction_balance_effects') is not null and to_regclass('people_payroll.correction_settlements') is not null
 when 'project_reimbursement' then to_regclass('projects.reimbursements') is not null and to_regclass('projects.reimbursement_effects') is not null
 else false end$$;

-- Private adapter over ACTUAL W4 stores. No shape shims, duplicated balances or dates.
create function analytics.cash_source_rows(t uuid,e uuid,b uuid,k text,before_date date,through_time timestamptz)
returns setof jsonb language plpgsql stable security definer set search_path='' as $$
declare q text;r record;source_hash text;proof jsonb;n integer:=0;begin
 if not analytics.cash_source_installed(k) then raise exception using errcode='55000',message='CASH_DATE_SOURCE_NOT_INSTALLED';end if;
 if k in('payroll_obligation','payroll_correction') then
  q:=format($q$with effects as (
   select o.id,o.branch_id,o.currency_code,o.account_id,o.amount original_amount,
    i.id issue_id,i.recorded_at issue_recorded_at,ij.id issue_journal,ij.posting_date issue_date,
    ef.id effect_id,ef.kind,ef.amount,ef.recorded_at,j.id journal_id,j.posting_date,j.status journal_status
   from %1$s o join %2$s p on p.tenant_id=o.tenant_id and p.legal_entity_id=o.legal_entity_id and p.id=o.%3$I
   join %4$s i on i.tenant_id=o.tenant_id and i.legal_entity_id=o.legal_entity_id and i.%5$I=o.id and i.kind='issue'
   join finance.journal_entries ij on ij.tenant_id=o.tenant_id and ij.id=p.posted_journal_id and ij.status='posted'
   join %4$s ef on ef.tenant_id=o.tenant_id and ef.legal_entity_id=o.legal_entity_id and ef.%5$I=o.id
   left join %6$s s on s.tenant_id=o.tenant_id and s.legal_entity_id=o.legal_entity_id and s.id=ef.source_id and ef.kind in('settle','settlement_reverse')
   left join finance.journal_entries j on j.tenant_id=o.tenant_id and j.id=case ef.kind when 'issue' then p.posted_journal_id
    when %7$L then p.reversal_journal_id when 'settle' then s.journal_id when 'settlement_reverse' then s.reversal_journal_id end
   where o.tenant_id=$1 and o.legal_entity_id=$2 and ($3 is null or o.branch_id=$3)
    and i.recorded_at<=$5 and ij.created_at<=$5 and ij.posting_date<$4 and ef.recorded_at<=$5
  ) select id,branch_id,currency_code,account_id,original_amount,issue_id,issue_journal,issue_date,
   coalesce(sum(amount) filter(where posting_date<$4),0) remaining,
   bool_or(journal_id is null or journal_status<>'posted') invalid,
   coalesce(jsonb_agg(jsonb_build_object('id',effect_id,'kind',kind,'amount',amount::text,'journalId',journal_id,
    'postingDate',posting_date::text,'recordedAt',analytics.process_utc(recorded_at)) order by effect_id) filter(where posting_date<$4),'[]') effects
  from effects group by id,branch_id,currency_code,account_id,original_amount,issue_id,issue_journal,issue_date order by id limit 10001$q$,
   case k when 'payroll_obligation' then 'people_payroll.obligations' else 'people_payroll.correction_balances' end,
   case k when 'payroll_obligation' then 'people_payroll.runs' else 'people_payroll.corrections' end,
   case k when 'payroll_obligation' then 'run_id' else 'correction_id' end,
   case k when 'payroll_obligation' then 'people_payroll.obligation_effects' else 'people_payroll.correction_balance_effects' end,
   case k when 'payroll_obligation' then 'obligation_id' else 'balance_id' end,
   case k when 'payroll_obligation' then 'people_payroll.settlements' else 'people_payroll.correction_settlements' end,
   case k when 'payroll_obligation' then 'run_reverse' else 'correction_reverse' end);
 else
  q:=$q$select o.id,o.branch_id,o.currency_code,o.account_id,o.amount original_amount,
   i.id issue_id,o.journal_id issue_journal,o.posting_date issue_date,
   coalesce(sum(ef.amount) filter(where ef.posting_date<$4),0) remaining,
   bool_or(j.id is null or j.status<>'posted' or j.posting_date<>ef.posting_date) invalid,
   coalesce(jsonb_agg(jsonb_build_object('id',ef.id,'kind',ef.kind,'amount',ef.amount::text,'journalId',ef.journal_id,
    'postingDate',ef.posting_date::text,'recordedAt',analytics.process_utc(ef.recorded_at)) order by ef.id) filter(where ef.posting_date<$4),'[]') effects
  from projects.reimbursements o
  join projects.reimbursement_effects i on i.tenant_id=o.tenant_id and i.legal_entity_id=o.legal_entity_id and i.obligation_id=o.id and i.kind='issue'
  join finance.journal_entries ij on ij.tenant_id=o.tenant_id and ij.id=o.journal_id and ij.status='posted'
  join projects.reimbursement_effects ef on ef.tenant_id=o.tenant_id and ef.legal_entity_id=o.legal_entity_id and ef.obligation_id=o.id
  left join finance.journal_entries j on j.tenant_id=o.tenant_id and j.id=ef.journal_id
  where o.tenant_id=$1 and o.legal_entity_id=$2 and ($3 is null or o.branch_id=$3)
   and o.posting_date<$4 and o.recorded_at<=$5 and i.recorded_at<=$5 and ij.created_at<=$5 and ef.recorded_at<=$5
  group by o.id,o.branch_id,o.currency_code,o.account_id,o.amount,i.id,o.journal_id,o.posting_date order by o.id limit 10001$q$;
 end if;
 for r in execute q using t,e,b,before_date,through_time loop
  n:=n+1;if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
  if r.invalid or r.remaining*r.original_amount<0 or abs(r.remaining)>abs(r.original_amount) then
   raise exception using errcode='55000',message='CASH_SOURCE_INTEGRITY_REQUIRED';end if;
  proof:=jsonb_build_object('kind',k,'id',r.id,'tenantId',t,'legalEntityId',e,'branchId',r.branch_id,'currency',r.currency_code,
   'originalAmount',r.original_amount::text,'accountId',r.account_id,'issueId',r.issue_id,'journalId',r.issue_journal,'issueDate',r.issue_date::text);
  source_hash:=encode(extensions.digest(proof::text,'sha256'),'hex');
  return next jsonb_build_object('sourceKind',k,'sourceId',r.id,'sourceHash',source_hash,'branchId',r.branch_id,'currency',r.currency_code,
   'originalAmount',r.original_amount::text,'remainingAmount',r.remaining::text,'inflow',r.original_amount<0,'issueDate',r.issue_date::text,
   'issueId',r.issue_id,'issueJournalId',r.issue_journal,'effects',r.effects);
 end loop;
end $$;

create function analytics.cash_date_current(t uuid,e uuid,k text,i uuid,through_time timestamptz) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',p.id,'decisionId',d.id,'sourceHash',p.source_hash,'dueDate',p.due_date::text,'version',d.approved_version::text,
  'proposalHash',p.proposal_hash,'approvedAt',analytics.process_utc(d.recorded_at))
 from analytics.cash_date_decisions d join analytics.cash_date_proposals p on p.id=d.proposal_id
 where d.tenant_id=t and d.legal_entity_id=e and d.source_kind=k and d.source_id=i and d.decision='approved' and d.recorded_at<=through_time
 order by d.approved_version desc limit 1$$;

create function api.wave5_cash_date_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind);
 return auth.uid();end $$;

create function api.wave5_cash_date_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_kind text,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare rows jsonb;last_id uuid;n integer;begin
 perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind);
 if p_branch_id is null then raise exception using errcode='42501',message='CASH_DATE_BRANCH_REQUIRED';end if;
 with all_rows as(select x from analytics.cash_source_rows(p_tenant_id,p_legal_entity_id,p_branch_id,p_kind,
  (statement_timestamp() at time zone 'UTC')::date+1,statement_timestamp()) x),bounded as(
  select x from all_rows where (p_after is null or (x->>'sourceId')::uuid>p_after) and (x->>'remainingAmount')::numeric<>0 order by x->>'sourceId' limit 51)
 select coalesce(jsonb_agg((x-array['effects','issueId','issueJournalId'])||jsonb_build_object('approved',analytics.cash_date_current(p_tenant_id,p_legal_entity_id,p_kind,(x->>'sourceId')::uuid,statement_timestamp())) order by x->>'sourceId'),'[]'),count(*)
 into rows,n from bounded;
 if n=51 then last_id:=(rows->49->>'sourceId')::uuid;rows:=rows-50;end if;
 return jsonb_build_object('rows',rows,'next',last_id);
end $$;

create function api.wave5_cash_date_get(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare p analytics.cash_date_proposals%rowtype;d analytics.cash_date_decisions%rowtype;begin
 select * into p from analytics.cash_date_proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,p.source_kind);
 select * into d from analytics.cash_date_decisions where proposal_id=p.id;
 return jsonb_build_object('id',p.id,'sourceKind',p.source_kind,'sourceId',p.source_id,'sourceHash',p.source_hash,'dueDate',p.due_date::text,
  'reasonCode',p.reason_code,'proposalHash',p.proposal_hash,'expectedVersion',p.expected_version::text,'preparedBy',p.prepared_by,
  'preparedAt',analytics.process_utc(p.prepared_at),'decision',d.decision,'approvedVersion',d.approved_version::text,
  'currentApproval',analytics.cash_date_current(p_tenant_id,p_legal_entity_id,p.source_kind,p.source_id,statement_timestamp()));
end $$;

create function api.wave5_cash_date_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_issued_at timestamptz,p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare p analytics.cash_date_proposals%rowtype;r jsonb;cur jsonb;h text;replay jsonb;receipt jsonb;
 i uuid;k text;source uuid;version bigint;new_version bigint;due date;decision text;begin
 if p_command_id is null or p_idempotency_key is null or p_issued_at is null or not isfinite(p_issued_at)
  or p_issued_at>clock_timestamp()+interval '5 minutes' or p_action not in('prepare','approve','reject') or p_action is null
  or jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 then
  raise exception using errcode='22023',message='CASH_DATE_COMMAND_INVALID';end if;
 i:=(p_payload->>'id')::uuid;
 if p_action='prepare' then
  if not(p_payload ?& array['id','sourceKind','sourceId','sourceHash','dueDate','reasonCode','expectedVersion'])
   or (p_payload-array['id','sourceKind','sourceId','sourceHash','dueDate','reasonCode','expectedVersion'])<>'{}'
   or exists(select 1 from jsonb_each(p_payload) where jsonb_typeof(value)<>'string')
   or coalesce(p_payload->>'sourceHash','')!~'^[a-f0-9]{64}$' or coalesce(p_payload->>'expectedVersion','')!~'^(0|[1-9][0-9]{0,15})$'
   or coalesce(p_payload->>'dueDate','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(p_payload->>'reasonCode','') not in('payroll_calendar','payment_terms','reviewed_reschedule','correction_recovery') then
   raise exception using errcode='22023',message='CASH_DATE_COMMAND_INVALID';end if;
  k:=p_payload->>'sourceKind';source:=(p_payload->>'sourceId')::uuid;version:=(p_payload->>'expectedVersion')::bigint;due:=(p_payload->>'dueDate')::date;
 else
  if not(p_payload ?& array['id','proposalHash']) or (p_payload-array['id','proposalHash'])<>'{}'
   or exists(select 1 from jsonb_each(p_payload) where jsonb_typeof(value)<>'string') or coalesce(p_payload->>'proposalHash','')!~'^[a-f0-9]{64}$' then
   raise exception using errcode='22023',message='CASH_DATE_COMMAND_INVALID';end if;
  select * into p from analytics.cash_date_proposals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=i;
  if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
  k:=p.source_kind;source:=p.source_id;version:=p.expected_version;
 end if;
 perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,k,case when p_action='prepare' then 'prepare' else 'approve' end);
 h:=core.wave3_request_hash('analytics.cash_dates.'||p_action,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,
  jsonb_build_object('issuedAt',analytics.process_utc(p_issued_at),'payload',p_payload),version);
 replay:=core.wave3_replay(p_tenant_id,'analytics.cash_dates.'||p_action,p_command_id,p_idempotency_key,h);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':'||p_legal_entity_id::text||':'||k||':'||source::text,512));
 cur:=analytics.cash_date_current(p_tenant_id,p_legal_entity_id,k,source,clock_timestamp());
 if version is distinct from coalesce((cur->>'version')::bigint,0) then raise exception using errcode='40001',message='CASH_DATE_VERSION_CONFLICT';end if;
 select x into r from analytics.cash_source_rows(p_tenant_id,p_legal_entity_id,p_branch_id,k,
  (statement_timestamp() at time zone 'UTC')::date+1,clock_timestamp()) x where x->>'sourceId'=source::text;
 if r is null or (r->>'remainingAmount')::numeric=0 then raise exception using errcode='55000',message='CASH_DATE_ISSUED_SOURCE_REQUIRED';end if;
 if p_action='prepare' then
  if i is null or version not between 0 and 9007199254740990 or due not between date '0001-01-01' and date '9999-12-31'
   or due<(r->>'issueDate')::date then raise exception using errcode='22023',message='CASH_DATE_COMMAND_INVALID';end if;
  if p_payload->>'sourceHash' is distinct from r->>'sourceHash' then raise exception using errcode='40001',message='CASH_DATE_SOURCE_CHANGED';end if;
  insert into analytics.cash_date_proposals(id,tenant_id,legal_entity_id,branch_id,source_kind,source_id,source_hash,expected_version,due_date,reason_code,proposal_hash,prepared_by)
   values(i,p_tenant_id,p_legal_entity_id,p_branch_id,k,source,r->>'sourceHash',version,due,p_payload->>'reasonCode',
    encode(extensions.digest(jsonb_build_object('scope',jsonb_build_array(p_tenant_id,p_legal_entity_id,p_branch_id),'payload',p_payload)::text,'sha256'),'hex'),auth.uid()) returning * into p;
  receipt:=jsonb_build_object('id',p.id,'version',version::text,'status','prepared','proposalHash',p.proposal_hash);
 else
  if p.prepared_by=auth.uid() then raise exception using errcode='42501',message='CASH_DATE_INDEPENDENT_APPROVER_REQUIRED';end if;
  if p.proposal_hash is distinct from p_payload->>'proposalHash' then raise exception using errcode='40001',message='CASH_DATE_PROPOSAL_CHANGED';end if;
  if p.source_hash is distinct from r->>'sourceHash' then raise exception using errcode='40001',message='CASH_DATE_SOURCE_CHANGED';end if;
  if exists(select 1 from analytics.cash_date_decisions where proposal_id=i) then raise exception using errcode='55000',message='CASH_DATE_ALREADY_DECIDED';end if;
  decision:=case p_action when 'approve' then 'approved' else 'rejected' end;new_version:=case when p_action='approve' then version+1 end;
  insert into analytics.cash_date_decisions values(p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,i,k,source,decision,new_version,auth.uid(),clock_timestamp());
  receipt:=jsonb_build_object('id',i,'version',coalesce(new_version,version)::text,'status',decision,'proposalHash',p.proposal_hash);
 end if;
 return core.wave3_finish_command(p_tenant_id,'analytics.cash_dates.'||p_action,p_command_id,'analytics.cash_date',i,p_idempotency_key,h,null,
  receipt,p_legal_entity_id,p_branch_id);
end $$;

-- Extend rather than edit/replay the reviewed bank/AR/AP source.
alter function api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz) rename to wave5_cash_basis_v2;
revoke all on function api.wave5_cash_basis_v2(uuid,uuid,uuid,date,date,timestamptz) from public,anon,authenticated;
create function api.wave5_cash_basis(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_start date,p_end date,p_recorded_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare data jsonb;providers jsonb;statuses jsonb;family text;k text;row jsonb;d jsonb;rows jsonb;refs jsonb;st text;n integer;begin
 data:=(api.wave5_cash_basis_v2(p_tenant_id,p_legal_entity_id,p_branch_id,p_start,p_end,p_recorded_through)->>'canonicalText')::jsonb;
 providers:=data->'completeProviders';statuses:=data->'providerStatus';
 -- AR/AP use explicit directions in the new contract too.
 select coalesce(jsonb_agg(x||jsonb_build_object('inflow',x->>'provider'='receivables') order by x->>'provider',x->>'id'),'[]') into rows from jsonb_array_elements(data->'obligations') x;
 data:=jsonb_set(data,'{obligations}',rows);
 foreach family in array array['payroll','project_reimbursements'] loop
  rows:='[]';refs:='[]';st:='available';n:=0;
  if (family='payroll' and (not analytics.cash_source_installed('payroll_obligation') or not analytics.cash_source_installed('payroll_correction')))
   or (family='project_reimbursements' and not analytics.cash_source_installed('project_reimbursement')) then st:='source_not_installed';
  else
   begin
    perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,case family when 'payroll' then 'payroll_obligation' else 'project_reimbursement' end);
   exception when insufficient_privilege then st:=case when coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then 'mfa_required' else 'permission_required' end;end;
   if st='available' then
    foreach k in array case family when 'payroll' then array['payroll_obligation','payroll_correction'] else array['project_reimbursement'] end loop
     for row in select * from analytics.cash_source_rows(p_tenant_id,p_legal_entity_id,p_branch_id,k,p_start,p_recorded_through) loop
      n:=n+1;if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
      -- Also cover inactive source branches: no row may bypass current authority.
      begin perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,(row->>'branchId')::uuid,k);
      exception when insufficient_privilege then st:='permission_required';end;
      if (row->>'remainingAmount')::numeric=0 then continue;end if;
      d:=analytics.cash_date_current(p_tenant_id,p_legal_entity_id,k,(row->>'sourceId')::uuid,p_recorded_through);
      if d is null then if st='available' then st:='missing_payment_date';end if;continue;end if;
      if d->>'sourceHash' is distinct from row->>'sourceHash' then raise exception using errcode='55000',message='CASH_DATE_SOURCE_CHANGED';end if;
      if (d->>'dueDate')::date<p_start or (d->>'dueDate')::date>=p_end then continue;end if;
      rows:=rows||jsonb_build_array(jsonb_build_object('id',row->>'sourceId','branchId',row->>'branchId','currency',row->>'currency',
       'dueDate',d->>'dueDate','amount',abs((row->>'remainingAmount')::numeric)::text,'version',d->>'version','provider',family,'inflow',row->'inflow'));
      refs:=refs||jsonb_build_array(jsonb_build_object('kind',k,'id',row->>'sourceId','branchId',row->>'branchId',
       'sourceHash',row->>'sourceHash','originalAmount',row->>'originalAmount','issueId',row->>'issueId','journalId',row->>'issueJournalId',
       'issueDate',row->>'issueDate','dateRevision',d,'effects',row->'effects'));
      if jsonb_array_length(rows)>10000 or octet_length(refs::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
     end loop;
    end loop;
   end if;
  end if;
  statuses:=jsonb_set(statuses,array[family],to_jsonb(st));
  if st='available' then
   providers:=providers||jsonb_build_array(family);data:=jsonb_set(data,'{obligations}',(data->'obligations')||rows);
   data:=jsonb_set(data,'{sources}',(data->'sources')||refs);
  end if;
 end loop;
 if jsonb_array_length(data->'controls')+jsonb_array_length(data->'obligations')>10000 or jsonb_array_length(data->'sources')>10000
  or (select coalesce(sum(jsonb_array_length(x->'effects')),0) from jsonb_array_elements(data->'sources') x where x ? 'effects')+jsonb_array_length(data->'sources')>10000 then
  raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 if exists(select x->>'id' from jsonb_array_elements(data->'obligations') x group by x->>'id' having count(*)>1) then
  raise exception using errcode='55000',message='CASH_OBLIGATION_ID_AMBIGUOUS';end if;
 data:=data||jsonb_build_object('contractRevision',3,'definition','dated_transaction_cash_all_obligations.v3','completeProviders',providers,
  'providerStatus',statuses,'exclusions',jsonb_build_array('overdue_before_horizon','unallocated_credits','recognition_on_or_after_opening'));
 if octet_length(data::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('canonicalText',data::text,'sourceHash',encode(extensions.digest(data::text,'sha256'),'hex'));
end $$;

-- Freeze/reopen recheck each captured private source family, even with zero rows.
alter function api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb) rename to wave5_cash_save_v2;
revoke all on function api.wave5_cash_save_v2(uuid,uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
create function api.wave5_cash_save(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_source_hash text,p_parameters jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare basis jsonb;begin
 if not exists(select 1 from analytics.cash_scenario_revisions where id=p_id) then
  basis:=(api.wave5_cash_basis(p_tenant_id,p_legal_entity_id,p_branch_id,(p_parameters->>'horizonStart')::date,(p_parameters->>'horizonEnd')::date,(p_parameters->>'recordedThrough')::timestamptz)->>'canonicalText')::jsonb;
  if not(basis->'completeProviders' ?& array['bank_cash','receivables','payables','payroll','project_reimbursements']) then
   raise exception using errcode='55000',message='CASH_COMPLETE_PROVIDERS_REQUIRED';end if;
 end if;
 return api.wave5_cash_save_v2(p_tenant_id,p_legal_entity_id,p_branch_id,p_id,p_source_hash,p_parameters);
end $$;
alter function api.wave5_cash_get(uuid,uuid,uuid,uuid) rename to wave5_cash_get_v2;
revoke all on function api.wave5_cash_get_v2(uuid,uuid,uuid,uuid) from public,anon,authenticated;
create function api.wave5_cash_get(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare result jsonb;data jsonb;row jsonb;begin
 result:=api.wave5_cash_get_v2(p_tenant_id,p_legal_entity_id,p_branch_id,p_id);data:=(result->>'canonicalText')::jsonb;
 if data->'completeProviders' ? 'payroll' then perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,'payroll_obligation');end if;
 if data->'completeProviders' ? 'project_reimbursements' then perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,p_branch_id,'project_reimbursement');end if;
 for row in select * from jsonb_array_elements(data->'sources') where value->>'kind' in('payroll_obligation','payroll_correction','project_reimbursement') loop
  perform analytics.cash_date_access(p_tenant_id,p_legal_entity_id,(row->>'branchId')::uuid,row->>'kind');
 end loop;return result;
end $$;

-- Governed W3 codec/jobs are preserved; v2/pipeline documents retain their shape.
alter function finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) rename to wave5_report_export_document_v2;
revoke all on function finance.wave5_report_export_document_v2(uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated;
create function finance.report_export_document(t uuid,e uuid,b uuid,resource text,i uuid,section text,filters jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare f jsonb;s jsonb;data jsonb;rows jsonb;meta jsonb;n integer;begin
 if resource is distinct from 'w5_cash' then return finance.wave5_report_export_document_v2(t,e,b,resource,i,section,filters);end if;
 s:=api.wave5_cash_get(t,e,b,i);data:=(s->>'canonicalText')::jsonb;
 if data->>'contractRevision'<>'3' then return finance.wave5_report_export_document_v2(t,e,b,resource,i,section,filters);end if;
 perform core.wave3_require_scope(t,'finance.reports.export',e,b);
 if section is distinct from 'buckets' or filters is null or jsonb_typeof(filters)<>'object' or (filters-'currency')<>'{}'
  or (filters ? 'currency' and (jsonb_typeof(filters->'currency')<>'string' or coalesce(filters->>'currency','')!~'^[A-Z]{3}$')) then
  raise exception using errcode='22023',message='REPORT_EXPORT_FILTER_INVALID';end if;
 if not(data->'completeProviders' ?& array['bank_cash','receivables','payables','payroll','project_reimbursements']) then
  raise exception using errcode='55000',message='CASH_COMPLETE_PROVIDERS_REQUIRED';end if;
 if exists(select 1 from jsonb_array_elements(data->'obligations') o where not exists(select 1 from jsonb_array_elements(data->'controls') c where c->>'currency'=o->>'currency')) then
  raise exception using errcode='55000',message='CASH_CURRENCY_MAPPING_REQUIRED';end if;
 with opening as(select x->>'currency' currency,sum((x->>'amount')::numeric) balance from jsonb_array_elements(data->'controls') x group by x->>'currency'),
 flows as(select o->>'currency' currency,coalesce((s#>>array['parameters','overrides',o->>'id','dueDate'])::date,(o->>'dueDate')::date) due_date,
  coalesce((s#>>array['parameters','overrides',o->>'id','remainingUnits'])::numeric/1000000,(o->>'amount')::numeric) amount,(o->>'inflow')::boolean inflow from jsonb_array_elements(data->'obligations') o),
 days as(select c.currency,c.balance,d::date bucket_date from opening c cross join generate_series((data->>'horizonStart')::date,(data->>'horizonEnd')::date-1,interval '1 day') d where filters->>'currency' is null or c.currency=filters->>'currency'),
 buckets as(select d.currency,d.bucket_date,d.balance,coalesce(sum(f.amount) filter(where f.inflow),0) inflow,coalesce(sum(f.amount) filter(where not f.inflow),0) outflow
  from days d left join flows f on f.currency=d.currency and f.due_date=d.bucket_date group by d.currency,d.bucket_date,d.balance)
 select coalesce(jsonb_agg(jsonb_build_object('date',bucket_date::text,'currency',currency,'inflow',inflow::text,'outflow',outflow::text,'balance',total::text) order by currency,bucket_date),'[]'),count(*) into rows,n
 from(select currency,bucket_date,inflow,outflow,balance+sum(inflow-outflow) over(partition by currency order by bucket_date) total from buckets order by currency,bucket_date limit 10001) x;
 if n>10000 then raise exception using errcode='54000',message='REPORT_EXPORT_ROW_LIMIT';end if;
 meta:=jsonb_build_object('as_of',data->>'horizonStart','generated_at',data->>'recordedThrough','horizon_start',data->>'horizonStart','horizon_end',data->>'horizonEnd',
  'calculation',data->>'definition','source_basis_hash',s->>'sourceHash','scenario_parameters',s->'parameters','exclusions',data->'exclusions','complete_providers',data->'completeProviders',
  'id',i,'version',1,'tenant_id',t,'legal_entity_id',e,'branch_id',b,'actor_id',auth.uid(),'working_branch_id',b,'source_type',resource,'source_id',i,'section',section,'filters',filters,'row_count',jsonb_array_length(rows));
 f:=jsonb_build_object('version',1,'metadata',meta,'rows',rows);
 if octet_length(f::text)>8388608 then raise exception using errcode='54000',message='REPORT_EXPORT_EVIDENCE_LIMIT';end if;return f;
end $$;

revoke all on function analytics.cash_date_access(uuid,uuid,uuid,text,text),analytics.cash_source_installed(text),analytics.cash_source_rows(uuid,uuid,uuid,text,date,timestamptz),analytics.cash_date_current(uuid,uuid,text,uuid,timestamptz),
 finance.report_export_document(uuid,uuid,uuid,text,uuid,text,jsonb) from public,anon,authenticated;
revoke all on function api.wave5_cash_date_authorize(uuid,uuid,uuid,text),api.wave5_cash_date_sources(uuid,uuid,uuid,text,uuid),api.wave5_cash_date_get(uuid,uuid,uuid,uuid),api.wave5_cash_date_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb),
 api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_cash_date_authorize(uuid,uuid,uuid,text),api.wave5_cash_date_sources(uuid,uuid,uuid,text,uuid),api.wave5_cash_date_get(uuid,uuid,uuid,uuid),api.wave5_cash_date_command(uuid,uuid,uuid,uuid,uuid,timestamptz,text,jsonb) to authenticated;
grant execute on function api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) to authenticated;
