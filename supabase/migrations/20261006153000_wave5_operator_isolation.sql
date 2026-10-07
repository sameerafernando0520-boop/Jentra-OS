-- Separate operator authority; no operators or access grants are seeded.
create table intelligence_control.operators(
 actor_id uuid primary key references auth.users(id),active boolean not null default false,
 health_read boolean not null default false,grant_manage boolean not null default false
);
revoke all on intelligence_control.operators from public,anon,authenticated;
alter table intelligence_control.operators enable row level security;
alter table intelligence_control.operators force row level security;
create table intelligence_control.operator_tenant_grants(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references core.tenants(id),
 operator_id uuid not null references intelligence_control.operators(actor_id),issued_by uuid not null references auth.users(id),
 reason text not null check(length(trim(reason)) between 10 and 500),issued_at timestamptz not null default statement_timestamp(),
 expires_at timestamptz not null,unique(tenant_id,id),
 check(isfinite(expires_at) and expires_at>issued_at and expires_at-issued_at<=interval '1 hour')
);
create table intelligence_control.operator_access_events(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,grant_id uuid not null,actor_id uuid not null references auth.users(id),
 recorded_at timestamptz not null default statement_timestamp(),foreign key(tenant_id,grant_id)
 references intelligence_control.operator_tenant_grants(tenant_id,id)
);
create table intelligence_control.health_probes(
 id uuid primary key default gen_random_uuid(),tenant_id uuid references core.tenants(id),
 code text not null check(code in('worker_lag_seconds','retry_count','dead_letter_count','quota_remaining')),
 exact_value numeric(20,0) not null check(exact_value>=0),observed_at timestamptz not null,
 contract_revision integer not null check(contract_revision=1),check(isfinite(observed_at))
);
do $$declare rel text;begin foreach rel in array array['operator_tenant_grants','operator_access_events','health_probes'] loop
 execute format('alter table intelligence_control.%I enable row level security',rel);
 execute format('alter table intelligence_control.%I force row level security',rel);
 execute format('revoke all on intelligence_control.%I from public,anon,authenticated',rel);
 execute format('create trigger immutable_operator_evidence before update or delete on intelligence_control.%I for each row execute function analytics.immutable_evidence()',rel);
end loop;end$$;
create index operator_grants_scope_idx on intelligence_control.operator_tenant_grants(tenant_id,operator_id,expires_at,id);
create index operator_grants_issuer_idx on intelligence_control.operator_tenant_grants(issued_by);
create index operator_access_actor_idx on intelligence_control.operator_access_events(actor_id,recorded_at);
create index operator_access_grant_idx on intelligence_control.operator_access_events(tenant_id,grant_id);
create index health_probes_scope_idx on intelligence_control.health_probes(tenant_id,code,observed_at desc,id);

create function intelligence_control.operator_required(cap text) returns void
language plpgsql stable security definer set search_path='' as $$begin
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' or not exists(select 1 from intelligence_control.operators
  where actor_id=auth.uid() and active and case cap when 'health' then health_read when 'grant' then grant_manage else false end) then
  raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
end $$;
revoke all on function intelligence_control.operator_required(text) from public,anon,authenticated;

create function api.issue_operator_tenant_grant(p_tenant_id uuid,p_operator_id uuid,p_reason text,p_expires_at timestamptz,p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare h text;replayed jsonb;identity uuid:=gen_random_uuid();entity jsonb;begin
 perform intelligence_control.operator_required('grant');
 if p_reason is null or length(trim(p_reason)) not between 10 and 500 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at<=statement_timestamp() or p_expires_at-statement_timestamp()>interval '1 hour' then
  raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 if not exists(select 1 from core.tenants where id=p_tenant_id) or not exists(select 1 from intelligence_control.operators
  where actor_id=p_operator_id and active and health_read) then raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
 h:=core.wave2_request_hash('operator.issue_grant',p_tenant_id,null,jsonb_build_object('operator',p_operator_id,'reason',p_reason,'expires',p_expires_at),null);
 replayed:=core.wave2_replay(p_tenant_id,'operator.issue_grant',p_idempotency_key,h);
 if replayed is not null then return replayed;end if;
 insert into intelligence_control.operator_tenant_grants(id,tenant_id,operator_id,issued_by,reason,expires_at)
  values(identity,p_tenant_id,p_operator_id,auth.uid(),trim(p_reason),p_expires_at);
 entity:=jsonb_build_object('id',identity,'version','1','operatorId',p_operator_id,'expiresAt',p_expires_at);
 -- Operator authority is independent of tenant membership. The existing Wave 2
 -- receipt/audit/outbox helper supports this reviewed separate authority.
 return core.wave2_finish_command(p_tenant_id,'operator.issue_grant','operator_tenant_grant',identity,p_idempotency_key,h,null,entity);
end $$;

create function intelligence_control.health_projection(t uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('contractRevision',1,'generatedAt',analytics.process_utc(statement_timestamp()),'probes',jsonb_agg(
  jsonb_build_object('code',codes.code,'state',case when p.observed_at is null or p.observed_at>statement_timestamp()
   or p.observed_at<statement_timestamp()-interval '5 minutes' then 'unknown' else 'observed' end,
   'exactValue',case when p.observed_at<=statement_timestamp() and p.observed_at>=statement_timestamp()-interval '5 minutes'
    then p.exact_value::text else null end,'observedAt',case when p.observed_at is null then null else analytics.process_utc(p.observed_at) end) order by codes.code))
 from unnest(array['worker_lag_seconds','retry_count','dead_letter_count','quota_remaining']) codes(code)
 left join lateral(select exact_value,observed_at from intelligence_control.health_probes
  where tenant_id is not distinct from t and code=codes.code order by observed_at desc,id limit 1) p on true
$$;
revoke all on function intelligence_control.health_projection(uuid) from public,anon,authenticated;
create function api.get_operator_health() returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform intelligence_control.operator_required('health');return intelligence_control.health_projection(null);end$$;
create function api.get_operator_tenant_health(p_tenant_id uuid,p_grant_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 perform intelligence_control.operator_required('health');
 if not exists(select 1 from intelligence_control.operator_tenant_grants where id=p_grant_id and tenant_id=p_tenant_id
  and operator_id=auth.uid() and issued_at<=statement_timestamp() and expires_at>statement_timestamp()) then
  raise exception using errcode='42501',message='OPERATOR_ACCESS_REQUIRED';end if;
 insert into intelligence_control.operator_access_events(tenant_id,grant_id,actor_id) values(p_tenant_id,p_grant_id,auth.uid());
 return intelligence_control.health_projection(p_tenant_id);
end $$;
create function api.record_wave5_health_probe(p_id uuid,p_tenant_id uuid,p_code text,p_value text,p_observed_at timestamptz)
returns void language plpgsql security definer set search_path='' as $$declare prior intelligence_control.health_probes%rowtype;begin
 perform intelligence_control.worker_required();
 if p_id is null or p_code is null or p_code not in('worker_lag_seconds','retry_count','dead_letter_count','quota_remaining')
  or p_value is null or p_value !~ '^(0|[1-9][0-9]{0,19})$' or p_observed_at is null or not isfinite(p_observed_at)
  or p_observed_at>statement_timestamp() then raise exception using errcode='22023',message='VALIDATION_ERROR';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,7));
 select * into prior from intelligence_control.health_probes where id=p_id;
 if found then
  if prior.tenant_id is distinct from p_tenant_id or prior.code<>p_code or prior.exact_value<>p_value::numeric or prior.observed_at<>p_observed_at then
   raise exception using errcode='22023',message='IDEMPOTENCY_MISMATCH';end if;return;
 end if;
 insert into intelligence_control.health_probes values(p_id,p_tenant_id,p_code,p_value::numeric,p_observed_at,1);
end $$;
revoke all on function api.issue_operator_tenant_grant(uuid,uuid,text,timestamptz,uuid),api.get_operator_health(),
 api.get_operator_tenant_health(uuid,uuid),api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz) from public,anon,authenticated;
grant execute on function api.issue_operator_tenant_grant(uuid,uuid,text,timestamptz,uuid),api.get_operator_health(),api.get_operator_tenant_health(uuid,uuid) to authenticated;
grant execute on function api.record_wave5_health_probe(uuid,uuid,text,text,timestamptz) to service_role;
