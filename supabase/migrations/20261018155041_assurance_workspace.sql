-- Corporate Audit & Assurance A5: desktop workspace read models (blueprint 68,
-- FR-6823 reminders/escalations/overdue, FR-6824 workspace).
--
-- CANDIDATE ONLY. Installs after A1, A2, A4, A4b and A3. Adds no tables and no
-- writes: an engagement register and a work queue whose reminder levels are
-- derived from due dates at read time. Nothing is sent; delivery of reminders
-- (notifications, e-mail) is out of scope.

-- Finding owners must respond within this many days of issue.
create function assurance.response_sla_days() returns integer
language sql immutable set search_path = '' as $$ select 14 $$;

-- on_track: due in more than 3 days; due_soon: due within 3 days or today;
-- overdue: 1-7 days late; escalated: more than 7 days late.
create function assurance.reminder_level(p_due date, p_today date) returns text
language sql immutable set search_path = '' as $$
  select case when p_due is null then 'on_track'
              when p_today - p_due > 7 then 'escalated'
              when p_today - p_due >= 1 then 'overdue'
              when p_due - p_today <= 3 then 'due_soon'
              else 'on_track' end;
$$;

-- Open work items in one scope: unsubmitted evidence requests and findings
-- awaiting a response or remediation.
create function assurance.work_items(p_tenant_id uuid, p_legal_entity_id uuid, p_branch_id uuid)
returns table (engagement_id uuid, engagement_name text, engagement_version bigint, kind text,
  item_id uuid, title text, owner_id uuid, status text, due_date date, level text)
language sql stable set search_path = '' as $$
  select e.id, e.name, e.version, 'evidence_request', r.id, left(r.description, 160), r.owner_id,
         r.status, r.due_date, assurance.reminder_level(r.due_date, current_date)
    from assurance.engagements e join assurance.evidence_requests r on r.engagement_id = e.id
   where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id
     and e.status in ('planning','fieldwork') and r.status = 'open'
  union all
  select e.id, e.name, e.version, 'finding', f.id, f.title, f.owner_id, f.status,
         case when f.status = 'issued' then (f.issued_at at time zone 'UTC')::date + assurance.response_sla_days()
              else f.response_due end,
         assurance.reminder_level(case when f.status = 'issued'
           then (f.issued_at at time zone 'UTC')::date + assurance.response_sla_days() else f.response_due end,
           current_date)
    from assurance.engagements e join assurance.findings f on f.engagement_id = e.id
   where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
     and e.branch_id is not distinct from p_branch_id
     and e.status not in ('archived','cancelled') and f.status in ('issued','remediating');
$$;

create function api.assurance_engagements(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_after uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_items jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  select coalesce(jsonb_agg(x.j order by x.id), '[]'::jsonb) into v_items from (
    select e.id, jsonb_build_object('id', e.id, 'name', e.name, 'status', e.status, 'version', e.version,
      'period_start', e.period_start, 'period_end', e.period_end, 'lead_auditor_id', e.lead_auditor_id,
      'evidence_frozen', e.evidence_frozen_at is not null,
      'open_requests', (select count(*) from assurance.evidence_requests r
         where r.engagement_id = e.id and r.status in ('open','submitted')),
      'overdue_requests', (select count(*) from assurance.evidence_requests r
         where r.engagement_id = e.id and r.status = 'open' and r.due_date < current_date
           and e.status in ('planning','fieldwork')),
      'open_findings', (select count(*) from assurance.findings f
         where f.engagement_id = e.id and f.status not in ('closed','risk_accepted')),
      'overdue_findings', (select count(*) from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
         where w.engagement_id = e.id and w.kind = 'finding' and w.level in ('overdue','escalated')),
      'candidate_exceptions', (select count(*) from assurance.exceptions x
         where x.engagement_id = e.id and x.status = 'candidate')) j
    from assurance.engagements e
    where e.tenant_id = p_tenant_id and e.legal_entity_id = p_legal_entity_id
      and e.branch_id is not distinct from p_branch_id
      and (p_after is null or e.id > p_after)
    order by e.id
    limit 50) x;
  return jsonb_build_object('items', v_items,
    'next_cursor', case when jsonb_array_length(v_items) = 50 then v_items->49->>'id' end);
end $$;

-- The caller's own open work, plus overdue and escalated items on engagements
-- the caller leads or audits. Levels are derived at read time from due dates.
create function api.assurance_overview(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_mine jsonb;
  v_team jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.evidence.view', p_legal_entity_id, p_branch_id);
  select coalesce(jsonb_agg(to_jsonb(w) order by w.due_date, w.item_id), '[]'::jsonb) into v_mine
    from (select * from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
           where w.owner_id = v_uid order by w.due_date, w.item_id limit 100) w;
  select coalesce(jsonb_agg(to_jsonb(w) order by w.due_date, w.item_id), '[]'::jsonb) into v_team
    from (select * from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
           where w.owner_id <> v_uid and w.level in ('overdue','escalated')
             and assurance.team_role(w.engagement_id, v_uid) in ('lead','auditor')
           order by w.due_date, w.item_id limit 100) w;
  return jsonb_build_object('as_of', current_date, 'response_sla_days', assurance.response_sla_days(),
    'mine', v_mine, 'team', v_team,
    'counts', jsonb_build_object(
      'due_soon', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'due_soon'),
      'overdue', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'overdue'),
      'escalated', (select count(*) from jsonb_array_elements(v_mine || v_team) i where i->>'level' = 'escalated')));
end $$;

revoke all on all functions in schema assurance from public, anon, authenticated, service_role;
revoke all on function api.assurance_engagements(uuid, uuid, uuid, uuid) from public, anon, service_role;
revoke all on function api.assurance_overview(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function api.assurance_engagements(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function api.assurance_overview(uuid, uuid, uuid) to authenticated;
