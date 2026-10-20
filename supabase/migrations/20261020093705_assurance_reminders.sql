-- Corporate Audit & Assurance A10: reminder delivery.
-- CANDIDATE ONLY. Not installed. Requires A1-A5 and A9 (tenant-aware
-- assurance.work_items).
--
-- api.assurance_scan_reminders turns the scope's due-soon, overdue and
-- escalated work into in-app notices (workflow.notifications, read through
-- api.my_notifications): one per item, level and recipient. The item owner is
-- told at every level; escalated items also tell the engagement lead. Notices
-- name the engagement and the kind of item only, never request text or
-- finding detail, and point at the engagement (aggregate_type
-- 'assurance_engagement'). Scans are safe to repeat: the unique index below
-- makes a second scan of the same day a no-op. Engagement managers run it on
-- demand or when they open the workspace; there is no scheduler.

create unique index assurance_reminder_identity on workflow.notifications
  (tenant_id, recipient_id, notification_type, (source_context->>'due_key'))
  where notification_type = 'assurance.reminder';

create function api.assurance_scan_reminders(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_idempotency_key uuid,
  p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_hash text;
  v_receipt assurance.command_receipts%rowtype;
  v_after uuid;
  v_item record;
  v_recipient uuid;
  v_count integer := 0;
  v_emitted integer := 0;
  v_inserted integer;
  v_more boolean := false;
  v_last uuid;
  v_request uuid := gen_random_uuid();
  v_level text;
  v_response jsonb;
begin
  if v_uid is null then
    perform assurance.deny('Authentication required.');
  end if;
  if jsonb_typeof(p_payload) is distinct from 'object'
     or exists (select 1 from jsonb_object_keys(p_payload) k where k <> 'after_id') then
    raise exception using errcode = '22023', message = 'ASSURANCE_UNEXPECTED_FIELD';
  end if;
  perform assurance.require_scope(p_tenant_id, p_legal_entity_id, p_branch_id);
  perform core.require_permission(p_tenant_id, 'assurance.engagement.manage', p_legal_entity_id, p_branch_id);
  v_hash := encode(extensions.digest(convert_to(jsonb_build_array(
    p_tenant_id, p_legal_entity_id, p_branch_id, 'scan_reminders', p_payload)::text, 'UTF8'), 'sha256'), 'hex');
  select * into v_receipt from assurance.command_receipts
   where actor_id = v_uid and idempotency_key = p_idempotency_key;
  if found then
    if v_receipt.request_hash <> v_hash or v_receipt.tenant_id <> p_tenant_id then
      raise exception using errcode = '22023', message = 'IDEMPOTENCY_MISMATCH';
    end if;
    return v_receipt.response;
  end if;
  v_after := case when coalesce(jsonb_typeof(p_payload->'after_id'), 'null') = 'null' then null
                  else assurance.uuid_field(p_payload, 'after_id') end;

  for v_item in
    select w.engagement_id, w.engagement_name, w.kind, w.item_id, w.owner_id, w.level, e.lead_auditor_id
      from assurance.work_items(p_tenant_id, p_legal_entity_id, p_branch_id) w
      join assurance.engagements e on e.id = w.engagement_id
     where w.level in ('due_soon','overdue','escalated')
       and (v_after is null or w.item_id > v_after)
     order by w.item_id
     limit 101
  loop
    if v_count = 100 then
      v_more := true;
      exit;
    end if;
    v_count := v_count + 1;
    v_last := v_item.item_id;
    v_level := replace(v_item.level, '_', ' ');
    for v_recipient in
      select distinct r from unnest(array[v_item.owner_id]
        || case when v_item.level = 'escalated' then array[v_item.lead_auditor_id] else array[]::uuid[] end) r
       where assurance.active_member(p_tenant_id, r)
    loop
      insert into workflow.notifications(tenant_id, recipient_id, notification_type, title, body,
        aggregate_type, aggregate_id, legal_entity_id, branch_id, actor_id, request_id, correlation_id,
        source_context, created_by, updated_by)
      values (p_tenant_id, v_recipient, 'assurance.reminder',
        case v_item.kind when 'finding' then 'Finding response ' else 'Evidence request ' end || v_level,
        format('%s: %s is %s.', v_item.engagement_name,
          case v_item.kind when 'finding' then 'a finding response' else 'an evidence request' end, v_level),
        'assurance_engagement', v_item.engagement_id, p_legal_entity_id, p_branch_id, v_uid, v_request, v_request,
        jsonb_build_object('due_key', v_item.item_id::text || ':' || v_item.level, 'level', v_item.level,
          'kind', v_item.kind, 'engagement_id', v_item.engagement_id),
        v_uid, v_uid)
      on conflict do nothing;
      get diagnostics v_inserted = row_count;
      v_emitted := v_emitted + v_inserted;
    end loop;
  end loop;

  v_response := jsonb_build_object('examined', v_count, 'emitted', v_emitted, 'has_more', v_more,
    'next_after', case when v_more then to_jsonb(v_last) else 'null'::jsonb end);
  insert into assurance.command_receipts(actor_id, idempotency_key, tenant_id, request_hash, response)
  values (v_uid, p_idempotency_key, p_tenant_id, v_hash, v_response);
  return v_response;
end $$;

revoke all on function api.assurance_scan_reminders(uuid, uuid, uuid, uuid, jsonb) from public, anon, service_role;
grant execute on function api.assurance_scan_reminders(uuid, uuid, uuid, uuid, jsonb) to authenticated;
