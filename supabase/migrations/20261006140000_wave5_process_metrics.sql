alter table billing.tenant_subscriptions add column trial_started_at timestamptz;
-- Unapplied Wave 5 read candidate. Does not modify producers or enable plans.
create schema if not exists analytics;
revoke all on schema analytics from public,anon,authenticated;
create index wave5_process_cohort_idx on workflow.process_events(tenant_id,legal_entity_id,entered_at,id)
include(branch_id,document_id,created_at) where document_type='crm_opportunity';

create function analytics.process_access(t uuid,e uuid,b uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception using errcode='42501',message='AUTH_REQUIRED';end if;
 if t is null or e is null then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_require_scope(t,'analytics.view',e,b);
 perform core.wave3_require_scope(t,'workflow.process.view',e,b);
 if not (core.has_permission(t,'crm.opportunities.view',e,b) or core.has_permission(t,'crm.opportunities.manage',e,b)) then
  raise exception using errcode='42501',message='PERMISSION_DENIED';
 end if;
 if not exists(select 1 from billing.tenant_subscriptions s join billing.plan_entitlements p on p.plan_code=s.plan_code
  where s.tenant_id=t and p.entitlement_code='analytics' and p.enabled
  and ((s.status='trialing' and coalesce(s.trial_started_at,s.created_at)<=statement_timestamp() and s.trial_ends_at>current_timestamp)
   or (s.status='active' and (s.current_period_ends_at is null or s.current_period_ends_at>current_timestamp)))) then
  raise exception using errcode='42501',message='ENTITLEMENT_REQUIRED';
 end if;
end $$;
revoke all on function analytics.process_access(uuid,uuid,uuid) from public,anon,authenticated;

create function analytics.process_utc(v timestamptz) returns text
language sql immutable set search_path='' as $$select to_char(v at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
revoke all on function analytics.process_utc(timestamptz) from public,anon,authenticated;

create function api.analytics_process_snapshot(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_window_start timestamptz,p_window_end timestamptz,p_as_of timestamptz,p_recorded_through timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare rows json;ids json;canonical json;digest text;count_rows integer;result jsonb;
begin
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 if p_window_start is null or p_window_end is null or p_as_of is null or p_recorded_through is null
  or not isfinite(p_window_start) or not isfinite(p_window_end) or not isfinite(p_as_of) or not isfinite(p_recorded_through)
  or p_window_start>=p_window_end or p_window_end>p_as_of or p_as_of>p_recorded_through
  or p_recorded_through>statement_timestamp() then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if p_window_end-p_window_start>interval '366 days' then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 -- Compare the exact projected installed column contract, not a readiness label.
 if (select count(*) from pg_attribute a where a.attrelid='workflow.process_events'::regclass and not a.attisdropped
  and (a.attname,a.atttypid) in (('id','uuid'::regtype),('tenant_id','uuid'::regtype),('legal_entity_id','uuid'::regtype),
   ('branch_id','uuid'::regtype),('document_type','text'::regtype),('document_id','uuid'::regtype),
   ('entered_at','timestamptz'::regtype),('completed_at','timestamptz'::regtype),('created_at','timestamptz'::regtype),
   ('active_minutes','numeric'::regtype),('wait_minutes','numeric'::regtype)))<>11
  or (select count(*) from pg_attribute where attrelid='workflow.process_events'::regclass and not attisdropped
    and attname in ('active_minutes','wait_minutes') and atttypmod=1310730)<>2 then
  raise exception using errcode='55000',message='CONTRACT_MISMATCH';end if;
 select coalesce(json_agg(json_build_object('id',x.id,'tenantId',x.tenant_id,'legalEntityId',x.legal_entity_id,
   'branchId',x.branch_id,'documentType',x.document_type,'documentId',x.document_id,
   'enteredAt',analytics.process_utc(x.entered_at),'completedAt',analytics.process_utc(x.completed_at),
   'recordedAt',analytics.process_utc(x.created_at),'activeMinutes',x.active_minutes::text,'waitMinutes',x.wait_minutes::text)
   order by x.id),'[]'::json),coalesce(json_agg(x.id order by x.id),'[]'::json),count(*)
 into rows,ids,count_rows from (
  select ev.* from workflow.process_events ev join crm.opportunities o
   on o.tenant_id=ev.tenant_id and o.id=ev.document_id and o.legal_entity_id=ev.legal_entity_id
    and o.branch_id is not distinct from ev.branch_id
  where ev.tenant_id=p_tenant_id and ev.legal_entity_id=p_legal_entity_id
   and (p_branch_id is null or ev.branch_id=p_branch_id) and ev.document_type='crm_opportunity'
   and ev.entered_at>=p_window_start and ev.entered_at<p_window_end and ev.created_at<=p_recorded_through
   and (ev.branch_id is null or exists(select 1 from core.branches b where b.tenant_id=ev.tenant_id
     and b.legal_entity_id=ev.legal_entity_id and b.id=ev.branch_id and b.status='active'))
   and (core.has_permission(p_tenant_id,'crm.opportunities.view',p_legal_entity_id,ev.branch_id)
     or core.has_permission(p_tenant_id,'crm.opportunities.manage',p_legal_entity_id,ev.branch_id))
  order by ev.id limit 10001
 ) x;
 if count_rows>10000 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 canonical:=json_build_object('definitionCode','process.event_duration','definitionVersion',1,
  'sourceContractVersion','workflow.process_events.v1','tenantId',p_tenant_id,'legalEntityId',p_legal_entity_id,
  'branchId',p_branch_id,'documentType','crm_opportunity','windowStart',analytics.process_utc(p_window_start),
  'windowEnd',analytics.process_utc(p_window_end),'asOf',analytics.process_utc(p_as_of),
  'recordedThrough',analytics.process_utc(p_recorded_through),'observations',rows);
 -- All string values above are fixed codes, UUIDs, numeric strings or UTC instants.
 -- They cannot contain structural separators; no arbitrary text enters this JSON.
 digest:=encode(extensions.digest(convert_to(replace(replace(replace(canonical::text,' : ',':'),': ',':'),', ',','),'UTF8'),'sha256'),'hex');
 result:=jsonb_build_object('source',jsonb_build_object('snapshotId',gen_random_uuid(),'sourceManifestHash',digest,
  'sourceEventIds',ids,'sourceContractVersion','workflow.process_events.v1','tenantId',p_tenant_id,
  'legalEntityId',p_legal_entity_id,'branchId',p_branch_id,'documentType','crm_opportunity',
  'windowStart',analytics.process_utc(p_window_start),'windowEnd',analytics.process_utc(p_window_end),
  'asOf',analytics.process_utc(p_as_of),'recordedThrough',analytics.process_utc(p_recorded_through),
  'sourceCount',count_rows,'complete',true),'observations',rows);
 if octet_length(convert_to(result::text,'UTF8'))>8388608 then raise exception using errcode='54000',message='LIMIT_EXCEEDED';end if;
 return result;
end $$;
revoke all on function api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz) from public,anon;
grant execute on function api.analytics_process_snapshot(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz) to authenticated;

create function api.analytics_process_event(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,p_event_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare ev workflow.process_events%rowtype;
begin
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id);
 select x.* into ev from workflow.process_events x join crm.opportunities o on o.tenant_id=x.tenant_id and o.id=x.document_id
  and o.legal_entity_id=x.legal_entity_id and o.branch_id is not distinct from x.branch_id
 where x.id=p_event_id and x.tenant_id=p_tenant_id and x.legal_entity_id=p_legal_entity_id
  and (p_branch_id is null or x.branch_id=p_branch_id) and x.document_type='crm_opportunity';
 if not found then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,ev.branch_id);
 return jsonb_build_object('eventId',ev.id,'documentType',ev.document_type,'documentId',ev.document_id,
  'tenantId',ev.tenant_id,'legalEntityId',ev.legal_entity_id,'branchId',ev.branch_id);
end $$;
revoke all on function api.analytics_process_event(uuid,uuid,uuid,uuid) from public,anon;
grant execute on function api.analytics_process_event(uuid,uuid,uuid,uuid) to authenticated;

create function api.analytics_process_authorize(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid)
returns uuid language plpgsql stable security definer set search_path='' as $$begin
 perform analytics.process_access(p_tenant_id,p_legal_entity_id,p_branch_id);return auth.uid();end$$;
revoke all on function api.analytics_process_authorize(uuid,uuid,uuid) from public,anon;
grant execute on function api.analytics_process_authorize(uuid,uuid,uuid) to authenticated;
