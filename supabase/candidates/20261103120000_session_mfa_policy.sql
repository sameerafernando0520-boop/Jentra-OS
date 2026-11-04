-- Candidate only. Apply after the Finance period and Audit & Assurance schemas.
-- MFA belongs to the authenticated session, rather than a 15-minute timer.
-- Supabase verifies the JWT, maintains AAL2 on refresh, and starts a new AAL1
-- session after sign-out/sign-in. Never persist a separate "MFA passed" flag.
create or replace function core.session_has_mfa()
returns boolean language sql stable set search_path = '' as $$
  select (select auth.uid()) is not null
    and coalesce((select auth.jwt()->>'aal'), 'aal1') = 'aal2'
    and exists (
      select 1
      from jsonb_array_elements(
        case when jsonb_typeof((select auth.jwt())->'amr') = 'array'
          then (select auth.jwt())->'amr' else '[]'::jsonb end
      ) method
      where method->>'method' in ('totp', 'webauthn', 'phone', 'otp')
        and case when method->>'timestamp' ~ '^[0-9]{1,12}$'
          then (method->>'timestamp')::bigint
          else null end
          between 1 and extract(epoch from now())::bigint + 60
    );
$$;
revoke all on function core.session_has_mfa() from public, anon, service_role;
grant execute on function core.session_has_mfa() to authenticated;
comment on function core.session_has_mfa() is
  'Requires signed AAL2 and second-factor evidence for the current session. No elapsed-time re-challenge.';

-- Keep existing signatures and error codes so installed clients and RPCs remain
-- compatible. The legacy window argument no longer expires session assurance.
create or replace function assurance.recent_mfa(p_window_seconds integer default 900)
returns boolean language sql stable set search_path = '' as $$
  select core.session_has_mfa();
$$;

create or replace function finance.period_require_recent_mfa()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not core.session_has_mfa() then
    raise exception using errcode = '42501', message = 'RECENT_MFA_REQUIRED';
  end if;
end;
$$;

-- Company administration is a separate candidate on this checkout. Update its
-- guard when installed; do not install that feature as a side effect here.
do $policy$
begin
  if to_regprocedure('workspace_admin.require_admin(uuid,text)') is not null then
    execute $ddl$
      create or replace function workspace_admin.require_admin(t uuid, permission text)
      returns void language plpgsql security definer set search_path = '' as $body$
      begin
        perform core.require_permission(t, permission);
        if not exists (
          select 1 from core.tenants where id = t and status in ('active', 'trial')
        ) then
          raise exception using errcode = '42501', message = 'ADMIN_ACCESS_DENIED';
        end if;
        if not core.session_has_mfa() then
          raise exception using errcode = '42501', message = 'ADMIN_RECENT_MFA_REQUIRED';
        end if;
      end;
      $body$;
    $ddl$;
  end if;
end;
$policy$;
