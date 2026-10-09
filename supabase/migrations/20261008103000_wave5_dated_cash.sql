-- UNAPPLIED candidate. Uses posted journals, immutable AR items, and corrected
-- AP residuals. W4 payroll/project reimbursements lack authoritative payment
-- due dates and are explicitly unavailable from this provider.
create function analytics.cash_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null or e is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 perform core.wave3_require_scope(t,'finance.view',e,b);
 perform core.wave3_require_scope(t,'finance.receivables.view',e,b);
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>statement_timestamp())
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>statement_timestamp())))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';end if;
end $$;
revoke all on function analytics.cash_access(uuid,uuid,uuid) from public,anon,authenticated;

create function api.wave5_cash_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid) returns uuid
language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);return auth.uid();end $$;

-- Use separately owned AP read/reversal providers when installed. The fallback
-- only recognizes existing payment capabilities and never invents a bill API.
create function analytics.cash_payables_allowed(p_tenant uuid,p_entity uuid,p_branch uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$declare allowed boolean;begin
 if pg_catalog.to_regprocedure('finance.payable_read_allowed(uuid,uuid,uuid)') is not null then
  execute 'select finance.payable_read_allowed($1,$2,$3)' into allowed using p_tenant,p_entity,p_branch;
  return coalesce(allowed,false);
 end if;
 return core.is_tenant_member(p_tenant) and (core.has_permission(p_tenant,'finance.payments.manage',p_entity,p_branch)
  or core.has_permission(p_tenant,'finance.payments.post',p_entity,p_branch));
end $$;
create function analytics.cash_ap_reversal_evidence(p_tenant uuid,p_allocation uuid,p_before date,p_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare evidence jsonb;begin
 if pg_catalog.to_regclass('finance.allocation_reversals') is null then return null;end if;
 execute 'select jsonb_build_object(''id'',r.id,''postingDate'',r.posting_date::text) from finance.allocation_reversals r
  where r.tenant_id=$1 and r.allocation_id=$2 and r.posting_date<$3 and r.created_at<=$4 limit 1'
  into evidence using p_tenant,p_allocation,p_before,p_through;
 return evidence;
end $$;
revoke all on function analytics.cash_payables_allowed(uuid,uuid,uuid),analytics.cash_ap_reversal_evidence(uuid,uuid,date,timestamptz) from public,anon,authenticated;

create function api.wave5_cash_basis(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_start date,p_end date,p_recorded_through timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare controls jsonb;obligations jsonb;sources jsonb;result jsonb;n integer;
 can_read_payables boolean;providers jsonb:='["bank_cash","receivables"]'::jsonb;provider_status jsonb;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 can_read_payables:=analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,p_branch_id);
 if can_read_payables then providers:=providers||jsonb_build_array('payables');end if;
 provider_status:=jsonb_build_object('bank_cash','available','receivables','available',
  'payables',case when can_read_payables then 'available' else 'permission_required' end,
  'payroll','missing_authoritative_due_date','project_reimbursements','missing_authoritative_due_date');
 if p_start is null or p_end is null or p_end<=p_start or p_end-p_start>366 or not isfinite(p_start) or not isfinite(p_end)
  or p_recorded_through is null or not isfinite(p_recorded_through) or p_recorded_through>statement_timestamp()
  or p_start::timestamptz>p_recorded_through then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 -- Current cash-account configuration has no historical mapping journal.
 -- Reject a date predating its latest revision instead of inventing that mapping.
 if exists(select 1 from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.updated_at>p_start::timestamptz) then
  raise exception using errcode='55000',message='CASH_MAPPING_HISTORY_REQUIRED';end if;
 if exists(select account_id from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.status='active' group by account_id having count(*)>1) then
  raise exception using errcode='55000',message='CASH_CONTROL_MAPPING_AMBIGUOUS';end if;
 if exists(select 1 from finance.cash_bank_accounts c join finance.journal_lines l on l.tenant_id=c.tenant_id and l.account_id=c.account_id
  join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
  where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id and (p_branch_id is null or c.branch_id=p_branch_id)
   and (p_branch_id is null or l.branch_id=p_branch_id) and c.status='active' and j.status='posted'
   and l.posting_date<p_start and j.created_at<=p_recorded_through and l.currency_code<>c.currency_code
   and l.transaction_debit<>l.transaction_credit) then
  raise exception using errcode='55000',message='CASH_CURRENCY_MAPPING_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'accountId',c.account_id,'branchId',c.branch_id,'currency',c.currency_code,
  'version',c.version::text,'amount',coalesce((select sum(l.transaction_debit-l.transaction_credit)
   from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
   where l.tenant_id=c.tenant_id and l.legal_entity_id=c.legal_entity_id and l.account_id=c.account_id and l.currency_code=c.currency_code
    and (p_branch_id is null or l.branch_id=p_branch_id) and l.posting_date<p_start and j.status='posted' and j.created_at<=p_recorded_through),0)::text) order by c.id),'[]')
 into controls from finance.cash_bank_accounts c where c.tenant_id=p_tenant_id and c.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or c.branch_id=p_branch_id) and c.status='active';
 with ar_remaining as (select o.*,o.original_amount+
  coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0)-
  coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0) remaining
  from finance.open_items o where o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id and (p_branch_id is null or o.branch_id=p_branch_id)
   and o.kind='AR' and o.original_amount>0 and o.posting_date<p_start and o.created_at<=p_recorded_through and o.due_date>=p_start and o.due_date<p_end),
 ap_remaining as (select o.*,o.original_amount+
  coalesce((select sum(a.source_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.source_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through),0)-
  coalesce((select sum(a.transaction_amount+a.write_off+a.discount_amount) from finance.open_item_allocations a where a.tenant_id=o.tenant_id and a.target_open_item_id=o.id
   and a.posting_date<p_start and a.created_at<=p_recorded_through
   and analytics.cash_ap_reversal_evidence(a.tenant_id,a.id,p_start,p_recorded_through) is null),0) remaining
  from finance.open_items o where can_read_payables and o.tenant_id=p_tenant_id and o.legal_entity_id=p_legal_entity_id
   and (p_branch_id is null or o.branch_id=p_branch_id) and o.kind='AP' and o.original_amount>0 and o.posting_date<p_start
   and o.created_at<=p_recorded_through and o.due_date>=p_start and o.due_date<p_end),
 all_rows as (select id,branch_id,currency_code,due_date,remaining,'receivables'::text provider from ar_remaining where remaining>0
  union all select id,branch_id,currency_code,due_date,remaining,'payables'::text provider from ap_remaining where remaining>0),
 bounded as (select * from all_rows order by provider,id limit 10001)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'branchId',branch_id,'currency',currency_code,'dueDate',due_date::text,
  'amount',remaining::text,'version','1','provider',provider) order by provider,id),'[]'),count(*) into obligations,n from bounded;
 if n+jsonb_array_length(controls)>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- Retain each contributing posted journal/allocation identity, bounded as a
 -- complete manifest. Mutable document text and customer PII are excluded.
 with refs as (
 select jsonb_build_object('kind','cash_journal','id',l.id,'branchId',l.branch_id,'version','1',
  'debit',l.transaction_debit::text,'credit',l.transaction_credit::text,'currency',l.currency_code) value
 from finance.journal_lines l join finance.journal_entries j on j.tenant_id=l.tenant_id and j.id=l.journal_entry_id
 where l.tenant_id=p_tenant_id and l.legal_entity_id=p_legal_entity_id and (p_branch_id is null or l.branch_id=p_branch_id)
  and l.posting_date<p_start and j.status='posted' and j.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(controls) c where c->>'accountId'=l.account_id::text)
 union all select jsonb_build_object('kind','ar_allocation','id',a.id,'branchId',a.branch_id,'version','1',
  'sourceAmount',a.source_amount::text,'targetAmount',a.transaction_amount::text,'writeOff',a.write_off::text,'discount',a.discount_amount::text)
 from finance.open_item_allocations a where a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.posting_date<p_start and a.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(obligations) o where o->>'provider'='receivables' and o->>'id' in(a.source_open_item_id::text,a.target_open_item_id::text))
 union all select jsonb_build_object('kind','ap_allocation','id',a.id,'branchId',a.branch_id,'version','1',
  'sourceAmount',a.source_amount::text,'targetAmount',a.transaction_amount::text,'writeOff',a.write_off::text,'discount',a.discount_amount::text,
  'reversal',analytics.cash_ap_reversal_evidence(a.tenant_id,a.id,p_start,p_recorded_through))
 from finance.open_item_allocations a where can_read_payables and a.tenant_id=p_tenant_id and a.legal_entity_id=p_legal_entity_id
  and a.posting_date<p_start and a.created_at<=p_recorded_through
  and exists(select 1 from jsonb_array_elements(obligations) o where o->>'provider'='payables' and o->>'id' in(a.source_open_item_id::text,a.target_open_item_id::text)))
 select coalesce(jsonb_agg(value order by value->>'id'),'[]'),count(*) into sources,n from (select * from refs limit 10001) r;
 if n>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 if exists(select 1 from jsonb_array_elements(controls||obligations||sources) r where not core.has_permission(p_tenant_id,'finance.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or (r->>'provider'='receivables' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or (r->>'kind' like 'ar_%' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or ((r->>'provider'='payables' or r->>'kind' like 'ap_%') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 result:=jsonb_build_object('contractRevision',2,'definition','dated_transaction_cash_ar_and_ap.v2',
  'scope',jsonb_build_object('tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,'branchId',p_branch_id),
  'horizonStart',p_start::text,'horizonEnd',p_end::text,'recordedThrough',analytics.process_utc(p_recorded_through),
  'completeProviders',providers,'providerStatus',provider_status,'controls',controls,'obligations',obligations,'sources',sources,
  'exclusions',jsonb_build_array('overdue_before_horizon','unallocated_credits','payroll','project_reimbursements'));
 if octet_length(result::text)>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return jsonb_build_object('canonicalText',result::text,'sourceHash',encode(extensions.digest(result::text,'sha256'),'hex'));
end $$;
create table analytics.cash_scenario_revisions(id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid,
 actor_id uuid not null references auth.users(id),source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
 canonical_text text not null,evidence jsonb not null,parameters jsonb not null,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),foreign key(tenant_id,legal_entity_id) references core.legal_entities(tenant_id,id),foreign key(tenant_id,branch_id) references core.branches(tenant_id,id),
 check(octet_length(canonical_text)<=8388608 and octet_length(parameters::text)<=8388608),
 check(source_hash=encode(extensions.digest(convert_to(canonical_text,'UTF8'),'sha256'),'hex') and evidence=canonical_text::jsonb));
alter table analytics.cash_scenario_revisions enable row level security;
alter table analytics.cash_scenario_revisions force row level security;
revoke all on analytics.cash_scenario_revisions from public,anon,authenticated;
create trigger immutable before update or delete on analytics.cash_scenario_revisions for each row execute function analytics.immutable_evidence();
create function api.wave5_cash_save(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid,p_source_hash text,p_parameters jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare old analytics.cash_scenario_revisions%rowtype;basis jsonb;data jsonb;k text;v jsonb;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_id is null or p_parameters is null or jsonb_typeof(p_parameters)<>'object' or (p_parameters-array['horizonStart','horizonEnd','recordedThrough','overrides'])<>'{}'
  or not(p_parameters ?& array['horizonStart','horizonEnd','recordedThrough','overrides']) or jsonb_typeof(p_parameters->'overrides')<>'object' then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,509));
 select * into old from analytics.cash_scenario_revisions where id=p_id;
 if found then
  if old.tenant_id<>p_tenant_id or old.legal_entity_id<>p_legal_entity_id or old.branch_id is distinct from p_branch_id or old.actor_id<>auth.uid()
   or old.source_hash is distinct from p_source_hash or old.parameters<>p_parameters then raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;
  perform api.wave5_cash_get(p_tenant_id,p_legal_entity_id,p_branch_id,p_id);
  return jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1');end if;
 basis:=api.wave5_cash_basis(p_tenant_id,p_legal_entity_id,p_branch_id,(p_parameters->>'horizonStart')::date,(p_parameters->>'horizonEnd')::date,(p_parameters->>'recordedThrough')::timestamptz);
 if basis->>'sourceHash' is distinct from p_source_hash then raise exception using errcode='40001',message='SOURCE_BASIS_CHANGED';end if;
 data:=(basis->>'canonicalText')::jsonb;
 if not (data->'completeProviders' ? 'payables') then raise exception using errcode='42501',message='PAYABLES_PERMISSION_REQUIRED';end if;
 for k,v in select * from jsonb_each(p_parameters->'overrides') loop
  if not exists(select 1 from jsonb_array_elements(data->'obligations') o where o->>'id'=k)
   or jsonb_typeof(v)<>'object' or (v-array['dueDate','remainingUnits','reasonCode'])<>'{}' or not(v ?& array['dueDate','remainingUnits','reasonCode'])
   or jsonb_typeof(v->'remainingUnits')<>'string' or coalesce(v->>'remainingUnits','')!~ '^(0|[1-9][0-9]{0,19})$'
   or jsonb_typeof(v->'dueDate')<>'string' or coalesce(v->>'dueDate','')!~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   or coalesce(v->>'reasonCode','') not in('collection_delay','payment_delay','reviewed_amount')
   or (v->>'dueDate')::date<(p_parameters->>'horizonStart')::date or (v->>'dueDate')::date>=(p_parameters->>'horizonEnd')::date then
   raise exception using errcode='22023',message='INVALID_SCENARIO_OVERRIDE';end if;
 end loop;
 insert into analytics.cash_scenario_revisions values(p_id,p_tenant_id,p_legal_entity_id,p_branch_id,auth.uid(),p_source_hash,basis->>'canonicalText',data,p_parameters,statement_timestamp());
 perform core.wave3_finish_command(p_tenant_id,'analytics.cash_scenario',p_id,'cash_scenario',p_id,p_id,
  core.wave3_request_hash('analytics.cash_scenario',p_id,p_tenant_id,p_legal_entity_id,p_branch_id,p_parameters,null),null,
  jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1'),p_legal_entity_id,p_branch_id);
 return jsonb_build_object('id',p_id,'sourceHash',p_source_hash,'version','1');end $$;
create function api.wave5_cash_get(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare s analytics.cash_scenario_revisions%rowtype;begin
 perform analytics.cash_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 select * into s from analytics.cash_scenario_revisions where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id and branch_id is not distinct from p_branch_id and id=p_id;
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if (s.evidence->'completeProviders' ? 'payables') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,p_branch_id) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 if exists(select 1 from jsonb_array_elements((s.evidence->'controls')||(s.evidence->'obligations')||(s.evidence->'sources')) r where
  not core.has_permission(p_tenant_id,'finance.view',p_legal_entity_id,(r->>'branchId')::uuid)
  or (r->>'provider'='receivables' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or (r->>'kind' like 'ar_%' and not core.has_permission(p_tenant_id,'finance.receivables.view',p_legal_entity_id,(r->>'branchId')::uuid))
  or ((r->>'provider'='payables' or r->>'kind' like 'ap_%') and not analytics.cash_payables_allowed(p_tenant_id,p_legal_entity_id,(r->>'branchId')::uuid))) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 return jsonb_build_object('id',s.id,'sourceHash',s.source_hash,'canonicalText',s.canonical_text,'parameters',s.parameters);end $$;
revoke all on function api.wave5_cash_authorize(uuid,uuid,uuid),api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function api.wave5_cash_authorize(uuid,uuid,uuid),api.wave5_cash_basis(uuid,uuid,uuid,date,date,timestamptz),api.wave5_cash_save(uuid,uuid,uuid,uuid,text,jsonb),api.wave5_cash_get(uuid,uuid,uuid,uuid) to authenticated;
