-- W4-04 additive candidate. Private, synthetic sealed eligibility adjustments.
-- No existing role/plan grants. Temporal source edits remain operational impacts.
insert into core.permissions(code,module,description,privileged) values
 ('people.payroll.correction.prepare','people','Prepare linked synthetic payroll eligibility corrections',true),
 ('people.payroll.correction.approve','people','Independently approve linked payroll corrections',true)
on conflict(code) do nothing;

create table people_payroll.corrections(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 original_calculation_id uuid not null,employee_id uuid not null,original_run_id uuid not null,
 predecessor_id uuid,chain_version bigint not null check(chain_version between 0 and 2000),
 posting_date date not null,currency_code text not null references core.currencies(code),
 status text not null default 'prepared' check(status in('prepared','approved','rejected','posted','reversed')),
 version bigint not null default 1 check(version between 1 and 9007199254740991),
 digest text not null check(digest ~ '^[a-f0-9]{64}$'),
 before_calculation jsonb not null,after_calculation jsonb not null,difference jsonb not null,
 prepared_by uuid not null references auth.users(id),prepared_at timestamptz not null default clock_timestamp(),
 approved_by uuid references auth.users(id),approved_digest text,posted_journal_id uuid,reversal_journal_id uuid,
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,original_calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,original_run_id) references people_payroll.runs(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,predecessor_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,posted_journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_correction_scope_idx on people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id);
create index payroll_correction_original_idx on people_payroll.corrections(tenant_id,legal_entity_id,original_calculation_id,id);
create index payroll_correction_run_idx on people_payroll.corrections(tenant_id,legal_entity_id,original_run_id);
create index payroll_correction_employee_idx on people_payroll.corrections(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_predecessor_idx on people_payroll.corrections(tenant_id,legal_entity_id,predecessor_id);
create index payroll_correction_actor_idx on people_payroll.corrections(prepared_by);
create index payroll_correction_approver_idx on people_payroll.corrections(approved_by);
create index payroll_correction_journal_idx on people_payroll.corrections(tenant_id,posted_journal_id);
create index payroll_correction_reversal_idx on people_payroll.corrections(tenant_id,reversal_journal_id);
create table people_payroll.correction_sources(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,correction_id uuid not null,
 employee_id uuid not null,seal_id uuid not null,source_kind text not null check(source_kind in('attendance','leave','project','service')),
 source_id uuid not null,source_digest text not null check(source_digest ~ '^[a-f0-9]{64}$'),
 before_revision_id uuid not null,after_revision_id uuid not null unique,
 impact jsonb,
 before_version bigint not null check(before_version between 1 and 2001),
 before_seconds bigint not null check(before_seconds between 0 and 129600),
 after_seconds bigint not null check(after_seconds between 0 and 129600),
 original_seconds bigint not null check(original_seconds between 0 and 129600),
 check((impact is not null or(after_seconds<=original_seconds and before_seconds<=original_seconds)) and (impact is not null or before_seconds<>after_seconds)),
 unique(tenant_id,legal_entity_id,correction_id,seal_id),unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(seal_id) references people.work_input_seals(id)
);
create index payroll_correction_sources_seal_idx on people_payroll.correction_sources(seal_id);
create index payroll_correction_sources_employee_idx on people_payroll.correction_sources(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_sources_scope_idx on people_payroll.correction_sources(tenant_id,legal_entity_id,correction_id,id);
create table people_payroll.correction_source_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 correction_id uuid not null,source_id uuid not null,seal_id uuid not null,
 revision_id uuid not null unique,version bigint not null check(version between 2 and 2002),
 seconds bigint not null check(seconds between 0 and 129600),kind text not null check(kind in('apply','reverse')),
 operational_claim_id uuid,operational_source_id uuid,operational_source_version bigint,operational_snapshot jsonb,
 reversal_of uuid unique,recorded_at timestamptz not null default clock_timestamp(),
 unique(seal_id,version),unique(correction_id,seal_id,kind),
 foreign key(tenant_id,legal_entity_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,source_id) references people_payroll.correction_sources(tenant_id,legal_entity_id,id),
 foreign key(seal_id) references people.work_input_seals(id),foreign key(reversal_of) references people_payroll.correction_source_effects(id),
 check((kind='reverse')=(reversal_of is not null))
);
create index payroll_correction_source_effect_scope_idx on people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,id);
create index payroll_correction_source_effect_source_idx on people_payroll.correction_source_effects(tenant_id,legal_entity_id,source_id);
create table people_payroll.correction_balances(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 correction_id uuid not null,employee_id uuid not null,rule_version_id uuid,kind text not null check(kind in('net','deduction','employer_cost')),
 account_id uuid not null,currency_code text not null references core.currencies(code),amount numeric(20,6) not null check(amount<>0),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,rule_version_id) references people_payroll.rule_versions(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 check((kind='net')=(rule_version_id is null))
);
create index payroll_correction_balances_scope_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_balances_employee_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,employee_id);
create index payroll_correction_balances_rule_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,rule_version_id);
create index payroll_correction_balances_account_idx on people_payroll.correction_balances(tenant_id,legal_entity_id,account_id);
create table people_payroll.correction_balance_effects(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,balance_id uuid not null,
 kind text not null check(kind in('issue','settle','settlement_reverse','correction_reverse')),
 amount numeric(20,6) not null check(amount<>0),source_id uuid not null,reversal_of uuid unique,
 recorded_by uuid not null references auth.users(id),recorded_at timestamptz not null default clock_timestamp(),
 unique(balance_id,kind,source_id),
 foreign key(tenant_id,legal_entity_id,balance_id) references people_payroll.correction_balances(tenant_id,legal_entity_id,id),
 foreign key(reversal_of) references people_payroll.correction_balance_effects(id),
 check((kind in('settlement_reverse','correction_reverse'))=(reversal_of is not null))
);
create index payroll_correction_balance_effect_scope_idx on people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,id);
create index payroll_correction_balance_effect_actor_idx on people_payroll.correction_balance_effects(recorded_by);
create table people_payroll.correction_settlements(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,correction_id uuid not null,
 bank_id uuid not null,bank_account_id uuid not null,bank_version bigint not null,currency_code text not null,
 posting_date date not null,direction text not null check(direction in('pay','recover')),
 evidence_reference text not null check(length(btrim(evidence_reference)) between 1 and 160),
 reason text not null check(length(btrim(reason)) between 1 and 1000),
 version bigint not null default 1,status text not null default 'recorded' check(status in('recorded','reversed')),
 journal_id uuid not null,reversal_journal_id uuid,recorded_by uuid not null references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),unique(tenant_id,legal_entity_id,evidence_reference),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,bank_id) references finance.cash_bank_accounts(tenant_id,id),
 foreign key(tenant_id,legal_entity_id,bank_account_id) references finance.accounts(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,journal_id) references finance.journal_entries(tenant_id,id),
 foreign key(tenant_id,reversal_journal_id) references finance.journal_entries(tenant_id,id)
);
create index payroll_correction_settlement_scope_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_settlement_bank_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,bank_id);
create index payroll_correction_settlement_account_idx on people_payroll.correction_settlements(tenant_id,legal_entity_id,bank_account_id);
create index payroll_correction_settlement_journal_idx on people_payroll.correction_settlements(tenant_id,journal_id);
create index payroll_correction_settlement_reverse_idx on people_payroll.correction_settlements(tenant_id,reversal_journal_id);
create index payroll_correction_settlement_actor_idx on people_payroll.correction_settlements(recorded_by);
create table people_payroll.correction_settlement_allocations(
 tenant_id uuid not null,legal_entity_id uuid not null,settlement_id uuid not null,balance_id uuid not null,
 amount numeric(20,6) not null check(amount>0),primary key(settlement_id,balance_id),
 foreign key(tenant_id,legal_entity_id,settlement_id) references people_payroll.correction_settlements(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,balance_id) references people_payroll.correction_balances(tenant_id,legal_entity_id,id)
);
create index payroll_correction_settlement_allocation_balance_idx on people_payroll.correction_settlement_allocations(tenant_id,legal_entity_id,balance_id);
create table people_payroll.correction_payslips(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 correction_id uuid not null unique,employee_id uuid not null,payload jsonb not null,digest text not null,
 issued_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id)
);
create index payroll_correction_payslip_scope_idx on people_payroll.correction_payslips(tenant_id,legal_entity_id,branch_id,employee_id,id);
create table people_payroll.correction_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,legal_entity_id uuid not null,
 branch_id uuid not null,correction_id uuid not null,original_calculation_id uuid not null,
 action text not null,version bigint not null,chain_sequence bigint,actor_id uuid not null references auth.users(id),
 reason text not null,command_id uuid not null,recorded_at timestamptz not null default clock_timestamp(),
 unique(original_calculation_id,chain_sequence),
 foreign key(tenant_id,legal_entity_id,branch_id,correction_id) references people_payroll.corrections(tenant_id,legal_entity_id,branch_id,id),
 foreign key(tenant_id,legal_entity_id,original_calculation_id) references people_payroll.employee_calculations(tenant_id,legal_entity_id,id)
);
create index payroll_correction_event_scope_idx on people_payroll.correction_events(tenant_id,legal_entity_id,branch_id,correction_id,id);
create index payroll_correction_event_original_idx on people_payroll.correction_events(tenant_id,legal_entity_id,original_calculation_id,chain_sequence);
create index payroll_correction_event_actor_idx on people_payroll.correction_events(actor_id);

create function people_payroll.correction_guard() returns trigger language plpgsql set search_path='' as $$begin
 if tg_op='UPDATE' and tg_table_name='corrections' and
  (to_jsonb(new)-array['status','version','approved_by','approved_digest','posted_journal_id','reversal_journal_id'])=
  (to_jsonb(old)-array['status','version','approved_by','approved_digest','posted_journal_id','reversal_journal_id']) then return new;end if;
 if tg_op='UPDATE' and tg_table_name='correction_settlements' and
  (to_jsonb(new)-array['status','version','reversal_journal_id'])=(to_jsonb(old)-array['status','version','reversal_journal_id']) then return new;end if;
 raise exception using errcode='55000',message='PAYROLL_CORRECTION_HISTORY_IMMUTABLE';end $$;
do $$declare n text;begin
 foreach n in array array['corrections','correction_sources','correction_source_effects','correction_balances',
  'correction_balance_effects','correction_settlements','correction_settlement_allocations','correction_payslips','correction_events'] loop
  execute format('alter table people_payroll.%I enable row level security',n);
  execute format('alter table people_payroll.%I force row level security',n);
  execute format('revoke all on people_payroll.%I from public,anon,authenticated',n);
  execute format('create trigger immutable before update or delete on people_payroll.%I for each row execute function people_payroll.correction_guard()',n);
 end loop;end $$;

create function people_payroll.correction_access(t uuid,e uuid,b uuid,cap text,p_write boolean default false)
returns void language plpgsql security definer set search_path='' as $$begin
 if cap not in('people.payroll.view','people.payroll.correction.prepare','people.payroll.correction.approve',
  'people.payroll.post','people.payroll.reverse','people.payroll.settle','people.payroll.payslip.view') or cap is null then
  raise exception using errcode='42501',message='PAYROLL_CORRECTION_SCOPE_DENIED';end if;
 perform people.require_access(t,e,b,cap);
 if p_write and coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then raise exception using errcode='42501',message='PAYROLL_MFA_REQUIRED';end if;
end $$;
create function api.people_payroll_correction_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_capability text)
returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,p_capability,true);
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'actor_id',auth.uid(),'capability',p_capability,'authorized',true);end $$;
create function people_payroll.approved_source(t uuid,e uuid,b uuid,employee uuid,claim uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare w people.work_claims%rowtype;a people.attendance_entries%rowtype;l people.leave_requests%rowtype;r jsonb;begin
 select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and id=claim and active;
 if w.id is null then raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 if w.source_kind='attendance' then
  select * into a from people.attendance_entries where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and current_revision_id=w.source_id and active_claim_id=w.id and status='approved';
  if a.id is not null then r:=jsonb_build_object('source_id',w.source_id,'source_version',a.version,'paid_seconds',w.payable_seconds);end if;
 elsif w.source_kind='leave' then
  select * into l from people.leave_requests where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and active_claim_id=w.id and status='approved';
  if l.id is not null then r:=jsonb_build_object('source_id',w.source_id,'source_version',l.version,'paid_seconds',l.charge_seconds-l.unpaid_seconds);end if;
 elsif w.source_kind='project' and to_regprocedure('projects.payroll_source(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select projects.payroll_source($1,$2,$3,$4,$5)' into r using t,e,b,employee,claim;
 elsif w.source_kind='service' and to_regprocedure('service.payroll_source(uuid,uuid,uuid,uuid,uuid)') is not null then
  execute 'select service.payroll_source($1,$2,$3,$4,$5)' into r using t,e,b,employee,claim;
 end if;
 if r is null or r->>'source_id' is distinct from w.source_id::text or jsonb_typeof(r->'source_version')<>'number'
  or (r->>'source_version')::bigint not between 1 and 9007199254740991
  or jsonb_typeof(r->'paid_seconds')<>'number' or (r->>'paid_seconds')::bigint not between 0 and w.gross_seconds then
  raise exception using errcode='55000',message='PAYROLL_APPROVED_SOURCE_PROVIDER_REQUIRED';end if;
 return r;end $$;
create function people_payroll.correction_source_permission(t uuid,e uuid,b uuid,kind text,decision boolean)
returns void language plpgsql security definer set search_path='' as $$begin
 if kind='service' then
  if to_regprocedure('service.require_access(uuid,uuid,uuid,text)') is null then raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  execute 'select service.require_access($1,$2,$3,$4)' using t,e,b,case when decision then 'service.approve' else 'service.work' end;
  execute 'select service.require_access($1,$2,$3,$4)' using t,e,b,'service.cost.view';
  return;
 end if;
 perform people.require_access(t,e,b,case kind
  when 'attendance' then case when decision then 'people.attendance.approve' else 'people.attendance.manage' end
  when 'leave' then case when decision then 'people.leave.approve' else 'people.leave.manage' end
  when 'project' then case when decision then 'projects.time.approve' else 'projects.time.manage' end
  else null end);
 if kind='project' then perform core.wave3_require_scope(t,'projects.cost.view',e,b);end if;
end $$;
create function people_payroll.correction_summary(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'tenant_id',c.tenant_id,'legal_entity_id',c.legal_entity_id,'branch_id',c.branch_id,
  'original_calculation_id',c.original_calculation_id,'employee_id',c.employee_id,'original_run_id',c.original_run_id,
  'predecessor_id',c.predecessor_id,'chain_version',c.chain_version,'posting_date',c.posting_date,'currency_code',c.currency_code,
  'status',c.status,'version',c.version,'digest',c.digest,'prepared_by',c.prepared_by,'approved_by',c.approved_by,
  'posted_journal_id',c.posted_journal_id,'reversal_journal_id',c.reversal_journal_id)
 from people_payroll.corrections c where c.id=p_id $$;
create function people_payroll.correction_source_state(p_seal uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('seal_id',s.id,'revision_id',coalesce(x.revision_id,w.source_id),'version',coalesce(x.version,1),
  'paid_seconds',coalesce(x.seconds,s.seconds),'original_seconds',s.seconds,'source_kind',w.source_kind,'source_id',w.source_id,
  'source_digest',s.digest,'claim_id',case when x.id is null then w.id else x.operational_claim_id end,
  'operational_source_id',coalesce(x.operational_source_id,w.source_id),'operational_source_version',coalesce(x.operational_source_version,s.source_version),
  'operational_snapshot',x.operational_snapshot)
 from people.work_input_seals s join people.work_claims w on w.id=s.claim_id
 left join lateral(select * from people_payroll.correction_source_effects where seal_id=s.id order by version desc limit 1) x on true
 where s.id=p_seal $$;
create function people_payroll.correction_difference(before jsonb,after jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare lines jsonb;begin
 if jsonb_array_length(before->'lines')<>jsonb_array_length(after->'lines') then raise exception using errcode='22023',message='PAYROLL_CORRECTION_RULES_CHANGED';end if;
 select jsonb_agg(jsonb_build_object('rule_version_id',a->>'rule_version_id','code',a->>'code','classification',a->>'classification',
  'before',b,'after',a,'difference',round((a->>'amount')::numeric-(b->>'amount')::numeric,6)::text) order by a->>'code') into lines
 from jsonb_array_elements(after->'lines') a join jsonb_array_elements(before->'lines') b on b->>'rule_version_id'=a->>'rule_version_id';
 if jsonb_array_length(lines)<>jsonb_array_length(after->'lines') then raise exception using errcode='22023',message='PAYROLL_CORRECTION_RULES_CHANGED';end if;
 return jsonb_build_object('lines',lines,'gross',round((after->>'gross')::numeric-(before->>'gross')::numeric,6)::text,
  'deductions',round((after->>'deductions')::numeric-(before->>'deductions')::numeric,6)::text,
  'employer_cost',round((after->>'employer_cost')::numeric-(before->>'employer_cost')::numeric,6)::text,
  'net',round((after->>'net')::numeric-(before->>'net')::numeric,6)::text);end $$;

create function api.people_payroll_correction_originals(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.correction.prepare',true);
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'run_id',q.run_id,'employee_id',q.employee_id,'employee_code',q.inputs->>'employee_code',
  'employee_name',q.inputs->>'employee_name','start_date',q.inputs->>'start_date','end_date_exclusive',q.inputs->>'end_date_exclusive',
  'currency_code',r.currency_code,'original_net',q.net::text) order by q.id),'[]') into items
 from(select ec.* from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and r.status='posted'
  and ec.revision_id=r.current_revision_id and (p_after is null or ec.id>p_after) order by ec.id limit 51) q
 join people_payroll.runs r on r.id=q.run_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_correction_sources(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_calculation_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people_payroll.employee_calculations%rowtype;items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.correction.prepare',true);
 select ec.* into c from people_payroll.employee_calculations ec join people_payroll.runs r on r.id=ec.run_id
  where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and r.branch_id=p_branch_id and ec.id=p_calculation_id
  and r.status='posted' and ec.revision_id=r.current_revision_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_ORIGINAL_CALCULATION_NOT_FOUND';end if;
 select coalesce(jsonb_agg(people_payroll.correction_source_state(q.id)||jsonb_build_object('id',q.id,
  'start_utc',w.start_utc,'end_utc',w.end_utc,'calendar_version_id',w.calendar_version_id,
  'operational',people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,
   (people_payroll.correction_source_state(q.id)->>'claim_id')::uuid,gen_random_uuid(),jsonb_build_object('source_kind',w.source_kind,
    'original_source_id',w.source_id,'snapshot',people_payroll.correction_source_state(q.id)->'operational_snapshot'),'read')) order by q.id),'[]') into items
 from(select * from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and run_id=c.run_id
  and employee_id=c.employee_id and claim_id in(select (value->>'claim_id')::uuid from jsonb_array_elements(c.inputs->'sources'))
  and (p_after is null or id>p_after) order by id limit 51) q join people.work_claims w on w.id=q.claim_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'calculation_id',p_calculation_id,
  'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_corrections(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare items jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.view',true);
 select coalesce(jsonb_agg(people_payroll.correction_summary(q.id) order by q.id),'[]') into items from
 (select id from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
  and(p_after is null or id>p_after) order by id limit 51) q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'items',items-50,
  'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;
create function api.people_payroll_correction_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_correction_id uuid,p_section text,p_after uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare c people_payroll.corrections%rowtype;items jsonb;source people_payroll.correction_sources%rowtype;effect jsonb;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,case when p_section='balances' then 'people.payroll.settle'
  when p_section='payslip' then 'people.payroll.payslip.view' else 'people.payroll.view' end,true);
 select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=p_correction_id;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_NOT_FOUND';end if;
 if p_section='calculation' then
  items:=jsonb_build_array(jsonb_build_object('id',c.id,'before',c.before_calculation,'after',c.after_calculation,'difference',c.difference,'reason',c.reason));
 elsif p_section='sources' then
  for source in select * from people_payroll.correction_sources where correction_id=c.id loop
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,source.source_kind,false);
   for effect in select value from jsonb_array_elements(coalesce(source.impact->'after'->'allocation_impacts','[]')) loop
    perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,effect->>'source_kind',false);
   end loop;
  end loop;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_sources where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='balances' then select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('amount',q.amount::text,'outstanding',
  round((select coalesce(sum(amount),0) from people_payroll.correction_balance_effects where balance_id=q.id),6)::text) order by q.id),'[]') into items
  from(select * from people_payroll.correction_balances where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='settlements' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_settlements where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='history' then select coalesce(jsonb_agg(to_jsonb(q) order by q.id),'[]') into items from
  (select * from people_payroll.correction_events where correction_id=c.id and(p_after is null or id>p_after) order by id limit 51) q;
 elsif p_section='payslip' then select coalesce(jsonb_agg(jsonb_build_object('id',id,'correction_id',correction_id,'employee_id',employee_id,
  'payload',payload,'digest',digest,'issued_at',issued_at)),'[]') into items from people_payroll.correction_payslips where correction_id=c.id;
 else raise exception using errcode='22023',message='PAYROLL_CORRECTION_SECTION_INVALID';end if;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,'correction',people_payroll.correction_summary(c.id),
 'section',p_section,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);end $$;

create function api.people_payroll_correction_command(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare act text:=p_payload->>'action';cid uuid;cap text;c people_payroll.corrections%rowtype;
 original people_payroll.employee_calculations%rowtype;r people_payroll.runs%rowtype;src people_payroll.correction_sources%rowtype;
 x jsonb;state jsonb;inputs jsonb;sources jsonb:='[]';changes jsonb:='[]';before_calc jsonb;after_calc jsonb;diff jsonb;impact jsonb;operational jsonb;replacement_id uuid;
 seq bigint;predecessor uuid;paid bigint:=0;seen uuid[]:='{}';w people.work_input_seals%rowtype;
 hash text;replay jsonb;before_summary jsonb:='{}';after_summary jsonb;line jsonb;lines jsonb:='[]';v_amount numeric;
 account uuid;balance uuid;journal uuid;request uuid:=gen_random_uuid();rule people_payroll.rule_versions%rowtype;
 setting people_payroll.settings_versions%rowtype;latest people_payroll.correction_events%rowtype;
begin
 if act is null or act not in('prepare','approve','reject','post','reverse') or p_command_id is null or p_idempotency_key is null
  or p_client_timestamp is null or p_expected_version is null or p_expected_version not between 0 and 9007199254740991
  or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>65536
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000 then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_COMMAND_INVALID';end if;
 if exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when act='prepare' then
  array['action','id','original_calculation_id','posting_date','replacements','reason'] when act='reverse' then
  array['action','id','digest','posting_date','reason','current_billing_impacts'] else array['action','id','digest','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_FIELDS_INVALID';end if;
 cap:=case act when 'prepare' then 'people.payroll.correction.prepare' when 'approve' then 'people.payroll.correction.approve'
  when 'post' then 'people.payroll.post' when 'reverse' then 'people.payroll.reverse' else 'people.payroll.correction.approve' end;
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 cid:=(p_payload->>'id')::uuid;
 hash:=core.wave3_request_hash('people.payroll.correction.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 -- Source-specific authority is checked before replay as well as business effects.
 if act='prepare' then
  select ec.* into original from people_payroll.employee_calculations ec join people_payroll.runs rr on rr.id=ec.run_id
   where ec.tenant_id=p_tenant_id and ec.legal_entity_id=p_legal_entity_id and rr.branch_id=p_branch_id
    and ec.id=(p_payload->>'original_calculation_id')::uuid and ec.revision_id=rr.current_revision_id and rr.status='posted';
 else
  select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=cid;
  select * into original from people_payroll.employee_calculations where id=c.original_calculation_id;
 end if;
 if original.id is null then raise exception using errcode='P0002',message='PAYROLL_ORIGINAL_CALCULATION_NOT_FOUND';end if;
 if act='prepare' then
  if jsonb_typeof(p_payload->'replacements')<>'array' or jsonb_array_length(p_payload->'replacements') not between 1 and 200 then
   raise exception using errcode='22023',message='PAYROLL_CORRECTION_REPLACEMENTS_INVALID';end if;
  for x in select value from jsonb_array_elements(p_payload->'replacements') loop
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and employee_id=original.employee_id and run_id=original.run_id and id=(x->>'seal_id')::uuid;
   if w.id is null then raise exception using errcode='42501',message='PAYROLL_CORRECTION_SOURCE_SCOPE_DENIED';end if;
   state:=people_payroll.correction_source_state(w.id);
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,state->>'source_kind',false);
  end loop;
 elsif act in('approve','reject','post','reverse') then
  for src in select * from people_payroll.correction_sources where correction_id=cid loop
   perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,src.source_kind,true);
  end loop;
 end if;
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.correction.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||p_tenant_id||':'||p_legal_entity_id,0));
 perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=original.employee_id for update;
 select * into r from people_payroll.runs where id=original.run_id for update;
 if r.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_ORIGINAL_RUN_NOT_POSTED';end if;
 select coalesce(max(chain_sequence),0) into seq from people_payroll.correction_events where original_calculation_id=original.id;
 select * into latest from people_payroll.correction_events where original_calculation_id=original.id and chain_sequence is not null order by chain_sequence desc limit 1;
 predecessor:=latest.correction_id;
 if seq>=2000 then raise exception using errcode='55000',message='PAYROLL_CORRECTION_CHAIN_BOUND_REQUIRED';end if;
 if act='prepare' then
  if p_expected_version<>0 or coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or(p_payload->>'posting_date')::date<r.end_date_exclusive then raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
  inputs:=original.inputs;
  for x in select value from jsonb_array_elements(original.inputs->'sources') order by value->>'claim_id' loop
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and run_id=r.id and employee_id=original.employee_id and claim_id=(x->>'claim_id')::uuid;
   if w.id is null or w.digest<>people_payroll.digest(x) then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   state:=people_payroll.correction_source_state(w.id);
   sources:=sources||jsonb_build_array(x||jsonb_build_object('paid_seconds',(state->>'paid_seconds')::bigint));
   paid:=paid+(state->>'paid_seconds')::bigint;
  end loop;
  inputs:=inputs||jsonb_build_object('sources',sources,'paid_seconds',paid);
  before_calc:=people_payroll.calculate(inputs,original.inputs->'rules',r.currency_code);
  paid:=0;sources:='[]';
  for x in select value from jsonb_array_elements(p_payload->'replacements') order by value->>'seal_id' loop
   if jsonb_typeof(x)<>'object' or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['seal_id','before_revision_id','expected_version','paid_seconds','impact']))
    or not(x ?& array['seal_id','before_revision_id','expected_version','paid_seconds'])
    or jsonb_typeof(x->'expected_version')<>'number' or jsonb_typeof(x->'paid_seconds')<>'number'
    or coalesce(x->>'paid_seconds','') !~ '^[0-9]{1,6}$' or(x->>'seal_id')::uuid=any(seen) then
    raise exception using errcode='22023',message='PAYROLL_CORRECTION_REPLACEMENTS_INVALID';end if;
   seen:=array_append(seen,(x->>'seal_id')::uuid);
   select * into w from people.work_input_seals where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
    and run_id=r.id and employee_id=original.employee_id and id=(x->>'seal_id')::uuid;
   state:=people_payroll.correction_source_state(w.id);
   if state->>'revision_id' is distinct from x->>'before_revision_id' or(state->>'version')::bigint is distinct from(x->>'expected_version')::bigint then
    raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   if(x->>'paid_seconds')::bigint not between 0 and 129600 or(x->'impact' is null and((x->>'paid_seconds')::bigint>w.seconds or(x->>'paid_seconds')::bigint=(state->>'paid_seconds')::bigint)) then
    raise exception using errcode='22023',message='PAYROLL_CORRECTION_ELIGIBILITY_INVALID';end if;
   replacement_id:=gen_random_uuid();impact:=null;
   perform people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,original.employee_id,(state->>'claim_id')::uuid);
   if x->'impact' is not null then
    if jsonb_typeof(x->'impact') is distinct from 'object' or exists(select 1 from jsonb_object_keys(x->'impact') k
     where k<>all(array['mode','expected_source_version','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids','allocation_changes']))
     or jsonb_typeof(x->'impact'->'expected_source_version') is distinct from 'number'
     or (x->'impact'->>'expected_source_version') !~ '^[1-9][0-9]{0,15}$' then raise exception using errcode='22023',message='PAYROLL_SOURCE_IMPACT_INVALID';end if;
    impact:=x->'impact'||jsonb_build_object('correction_id',cid,'source_kind',state->>'source_kind');
    operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,original.employee_id,(state->>'claim_id')::uuid,replacement_id,impact,'validate');
    if impact->>'mode'='geometry' and((operational->'after'->>'start_utc')::timestamptz<people.resolve_local_instant(original.inputs->>'timezone',(original.inputs->>'eligible_start')::timestamp)
     or(operational->'after'->>'end_utc')::timestamptz>people.resolve_local_instant(original.inputs->>'timezone',(original.inputs->>'eligible_end_exclusive')::timestamp)) then
     raise exception using errcode='55000',message='PAYROLL_CORRECTION_ORIGINAL_PERIOD_REQUIRED';end if;
    if (operational->>'paid_seconds')::bigint is distinct from(x->>'paid_seconds')::bigint then raise exception using errcode='22023',message='PAYROLL_CORRECTION_SOURCE_AMOUNT_MISMATCH';end if;
    impact:=impact||jsonb_build_object('before',operational->'before','after',operational->'after');
   end if;
   changes:=changes||jsonb_build_array(state||jsonb_build_object('id',gen_random_uuid(),'after_revision_id',replacement_id,'after_seconds',(x->>'paid_seconds')::bigint,'impact',impact));
  end loop;
  for x in select value from jsonb_array_elements(inputs->'sources') loop
   select * into w from people.work_input_seals where run_id=r.id and employee_id=original.employee_id and claim_id=(x->>'claim_id')::uuid;
   state:=(select value from jsonb_array_elements(changes) where value->>'seal_id'=w.id::text);
   paid:=paid+coalesce((state->>'after_seconds')::bigint,(x->>'paid_seconds')::bigint);
   sources:=sources||jsonb_build_array(x||jsonb_build_object('paid_seconds',coalesce((state->>'after_seconds')::bigint,(x->>'paid_seconds')::bigint)));
  end loop;
  after_calc:=people_payroll.calculate(inputs||jsonb_build_object('paid_seconds',paid,'sources',sources),original.inputs->'rules',r.currency_code);
  diff:=people_payroll.correction_difference(before_calc,after_calc);
  insert into people_payroll.corrections(id,tenant_id,legal_entity_id,branch_id,original_calculation_id,employee_id,original_run_id,
   predecessor_id,chain_version,posting_date,currency_code,digest,before_calculation,after_calculation,difference,prepared_by,reason)
  values(cid,p_tenant_id,p_legal_entity_id,p_branch_id,original.id,original.employee_id,r.id,predecessor,seq,(p_payload->>'posting_date')::date,
   r.currency_code,people_payroll.digest(jsonb_build_object('original_calculation_id',original.id,'chain_version',seq,
   'sources',changes,'before',before_calc,'after',after_calc,'posting_date',p_payload->>'posting_date')),before_calc,after_calc,diff,auth.uid(),btrim(p_payload->>'reason'));
  insert into people_payroll.correction_sources(id,tenant_id,legal_entity_id,correction_id,employee_id,seal_id,source_kind,source_id,
   source_digest,before_revision_id,after_revision_id,before_version,before_seconds,after_seconds,original_seconds,impact)
  select(replacement->>'id')::uuid,p_tenant_id,p_legal_entity_id,cid,original.employee_id,(replacement->>'seal_id')::uuid,replacement->>'source_kind',(replacement->>'source_id')::uuid,
   replacement->>'source_digest',(replacement->>'revision_id')::uuid,(replacement->>'after_revision_id')::uuid,(replacement->>'version')::bigint,(replacement->>'paid_seconds')::bigint,
   (replacement->>'after_seconds')::bigint,(replacement->>'original_seconds')::bigint,nullif(replacement->'impact','null'::jsonb) from jsonb_array_elements(changes) replacement;
 else
  select * into c from people_payroll.corrections where id=cid for update;
  before_summary:=people_payroll.correction_summary(cid);
  if c.version<>p_expected_version or c.digest is distinct from p_payload->>'digest' then
   raise exception using errcode='40001',message='PAYROLL_CORRECTION_VERSION_CONFLICT';end if;
  if act in('approve','reject') then
   if c.status<>'prepared' then raise exception using errcode='55000',message='PAYROLL_CORRECTION_STATE_INVALID';end if;
   if c.prepared_by=auth.uid() then raise exception using errcode='42501',message='PAYROLL_INDEPENDENT_APPROVAL_REQUIRED';end if;
   if c.chain_version<>seq or c.predecessor_id is distinct from predecessor then raise exception using errcode='40001',message='PAYROLL_CORRECTION_CHAIN_CHANGED';end if;
   update people_payroll.corrections set status=case when act='approve' then 'approved' else 'rejected' end,version=version+1,
    approved_by=auth.uid(),approved_digest=case when act='approve' then digest else null end where id=cid;
  elsif act='post' then
   if c.status<>'approved' or c.approved_digest is distinct from c.digest then raise exception using errcode='55000',message='PAYROLL_CORRECTION_APPROVAL_REQUIRED';end if;
   if c.chain_version<>seq or c.predecessor_id is distinct from predecessor then raise exception using errcode='40001',message='PAYROLL_CORRECTION_CHAIN_CHANGED';end if;
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);
    if(state->>'version')::bigint<>src.before_version or state->>'revision_id'<>src.before_revision_id::text
     or(state->>'paid_seconds')::bigint<>src.before_seconds then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
    perform people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid);
   end loop;
   select s.* into setting from people_payroll.settings_versions s join people_payroll.run_revisions rv on rv.settings_version_id=s.id where rv.id=original.revision_id;
   v_amount:=(c.difference->>'net')::numeric;
   if v_amount<>0 then
    perform people_payroll.account(p_tenant_id,p_legal_entity_id,setting.net_account_id,'liability',c.currency_code);
    balance:=gen_random_uuid();
    insert into people_payroll.correction_balances values(balance,p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,null,'net',setting.net_account_id,c.currency_code,v_amount);
    lines:=lines||jsonb_build_array(jsonb_build_object('account_id',setting.net_account_id,'amount',(-v_amount)::text,'base_amount',(-v_amount)::text,'source_line_id',balance));
   end if;
   for line in select value from jsonb_array_elements(c.difference->'lines') loop
    v_amount:=(line->>'difference')::numeric;
    if v_amount=0 then continue;end if;
    select * into rule from people_payroll.rule_versions where id=(line->>'rule_version_id')::uuid;
    if line->>'classification' in('earning','employer_cost') then
     perform people_payroll.account(p_tenant_id,p_legal_entity_id,rule.expense_account_id,'expense',c.currency_code);
     lines:=lines||jsonb_build_array(jsonb_build_object('account_id',rule.expense_account_id,'amount',v_amount::text,'base_amount',v_amount::text,'source_line_id',cid));
    end if;
    if line->>'classification' in('deduction','employer_cost') then
     perform people_payroll.account(p_tenant_id,p_legal_entity_id,rule.liability_account_id,'liability',c.currency_code);
     balance:=gen_random_uuid();
     insert into people_payroll.correction_balances values(balance,p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,rule.id,line->>'classification',rule.liability_account_id,c.currency_code,v_amount);
     lines:=lines||jsonb_build_array(jsonb_build_object('account_id',rule.liability_account_id,'amount',(-v_amount)::text,'base_amount',(-v_amount)::text,'source_line_id',balance));
    end if;
   end loop;
   -- Even a zero-amount correction needs an open date; it never invents a journal.
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,c.posting_date);
   if jsonb_array_length(lines)>0 then journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
    'branch_id',p_branch_id,'document_date',c.posting_date,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
    lines,'payroll_correction',cid,request,p_command_id);end if;
   insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
    select tenant_id,legal_entity_id,id,'issue',amount,cid,auth.uid() from people_payroll.correction_balances where correction_id=cid;
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);
    if src.impact is not null then
     operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid,src.after_revision_id,src.impact,'apply');
    else operational:=jsonb_build_object('claim_id',state->'claim_id','source_id',state->'operational_source_id','source_version',state->'operational_source_version','after',state->'operational_snapshot');end if;
    insert into people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,source_id,seal_id,revision_id,version,seconds,kind,operational_claim_id,operational_source_id,operational_source_version,operational_snapshot)
     values(p_tenant_id,p_legal_entity_id,cid,src.id,src.seal_id,src.after_revision_id,src.before_version+1,src.after_seconds,'apply',
      (operational->>'claim_id')::uuid,(operational->>'source_id')::uuid,(operational->>'source_version')::bigint,operational->'after');
   end loop;
   inputs:=jsonb_build_object('original_calculation_id',original.id,'employee_id',c.employee_id,'employee_name',original.inputs->>'employee_name',
    'employee_code',original.inputs->>'employee_code','start_date',original.inputs->>'start_date','end_date_exclusive',original.inputs->>'end_date_exclusive',
    'posting_date',c.posting_date,'currency_code',c.currency_code,'before',c.before_calculation,'after',c.after_calculation,'difference',c.difference,'synthetic',true);
   insert into people_payroll.correction_payslips values(gen_random_uuid(),p_tenant_id,p_legal_entity_id,p_branch_id,cid,c.employee_id,inputs,people_payroll.digest(inputs),clock_timestamp());
   update people_payroll.corrections set status='posted',posted_journal_id=journal,version=version+1 where id=cid;
  else
   if c.status<>'posted' then raise exception using errcode='55000',message='PAYROLL_CORRECTION_STATE_INVALID';end if;
   if exists(select 1 from people_payroll.corrections later join people_payroll.correction_events le on le.correction_id=later.id and le.action='post'
    where later.original_calculation_id=c.original_calculation_id and later.status='posted' and
    le.chain_sequence>(select chain_sequence from people_payroll.correction_events where correction_id=cid and action='post')) then
    raise exception using errcode='55000',message='PAYROLL_LATER_CORRECTION_BLOCKS_REVERSAL';end if;
   if exists(select 1 from people_payroll.correction_balances b where b.correction_id=cid and
    b.amount<>(select coalesce(sum(amount),0) from people_payroll.correction_balance_effects where balance_id=b.id)) then
    raise exception using errcode='55000',message='PAYROLL_ACTIVE_SETTLEMENT_BLOCKS_REVERSAL';end if;
   if coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or(p_payload->>'posting_date')::date<c.posting_date then
    raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
   if jsonb_typeof(coalesce(p_payload->'current_billing_impacts','[]')) is distinct from 'array'
    or jsonb_array_length(coalesce(p_payload->'current_billing_impacts','[]'))>50 then
    raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   seen:='{}';
   for x in select value from jsonb_array_elements(coalesce(p_payload->'current_billing_impacts','[]')) loop
    if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['seal_id','source_revision_id','expected_source_version','billing_credit_line_ids','allocation_credits'])
     or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['seal_id','source_revision_id','expected_source_version','billing_credit_line_ids','allocation_credits']))
     or coalesce(x->>'seal_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or coalesce(x->>'source_revision_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or jsonb_typeof(x->'expected_source_version') is distinct from 'number' or coalesce(x->>'expected_source_version','') !~ '^[1-9][0-9]{0,15}$'
     or (x->>'seal_id')::uuid=any(seen) or not exists(select 1 from people_payroll.correction_sources s where s.correction_id=cid and s.seal_id=(x->>'seal_id')::uuid and s.impact is not null and s.source_kind in('attendance','project','service'))
     or jsonb_typeof(x->'billing_credit_line_ids') is distinct from 'array' or jsonb_array_length(x->'billing_credit_line_ids')>50
     or jsonb_typeof(x->'allocation_credits') is distinct from 'array' or jsonb_array_length(x->'allocation_credits')>50 then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
    seen:=array_append(seen,(x->>'seal_id')::uuid);
    state:=people_payroll.correction_source_state((x->>'seal_id')::uuid);
    operational:=people_payroll.approved_source(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid);
    if x->>'source_revision_id' is distinct from operational->>'source_id'
     or (x->>'expected_source_version')::bigint is distinct from (operational->>'source_version')::bigint then
     raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
    perform people_payroll.current_credit_ids(x->'billing_credit_line_ids');
    perform people_payroll.current_allocation_credits(x->'allocation_credits');
    if (state->>'source_kind'='attendance' and jsonb_array_length(x->'billing_credit_line_ids')<>0)
     or(state->>'source_kind'<>'attendance' and jsonb_array_length(x->'allocation_credits')<>0) then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   end loop;
   perform finance.wave3_lock_open_period(p_tenant_id,p_legal_entity_id,(p_payload->>'posting_date')::date);
   if c.posted_journal_id is not null then
    select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,
     'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines
     where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=c.posted_journal_id;
    journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
     'document_date',p_payload->>'posting_date','currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
     lines,'payroll_correction_reverse',cid,request,p_command_id);
   end if;
   insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,reversal_of,recorded_by)
    select tenant_id,legal_entity_id,balance_id,'correction_reverse',-amount,cid,id,auth.uid() from people_payroll.correction_balance_effects where source_id=cid and kind='issue';
   for src in select * from people_payroll.correction_sources where correction_id=cid order by seal_id loop
    state:=people_payroll.correction_source_state(src.seal_id);replacement_id:=gen_random_uuid();
    if src.impact is not null then
     perform people_payroll.correction_source_permission(p_tenant_id,p_legal_entity_id,p_branch_id,src.source_kind,true);
     x:=(select value from jsonb_array_elements(coalesce(p_payload->'current_billing_impacts','[]')) where value->>'seal_id'=src.seal_id::text);
     operational:=people_payroll.source_impact(p_tenant_id,p_legal_entity_id,p_branch_id,c.employee_id,(state->>'claim_id')::uuid,replacement_id,
      src.impact||jsonb_build_object('current_billing_credit_line_ids',coalesce(x->'billing_credit_line_ids','[]'),
       'current_source_revision_id',x->'source_revision_id','current_source_version',x->'expected_source_version',
       'current_allocation_credits',coalesce(x->'allocation_credits','[]')),'reverse');
    else operational:=jsonb_build_object('claim_id',state->'claim_id','source_id',state->'operational_source_id','source_version',state->'operational_source_version','after',state->'operational_snapshot');end if;
    insert into people_payroll.correction_source_effects(tenant_id,legal_entity_id,correction_id,source_id,seal_id,revision_id,version,seconds,kind,reversal_of,operational_claim_id,operational_source_id,operational_source_version,operational_snapshot)
     values(p_tenant_id,p_legal_entity_id,cid,src.id,src.seal_id,replacement_id,(state->>'version')::bigint+1,src.before_seconds,'reverse',
      (select id from people_payroll.correction_source_effects where source_id=src.id and kind='apply'),(operational->>'claim_id')::uuid,
      (operational->>'source_id')::uuid,(operational->>'source_version')::bigint,operational->'after');
   end loop;
   update people_payroll.corrections set status='reversed',reversal_journal_id=journal,version=version+1 where id=cid;
  end if;
 end if;
 after_summary:=people_payroll.correction_summary(cid);
 insert into people_payroll.correction_events(tenant_id,legal_entity_id,branch_id,correction_id,original_calculation_id,action,version,chain_sequence,actor_id,reason,command_id)
 values(p_tenant_id,p_legal_entity_id,p_branch_id,cid,original.id,act,(after_summary->>'version')::bigint,
  case when act in('post','reverse') then seq+1 end,auth.uid(),btrim(p_payload->>'reason'),p_command_id);
 return core.wave3_finish_command(p_tenant_id,'people.payroll.correction.'||act,p_command_id,'people.payroll.correction',cid,p_idempotency_key,hash,
  before_summary,after_summary,p_legal_entity_id,p_branch_id,p_source_context=>jsonb_build_object('action',act),p_request_id=>request);
end $$;

create function people_payroll.original_run_correction_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.status='reversed' and old.status='posted' and exists(select 1 from people_payroll.corrections where original_run_id=old.id and status='posted') then
  raise exception using errcode='55000',message='PAYROLL_ACTIVE_CORRECTION_BLOCKS_REVERSAL';end if;return new;end $$;
create trigger payroll_original_correction_guard before update on people_payroll.runs for each row execute function people_payroll.original_run_correction_guard();

create function api.people_payroll_correction_settlement(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare act text:=p_payload->>'action';sid uuid;cid uuid;c people_payroll.corrections%rowtype;s people_payroll.correction_settlements%rowtype;
 bank finance.cash_bank_accounts%rowtype;b people_payroll.correction_balances%rowtype;
 x jsonb;lines jsonb:='[]';v_amount numeric;outstanding numeric;total numeric:=0;signum integer;seen uuid[]:='{}';
 hash text;replay jsonb;journal uuid;request uuid:=gen_random_uuid();answer jsonb;posting date;begin
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.payroll.settle',true);
 if act is null or act not in('record','reverse') or p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or p_expected_version is null or p_expected_version not between 0 and 9007199254740991 or jsonb_typeof(p_payload)<>'object'
  or octet_length(p_payload::text)>65536 or length(btrim(coalesce(p_payload->>'reason',''))) not between 1 and 1000
  or coalesce(p_payload->>'posting_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  or coalesce(p_payload->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or coalesce(p_payload->>'correction_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(case when act='record' then
  array['action','id','correction_id','posting_date','direction','bank_id','bank_version','allocations','evidence_reference','reason']
  else array['action','id','correction_id','posting_date','reason'] end)) then
  raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
 sid:=(p_payload->>'id')::uuid;cid:=(p_payload->>'correction_id')::uuid;posting:=(p_payload->>'posting_date')::date;
 hash:=core.wave3_request_hash('people.payroll.correction_settlement.'||act,p_command_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 replay:=core.wave3_replay(p_tenant_id,'people.payroll.correction_settlement.'||act,p_command_id,p_idempotency_key,hash);
 if replay is not null then return replay;end if;
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||p_tenant_id||':'||p_legal_entity_id,0));
 select * into c from people_payroll.corrections where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and id=cid;
 if c.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_NOT_FOUND';end if;
 perform 1 from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and id=c.employee_id for update;
 select * into c from people_payroll.corrections where id=cid for update;
 if c.status<>'posted' or posting<c.posting_date then raise exception using errcode='55000',message='PAYROLL_CORRECTION_SETTLEMENT_STATE_INVALID';end if;
 if act='record' then
  if p_expected_version<>0 or p_payload->>'direction' not in('pay','recover') or p_payload->>'direction' is null
   or length(btrim(coalesce(p_payload->>'evidence_reference',''))) not between 1 and 160
   or jsonb_typeof(p_payload->'bank_version')<>'number' or(p_payload->>'bank_version')::bigint not between 1 and 9007199254740991
   or jsonb_typeof(p_payload->'allocations')<>'array' or jsonb_array_length(p_payload->'allocations') not between 1 and 200 then
   raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
  signum:=case when p_payload->>'direction'='pay' then 1 else -1 end;
  select * into bank from finance.cash_bank_accounts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
   and id=(p_payload->>'bank_id')::uuid and status='active' and currency_code=c.currency_code for share;
  if bank.id is null then raise exception using errcode='55000',message='PAYROLL_BANK_PROVIDER_REQUIRED';end if;
  if bank.version<>(p_payload->>'bank_version')::bigint then raise exception using errcode='40001',message='PAYROLL_BANK_VERSION_CONFLICT';end if;
  perform finance.flow_account(p_tenant_id,p_legal_entity_id,bank.account_id,'asset',c.currency_code);
  for x in select value from jsonb_array_elements(p_payload->'allocations') order by value->>'balance_id' loop
   if jsonb_typeof(x)<>'object' or(select count(*) from jsonb_object_keys(x))<>2 or not(x ?& array['balance_id','amount'])
    or(x->>'balance_id')::uuid=any(seen) then raise exception using errcode='22023',message='PAYROLL_CORRECTION_SETTLEMENT_INVALID';end if;
   seen:=array_append(seen,(x->>'balance_id')::uuid);
   select * into b from people_payroll.correction_balances where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id
    and correction_id=cid and id=(x->>'balance_id')::uuid for update;
   if b.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_BALANCE_NOT_FOUND';end if;
   v_amount:=people_payroll.amount(x->'amount');
   select coalesce(sum(amount),0) into outstanding from people_payroll.correction_balance_effects where balance_id=b.id;
   if v_amount<=0 or outstanding*signum<=0 or v_amount>outstanding*signum then
    raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_EXCEEDS_DUE';end if;
   perform people_payroll.account(p_tenant_id,p_legal_entity_id,b.account_id,'liability',c.currency_code);
   total:=total+v_amount*signum;
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',b.account_id,'amount',(v_amount*signum)::text,'base_amount',(v_amount*signum)::text,'source_line_id',b.id));
  end loop;
  if abs(total)>99999999999999.999999 then raise exception using errcode='22023',message='PAYROLL_AMOUNT_OVERFLOW';end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank.account_id,'amount',(-total)::text,'base_amount',(-total)::text,'source_line_id',sid));
  journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',posting,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
   lines,'payroll_correction_settlement',sid,request,p_command_id);
  insert into people_payroll.correction_settlements(id,tenant_id,legal_entity_id,branch_id,correction_id,bank_id,bank_account_id,bank_version,currency_code,
   posting_date,direction,evidence_reference,reason,journal_id,recorded_by)
  values(sid,p_tenant_id,p_legal_entity_id,p_branch_id,cid,bank.id,bank.account_id,bank.version,c.currency_code,posting,p_payload->>'direction',
   btrim(p_payload->>'evidence_reference'),btrim(p_payload->>'reason'),journal,auth.uid());
  insert into people_payroll.correction_settlement_allocations select p_tenant_id,p_legal_entity_id,sid,(allocation->>'balance_id')::uuid,people_payroll.amount(allocation->'amount')
   from jsonb_array_elements(p_payload->'allocations') allocation;
  insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,recorded_by)
   select p_tenant_id,p_legal_entity_id,balance_id,'settle',-amount*signum,sid,auth.uid() from people_payroll.correction_settlement_allocations where settlement_id=sid;
  answer:=jsonb_build_object('id',sid,'correction_id',cid,'status','recorded','version',1,'journal_id',journal);
 else
  select * into s from people_payroll.correction_settlements where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and correction_id=cid and id=sid for update;
  if s.id is null then raise exception using errcode='P0002',message='PAYROLL_CORRECTION_SETTLEMENT_NOT_FOUND';end if;
  if s.version<>p_expected_version then raise exception using errcode='40001',message='PAYROLL_CORRECTION_VERSION_CONFLICT';end if;
  if s.status<>'recorded' then raise exception using errcode='55000',message='PAYROLL_SETTLEMENT_ALREADY_REVERSED';end if;
  if posting<s.posting_date then raise exception using errcode='22023',message='PAYROLL_OFFCYCLE_DATE_INVALID';end if;
  select jsonb_agg(jsonb_build_object('account_id',account_id,'source_line_id',source_line_id,'amount',(transaction_credit-transaction_debit)::text,
   'base_amount',(base_credit-base_debit)::text) order by line_number) into lines from finance.journal_lines
   where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and journal_entry_id=s.journal_id;
  journal:=finance.flow_post_journal(jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
   'document_date',posting,'currency_code',c.currency_code,'base_currency_code',c.currency_code,'exchange_rate','1.000000'),
   lines,'payroll_correction_settlement_reverse',sid,request,p_command_id);
  insert into people_payroll.correction_balance_effects(tenant_id,legal_entity_id,balance_id,kind,amount,source_id,reversal_of,recorded_by)
   select tenant_id,legal_entity_id,balance_id,'settlement_reverse',-amount,sid,id,auth.uid() from people_payroll.correction_balance_effects where source_id=sid and kind='settle';
  update people_payroll.correction_settlements set status='reversed',version=version+1,reversal_journal_id=journal where id=sid;
  answer:=jsonb_build_object('id',sid,'correction_id',cid,'status','reversed','version',s.version+1,'reversal_journal_id',journal);
 end if;
 return core.wave3_finish_command(p_tenant_id,'people.payroll.correction_settlement.'||act,p_command_id,'people.payroll.correction_settlement',sid,p_idempotency_key,hash,
  '{}',answer||jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id),p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('action',act),p_request_id=>request);end $$;

create function api.people_payroll_correction_own_receipt(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_command_id uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare cap text;result jsonb;begin
 cap:=case p_action when 'prepare' then 'people.payroll.correction.prepare' when 'approve' then 'people.payroll.correction.approve'
  when 'reject' then 'people.payroll.correction.approve' when 'post' then 'people.payroll.post' when 'reverse' then 'people.payroll.reverse'
  when 'settlement.record' then 'people.payroll.settle' when 'settlement.reverse' then 'people.payroll.settle' end;
 perform people_payroll.correction_access(p_tenant_id,p_legal_entity_id,p_branch_id,cap,true);
 select response into result from core.command_receipts where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and actor_id=auth.uid() and command_id=p_command_id
  and command_name=case when p_action like 'settlement.%' then 'people.payroll.correction_settlement.'||split_part(p_action,'.',2)
   else 'people.payroll.correction.'||p_action end;
 if result is not null and (result->'entity'->>'legal_entity_id' is distinct from p_legal_entity_id::text
  or result->'entity'->>'branch_id' is distinct from p_branch_id::text) then raise exception using errcode='42501',message='PAYROLL_RECEIPT_SCOPE_DENIED';end if;
 return result;end $$;

revoke all on all functions in schema people_payroll from public,anon,authenticated;
revoke all on function api.people_payroll_correction_authorize(uuid,uuid,uuid,text),
 api.people_payroll_correction_originals(uuid,uuid,uuid,uuid),api.people_payroll_correction_sources(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_corrections(uuid,uuid,uuid,uuid),api.people_payroll_correction_detail(uuid,uuid,uuid,uuid,text,uuid),
 api.people_payroll_correction_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_own_receipt(uuid,uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function api.people_payroll_correction_authorize(uuid,uuid,uuid,text),
 api.people_payroll_correction_originals(uuid,uuid,uuid,uuid),api.people_payroll_correction_sources(uuid,uuid,uuid,uuid,uuid),
 api.people_payroll_corrections(uuid,uuid,uuid,uuid),api.people_payroll_correction_detail(uuid,uuid,uuid,uuid,text,uuid),
 api.people_payroll_correction_command(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_settlement(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint),
 api.people_payroll_correction_own_receipt(uuid,uuid,uuid,uuid,text) to authenticated;

create or replace function people_payroll.freeze(t uuid,e uuid,b uuid,employee uuid,period_start date,period_end date,currency text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare assignment people.employment_assignments%rowtype;org people.organization_assignments%rowtype;
 calendar people.work_calendar_versions%rowtype;employee_row people.employees%rowtype;
 eligible_start date;eligible_end date;rules jsonb;facts jsonb;days jsonb:='[]';slot jsonb;day date;
 local_start timestamp;local_end timestamp;utc_start timestamptz;utc_end timestamptz;
 planned bigint:=0;paid bigint:=0;cnt integer;begin
 select * into employee_row from people.employees where tenant_id=t and legal_entity_id=e and id=employee;
 select count(*) into cnt from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt<>1 then raise exception using errcode='55000',message='PAYROLL_SINGLE_EMPLOYMENT_SLICE_REQUIRED';end if;
 select * into assignment from people.employment_assignments a where tenant_id=t and legal_entity_id=e
  and branch_id=b and employee_id=employee and daterange(a.start_date,a.end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 eligible_start:=greatest(period_start,assignment.start_date);eligible_end:=least(period_end,assignment.end_date_exclusive);
 select * into org from people.organization_assignments o where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and superseded_at is null and daterange(o.start_date,o.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if org.id is null then raise exception using errcode='55000',message='PAYROLL_ORGANIZATION_COVERAGE_REQUIRED';end if;
 select * into calendar from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=org.calendar_version_id
  and daterange(start_date,end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)');
 if calendar.id is null then raise exception using errcode='55000',message='PAYROLL_CALENDAR_COVERAGE_REQUIRED';end if;
 select count(*) into cnt from people_payroll.component_assignments a where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and daterange(start_date,end_date_exclusive,'[)') && daterange(period_start,period_end,'[)');
 if cnt not between 1 and 100 then raise exception using errcode='55000',message='PAYROLL_COMPONENT_BOUND_REQUIRED';end if;
 select coalesce(jsonb_agg(people_payroll.rule_payload(r.id)||jsonb_build_object('assignment_id',a.id) order by c.code),'[]'::jsonb) into rules
 from people_payroll.component_assignments a join people_payroll.components c on c.id=a.component_id
 join people_payroll.rule_versions r on r.component_id=a.component_id
 where a.tenant_id=t and a.legal_entity_id=e and a.branch_id=b and a.employee_id=employee
  and daterange(a.start_date,a.end_date_exclusive,'[)') @> daterange(eligible_start,eligible_end,'[)')
  and daterange(r.start_date,r.end_date_exclusive,'[)') @> daterange(period_start,period_end,'[)');
 if jsonb_array_length(rules)<>cnt then raise exception using errcode='55000',message='PAYROLL_RULE_COVERAGE_REQUIRED';end if;
 for day in select generate_series(eligible_start::timestamp,(eligible_end-1)::timestamp,interval '1 day')::date loop
  if exists(select 1 from jsonb_array_elements(calendar.date_overrides) x where x->>'date'=day::text and not(x->>'is_working_day')::boolean) then continue;end if;
  for slot in select value from jsonb_array_elements(calendar.weekly_intervals) where (value->>'day_of_week')::integer=extract(isodow from day)::integer loop
   local_start:=day::timestamp+(slot->>'start_minute')::integer*interval '1 minute';
   local_end:=day::timestamp+(slot->>'end_day_offset')::integer*interval '1 day'+(slot->>'end_minute')::integer*interval '1 minute';
   utc_start:=people.resolve_local_instant(calendar.timezone,local_start);
   utc_end:=people.resolve_local_instant(calendar.timezone,local_end);
   if local_end>eligible_end::timestamp then raise exception using errcode='55000',message='PAYROLL_OVERNIGHT_SLICE_REQUIRED';end if;
   planned:=planned+extract(epoch from utc_end-utc_start)::bigint;
   days:=days||jsonb_build_array(jsonb_build_object('date',day,'start_local',local_start,'end_local',local_end,
    'start_utc',utc_start,'end_utc',utc_end,'seconds',extract(epoch from utc_end-utc_start)::bigint));
   if jsonb_array_length(days)>2000 then raise exception using errcode='55000',message='PAYROLL_PLANNED_SLOT_BOUND_REQUIRED';end if;
  end loop;
 end loop;
 -- Any unresolved or boundary-straddling claim is explicit; never silently truncate.
 utc_start:=people.resolve_local_instant(calendar.timezone,eligible_start::timestamp);
 utc_end:=people.resolve_local_instant(calendar.timezone,eligible_end::timestamp);
 if exists(select 1 from people.work_claims w where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee
  and w.active and tstzrange(w.start_utc,w.end_utc,'[)') && tstzrange(utc_start,utc_end,'[)')
  and (w.start_utc<utc_start or w.end_utc>utc_end)) then
  raise exception using errcode='55000',message='PAYROLL_WORK_BOUNDARY_SLICE_REQUIRED';end if;
 select count(*) into cnt from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and active and start_utc>=utc_start and end_utc<=utc_end;
 if cnt>2000 then raise exception using errcode='55000',message='PAYROLL_SOURCE_BOUND_REQUIRED';end if;
 for facts in select jsonb_build_array(people_payroll.approved_source(t,e,b,employee,id)) from people.work_claims
  where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and active and start_utc>=utc_start and end_utc<=utc_end loop
  null;
 end loop;
 select coalesce(jsonb_agg(jsonb_build_object('claim_id',w.id,'source_kind',w.source_kind,'source_id',w.source_id,
  'source_version',(provider.body->>'source_version')::bigint,
  'calendar_version_id',w.calendar_version_id,'start_utc',w.start_utc,'end_utc',w.end_utc,
  'gross_seconds',w.gross_seconds,'break_seconds',w.break_seconds,'paid_seconds',(provider.body->>'paid_seconds')::bigint,
  'leave_policy_version_id',lr.policy_version_id,'leave_charge_seconds',lr.charge_seconds,'unpaid_seconds',lr.unpaid_seconds,
  'leave_effects',case when w.source_kind='leave' then(select coalesce(jsonb_agg(jsonb_build_object('id',le.id,'grant_id',le.grant_id,
   'seconds',le.seconds,'reversal_of',le.reversal_of) order by le.id),'[]'::jsonb) from people.leave_effects le where le.request_id=lr.id) end)
  order by w.id),'[]'::jsonb) into facts from people.work_claims w
  cross join lateral(select people_payroll.approved_source(t,e,b,employee,w.id) body) provider
  left join people.leave_requests lr on lr.active_claim_id=w.id and w.source_kind='leave'
  where w.tenant_id=t and w.legal_entity_id=e and w.branch_id=b and w.employee_id=employee and w.active
   and w.start_utc>=utc_start and w.end_utc<=utc_end;
 select coalesce(sum((x->>'paid_seconds')::bigint),0) into paid from jsonb_array_elements(facts) x;
 return jsonb_build_object('employee_id',employee,'employee_version',employee_row.version,'employee_code',employee_row.code,
  'employee_name',employee_row.display_name,'employment_assignment',jsonb_build_object('id',assignment.id,'spell_id',assignment.spell_id,
   'start_date',assignment.start_date,'end_date_exclusive',assignment.end_date_exclusive,'type',assignment.employment_type,'job_title',assignment.job_title),
  'organization_assignment_id',org.id,'calendar_version_id',calendar.id,'timezone',calendar.timezone,
  'start_date',period_start,'end_date_exclusive',period_end,'eligible_start',eligible_start,'eligible_end_exclusive',eligible_end,
  'period_days',period_end-period_start,'eligible_days',eligible_end-eligible_start,
  'paid_seconds',paid,'planned_seconds',planned,'planned_slots',days,'sources',facts,'rules',rules);
end $$;


revoke all on function people_payroll.freeze(uuid,uuid,uuid,uuid,date,date,text) from public,anon,authenticated;

-- Trusted operational impact adapters. Ordinary source commands continue to use
-- revoke_work_claim and its seal guard; this path requires an approved linked
-- correction and appends a new claim, never rewriting sealed geometry.
create function people_payroll.current_credit_ids(ids jsonb) returns void language plpgsql set search_path='' as $$begin
 if jsonb_typeof(ids) is distinct from 'array' or jsonb_array_length(ids)>50
  or exists(select 1 from jsonb_array_elements(ids) x where jsonb_typeof(x) is distinct from 'string'
   or (x#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  or (select count(distinct x#>>'{}') from jsonb_array_elements(ids) x)<>jsonb_array_length(ids) then
  raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
end $$;
create function people_payroll.current_allocation_credits(rows jsonb) returns void language plpgsql set search_path='' as $$
declare x jsonb;seen uuid[]:='{}';begin
 if jsonb_typeof(rows) is distinct from 'array' or jsonb_array_length(rows)>50 then
  raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
 for x in select value from jsonb_array_elements(rows) loop
  if jsonb_typeof(x) is distinct from 'object' or not(x ?& array['entry_id','source_revision_id','expected_source_version','billing_credit_line_ids'])
   or exists(select 1 from jsonb_object_keys(x) k where k<>all(array['entry_id','source_revision_id','expected_source_version','billing_credit_line_ids']))
   or coalesce(x->>'entry_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or coalesce(x->>'source_revision_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(x->'expected_source_version') is distinct from 'number' or coalesce(x->>'expected_source_version','') !~ '^[1-9][0-9]{0,15}$'
   or (x->>'entry_id')::uuid=any(seen) then raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
  seen:=array_append(seen,(x->>'entry_id')::uuid);
  perform people_payroll.current_credit_ids(x->'billing_credit_line_ids');
 end loop;
end $$;
create function people_payroll.replace_claim(t uuid,e uuid,b uuid,employee uuid,old_claim uuid,
 kind text,source_id uuid,calendar uuid,p_start timestamptz,p_end timestamptz,p_breaks jsonb,correction_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare c people_payroll.corrections%rowtype;w people.work_claims%rowtype;new_claim uuid;new_w people.work_claims%rowtype;begin
 perform pg_advisory_xact_lock(hashtextextended('people.payroll:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('projects:'||t||':'||e,0));
 perform pg_advisory_xact_lock(hashtextextended('service:'||t||':'||e,0));
 perform 1 from people.employees where tenant_id=t and legal_entity_id=e and id=employee for update;
 select * into c from people_payroll.corrections where tenant_id=t and legal_entity_id=e and branch_id=b
  and employee_id=employee and id=correction_id and status in('approved','posted');
 if c.id is null or not exists(select 1 from people_payroll.correction_sources s where s.correction_id=c.id
  and s.source_kind=kind and s.impact is not null
  and (people_payroll.correction_source_state(s.seal_id)->>'claim_id')::uuid is not distinct from old_claim) then
  raise exception using errcode='42501',message='PAYROLL_APPROVED_LINKED_IMPACT_REQUIRED';end if;
 if old_claim is not null then
  select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and id=old_claim and source_kind=kind and active for update;
  if w.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if exists(select 1 from people.work_allocations where claim_id=w.id and active) then
   raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
  update people.work_claims set active=false,revoked_at=clock_timestamp() where id=w.id;
  update people.work_claim_segments set active=false where claim_id=w.id and active;
 end if;
 if source_id is null then return null;end if;
 new_claim:=people.make_work_claim(t,e,b,employee,kind,source_id,p_start,p_end,p_breaks,calendar,auth.uid());
 select * into new_w from people.work_claims where id=new_claim;
 insert into people.work_input_seals(tenant_id,legal_entity_id,employee_id,run_id,claim_id,source_version,seconds,digest)
  values(t,e,employee,c.original_run_id,new_claim,1,new_w.payable_seconds,people_payroll.digest(to_jsonb(new_w)));
 return new_claim;
end $$;

create function people_payroll.source_impact(t uuid,e uuid,b uuid,employee uuid,claim uuid,
 revision uuid,proposal jsonb,p_mode text) returns jsonb language plpgsql security definer set search_path='' as $$
declare w people.work_claims%rowtype;a people.attendance_entries%rowtype;r people.attendance_revisions%rowtype;
 l people.leave_requests%rowtype;account people.leave_accounts%rowtype;calendar people.work_calendar_versions%rowtype;
 body jsonb;before_body jsonb;after_body jsonb;target jsonb;result jsonb;effect jsonb;effects jsonb;
 start_local timestamp;end_local timestamp;start_utc timestamptz;end_utc timestamptz;break_seconds bigint;
 new_claim uuid;source_kind text:=proposal->>'source_kind';allocation people.work_allocations%rowtype;
 allocation_body jsonb;allocation_effects jsonb:='[]';change jsonb;change_ids uuid[]:='{}';linked_ids uuid[]:='{}';
begin
 if p_mode not in('read','validate','apply','reverse') or revision is null then raise exception using errcode='22023',message='PAYROLL_SOURCE_IMPACT_INVALID';end if;
 select * into w from people.work_claims where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and id=claim and active;
 source_kind:=coalesce(w.source_kind,source_kind);
 if p_mode='read' then perform people_payroll.correction_source_permission(t,e,b,source_kind,false);end if;
 if source_kind in('project','service') then
  if to_regprocedure(source_kind||'s.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null and source_kind='project' then
   execute 'select projects.payroll_impact($1,$2,$3,$4,$5,$6,$7,$8)' into result using t,e,b,employee,claim,revision,proposal,p_mode;
  elsif source_kind='service' and to_regprocedure('service.payroll_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)') is not null then
   execute 'select service.payroll_impact($1,$2,$3,$4,$5,$6,$7,$8)' into result using t,e,b,employee,claim,revision,proposal,p_mode;
  else raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';end if;
  return result;
 end if;
 if source_kind='attendance' then
  select * into a from people.attendance_entries where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee and active_claim_id=claim and status='approved';
  select * into r from people.attendance_revisions where id=a.current_revision_id;
  if a.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  before_body:=to_jsonb(r)||jsonb_build_object('entry_version',a.version,'claim_id',claim);
  if p_mode='read' then
   for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
    if to_regprocedure(case allocation.source_kind when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';
    else
     execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
      into allocation_body using t,e,b,employee,allocation.id,revision,proposal,'read';
    end if;
    allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',allocation.id,'source_kind',allocation.source_kind,'source_id',allocation.source_id,'operational',allocation_body));
   end loop;
   return jsonb_build_object('before',before_body,'source_id',r.id,'source_version',a.version,'paid_seconds',r.payable_seconds,'claim_id',claim,'allocations',allocation_effects);
  end if;
  if p_mode<>'reverse' and (a.version is distinct from(proposal->>'expected_source_version')::bigint
   or proposal->>'mode' is distinct from 'geometry') then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  target:=case when p_mode='reverse' then proposal->'before' else proposal end;
  if p_mode='apply' and proposal->'before' is distinct from before_body then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  select * into calendar from people.work_calendar_versions where tenant_id=t and legal_entity_id=e and id=r.calendar_version_id;
  start_local:=(target->>'start_local')::timestamp;end_local:=(target->>'end_local')::timestamp;
  if extract(second from start_local)%1<>0 or extract(second from end_local)%1<>0 then raise exception using errcode='22023',message='WORK_LOCAL_BOUNDARY_INVALID';end if;
  perform people.work_local_coverage(t,e,b,employee,calendar.id,start_local,end_local);
  start_utc:=people.resolve_local_instant(calendar.timezone,start_local,(target->>'start_offset_seconds')::integer);
  end_utc:=people.resolve_local_instant(calendar.timezone,end_local,(target->>'end_offset_seconds')::integer);
  break_seconds:=people.work_break_seconds(start_utc,end_utc,target->'breaks');
  after_body:=jsonb_build_object('start_local',start_local,'end_local',end_local,'start_offset_seconds',(target->>'start_offset_seconds')::integer,
   'end_offset_seconds',(target->>'end_offset_seconds')::integer,'start_utc',start_utc,'end_utc',end_utc,'breaks',target->'breaks',
   'gross_seconds',extract(epoch from end_utc-start_utc)::bigint,'break_seconds',break_seconds,
   'payable_seconds',extract(epoch from end_utc-start_utc)::bigint-break_seconds,'calendar_version_id',calendar.id);
  if p_mode<>'reverse' then
   for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
    execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,allocation.id,revision,proposal,'read';
    if coalesce((allocation_body->>'entry_id')::uuid,(allocation_body->'before'->>'entry_id')::uuid,(allocation_body->'before'->>'id')::uuid) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    linked_ids:=array_append(linked_ids,coalesce((allocation_body->>'entry_id')::uuid,(allocation_body->'before'->>'entry_id')::uuid,(allocation_body->'before'->>'id')::uuid));
   end loop;
   if jsonb_typeof(coalesce(proposal->'allocation_changes','[]')) is distinct from 'array'
    or jsonb_array_length(coalesce(proposal->'allocation_changes','[]'))>50 then raise exception using errcode='22023',message='WORK_ALLOCATION_IMPACT_INVALID';end if;
   for change in select value from jsonb_array_elements(coalesce(proposal->'allocation_changes','[]')) loop
    if jsonb_typeof(change) is distinct from 'object' or exists(select 1 from jsonb_object_keys(change) k where k<>all(array['entry_id','mode','start_local','end_local','start_offset_seconds','end_offset_seconds','breaks','billing_credit_line_ids']))
     or coalesce(change->>'mode','') not in('retain','geometry','remove')
     or coalesce(change->>'entry_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     or (change->>'entry_id')::uuid=any(change_ids)
     or not ((change->>'entry_id')::uuid=any(linked_ids)) then
     raise exception using errcode='22023',message='WORK_ALLOCATION_IMPACT_INVALID';end if;
    change_ids:=array_append(change_ids,(change->>'entry_id')::uuid);
   end loop;
  end if;
  if p_mode='reverse' then
   for effect in select value from jsonb_array_elements(proposal->'after'->'allocation_impacts') loop
    if coalesce((effect->'impact'->>'entry_id')::uuid,(effect->'impact'->'before'->>'entry_id')::uuid,(effect->'impact'->'before'->>'id')::uuid) is null then
     raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
    linked_ids:=array_append(linked_ids,coalesce((effect->'impact'->>'entry_id')::uuid,(effect->'impact'->'before'->>'entry_id')::uuid,(effect->'impact'->'before'->>'id')::uuid));
   end loop;
   for change in select value from jsonb_array_elements(coalesce(proposal->'current_allocation_credits','[]')) loop
    if not ((change->>'entry_id')::uuid=any(linked_ids)) or linked_ids is null then
     raise exception using errcode='22023',message='PAYROLL_CURRENT_BILLING_IMPACT_INVALID';end if;
   end loop;
   for effect in select value from jsonb_array_elements(proposal->'after'->'allocation_impacts') loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,
      proposal||jsonb_build_object('attendance_after',after_body,'operational_mode','reverse','current_claim_id',claim,'allocation_impact',effect->'impact'),'validate';
    allocation_effects:=allocation_effects||jsonb_build_array(effect||jsonb_build_object('impact',allocation_body,'original_impact',effect->'impact'));
   end loop;
  else
  for allocation in select * from people.work_allocations where claim_id=claim and active order by id loop
   if to_regprocedure(case allocation.source_kind when 'project' then 'projects.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' else 'service.payroll_allocation_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text)' end) is null then
    raise exception using errcode='55000',message='WORK_ALLOCATION_IMPACT_REQUIRED';end if;
   execute case allocation.source_kind when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
    into allocation_body using t,e,b,employee,allocation.id,revision,proposal||jsonb_build_object('attendance_after',after_body),case when p_mode in('apply','reverse') then 'validate' else p_mode end;
   allocation_effects:=allocation_effects||jsonb_build_array(jsonb_build_object('allocation_id',allocation.id,'source_kind',allocation.source_kind,'impact',allocation_body));
  end loop;
  end if;
  after_body:=after_body||jsonb_build_object('allocation_impacts',allocation_effects);
  if p_mode in('apply','reverse') then
   if p_mode='apply' and after_body is distinct from proposal->'after' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   -- Module hooks relinquish old allocations before the common claim replacement.
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'operational_mode',p_mode,'current_claim_id',claim,'allocation_impact',coalesce(effect->'original_impact',effect->'impact')),'release';
   end loop;
   new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'attendance',revision,calendar.id,start_utc,end_utc,target->'breaks',(proposal->>'correction_id')::uuid);
   insert into people.attendance_revisions(id,tenant_id,legal_entity_id,branch_id,employee_id,entry_id,version,calendar_version_id,
    start_local,start_offset_seconds,end_local,end_offset_seconds,start_utc,end_utc,breaks,gross_seconds,break_seconds,payable_seconds,
    reason,supersedes_revision_id,recorded_by)
   values(revision,t,e,b,employee,a.id,a.version+1,calendar.id,start_local,(target->>'start_offset_seconds')::integer,end_local,
    (target->>'end_offset_seconds')::integer,start_utc,end_utc,target->'breaks',extract(epoch from end_utc-start_utc)::bigint,
    break_seconds,extract(epoch from end_utc-start_utc)::bigint-break_seconds,'Linked sealed payroll source correction',r.id,auth.uid());
   update people.attendance_entries set current_revision_id=revision,active_claim_id=new_claim,version=version+1,decided_by=auth.uid() where id=a.id;
   insert into people.attendance_events(tenant_id,legal_entity_id,branch_id,employee_id,entry_id,revision_id,
    action,before_status,after_status,reason,actor_id,command_id)
    values(t,e,b,employee,a.id,revision,'correct','approved','approved',
     case when p_mode='reverse' then 'Original geometry restored by linked payroll correction reversal' else 'Approved geometry appended by linked payroll source correction' end,
     auth.uid(),revision);
   for effect in select value from jsonb_array_elements(allocation_effects) loop
    execute case effect->>'source_kind' when 'project' then 'select projects.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' else 'select service.payroll_allocation_impact($1,$2,$3,$4,$5,$6,$7,$8)' end
     into allocation_body using t,e,b,employee,(effect->>'allocation_id')::uuid,revision,proposal||jsonb_build_object('attendance_after',after_body,'new_claim_id',new_claim,'operational_mode',p_mode,'current_claim_id',claim,'allocation_impact',coalesce(effect->'original_impact',effect->'impact')),p_mode;
   end loop;
  else new_claim:=claim;end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',revision,'source_version',a.version+1,
   'paid_seconds',extract(epoch from end_utc-start_utc)::bigint-break_seconds,'claim_id',new_claim);
 elsif source_kind='leave' then
  select * into l from people.leave_requests where tenant_id=t and legal_entity_id=e and branch_id=b and employee_id=employee
   and (active_claim_id=claim or (p_mode='reverse' and id=(proposal->'before'->>'id')::uuid)
    or (p_mode='read' and claim is null and id=coalesce((proposal->'snapshot'->>'request_id')::uuid,(proposal->>'original_source_id')::uuid)));
  if l.id is null then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  select * into account from people.leave_accounts where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
  if p_mode in('apply','reverse') then select * into account from people.leave_accounts where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id for update;end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]') into effects from people.leave_effects x where x.request_id=l.id
   and x.seconds<0 and not exists(select 1 from people.leave_effects y where y.reversal_of=x.id);
  before_body:=to_jsonb(l)||jsonb_build_object('balance_version',account.version,'effects',effects);
  if p_mode='read' then return jsonb_build_object('before',before_body,'source_id',coalesce(w.source_id,l.id),'source_version',l.version,'paid_seconds',case when l.status='cancelled' then 0 else l.charge_seconds-l.unpaid_seconds end,'claim_id',claim);end if;
  if p_mode<>'reverse' and (l.status<>'approved' or l.version is distinct from(proposal->>'expected_source_version')::bigint
   or proposal->>'mode' is distinct from 'cancel_leave') then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  if p_mode='apply' and proposal->'before' is distinct from before_body then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
  after_body:=jsonb_build_object('status','cancelled','request_id',l.id,'original_effects',effects);
  if p_mode='apply' then
   new_claim:=people_payroll.replace_claim(t,e,b,employee,claim,'leave',null,l.calendar_version_id,l.start_utc,l.end_utc,'[]',(proposal->>'correction_id')::uuid);
   insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,effective_date,seconds,reversal_of,recorded_by)
    select tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,(clock_timestamp() at time zone 'UTC')::date,-seconds,id,auth.uid()
    from people.leave_effects x where x.request_id=l.id and x.seconds<0 and not exists(select 1 from people.leave_effects y where y.reversal_of=x.id);
   update people.leave_requests set status='cancelled',active_claim_id=null,version=version+1,decided_by=auth.uid() where id=l.id;
   update people.leave_accounts set version=version+1 where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
  elsif p_mode='reverse' then
   if l.status<>'cancelled' then raise exception using errcode='40001',message='PAYROLL_CORRECTION_SOURCE_CHANGED';end if;
   for effect in select value from jsonb_array_elements(proposal->'before'->'effects') loop
    if not exists(select 1 from people.leave_grants g where g.id=(effect->>'grant_id')::uuid and g.tenant_id=t and g.legal_entity_id=e and g.employee_id=employee
     and g.seconds+coalesce((select sum(x.seconds) from people.leave_effects x where x.grant_id=g.id),0)>=-(effect->>'seconds')::bigint) then
     raise exception using errcode='55000',message='LEAVE_ORIGINAL_BALANCE_IMPACT_REQUIRED';end if;
    insert into people.leave_effects(tenant_id,legal_entity_id,employee_id,policy_id,grant_id,request_id,effective_date,seconds,recorded_by)
     values(t,e,employee,l.policy_id,(effect->>'grant_id')::uuid,l.id,(effect->>'effective_date')::date,(effect->>'seconds')::bigint,auth.uid());
   end loop;
   new_claim:=people_payroll.replace_claim(t,e,b,employee,null,'leave',revision,l.calendar_version_id,l.start_utc,l.end_utc,'[]',(proposal->>'correction_id')::uuid);
   update people.leave_requests set status='approved',active_claim_id=new_claim,version=version+1,decided_by=auth.uid() where id=l.id;
   update people.leave_accounts set version=version+1 where tenant_id=t and legal_entity_id=e and employee_id=employee and policy_id=l.policy_id;
   after_body:=proposal->'before';
  else new_claim:=claim;end if;
  if p_mode in('apply','reverse') then
   insert into people.leave_events(tenant_id,legal_entity_id,branch_id,employee_id,request_id,
    action,before_status,after_status,reason,actor_id,command_id)
    values(t,e,b,employee,l.id,case when p_mode='apply' then 'cancel' else 'approve' end,l.status,
     case when p_mode='apply' then 'cancelled' else 'approved' end,
     case when p_mode='apply' then 'Original grant debits restored by linked payroll leave cancellation' else 'Original grant debits reconsumed by linked payroll correction reversal' end,
     auth.uid(),revision);
  end if;
  return jsonb_build_object('before',before_body,'after',after_body,'source_id',case when p_mode='reverse' then revision else l.id end,
   'source_version',l.version+1,'paid_seconds',case when p_mode='reverse' then l.charge_seconds-l.unpaid_seconds else 0 end,'claim_id',new_claim);
 end if;
 raise exception using errcode='55000',message='PAYROLL_SOURCE_IMPACT_PROVIDER_REQUIRED';
end $$;
revoke all on function people_payroll.replace_claim(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid,timestamptz,timestamptz,jsonb,uuid),
 people_payroll.source_impact(uuid,uuid,uuid,uuid,uuid,uuid,jsonb,text),people_payroll.current_credit_ids(jsonb),
 people_payroll.current_allocation_credits(jsonb) from public,anon,authenticated;
