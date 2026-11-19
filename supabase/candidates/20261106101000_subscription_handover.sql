alter table core.organization_identity_challenges
  drop constraint organization_identity_challenges_purpose_check,
  add check (purpose in ('reset', 'verify', 'purchase'));
alter table core.organization_identity_limits
  drop constraint organization_identity_limits_purpose_check,
  add check (purpose in ('reset', 'verify', 'purchase'));

create function api.subscription_issue_buyer_verification(p_buyer_id uuid, p_email text, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from billing.subscription_checkout_settings where enabled) or not exists (
    select 1 from auth.users u
    where u.id = p_buyer_id and lower(u.email) = p_email and u.deleted_at is null
      and u.raw_app_meta_data->>'managed_org_admin' is distinct from 'true'
      and right(p_email, 21) <> '@admin.jentra.invalid'
  ) then raise exception using errcode = '42501', message = 'Buyer email unavailable.'; end if;
  return core.organization_issue_identity_challenge(p_buyer_id, 'purchase', p_email, p_hash);
end;
$$;

create function api.subscription_consume_buyer_verification(p_buyer_id uuid, p_email text, p_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if core.organization_consume_identity_challenge(p_buyer_id, 'purchase', p_hash)
      is distinct from p_email then return false; end if;
  perform api.subscription_record_buyer_verification(p_buyer_id, p_email);
  return true;
end;
$$;

alter table billing.subscription_handover_jobs
  add column generation uuid not null unique default gen_random_uuid(),
  add column credential_expires_at timestamptz,
  add column next_attempt_at timestamptz not null default statement_timestamp(),
  add column reissue_requested_at timestamptz,
  add column sent_message_id text check (length(sent_message_id) <= 200);

-- Generation-bound encrypted payloads stay out of tenant archives. No
-- identifying data is stored here, and expiry cleanup can run during a lock.
create table billing.subscription_handover_payloads (
  generation uuid primary key,
  ciphertext text not null check (length(ciphertext) <= 512),
  expires_at timestamptz not null
);
alter table billing.subscription_handover_payloads enable row level security;
revoke all on billing.subscription_handover_payloads from public, anon, authenticated, service_role;

alter table core.organization_administrator_logins
  add column checkout_order_id uuid unique
    references billing.subscription_checkout_orders(id) on delete cascade,
  add column temporary_password_expires_at timestamptz;

create table billing.subscription_password_reset_grants (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token uuid not null,
  generation uuid,
  expires_at timestamptz not null
);
alter table billing.subscription_password_reset_grants enable row level security;
revoke all on billing.subscription_password_reset_grants from public, anon, authenticated, service_role;

create function api.subscription_claim_handover()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_order billing.subscription_checkout_orders;
  v_job billing.subscription_handover_jobs;
begin
  update billing.subscription_handover_jobs
  set status = 'failed', lease_token = null, lease_until = null, updated_at = v_now,
      last_error = case when credential_expires_at <= v_now then 'credential_expired' else 'retry_limit_reached' end
  where status in ('pending','processing') and (lease_until is null or lease_until <= v_now)
    and (credential_expires_at <= v_now or attempts >= 5)
    and core.organization_available(tenant_id);

  delete from billing.subscription_handover_payloads p where p.expires_at <= v_now
    or not exists (select 1 from billing.subscription_handover_jobs j
      where j.generation = p.generation and j.status in ('pending','processing'));
  delete from billing.subscription_password_reset_grants where expires_at <= v_now;

  select j.* into v_job
  from billing.subscription_handover_jobs j
  join billing.subscription_checkout_orders o on o.id = j.order_id
  join billing.organization_activations a on a.tenant_id = o.tenant_id and a.signup_email = o.signup_email
  where o.kind = 'initial' and o.status = 'paid' and core.organization_available(o.tenant_id)
    and j.attempts < 5 and (j.credential_expires_at is null or j.credential_expires_at > v_now)
    and ((j.status = 'pending' and j.next_attempt_at <= v_now)
      or (j.status = 'processing' and j.lease_until <= v_now))
  order by j.next_attempt_at, j.order_id limit 1 for update of j skip locked;
  if not found then return null; end if;

  update billing.subscription_handover_jobs
  set status = 'processing', lease_token = gen_random_uuid(), lease_until = v_now + interval '3 minutes',
      attempts = attempts + 1, updated_at = v_now
  where order_id = v_job.order_id returning * into v_job;
  select * into v_order from billing.subscription_checkout_orders where id = v_job.order_id;
  return jsonb_build_object(
    'order_id', v_order.id, 'tenant_id', v_order.tenant_id, 'username', v_order.username,
    'organization_name', v_order.organization_name, 'email', v_order.signup_email,
    'lease_token', v_job.lease_token, 'generation', v_job.generation,
    'ciphertext', (select p.ciphertext from billing.subscription_handover_payloads p where p.generation = v_job.generation),
    'credential_expires_at', v_job.credential_expires_at
  );
end;
$$;

create function api.subscription_stage_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_ciphertext text
)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare v_expiry timestamptz;
begin
  update billing.subscription_handover_jobs
  set credential_expires_at = clock_timestamp() + interval '24 hours', updated_at = clock_timestamp()
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > clock_timestamp() and credential_expires_at is null
    and p_ciphertext ~ '^v1\.[A-Za-z0-9+/=]+\.[A-Za-z0-9+/=]+$'
  returning credential_expires_at into v_expiry;
  if not found then return null; end if;
  insert into billing.subscription_handover_payloads (generation, ciphertext, expires_at)
    values (p_generation, p_ciphertext, v_expiry);
  return v_expiry;
end;
$$;

create function api.subscription_handover_identity(p_order_id uuid, p_lease_token uuid, p_generation uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', u.id,
    'password_prepared', coalesce(u.raw_app_meta_data->>'jentra_handover_generation' = j.generation::text, false)
  )
  from billing.subscription_handover_jobs j
  join billing.subscription_checkout_orders o on o.id = j.order_id
  left join auth.users u on u.email = o.username || '@admin.jentra.invalid'
    and u.deleted_at is null and u.raw_app_meta_data->>'managed_org_admin' = 'true'
    and u.raw_app_meta_data->>'checkout_order_id' = o.id::text
    and u.raw_app_meta_data->>'provisioned_tenant_id' = o.tenant_id::text
  where j.order_id = p_order_id and j.status = 'processing' and j.lease_token = p_lease_token
    and j.generation = p_generation and j.lease_until > statement_timestamp()
    and j.credential_expires_at > statement_timestamp()
    and o.kind = 'initial' and o.status = 'paid' and core.organization_available(o.tenant_id);
$$;

create function api.subscription_register_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_user_id uuid
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_job billing.subscription_handover_jobs;
  v_order billing.subscription_checkout_orders;
  v_role uuid;
  v_membership uuid;
begin
  select * into v_job from billing.subscription_handover_jobs
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > v_now and credential_expires_at > v_now
  for update;
  if not found then return false; end if;

  select o.* into v_order from billing.subscription_checkout_orders o
  join billing.organization_activations a on a.tenant_id = o.tenant_id and a.signup_email = o.signup_email
  where o.id = p_order_id and o.kind = 'initial' and o.status = 'paid'
    and core.organization_available(o.tenant_id);
  if not found or not exists (
    select 1 from auth.users u
    where u.id = p_user_id and u.email = v_order.username || '@admin.jentra.invalid' and u.deleted_at is null
      and u.raw_app_meta_data->>'managed_org_admin' = 'true'
      and u.raw_app_meta_data->>'checkout_order_id' = v_order.id::text
      and u.raw_app_meta_data->>'provisioned_tenant_id' = v_order.tenant_id::text
      and u.raw_app_meta_data->>'jentra_handover_generation' = v_job.generation::text
  ) then return false; end if;

  if v_job.user_id is not null then
    return v_job.user_id = p_user_id and exists (
      select 1 from core.organization_administrator_logins l
      where l.user_id = p_user_id and l.checkout_order_id = p_order_id and l.must_change_password
        and l.temporary_password_expires_at = v_job.credential_expires_at
    );
  end if;

  select id into strict v_role from core.roles
  where tenant_id = v_order.tenant_id and code = 'tenant_owner' and is_system;
  insert into core.organization_administrator_logins (
    user_id, tenant_id, username, checkout_order_id, temporary_password_expires_at, password_changed_at
  ) values (
    p_user_id, v_order.tenant_id, v_order.username, p_order_id, v_job.credential_expires_at, v_now
  );
  insert into core.organization_account_recovery (user_id, email, verified_at, password_changed_at)
    values (p_user_id, v_order.signup_email, v_now, v_now);
  insert into core.memberships (tenant_id, user_id, invited_by, joined_at)
    values (v_order.tenant_id, p_user_id, v_order.buyer_id, v_now) returning id into v_membership;
  insert into core.role_assignments (tenant_id, membership_id, role_id, created_by)
    values (v_order.tenant_id, v_membership, v_role, v_order.buyer_id);
  update billing.subscription_handover_jobs set user_id = p_user_id, updated_at = v_now
    where order_id = p_order_id;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_order.tenant_id, v_order.buyer_id, p_order_id, 'organization.administrator_created',
      'membership', v_membership);
  return true;
end;
$$;

create function api.subscription_finish_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_message_id text
)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_job billing.subscription_handover_jobs;
  v_order billing.subscription_checkout_orders;
begin
  update billing.subscription_handover_jobs
  set status = 'sent', lease_token = null, lease_until = null,
      last_error = null, sent_message_id = p_message_id, updated_at = v_now
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > v_now and user_id is not null
    and credential_expires_at > v_now and length(p_message_id) between 1 and 200
  returning * into v_job;
  if not found then return false; end if;
  delete from billing.subscription_handover_payloads where generation = p_generation;

  update core.organization_administrator_logins set handover_sent_at = v_now
    where user_id = v_job.user_id and checkout_order_id = p_order_id and must_change_password;
  select * into v_order from billing.subscription_checkout_orders where id = p_order_id;
  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_order.tenant_id, v_order.buyer_id, v_job.generation, 'organization.administrator_handover',
      'administrator', v_job.user_id);
  return true;
end;
$$;

create function api.subscription_fail_handover(
  p_order_id uuid, p_lease_token uuid, p_generation uuid, p_error text, p_retryable boolean
)
returns void language plpgsql security definer set search_path = '' as $$
declare v_status text;
begin
  update billing.subscription_handover_jobs
  set status = case when p_retryable and attempts < 5 then 'pending' else 'failed' end,
      lease_token = null, lease_until = null, updated_at = clock_timestamp(),
      next_attempt_at = clock_timestamp() + make_interval(mins => attempts * attempts),
      last_error = case when p_error in ('mail_unavailable','mail_rejected','username_unavailable',
        'identity_unavailable','credential_unavailable','job_unavailable') then p_error else 'job_unavailable' end
  where order_id = p_order_id and status = 'processing' and lease_token = p_lease_token
    and generation = p_generation and lease_until > clock_timestamp()
  returning status into v_status;
  if v_status = 'failed' then
    delete from billing.subscription_handover_payloads where generation = p_generation;
  end if;
end;
$$;

create function api.subscription_reissue_handover(p_order_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_order billing.subscription_checkout_orders;
  v_job billing.subscription_handover_jobs;
begin
  select * into v_order from billing.subscription_checkout_orders
  where id = p_order_id and kind = 'initial' and status = 'paid';
  if not found or not (
    exists (
      select 1 from billing.subscription_verified_buyers b join auth.users u on u.id = b.buyer_id
      where b.buyer_id = auth.uid() and b.buyer_id = v_order.buyer_id and b.email = v_order.signup_email
        and lower(u.email) = b.email and u.deleted_at is null and core.organization_account_ready(b.buyer_id)
    ) or api.platform_organization_access()
  ) then raise exception using errcode = '42501', message = 'HANDOVER_UNAVAILABLE'; end if;

  select * into v_job from billing.subscription_handover_jobs where order_id = p_order_id for update;
  if not found or not core.organization_available(v_order.tenant_id) or v_job.status not in ('failed','sent')
      or v_job.updated_at > v_now - interval '1 minute' then
    raise exception using errcode = '22023', message = 'HANDOVER_UNAVAILABLE';
  end if;
  if v_job.user_id is not null then
    update core.organization_administrator_logins
    set handover_sent_at = null, handover_requested_at = v_now,
        temporary_password_expires_at = v_now, password_changed_at = v_now
    where user_id = v_job.user_id and checkout_order_id = p_order_id and must_change_password;
    if not found then raise exception using errcode = '22023', message = 'HANDOVER_UNAVAILABLE'; end if;
    update core.organization_account_recovery set password_changed_at = v_now where user_id = v_job.user_id;
  end if;

  update billing.subscription_handover_jobs set status = 'pending', generation = gen_random_uuid(),
    attempts = 0, lease_token = null, lease_until = null,
    credential_expires_at = null, next_attempt_at = v_now, reissue_requested_at = v_now,
    updated_at = v_now, sent_message_id = null, last_error = null where order_id = p_order_id;
  delete from billing.subscription_handover_payloads where generation = v_job.generation;

  insert into audit.events (tenant_id, actor_id, request_id, event_type, aggregate_type, aggregate_id)
    values (v_order.tenant_id, auth.uid(), gen_random_uuid(), 'organization.administrator_handover_requested',
      'subscription_checkout_order', v_order.id);
end;
$$;


create function api.subscription_consume_password_reset(p_login_email text, p_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid;
  v_token uuid;
begin
  v_user := api.organization_consume_reset(p_login_email, p_hash);
  if v_user is null then return null; end if;
  if exists (select 1 from core.organization_administrator_logins
      where user_id = v_user and checkout_order_id is not null) then
    v_token := gen_random_uuid();
    insert into billing.subscription_password_reset_grants (user_id, token, expires_at)
      values (v_user, v_token, clock_timestamp() + interval '2 minutes')
    on conflict (user_id) do update set token = excluded.token, generation = null, expires_at = excluded.expires_at;
  end if;
  return jsonb_build_object('user_id', v_user, 'reset_token', v_token);
end;
$$;

create function api.subscription_authorize_password_change(p_user_id uuid, p_password_changed_at timestamptz)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_login core.organization_administrator_logins;
  v_job billing.subscription_handover_jobs;
  v_token uuid := gen_random_uuid();
begin
  select * into v_login from core.organization_administrator_logins
    where user_id = p_user_id and checkout_order_id is not null;
  if not found then return null; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text, 34555));
  select * into strict v_job from billing.subscription_handover_jobs
    where order_id = v_login.checkout_order_id for update;
  select * into strict v_login from core.organization_administrator_logins where user_id = p_user_id;
  if not v_login.must_change_password or v_job.status <> 'sent'
    or v_login.password_changed_at is distinct from p_password_changed_at
    or v_login.temporary_password_expires_at is null or v_login.temporary_password_expires_at <= v_now
    or not core.organization_available(v_login.tenant_id)
  then raise exception using errcode = '42501', message = 'Temporary credential unavailable.'; end if;
  insert into billing.subscription_password_reset_grants (user_id, token, generation, expires_at)
    values (p_user_id, v_token, v_job.generation,
      least(v_login.temporary_password_expires_at, v_now + interval '2 minutes'))
  on conflict (user_id) do update set token = excluded.token,
    generation = excluded.generation, expires_at = excluded.expires_at;
  return v_token;
end;
$$;

-- Leave the current tracking contract in place for existing accounts. For
-- purchase accounts the deferred trigger below inspects the completed Auth
-- transaction, including private metadata that GoTrue can write after the hash.
create or replace function core.organization_track_password_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.raw_app_meta_data->>'checkout_order_id' is not null then return new; end if;

  if new.encrypted_password is distinct from old.encrypted_password then
    perform pg_advisory_xact_lock(hashtextextended(new.id::text, 34555));
    insert into core.organization_account_recovery (user_id, password_changed_at)
      values (new.id, statement_timestamp())
    on conflict (user_id) do update set password_changed_at = excluded.password_changed_at;
    update core.organization_administrator_logins
      set password_changed_at = statement_timestamp(), must_change_password = false where user_id = new.id;
    update core.organization_identity_challenges set consumed = true where user_id = new.id;
  end if;
  if new.raw_app_meta_data->>'jentra_handover_generation' is not null
      and new.raw_app_meta_data->>'jentra_handover_generation'
        is distinct from old.raw_app_meta_data->>'jentra_handover_generation' then
    update core.organization_administrator_logins
      set must_change_password = true, handover_sent_at = null where user_id = new.id;
  end if;
  return new;
end;
$$;

create function core.subscription_track_password_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_now timestamptz := clock_timestamp();
  v_login core.organization_administrator_logins;
  v_job billing.subscription_handover_jobs;
  v_metadata jsonb;
  v_prepare_token text;
  v_reset_token text;
  v_temporary boolean := false;
begin
  if new.encrypted_password is not distinct from old.encrypted_password then return new; end if;
  select * into v_login from core.organization_administrator_logins
  where user_id = new.id and checkout_order_id is not null;
  if not found then return new; end if;

  perform pg_advisory_xact_lock(hashtextextended(new.id::text, 34555));
  select * into strict v_job from billing.subscription_handover_jobs
  where order_id = v_login.checkout_order_id for update;
  select * into strict v_login from core.organization_administrator_logins where user_id = new.id for update;
  select raw_app_meta_data into v_metadata from auth.users where id = new.id;
  v_prepare_token := v_metadata->>'jentra_subscription_prepare_token';
  v_reset_token := v_metadata->>'jentra_subscription_reset_token';

  if v_prepare_token is distinct from old.raw_app_meta_data->>'jentra_subscription_prepare_token' then
    if v_job.status <> 'processing' or v_job.user_id is distinct from new.id
      or v_prepare_token is distinct from v_job.lease_token::text or v_job.lease_until <= v_now
      or v_metadata->>'jentra_handover_generation' is distinct from v_job.generation::text
      or v_job.credential_expires_at is null or v_job.credential_expires_at <= v_now
    then raise exception using errcode = '42501', message = 'Handover no longer available.'; end if;
    v_temporary := true;
  elsif v_reset_token is distinct from old.raw_app_meta_data->>'jentra_subscription_reset_token' then
    if not exists (select 1 from billing.subscription_password_reset_grants
      where user_id = new.id and token::text = v_reset_token and expires_at > v_now
        and (generation is null or (generation = v_job.generation and v_job.status = 'sent'
          and core.organization_available(v_login.tenant_id)))
    ) then raise exception using errcode = '42501', message = 'Password reset no longer available.'; end if;
  elsif v_metadata->>'jentra_handover_generation'
      is distinct from old.raw_app_meta_data->>'jentra_handover_generation' then
    raise exception using errcode = '42501', message = 'Handover no longer available.';
  elsif v_login.must_change_password then
    raise exception using errcode = '42501', message = 'Use the Jentra account setup to change this password.';
  end if;

  update core.organization_account_recovery set password_changed_at = v_now where user_id = new.id;
  update core.organization_administrator_logins
  set password_changed_at = v_now, must_change_password = v_temporary,
      temporary_password_expires_at = case when v_temporary then v_job.credential_expires_at end,
      handover_sent_at = case when v_temporary then null else handover_sent_at end
  where user_id = new.id;
  update core.organization_identity_challenges set consumed = true where user_id = new.id;
  delete from billing.subscription_password_reset_grants where user_id = new.id;
  if not v_temporary and v_job.status <> 'completed' then
    update billing.subscription_handover_jobs
    set status = 'completed', lease_token = null, lease_until = null,
      updated_at = v_now, last_error = null where order_id = v_job.order_id;
    delete from billing.subscription_handover_payloads where generation = v_job.generation;
  end if;
  return new;
end;
$$;

create constraint trigger subscription_track_password_change
after update of encrypted_password on auth.users
deferrable initially deferred for each row execute function core.subscription_track_password_change();

create function core.subscription_guard_session_start()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from auth.users u
    left join core.organization_administrator_logins l on l.user_id = u.id
    left join billing.subscription_handover_jobs j on j.order_id = l.checkout_order_id
    where u.id = new.user_id and u.raw_app_meta_data->>'checkout_order_id' is not null
      and (l.user_id is null or (l.must_change_password and (
        j.status is distinct from 'sent' or l.temporary_password_expires_at is null
        or l.temporary_password_expires_at <= clock_timestamp()
      )))
  ) then raise exception using errcode = '42501', message = 'Temporary credential unavailable.'; end if;
  return new;
end;
$$;
create trigger subscription_guard_session_start before insert on auth.sessions
for each row execute function core.subscription_guard_session_start();


create or replace function core.organization_provisioning_recipient(p_actor_id uuid, p_tenant_id uuid, p_signup_email text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_email text;
begin
  if not exists (select 1 from intelligence_control.operators
    where actor_id = p_actor_id and active and organization_manage) then
    raise exception using errcode = '42501', message = 'Platform organization operator required.';
  end if;
  select signup_email into v_email from billing.organization_activations where tenant_id = p_tenant_id;
  if v_email is null or not core.organization_available(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Confirmed activation required.';
  end if;
  if exists (select 1 from billing.subscription_handover_jobs j
    where j.tenant_id = p_tenant_id and not exists (
      select 1 from core.organization_administrator_logins l where l.checkout_order_id = j.order_id
    )) then
    raise exception using errcode = '42501', message = 'Automatic handover must register the first administrator.';
  end if;
  if exists (select 1 from core.organization_administrator_logins where tenant_id = p_tenant_id) then
    v_email := coalesce(p_signup_email, v_email);
  elsif p_signup_email is distinct from v_email then
    raise exception using errcode = '22023', message = 'First administrator must use the activation email.';
  end if;
  if length(v_email) not between 5 and 254 or position('@' in v_email) < 2
      or right(v_email, 21) = '@admin.jentra.invalid' then
    raise exception using errcode = '22023', message = 'Invalid handover address.';
  end if;
  return v_email;
end;
$$;

create or replace function api.organization_admin_reissue_target(p_actor_id uuid, p_tenant_id uuid, p_username text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_result jsonb;
begin
  if not exists (select 1 from intelligence_control.operators
    where actor_id = p_actor_id and active and organization_manage) then
    raise exception using errcode = '42501', message = 'Platform organization operator required.';
  end if;
  update core.organization_administrator_logins as l set handover_requested_at = statement_timestamp()
  from core.organization_account_recovery as r
  where l.tenant_id = p_tenant_id and l.username = p_username and core.organization_available(l.tenant_id)
    and l.user_id = r.user_id and core.organization_is_administrator(l.user_id)
    and l.checkout_order_id is null and (r.verified_at is not null or l.handover_sent_at is null)
    and l.handover_requested_at <= statement_timestamp() - interval '1 minute'
  returning jsonb_build_object('user_id', l.user_id, 'email', r.email) into v_result;
  return v_result;
end;
$$;

create or replace function api.platform_organization_activity(p_tenant_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform intelligence_control.operator_required('organization');
  if not exists (select 1 from core.tenants where id = p_tenant_id) then
    raise exception using errcode = '22023', message = 'ORGANIZATION_UNAVAILABLE';
  end if;
  return jsonb_build_object(
    'administrators', (select coalesce(jsonb_agg(jsonb_build_object(
      'username', l.username, 'status', m.status, 'password_changed_at', l.password_changed_at,
      'must_change_password', l.must_change_password, 'handover_sent_at', l.handover_sent_at,
      'checkout_order_id', l.checkout_order_id
    ) order by l.username), '[]'::jsonb)
    from core.organization_administrator_logins l
    join core.memberships m on (m.tenant_id, m.user_id) = (l.tenant_id, l.user_id)
    where l.tenant_id = p_tenant_id and l.department_code is null),
    'recent_activity', (select coalesce(jsonb_agg(jsonb_build_object(
      'event_type', a.event_type, 'occurred_at', a.occurred_at
    ) order by a.occurred_at desc), '[]'::jsonb) from (
      select event_type, occurred_at from audit.events where tenant_id = p_tenant_id
        and event_type like 'organization.%' order by occurred_at desc, id limit 20
    ) a)
  );
end;
$$;

revoke all on function core.subscription_track_password_change(), core.subscription_guard_session_start()
  from public, anon, authenticated, service_role;
revoke all on function api.subscription_issue_buyer_verification(uuid,text,text),
  api.subscription_consume_buyer_verification(uuid,text,text), api.subscription_claim_handover(),
  api.subscription_stage_handover(uuid,uuid,uuid,text), api.subscription_handover_identity(uuid,uuid,uuid),
  api.subscription_register_handover(uuid,uuid,uuid,uuid), api.subscription_finish_handover(uuid,uuid,uuid,text),
  api.subscription_fail_handover(uuid,uuid,uuid,text,boolean), api.subscription_consume_password_reset(text,text),
  api.subscription_authorize_password_change(uuid,timestamptz), api.subscription_reissue_handover(uuid)
  from public, anon, authenticated, service_role;
grant execute on function api.subscription_issue_buyer_verification(uuid,text,text),
  api.subscription_consume_buyer_verification(uuid,text,text), api.subscription_claim_handover(),
  api.subscription_stage_handover(uuid,uuid,uuid,text), api.subscription_handover_identity(uuid,uuid,uuid),
  api.subscription_register_handover(uuid,uuid,uuid,uuid), api.subscription_finish_handover(uuid,uuid,uuid,text),
  api.subscription_fail_handover(uuid,uuid,uuid,text,boolean), api.subscription_consume_password_reset(text,text),
  api.subscription_authorize_password_change(uuid,timestamptz)
  to service_role;
grant execute on function api.subscription_reissue_handover(uuid) to authenticated;


create or replace function billing.checkout_order_projection(p_order billing.subscription_checkout_orders, p_operator boolean default false)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', p_order.id, 'kind', p_order.kind,
    'status', case when p_order.expires_at <= statement_timestamp()
      and p_order.status in ('awaiting_payment', 'payment_rejected') then 'expired' else p_order.status end,
    'plan_code', p_order.plan_code, 'plan_name', p_order.plan_name,
    'plan_revision', p_order.plan_revision, 'price_minor', p_order.price_minor,
    'currency_code', p_order.currency_code, 'term_days', p_order.term_days,
    'organization_name', p_order.organization_name, 'username', p_order.username, 'tenant_id', p_order.tenant_id,
    'transfer_reference', p_order.transfer_reference, 'bank', p_order.bank,
    'created_at', p_order.created_at, 'expires_at', p_order.expires_at,
    'paid_at', p_order.paid_at, 'term_ends_at', p_order.term_ends_at,
    'handover_status', case when j.status = 'sent' and j.credential_expires_at <= statement_timestamp()
      then 'expired' else j.status end,
    'handover_expires_at', case when j.status = 'sent' then j.credential_expires_at end,
    'handover_can_reissue', coalesce(j.status in ('failed','sent')
      and j.updated_at <= statement_timestamp() - interval '1 minute'
      and core.organization_available(j.tenant_id), false)
  ) || case when p_operator then jsonb_build_object(
    'signup_email', p_order.signup_email, 'verified_reference', p_order.verified_reference,
    'verified_amount_minor', p_order.verified_amount_minor, 'verified_paid_at', p_order.verified_paid_at,
    'reviewed_at', p_order.reviewed_at, 'decision_reason', p_order.decision_reason,
    'exception_reason', p_order.exception_reason, 'handover_error', j.last_error,
    'handover_attempts', j.attempts
  ) else '{}' end
  from (select 1) base left join billing.subscription_handover_jobs j on j.order_id = p_order.id;
$$;
