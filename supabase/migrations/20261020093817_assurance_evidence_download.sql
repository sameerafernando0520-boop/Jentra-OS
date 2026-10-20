-- Corporate Audit & Assurance A12: reviewer download of verified evidence.
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and the evidence-storage
-- candidate (20261019120000).
--
-- Reviewers read uploaded evidence only after the service has hashed it. A
-- human session with current authority mints a five-minute, one-use ticket;
-- the edge function `assurance-evidence-download` redeems it with the service
-- key, and this redemption re-checks that the stored object is still the
-- verified version before the function signs a 60-second URL. The device
-- hashes the bytes again before saving. Tickets are the download log.

create table assurance.evidence_download_tickets (
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
create index assurance_download_tickets_evidence_idx
  on assurance.evidence_download_tickets (evidence_id, issued_at);
alter table assurance.evidence_download_tickets enable row level security;
alter table assurance.evidence_download_tickets force row level security;
revoke all on assurance.evidence_download_tickets from public, anon, authenticated, service_role;
create trigger evidence_download_tickets_consume_only
  before update or delete on assurance.evidence_download_tickets
  for each row execute function assurance.ticket_consume_only();

-- Who may download: evidence viewers in scope, or a current external team
-- member on this engagement (the A1 time-bound, read-only path). Authority is
-- checked before the engagement or item is looked up.
create function api.assurance_evidence_download_ticket(
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
  v_ticket assurance.evidence_download_tickets%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  if exists (select 1 from assurance.engagement_team
             where engagement_id = p_engagement_id and user_id = v_uid and role = 'external') then
    if assurance.team_role(p_engagement_id, v_uid) is distinct from 'external'
       or not core.has_permission(p_tenant_id, 'assurance.external_review', p_legal_entity_id, p_branch_id) then
      perform assurance.deny('ASSURANCE_EXTERNAL_ACCESS_EXPIRED');
    end if;
  elsif not core.has_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id) then
    perform assurance.deny('Permission denied or multi-factor authentication required.');
  end if;
  select * into v_eng from assurance.engagements
   where id = p_engagement_id and tenant_id = p_tenant_id and legal_entity_id = p_legal_entity_id
     and branch_id is not distinct from p_branch_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_ENGAGEMENT_NOT_FOUND';
  end if;
  -- Only uploaded items have bytes; adapter evidence is digested from source rows.
  select * into v_item from assurance.evidence_items
   where id = p_evidence_id and engagement_id = v_eng.id
     and storage_ref = assurance.upload_path(v_eng.tenant_id, v_eng.id, p_evidence_id);
  if not found then
    raise exception using errcode = 'P0002', message = 'ASSURANCE_EVIDENCE_NOT_FOUND';
  end if;
  if not assurance.evidence_bytes_verified(v_item.id) then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_UNVERIFIED';
  end if;
  insert into assurance.evidence_download_tickets(tenant_id, engagement_id, evidence_id, user_id,
    issued_at, expires_at)
  values (v_eng.tenant_id, v_eng.id, v_item.id, v_uid, v_now, v_now + interval '5 minutes')
  returning * into v_ticket;
  return jsonb_build_object('evidence_id', v_item.id, 'ticket_id', v_ticket.id,
    'expires_at', v_ticket.expires_at);
end $$;

-- Service redemption: one use, by the human who asked, while they are still an
-- active member and the stored object is still the verified version. Returns
-- only the fixed bucket, the generated path and the recorded digest and size.
create function api.assurance_evidence_service_download(p_ticket_id uuid, p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_ticket assurance.evidence_download_tickets%rowtype;
  v_item assurance.evidence_items%rowtype;
begin
  perform assurance.service_only();
  select * into v_ticket from assurance.evidence_download_tickets where id = p_ticket_id for update;
  if not found or v_ticket.user_id is distinct from p_user_id or v_ticket.consumed_at is not null
     or v_ticket.expires_at <= clock_timestamp()
     or not assurance.active_member(v_ticket.tenant_id, p_user_id) then
    raise exception using errcode = '42501', message = 'ASSURANCE_TICKET_INVALID';
  end if;
  update assurance.evidence_download_tickets set consumed_at = clock_timestamp() where id = v_ticket.id;
  select * into v_item from assurance.evidence_items where id = v_ticket.evidence_id;
  if not assurance.evidence_bytes_verified(v_item.id) then
    raise exception using errcode = '55000', message = 'ASSURANCE_EVIDENCE_UNVERIFIED';
  end if;
  return jsonb_build_object('evidence_id', v_item.id, 'bucket', 'jentra-assurance-evidence',
    'object_path', v_item.storage_ref, 'sha256', v_item.sha256, 'byte_size', v_item.byte_size);
end $$;

revoke all on function api.assurance_evidence_download_ticket(uuid,uuid,uuid,uuid,uuid),
  api.assurance_evidence_service_download(uuid,uuid)
  from public, anon, authenticated, service_role;
grant execute on function api.assurance_evidence_download_ticket(uuid,uuid,uuid,uuid,uuid) to authenticated;
grant execute on function api.assurance_evidence_service_download(uuid,uuid) to service_role;
