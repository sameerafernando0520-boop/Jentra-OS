-- Corporate Audit & Assurance: protected storage and byte verification for
-- submitted evidence (PR #1 review, thread 4309904782).
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and the version-guard candidate.
--
-- `submit_evidence` records a caller-supplied SHA-256 and size for the
-- generated path assurance/{tenant}/{engagement}/{evidence}. Nothing stored
-- bytes there or checked them, so evidence that was never uploaded could be
-- accepted, frozen and exported. This slice adds:
--
--   * a private bucket whose object names are exactly those generated paths;
--   * storage.objects policies: only the request owner may upload, once, to
--     the path of their own submitted, unfrozen, unverified evidence item;
--     nobody may overwrite or delete through the client API;
--   * a verification record written only by the service (edge function
--     `assurance-evidence-verify`), which downloads the stored object, hashes
--     every byte and reports the observed digest and size. SQL cannot read
--     Storage bytes (they live in the object store, not in Postgres), so the
--     hash is computed by a trusted service holding a one-use ticket that a
--     human with current authority obtained through their own session;
--   * triggers that refuse to accept such evidence, or freeze an engagement
--     holding it, unless a matching `verified` record exists and the stored
--     object is still the one that was hashed.
--
-- Server-collected evidence (A4/A4b adapters) is digested in SQL from the
-- source rows and never uses the upload path, so it is unaffected.
-- `api.assurance_command` is not replaced: the gate sits on the state change.

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('jentra-assurance-evidence', 'jentra-assurance-evidence', false, 104857600, array[
  'application/pdf', 'image/png', 'image/jpeg', 'text/plain', 'text/csv',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document']);

create table assurance.evidence_verification_tickets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references core.tenants(id),
  engagement_id uuid not null references assurance.engagements(id),
  evidence_id uuid not null references assurance.evidence_items(id),
  user_id uuid not null references auth.users(id),
  issued_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  check (expires_at > issued_at and expires_at <= issued_at + interval '5 minutes')
);

create table assurance.evidence_verifications (
  evidence_id uuid primary key references assurance.evidence_items(id),
  engagement_id uuid not null references assurance.engagements(id),
  storage_object_id uuid not null,
  object_updated_at timestamptz not null,
  object_version text,
  outcome text not null check (outcome in ('verified','mismatch')),
  observed_sha256 text not null check (observed_sha256 ~ '^[0-9a-f]{64}$'),
  observed_byte_size bigint not null check (observed_byte_size >= 0),
  requested_by uuid not null references auth.users(id),
  ticket_id uuid not null unique references assurance.evidence_verification_tickets(id),
  verifier text not null check (verifier = 'assurance-evidence-verify/v1'),
  verified_at timestamptz not null default clock_timestamp()
);

create index assurance_verification_tickets_evidence_idx
  on assurance.evidence_verification_tickets (evidence_id, expires_at);

do $$
declare t text;
begin
  foreach t in array array['evidence_verification_tickets','evidence_verifications'] loop
    execute format('alter table assurance.%I enable row level security', t);
    execute format('alter table assurance.%I force row level security', t);
    execute format('revoke all on assurance.%I from public, anon, authenticated, service_role', t);
  end loop;
end $$;

-- A verification is history. A ticket only ever gains its consumption time.
create trigger evidence_verifications_immutable before update or delete on assurance.evidence_verifications
  for each row execute function assurance.forbid_mutation();

create function assurance.ticket_consume_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' or old.consumed_at is not null or new.consumed_at is null
     or (to_jsonb(new) - 'consumed_at') is distinct from (to_jsonb(old) - 'consumed_at') then
    raise exception using errcode = '55000', message = 'ASSURANCE_HISTORY_IMMUTABLE';
  end if;
  return new;
end $$;
create trigger evidence_verification_tickets_consume_only
  before update or delete on assurance.evidence_verification_tickets
  for each row execute function assurance.ticket_consume_only();

create function assurance.upload_path(p_tenant_id uuid, p_engagement_id uuid, p_evidence_id uuid)
returns text language sql immutable set search_path = '' as $$
  select format('assurance/%s/%s/%s', p_tenant_id, p_engagement_id, p_evidence_id)
$$;

-- The current version at a path: Storage keeps archived versions and delete
-- markers when versioning is on. Read through jsonb so the predicate also
-- holds on Storage schemas without those columns.
create function assurance.live_object(p_name text)
returns setof storage.objects language sql stable security definer set search_path = '' as $
  select o.* from storage.objects o
  where o.bucket_id = 'jentra-assurance-evidence' and o.name = p_name
    and to_jsonb(o)->>'archived_at' is null
    and not coalesce((to_jsonb(o)->>'is_delete_marker')::boolean, false)
$;

-- True only when the current stored object is the one a `verified` record
-- hashed, and that record matches the claimed digest and size.
create function assurance.evidence_bytes_verified(p_evidence_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from assurance.evidence_items i
    join assurance.evidence_verifications v on v.evidence_id = i.id
    join lateral assurance.live_object(i.storage_ref) o on o.id = v.storage_object_id
    where i.id = p_evidence_id and v.outcome = 'verified'
      and v.observed_sha256 = i.sha256 and v.observed_byte_size = i.byte_size
      and o.updated_at is not distinct from v.object_updated_at
      and o.version is not distinct from v.object_version)
$$;

-- Items submitted through `submit_evidence` live on the generated upload path;
-- adapter evidence uses source references and is digested by the server.
create function assurance.needs_upload(p_evidence_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from assurance.evidence_items i
    join assurance.engagements e on e.id = i.engagement_id
    where i.id = p_evidence_id
      and i.storage_ref = assurance.upload_path(e.tenant_id, e.id, i.id))
$$;

create function assurance.require_verified_acceptance() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'submitted' and new.status = 'accepted'
     and assurance.needs_upload(new.current_evidence_id)
     and not assurance.evidence_bytes_verified(new.current_evidence_id) then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_UNVERIFIED';
  end if;
  return new;
end $$;
create trigger evidence_requests_verified_acceptance before update on assurance.evidence_requests
  for each row execute function assurance.require_verified_acceptance();

-- Covers evidence accepted before this slice was installed.
create function assurance.require_verified_freeze() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.evidence_frozen_at is null and new.evidence_frozen_at is not null
     and exists (select 1 from assurance.evidence_requests r
       where r.engagement_id = new.id and r.status = 'accepted'
         and assurance.needs_upload(r.current_evidence_id)
         and not assurance.evidence_bytes_verified(r.current_evidence_id)) then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_UNVERIFIED';
  end if;
  return new;
end $$;
create trigger engagements_verified_freeze before update on assurance.engagements
  for each row execute function assurance.require_verified_freeze();

-- Storage policy predicates run as the caller, so they live in `core` (which
-- the client roles can use) and expose only a boolean about the caller's own
-- submitted item.
create function core.assurance_evidence_upload_allowed(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_parts text[];
  v_tenant uuid;
  v_engagement uuid;
  v_evidence uuid;
begin
  if v_uid is null or p_name is null
     or p_name !~ '^assurance/[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}$' then
    return false;
  end if;
  v_parts := string_to_array(p_name, '/');
  v_tenant := v_parts[2]::uuid;
  v_engagement := v_parts[3]::uuid;
  v_evidence := v_parts[4]::uuid;
  return exists (
    select 1 from assurance.evidence_items i
    join assurance.evidence_requests r on r.id = i.request_id and r.current_evidence_id = i.id
    join assurance.engagements e on e.id = i.engagement_id
    where i.id = v_evidence and e.id = v_engagement and e.tenant_id = v_tenant
      and i.storage_ref = p_name and i.collected_by = v_uid and r.owner_id = v_uid
      and r.status = 'submitted' and e.status = 'fieldwork' and e.evidence_frozen_at is null
      and core.has_permission(e.tenant_id, 'assurance.evidence.submit', e.legal_entity_id, e.branch_id))
    and not exists (select 1 from assurance.evidence_verifications v where v.evidence_id = v_evidence);
exception when invalid_text_representation then
  return false;
end $$;
revoke all on function core.assurance_evidence_upload_allowed(text) from public, anon;
grant execute on function core.assurance_evidence_upload_allowed(text) to authenticated;

create policy assurance_evidence_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'jentra-assurance-evidence'
    and owner_id = (select auth.uid())::text
    and core.assurance_evidence_upload_allowed(name));
-- The uploader may see the row they created (Storage reads it back on upload).
-- Reviewers read verification results, never bytes, through the API.
create policy assurance_evidence_read_own on storage.objects
  for select to authenticated
  using (bucket_id = 'jentra-assurance-evidence' and owner_id = (select auth.uid())::text);
-- Restrictive guards keep any other permissive policy from opening the bucket.
create policy assurance_evidence_insert_guard on storage.objects as restrictive
  for insert to anon, authenticated
  with check (bucket_id <> 'jentra-assurance-evidence'
    or (owner_id = (select auth.uid())::text and core.assurance_evidence_upload_allowed(name)));
create policy assurance_evidence_read_guard on storage.objects as restrictive
  for select to anon, authenticated
  using (bucket_id <> 'jentra-assurance-evidence' or owner_id = (select auth.uid())::text);
create policy assurance_evidence_no_update on storage.objects as restrictive
  for update to anon, authenticated
  using (bucket_id <> 'jentra-assurance-evidence')
  with check (bucket_id <> 'jentra-assurance-evidence');
create policy assurance_evidence_no_delete on storage.objects as restrictive
  for delete to anon, authenticated
  using (bucket_id <> 'jentra-assurance-evidence');

create function assurance.verification_json(v assurance.evidence_verifications)
returns jsonb language sql immutable set search_path = '' as $$
  select case when v.evidence_id is null then null else jsonb_build_object(
    'evidence_id', v.evidence_id, 'outcome', v.outcome, 'observed_sha256', v.observed_sha256,
    'observed_byte_size', v.observed_byte_size, 'verified_at', v.verified_at, 'verifier', v.verifier) end
$$;

create function assurance.service_only() returns void
language plpgsql stable set search_path = '' as $$
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'ASSURANCE_TRUSTED_SERVICE_REQUIRED';
  end if;
end $$;

-- Who may ask for a verification: the request owner with submit authority, or
-- an internal audit team member with review authority. External reviewers are
-- read-only.
create function api.assurance_evidence_verification_ticket(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_engagement_id uuid,
  p_evidence_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_eng assurance.engagements%rowtype;
  v_item assurance.evidence_items%rowtype;
  v_owner uuid;
  v_role text;
  v_ver assurance.evidence_verifications%rowtype;
  v_ticket assurance.evidence_verification_tickets%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'assurance.evidence.submit', p_legal_entity_id, p_branch_id)
     and not core.has_permission(p_tenant_id, 'assurance.test.review', p_legal_entity_id, p_branch_id) then
    perform assurance.deny('Permission denied or multi-factor authentication required.');
  end if;
  select * into v_eng from assurance.engagements
   where id = p_engagement_id and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  select * into v_item from assurance.evidence_items
   where id = p_evidence_id and engagement_id = v_eng.id
     and storage_ref = assurance.upload_path(v_eng.tenant_id, v_eng.id, p_evidence_id);
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_EVIDENCE_NOT_FOUND';
  end if;
  select owner_id into v_owner from assurance.evidence_requests where id = v_item.request_id;
  v_role := assurance.team_role(v_eng.id, v_uid);
  if v_role = 'external' then
    perform assurance.deny('ASSURANCE_EXTERNAL_READ_ONLY');
  end if;
  if not ((v_owner = v_uid and v_item.collected_by = v_uid
           and core.has_permission(p_tenant_id, 'assurance.evidence.submit', p_legal_entity_id, p_branch_id))
       or (v_role in ('lead','auditor','reviewer')
           and core.has_permission(p_tenant_id, 'assurance.test.review', p_legal_entity_id, p_branch_id))) then
    perform assurance.deny('ASSURANCE_VERIFICATION_ACTOR_REQUIRED');
  end if;
  select * into v_ver from assurance.evidence_verifications where evidence_id = v_item.id;
  if found then
    return jsonb_build_object('evidence_id', v_item.id, 'ticket_id', null,
      'verification', assurance.verification_json(v_ver));
  end if;
  insert into assurance.evidence_verification_tickets(tenant_id, engagement_id, evidence_id, user_id,
    issued_at, expires_at)
  values (v_eng.tenant_id, v_eng.id, v_item.id, v_uid, v_now, v_now + interval '5 minutes')
  returning * into v_ticket;
  return jsonb_build_object('evidence_id', v_item.id, 'ticket_id', v_ticket.id,
    'expires_at', v_ticket.expires_at, 'verification', null);
end $$;

create function assurance.service_ticket(p_ticket_id uuid, p_user_id uuid, p_lock boolean)
returns assurance.evidence_verification_tickets
language plpgsql security definer set search_path = '' as $$
declare v_ticket assurance.evidence_verification_tickets%rowtype;
begin
  perform assurance.service_only();
  if p_lock then
    select * into v_ticket from assurance.evidence_verification_tickets where id = p_ticket_id for update;
  else
    select * into v_ticket from assurance.evidence_verification_tickets where id = p_ticket_id;
  end if;
  -- The human must still be an active member when the service acts.
  if not found or v_ticket.user_id is distinct from p_user_id or v_ticket.consumed_at is not null
     or v_ticket.expires_at <= clock_timestamp()
     or not assurance.active_member(v_ticket.tenant_id, p_user_id) then
    raise exception using errcode = '42501', message = 'ASSURANCE_TICKET_INVALID';
  end if;
  return v_ticket;
end $$;

-- Service step 1: what to hash. Returns only the fixed bucket, the generated
-- path and the claimed digest and size.
create function api.assurance_evidence_service_target(p_ticket_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ticket assurance.evidence_verification_tickets%rowtype;
  v_item assurance.evidence_items%rowtype;
  v_object uuid;
begin
  v_ticket := assurance.service_ticket(p_ticket_id, p_user_id, false);
  select * into v_item from assurance.evidence_items where id = v_ticket.evidence_id;
  select o.id into v_object from assurance.live_object(v_item.storage_ref) o;
  if v_object is null then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_OBJECT_MISSING';
  end if;
  return jsonb_build_object('evidence_id', v_item.id, 'bucket', 'jentra-assurance-evidence',
    'object_path', v_item.storage_ref, 'sha256', v_item.sha256, 'byte_size', v_item.byte_size,
    'verified', exists (select 1 from assurance.evidence_verifications where evidence_id = v_item.id));
end $$;

-- Service step 2: record what the stored bytes actually hash to. The outcome
-- is final: clients can neither overwrite nor delete the object, so a
-- mismatch is resolved by rejecting the submission and submitting new
-- evidence under a new id and path.
create function api.assurance_evidence_service_verify(
  p_ticket_id uuid,
  p_user_id uuid,
  p_observed_sha256 text,
  p_observed_byte_size bigint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_ticket assurance.evidence_verification_tickets%rowtype;
  v_item assurance.evidence_items%rowtype;
  v_object storage.objects%rowtype;
  v_ver assurance.evidence_verifications%rowtype;
  v_outcome text;
begin
  v_ticket := assurance.service_ticket(p_ticket_id, p_user_id, true);
  if p_observed_sha256 is null or p_observed_sha256 !~ '^[0-9a-f]{64}$'
     or p_observed_byte_size is null or p_observed_byte_size < 0 then
    raise exception using errcode = '22023', message = 'ASSURANCE_FIELD_INVALID';
  end if;
  update assurance.evidence_verification_tickets set consumed_at = clock_timestamp() where id = v_ticket.id;
  select * into v_ver from assurance.evidence_verifications where evidence_id = v_ticket.evidence_id;
  if found then
    return assurance.verification_json(v_ver);
  end if;
  select * into v_item from assurance.evidence_items where id = v_ticket.evidence_id;
  select * into v_object from assurance.live_object(v_item.storage_ref);
  if not found then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_OBJECT_MISSING';
  end if;
  perform 1 from storage.objects where id = v_object.id for update;
  -- Storage's own size record must agree with the bytes the service read.
  v_outcome := case when p_observed_sha256 = v_item.sha256 and p_observed_byte_size = v_item.byte_size
      and (v_object.metadata->>'size') is not distinct from p_observed_byte_size::text
    then 'verified' else 'mismatch' end;
  insert into assurance.evidence_verifications(evidence_id, engagement_id, storage_object_id, object_updated_at, object_version,
    outcome, observed_sha256, observed_byte_size, requested_by, ticket_id, verifier)
  values (v_item.id, v_item.engagement_id, v_object.id, v_object.updated_at, v_object.version, v_outcome,
    p_observed_sha256, p_observed_byte_size, p_user_id, v_ticket.id, 'assurance-evidence-verify/v1')
  returning * into v_ver;
  return assurance.verification_json(v_ver);
end $$;

-- Read model for the desktop: whether bytes are required, stored and verified.
create function api.assurance_evidence_verification(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_engagement_id uuid,
  p_evidence_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_eng assurance.engagements%rowtype;
  v_item assurance.evidence_items%rowtype;
  v_ver assurance.evidence_verifications%rowtype;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if not core.has_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id)
     and not core.has_permission(p_tenant_id, 'assurance.evidence.submit', p_legal_entity_id, p_branch_id) then
    perform assurance.deny('Permission denied or multi-factor authentication required.');
  end if;
  select * into v_eng from assurance.engagements
   where id = p_engagement_id and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  select * into v_item from assurance.evidence_items where id = p_evidence_id and engagement_id = v_eng.id;
  if not found
     or (not core.has_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id)
         and v_item.collected_by <> v_uid) then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_EVIDENCE_NOT_FOUND';
  end if;
  select * into v_ver from assurance.evidence_verifications where evidence_id = v_item.id;
  return jsonb_build_object('engagement_id', v_eng.id, 'evidence_id', v_item.id,
    'sha256', v_item.sha256, 'byte_size', v_item.byte_size,
    'upload_required', assurance.needs_upload(v_item.id),
    'stored', exists (select 1 from assurance.live_object(v_item.storage_ref)),
    'bytes_verified', assurance.evidence_bytes_verified(v_item.id),
    'verification', case when v_ver.evidence_id is null then null else assurance.verification_json(v_ver) end);
end $$;

revoke all on function assurance.upload_path(uuid,uuid,uuid), assurance.live_object(text),
  assurance.evidence_bytes_verified(uuid),
  assurance.needs_upload(uuid), assurance.require_verified_acceptance(), assurance.require_verified_freeze(),
  assurance.ticket_consume_only(), assurance.verification_json(assurance.evidence_verifications),
  assurance.service_only(), assurance.service_ticket(uuid,uuid,boolean)
  from public, anon, authenticated, service_role;
revoke all on function api.assurance_evidence_verification_ticket(uuid,uuid,uuid,uuid,uuid),
  api.assurance_evidence_verification(uuid,uuid,uuid,uuid,uuid),
  api.assurance_evidence_service_target(uuid,uuid),
  api.assurance_evidence_service_verify(uuid,uuid,text,bigint)
  from public, anon, authenticated, service_role;
grant execute on function api.assurance_evidence_verification_ticket(uuid,uuid,uuid,uuid,uuid),
  api.assurance_evidence_verification(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function api.assurance_evidence_service_target(uuid,uuid),
  api.assurance_evidence_service_verify(uuid,uuid,text,bigint) to service_role;
