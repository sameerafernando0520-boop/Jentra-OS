-- No tenants are allowlisted here. Bootstrap requires a separately approved
-- synthetic tenant. Existing billing rows remain the only entitlement authority.
create table intelligence_control.synthetic_tenants(
 tenant_id uuid primary key references core.tenants(id),allowed boolean not null default false
);
create table intelligence_control.subscription_revisions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),
 actor_id uuid not null references auth.users(id),expected_version bigint not null check(expected_version>0),
 plan_code text not null references billing.plans(code),seats integer not null check(seats between 1 and 10000),
 trial_starts_at timestamptz not null,trial_ends_at timestamptz not null,
 reason_code text not null default 'synthetic_trial_review' check(reason_code='synthetic_trial_review'),
 request_id uuid not null,execution_id uuid not null unique,created_at timestamptz not null default statement_timestamp(),
 unique(tenant_id,id),check(isfinite(trial_starts_at) and isfinite(trial_ends_at) and trial_ends_at>trial_starts_at
  and trial_ends_at-trial_starts_at<=interval '366 days')
);
create table intelligence_control.subscription_activations(
 tenant_id uuid not null,revision_id uuid not null,response jsonb not null,recorded_at timestamptz not null default statement_timestamp(),
 primary key(tenant_id,revision_id),foreign key(tenant_id,revision_id) references intelligence_control.subscription_revisions(tenant_id,id)
);
insert into core.permissions values('billing.synthetic.manage','billing','Schedule reasoned synthetic trial/plan/seat revisions with MFA',true) on conflict do nothing;
do $$declare rel text;begin foreach rel in array array['synthetic_tenants','subscription_revisions','subscription_activations'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 if rel<>'synthetic_tenants' then execute format('create trigger immutable_subscription_evidence before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);end if;
end loop;end$$;
create index subscription_revisions_actor_idx on intelligence_control.subscription_revisions(actor_id);
create index subscription_revisions_plan_idx on intelligence_control.subscription_revisions(plan_code);
create index subscription_revisions_due_idx on intelligence_control.subscription_revisions(tenant_id,trial_starts_at,id);

create function api.schedule_synthetic_subscription(p_tenant_id uuid,p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,
 p_expected_version bigint,p_plan_code text,p_seats integer,p_trial_starts_at timestamptz,p_trial_ends_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$declare s billing.tenant_subscriptions%rowtype;h text;replayed jsonb;identity uuid:=gen_random_uuid();begin
 perform core.require_permission(p_tenant_id,'billing.synthetic.manage',null,null);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=p_tenant_id and allowed) then
  raise exception using errcode='42501',message='SYNTHETIC_TARGET_REQUIRED';end if;
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null or not isfinite(p_client_timestamp)
  or p_seats is null or p_seats not between 1 and 10000 or p_plan_code is null
  or not exists(select 1 from billing.plans where code=p_plan_code) or p_trial_starts_at is null or p_trial_ends_at is null
  or not isfinite(p_trial_starts_at) or not isfinite(p_trial_ends_at) or p_trial_ends_at<=p_trial_starts_at
  or p_trial_ends_at-p_trial_starts_at>interval '366 days' then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 h:=core.wave3_request_hash('billing.synthetic.schedule',p_command_id,p_tenant_id,null,null,
  jsonb_build_object('plan',p_plan_code,'seats',p_seats,'start',p_trial_starts_at,'end',p_trial_ends_at,'client',p_client_timestamp),p_expected_version);
 replayed:=core.wave3_replay(p_tenant_id,'billing.synthetic.schedule',p_command_id,p_idempotency_key,h);
 if replayed is not null then return replayed;end if;
 if p_trial_starts_at<statement_timestamp()-interval '1 minute' or p_trial_starts_at>statement_timestamp()+interval '366 days' then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 select * into s from billing.tenant_subscriptions where tenant_id=p_tenant_id for update;
 if not found then raise exception using errcode='55000',message='PROVIDER_UNAVAILABLE';end if;
 perform core.wave3_assert_expected_version(s.version,p_expected_version,jsonb_build_object('id',s.id,'version',s.version::text));
 insert into intelligence_control.subscription_revisions(id,tenant_id,actor_id,expected_version,plan_code,seats,trial_starts_at,trial_ends_at,request_id,execution_id)
  values(identity,p_tenant_id,auth.uid(),s.version,p_plan_code,p_seats,p_trial_starts_at,p_trial_ends_at,p_command_id,gen_random_uuid());
 return core.wave3_finish_command(p_tenant_id,'billing.synthetic.schedule',p_command_id,'synthetic_subscription_revision',identity,p_idempotency_key,h,null,
  jsonb_build_object('id',identity,'version','1','state','scheduled','explanationCode','synthetic_trial_review'));
end $$;

create function api.apply_synthetic_subscription(p_tenant_id uuid,p_revision_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$declare s billing.tenant_subscriptions%rowtype;r intelligence_control.subscription_revisions%rowtype;
 prior jsonb;result jsonb;before_value jsonb;begin
 perform intelligence_control.worker_required();
 select * into s from billing.tenant_subscriptions where tenant_id=p_tenant_id for update;
 select * into r from intelligence_control.subscription_revisions where tenant_id=p_tenant_id and id=p_revision_id;
 if r.id is null or s.id is null or not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=p_tenant_id and allowed) then
  raise exception using errcode='42501',message='SYNTHETIC_TARGET_REQUIRED';end if;
 select response into prior from intelligence_control.subscription_activations where tenant_id=p_tenant_id and revision_id=p_revision_id;
 if prior is not null then return prior;end if;
 if statement_timestamp()<r.trial_starts_at then raise exception using errcode='22023',message='NOT_EFFECTIVE';end if;
 if statement_timestamp()>=r.trial_ends_at then raise exception using errcode='22023',message='APPROVAL_EXPIRED';end if;
 if not exists(select 1 from auth.mfa_factors where user_id=r.actor_id and status='verified') or not exists(
  select 1 from core.memberships m join core.role_assignments ra on ra.tenant_id=m.tenant_id and ra.membership_id=m.id
   join core.role_permissions rp on rp.tenant_id=ra.tenant_id and rp.role_id=ra.role_id
  where m.tenant_id=p_tenant_id and m.user_id=r.actor_id and m.status='active' and rp.permission_code='billing.synthetic.manage'
   and ra.legal_entity_id is null and ra.branch_id is null) then raise exception using errcode='42501',message='PERMISSION_DENIED';end if;
 perform core.wave3_assert_expected_version(s.version,r.expected_version,jsonb_build_object('id',s.id,'version',s.version::text));
 if exists(select 1 from intelligence_control.quota_periods where tenant_id=p_tenant_id and period_end>r.trial_starts_at) then
  raise exception using errcode='40001',message='BILLING_PERIOD_BUSY';end if;
 if (select count(*) from core.memberships where tenant_id=p_tenant_id and status in('active','invited'))>r.seats then
  raise exception using errcode='54000',message='SEAT_QUOTA_EXCEEDED';end if;
 before_value:=jsonb_build_object('plan',s.plan_code,'status',s.status,'seats',s.seats,'version',s.version::text);
 update billing.tenant_subscriptions set plan_code=r.plan_code,status='trialing',seats=r.seats,trial_started_at=r.trial_starts_at,
  trial_ends_at=r.trial_ends_at,current_period_ends_at=null where tenant_id=p_tenant_id returning * into s;
 result:=jsonb_build_object('request_id',r.execution_id,'entity',jsonb_build_object('id',s.id,'version',s.version::text,'revisionId',r.id,
  'plan',s.plan_code,'status',s.status,'seats',s.seats,'trialStart',analytics.process_utc(s.trial_started_at),'trialEnd',analytics.process_utc(s.trial_ends_at)), 'warnings','[]'::jsonb);
 insert into intelligence_control.subscription_activations values(p_tenant_id,r.id,result,statement_timestamp());
 insert into audit.events(tenant_id,actor_id,request_id,event_type,aggregate_type,aggregate_id,before_context,after_context,metadata)
  values(p_tenant_id,r.actor_id,r.execution_id,'billing.synthetic.activate','tenant_subscription',s.id,before_value,result->'entity',jsonb_build_object('executed_by','trusted_worker','schedule_request',r.request_id));
 insert into core.outbox_events(tenant_id,topic,aggregate_type,aggregate_id,payload)
  values(p_tenant_id,'billing.synthetic.activated','tenant_subscription',s.id,jsonb_build_object('revisionId',r.id,'version',s.version::text));
 insert into core.command_receipts(tenant_id,actor_id,idempotency_key,command_name,request_id,request_hash,response,command_id,aggregate_type,aggregate_id)
  values(p_tenant_id,r.actor_id,r.execution_id,'billing.synthetic.activate',r.execution_id,encode(extensions.digest(r.id::text,'sha256'),'hex'),result,r.execution_id,'tenant_subscription',s.id);
 return result;
end $$;

create function intelligence_control.synthetic_seat_guard() returns trigger language plpgsql security definer set search_path='' as $$declare cap integer;begin
 if new.status not in('active','invited') or not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=new.tenant_id and allowed) then return new;end if;
 select seats into cap from billing.tenant_subscriptions where tenant_id=new.tenant_id for update;
 if cap is null then raise exception using errcode='55000',message='PROVIDER_UNAVAILABLE';end if;
 if (select count(*) from core.memberships where tenant_id=new.tenant_id and status in('active','invited') and id<>new.id)+1>cap then
  raise exception using errcode='54000',message='SEAT_QUOTA_EXCEEDED';end if;return new;
end $$;
revoke all on function intelligence_control.synthetic_seat_guard() from public,anon,authenticated;
create trigger wave5_synthetic_seat_guard before insert or update on core.memberships for each row execute function intelligence_control.synthetic_seat_guard();
revoke all on function api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz),api.apply_synthetic_subscription(uuid,uuid) from public,anon,authenticated;
grant execute on function api.schedule_synthetic_subscription(uuid,uuid,uuid,timestamptz,bigint,text,integer,timestamptz,timestamptz) to authenticated;
grant execute on function api.apply_synthetic_subscription(uuid,uuid) to service_role;

create function api.wave5_subscription_authorize(p_tenant_id uuid) returns uuid language plpgsql security definer set search_path='' as $$begin
 perform core.require_permission(p_tenant_id,'billing.synthetic.manage',null,null);
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or not exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=p_tenant_id and allowed) then
  raise exception using errcode='42501',message='SYNTHETIC_TARGET_REQUIRED';end if;return auth.uid();end $$;
create function api.get_wave5_subscription(p_tenant_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare s billing.tenant_subscriptions%rowtype;begin
 perform core.require_permission(p_tenant_id,'billing.read',null,null);
 select * into s from billing.tenant_subscriptions where tenant_id=p_tenant_id;
 if s.id is null then raise exception using errcode='55000',message='PROVIDER_UNAVAILABLE';end if;
 return jsonb_build_object('contractRevision',1,'tenantId',p_tenant_id,'id',s.id,'version',s.version::text,
  'plan',s.plan_code,'status',s.status,'seats',s.seats,'trialStart',analytics.process_utc(coalesce(s.trial_started_at,s.created_at)),
  'trialEnd',analytics.process_utc(s.trial_ends_at),'syntheticTarget',exists(select 1 from intelligence_control.synthetic_tenants where tenant_id=p_tenant_id and allowed));end $$;
revoke all on function api.wave5_subscription_authorize(uuid),api.get_wave5_subscription(uuid) from public,anon;
grant execute on function api.wave5_subscription_authorize(uuid),api.get_wave5_subscription(uuid) to authenticated;
