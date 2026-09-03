-- Wave 2 special commands: serialized numbering, private attachment lifecycle,
-- recipient notifications, and bounded atomic import/export jobs.

create function core.wave2_derived_uuid(p_parent uuid, p_ordinal integer)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select (
    substr(md5(p_parent::text || ':' || p_ordinal::text), 1, 8) || '-' ||
    substr(md5(p_parent::text || ':' || p_ordinal::text), 9, 4) || '-' ||
    substr(md5(p_parent::text || ':' || p_ordinal::text), 13, 4) || '-' ||
    substr(md5(p_parent::text || ':' || p_ordinal::text), 17, 4) || '-' ||
    substr(md5(p_parent::text || ':' || p_ordinal::text), 21, 12)
  )::uuid;
$$;

create function core.reserve_document_number_impl(
  p_tenant_id uuid,
  p_sequence_id uuid,
  p_document_date date,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_sequence core.document_sequences%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_request_hash text;
  v_replay jsonb;
  v_reset_key text;
  v_next_value bigint;
  v_number text;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  select ds.* into v_sequence
  from core.document_sequences as ds
  where ds.tenant_id = p_tenant_id and ds.id = p_sequence_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Document sequence was not found.';
  end if;
  perform core.require_permission(
    p_tenant_id,
    'core.setup.view',
    v_sequence.legal_entity_id,
    v_sequence.branch_id
  );

  v_request_hash := core.wave2_request_hash(
    'reserve_document_number',
    p_tenant_id,
    v_sequence.legal_entity_id,
    jsonb_build_object(
      'sequence_id', p_sequence_id,
      'document_date', coalesce(p_document_date, current_date)
    ),
    null
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'reserve_document_number', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select ds.* into v_sequence
  from core.document_sequences as ds
  where ds.tenant_id = p_tenant_id and ds.id = p_sequence_id
  for update;
  if v_sequence.status <> 'active' then
    raise exception using errcode = '55000', message = 'Document sequence is inactive.';
  end if;
  v_before := to_jsonb(v_sequence);

  v_reset_key := case v_sequence.reset_policy
    when 'yearly' then to_char(coalesce(p_document_date, current_date), 'YYYY')
    when 'monthly' then to_char(coalesce(p_document_date, current_date), 'YYYY-MM')
    else null
  end;
  v_next_value := case
    when v_reset_key is not null
      and v_sequence.last_reset_key is distinct from v_reset_key then 1
    else v_sequence.next_value
  end;
  v_number := v_sequence.prefix
    || lpad(v_next_value::text, v_sequence.padding, '0')
    || v_sequence.suffix;

  update core.document_sequences set
    next_value = v_next_value + 1,
    last_reset_key = v_reset_key,
    updated_by = v_actor
  where id = p_sequence_id
  returning * into v_sequence;

  v_entity := to_jsonb(v_sequence) || jsonb_build_object(
    'code', v_sequence.document_type,
    'name', replace(initcap(replace(v_sequence.document_type, '_', ' ')), '.', ' '),
    'number', v_number,
    'reserved_value', v_next_value,
    'document_date', coalesce(p_document_date, current_date)
  );

  return core.wave2_finish_command(
    p_tenant_id,
    'reserve_document_number',
    'document_sequence',
    p_sequence_id,
    p_idempotency_key,
    v_request_hash,
    v_before,
    v_entity,
    v_sequence.legal_entity_id,
    v_sequence.branch_id
  );
end;
$$;

create function core.register_attachment_impl(
  p_tenant_id uuid,
  p_payload jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_id uuid := gen_random_uuid();
  v_file_name text := trim(p_payload->>'file_name');
  v_mime_type text := p_payload->>'mime_type';
  v_byte_size bigint := (p_payload->>'byte_size')::bigint;
  v_aggregate_type text := p_payload->>'aggregate_type';
  v_aggregate_id uuid := nullif(p_payload->>'aggregate_id', '')::uuid;
  v_extension text;
  v_object_path text;
  v_request_hash text;
  v_replay jsonb;
  v_entity jsonb;
  v_row core.attachments%rowtype;
begin
  perform core.require_permission(p_tenant_id, 'core.files.manage');
  if jsonb_typeof(p_payload) <> 'object'
     or coalesce(v_file_name, '') = ''
     or coalesce(v_aggregate_type, '') !~ '^[a-z][a-z0-9_.-]{1,79}$'
     or v_aggregate_id is null then
    raise exception using errcode = '22023', message = 'Attachment metadata is invalid.';
  end if;
  if v_file_name ~ '[[:cntrl:]]'
     or v_file_name ~ '[\\/]'
     or position('..' in v_file_name) > 0 then
    raise exception using errcode = '22023', message = 'Attachment file name is unsafe.';
  end if;
  if v_mime_type not in (
    'application/pdf', 'image/png', 'image/jpeg', 'text/csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ) then
    raise exception using errcode = '22023', message = 'Attachment MIME type is not allowed.';
  end if;
  if v_byte_size not between 1 and 26214400 then
    raise exception using errcode = '22023', message = 'Attachment size exceeds the allowed limit.';
  end if;

  v_request_hash := core.wave2_request_hash(
    'register_attachment', p_tenant_id, null, p_payload, null
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'register_attachment', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  v_extension := coalesce(
    (regexp_match(lower(v_file_name), '(\.[a-z0-9]{1,10})$'))[1],
    ''
  );
  v_object_path := p_tenant_id::text || '/' || v_aggregate_type || '/'
    || v_aggregate_id::text || '/' || v_id::text || '/' || v_id::text || v_extension;

  insert into core.attachments (
    id, tenant_id, aggregate_type, aggregate_id, file_name, mime_type,
    byte_size, bucket_id, object_path, upload_status, created_by, updated_by
  ) values (
    v_id, p_tenant_id, v_aggregate_type, v_aggregate_id, v_file_name,
    v_mime_type, v_byte_size, 'jentra-attachments', v_object_path,
    'staged', v_actor, v_actor
  ) returning * into v_row;
  v_entity := to_jsonb(v_row) || jsonb_build_object(
    'code', left(v_row.file_name, 48),
    'name', v_row.file_name
  );

  return core.wave2_finish_command(
    p_tenant_id,
    'register_attachment',
    'attachment',
    v_id,
    p_idempotency_key,
    v_request_hash,
    null,
    v_entity
  );
end;
$$;

create function core.complete_attachment_impl(
  p_tenant_id uuid,
  p_attachment_id uuid,
  p_checksum_sha256 text,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_attachment core.attachments%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_request_hash text;
  v_replay jsonb;
begin
  perform core.require_permission(p_tenant_id, 'core.files.manage');
  if p_checksum_sha256 is not null and p_checksum_sha256 !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'Attachment checksum is invalid.';
  end if;
  v_request_hash := core.wave2_request_hash(
    'complete_attachment',
    p_tenant_id,
    null,
    jsonb_build_object(
      'attachment_id', p_attachment_id,
      'checksum_sha256', p_checksum_sha256
    ),
    p_expected_version
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'complete_attachment', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select a.* into v_attachment
  from core.attachments as a
  where a.tenant_id = p_tenant_id and a.id = p_attachment_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Attachment was not found.';
  end if;
  perform core.wave2_assert_expected_version(v_attachment.version, p_expected_version);
  if v_attachment.upload_status = 'rejected' then
    raise exception using errcode = '55000', message = 'Rejected attachment cannot be completed.';
  end if;
  if not exists (
    select 1 from storage.objects as o
    where o.bucket_id = v_attachment.bucket_id
      and o.name = v_attachment.object_path
  ) then
    raise exception using errcode = 'P0002', message = 'Attachment upload is missing.';
  end if;

  v_before := to_jsonb(v_attachment);
  update core.attachments set
    upload_status = 'ready',
    checksum_sha256 = p_checksum_sha256,
    updated_by = v_actor
  where id = p_attachment_id
  returning * into v_attachment;
  v_entity := to_jsonb(v_attachment) || jsonb_build_object(
    'code', left(v_attachment.file_name, 48),
    'name', v_attachment.file_name
  );

  return core.wave2_finish_command(
    p_tenant_id,
    'complete_attachment',
    'attachment',
    p_attachment_id,
    p_idempotency_key,
    v_request_hash,
    v_before,
    v_entity
  );
end;
$$;

create function core.mark_notification_read_impl(
  p_tenant_id uuid,
  p_notification_id uuid,
  p_expected_version bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_notification workflow.notifications%rowtype;
  v_before jsonb;
  v_entity jsonb;
  v_request_hash text;
  v_replay jsonb;
begin
  if v_actor is null or not core.is_tenant_member(p_tenant_id) then
    raise exception using errcode = '42501', message = 'Permission denied.';
  end if;
  v_request_hash := core.wave2_request_hash(
    'mark_notification_read',
    p_tenant_id,
    null,
    jsonb_build_object('notification_id', p_notification_id),
    p_expected_version
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'mark_notification_read', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select n.* into v_notification
  from workflow.notifications as n
  where n.tenant_id = p_tenant_id
    and n.id = p_notification_id
    and n.recipient_id = v_actor
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Notification was not found.';
  end if;
  perform core.wave2_assert_expected_version(v_notification.version, p_expected_version);

  v_before := to_jsonb(v_notification);
  update workflow.notifications set
    read_at = coalesce(read_at, now()),
    updated_by = v_actor
  where id = p_notification_id
  returning * into v_notification;
  v_entity := to_jsonb(v_notification) || jsonb_build_object(
    'code', v_notification.notification_type,
    'name', v_notification.title
  );

  return core.wave2_finish_command(
    p_tenant_id,
    'mark_notification_read',
    'notification',
    p_notification_id,
    p_idempotency_key,
    v_request_hash,
    v_before,
    v_entity
  );
end;
$$;

create function core.import_setup_records_impl(
  p_tenant_id uuid,
  p_legal_entity_id uuid,
  p_resource text,
  p_file_format text,
  p_file_name text,
  p_file_size bigint,
  p_rows jsonb,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_permission text;
  v_request_payload jsonb;
  v_request_hash text;
  v_replay jsonb;
  v_job_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
  v_total integer;
  v_index integer := 0;
  v_row jsonb;
  v_status text := 'completed';
  v_accepted integer := 0;
  v_rejected integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_entity jsonb;
  v_response jsonb;
begin
  if v_actor is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  v_permission := core.wave2_permission(p_resource, true);
  if v_permission is null then
    raise exception using errcode = '22023', message = 'Import resource is not supported.';
  end if;
  perform core.require_permission(
    p_tenant_id, v_permission, p_legal_entity_id, null
  );
  if p_file_format not in ('csv', 'xlsx') then
    raise exception using errcode = '22023', message = 'Import format is invalid.';
  end if;
  if coalesce(length(trim(p_file_name)), 0) = 0
     or p_file_size not between 1 and 5242880 then
    raise exception using errcode = '22023', message = 'Import file metadata is invalid.';
  end if;
  if jsonb_typeof(p_rows) <> 'array' then
    raise exception using errcode = '22023', message = 'Import rows must be an array.';
  end if;
  v_total := jsonb_array_length(p_rows);
  if v_total not between 1 and 500 then
    raise exception using errcode = '22023', message = 'Import row limit is 500.';
  end if;

  v_request_payload := jsonb_build_object(
    'legal_entity_id', p_legal_entity_id,
    'resource', p_resource,
    'file_format', p_file_format,
    'file_name', p_file_name,
    'file_size', p_file_size,
    'rows', p_rows
  );
  v_request_hash := core.wave2_request_hash(
    'import_setup_records', p_tenant_id, p_legal_entity_id,
    v_request_payload, null
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'import_setup_records', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  begin
    for v_row in select value from jsonb_array_elements(p_rows)
    loop
      v_index := v_index + 1;
      if jsonb_typeof(v_row) <> 'object' then
        raise exception using errcode = '22023', message = 'Import row must be an object.';
      end if;
      perform core.upsert_setup_record_impl(
        p_resource,
        p_tenant_id,
        p_legal_entity_id,
        v_row,
        nullif(v_row->>'expected_version', '')::bigint,
        core.wave2_derived_uuid(p_idempotency_key, v_index)
      );
      v_accepted := v_accepted + 1;
    end loop;
  exception when others then
    v_status := 'failed';
    v_accepted := 0;
    v_rejected := v_total;
    v_errors := jsonb_build_array(jsonb_build_object(
      'row', greatest(v_index, 1),
      'field', '',
      'code', sqlstate,
      'message', sqlerrm
    ));
  end;

  if v_status = 'completed' then
    v_rejected := 0;
  end if;
  insert into core.import_jobs (
    id, tenant_id, legal_entity_id, actor_id, resource, file_format,
    file_name, file_size, status, total_rows, accepted_rows,
    rejected_rows, errors, request_id
  ) values (
    v_job_id, p_tenant_id, p_legal_entity_id, v_actor, p_resource,
    p_file_format, trim(p_file_name), p_file_size, v_status, v_total,
    v_accepted, v_rejected, v_errors, v_request_id
  );

  v_entity := jsonb_build_object(
    'id', v_job_id,
    'tenant_id', p_tenant_id,
    'legal_entity_id', p_legal_entity_id,
    'code', 'IMPORT-' || left(v_job_id::text, 8),
    'name', trim(p_file_name),
    'resource', p_resource,
    'file_format', p_file_format,
    'status', v_status,
    'total_rows', v_total,
    'accepted_rows', v_accepted,
    'rejected_rows', v_rejected,
    'errors', v_errors,
    'version', 1,
    'created_at', now(),
    'updated_at', now()
  );
  v_response := core.wave2_finish_command(
    p_tenant_id,
    'import_setup_records',
    'import_job',
    v_job_id,
    p_idempotency_key,
    v_request_hash,
    null,
    v_entity,
    p_legal_entity_id,
    null,
    '[]'::jsonb,
    v_request_id
  );

  insert into workflow.notifications (
    tenant_id, recipient_id, notification_type, title, body,
    aggregate_type, aggregate_id, created_by, updated_by
  ) values (
    p_tenant_id,
    v_actor,
    'import.' || v_status,
    case when v_status = 'completed' then 'Import completed' else 'Import needs attention' end,
    trim(p_file_name) || ': ' || v_accepted::text || ' accepted, '
      || v_rejected::text || ' rejected.',
    'import_job',
    v_job_id,
    v_actor,
    v_actor
  );

  return v_response;
end;
$$;

create function core.create_export_job_impl(
  p_tenant_id uuid,
  p_resource text,
  p_file_format text,
  p_filters jsonb,
  p_columns jsonb,
  p_row_count integer,
  p_file_name text,
  p_file_size bigint,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_permission text;
  v_request_payload jsonb;
  v_request_hash text;
  v_replay jsonb;
  v_job_id uuid := gen_random_uuid();
  v_request_id uuid := gen_random_uuid();
  v_entity jsonb;
  v_response jsonb;
begin
  v_permission := core.wave2_permission(p_resource, false);
  if v_permission is null then
    raise exception using errcode = '22023', message = 'Export resource is not supported.';
  end if;
  perform core.require_permission(p_tenant_id, v_permission);
  if p_file_format not in ('csv', 'xlsx')
     or coalesce(length(trim(p_file_name)), 0) = 0
     or p_file_size < 0
     or p_row_count not between 0 and 10000 then
    raise exception using errcode = '22023', message = 'Export metadata is invalid.';
  end if;
  if not core.report_contract_allowed(
    p_resource, p_columns, coalesce(p_filters, '{}'::jsonb), '[]'::jsonb
  ) then
    raise exception using errcode = '22023', message = 'Export fields are not allowed.';
  end if;

  v_request_payload := jsonb_build_object(
    'resource', p_resource,
    'file_format', p_file_format,
    'filters', coalesce(p_filters, '{}'::jsonb),
    'columns', p_columns,
    'row_count', p_row_count,
    'file_name', p_file_name,
    'file_size', p_file_size
  );
  v_request_hash := core.wave2_request_hash(
    'create_export_job', p_tenant_id, null, v_request_payload, null
  );
  v_replay := core.wave2_replay(
    p_tenant_id, 'create_export_job', p_idempotency_key, v_request_hash
  );
  if v_replay is not null then
    return v_replay;
  end if;

  insert into core.export_jobs (
    id, tenant_id, actor_id, resource, file_format, filters,
    columns_json, status, row_count, file_name, file_size, request_id
  ) values (
    v_job_id, p_tenant_id, v_actor, p_resource, p_file_format,
    coalesce(p_filters, '{}'::jsonb), p_columns, 'completed', p_row_count,
    trim(p_file_name), p_file_size, v_request_id
  );
  v_entity := jsonb_build_object(
    'id', v_job_id,
    'tenant_id', p_tenant_id,
    'code', 'EXPORT-' || left(v_job_id::text, 8),
    'name', trim(p_file_name),
    'resource', p_resource,
    'file_format', p_file_format,
    'filters', coalesce(p_filters, '{}'::jsonb),
    'columns', p_columns,
    'status', 'completed',
    'row_count', p_row_count,
    'file_size', p_file_size,
    'version', 1,
    'created_at', now(),
    'updated_at', now()
  );
  v_response := core.wave2_finish_command(
    p_tenant_id,
    'create_export_job',
    'export_job',
    v_job_id,
    p_idempotency_key,
    v_request_hash,
    null,
    v_entity,
    null,
    null,
    '[]'::jsonb,
    v_request_id
  );

  insert into workflow.notifications (
    tenant_id, recipient_id, notification_type, title, body,
    aggregate_type, aggregate_id, created_by, updated_by
  ) values (
    p_tenant_id, v_actor, 'export.completed', 'Export ready',
    trim(p_file_name) || ' contains ' || p_row_count::text || ' rows.',
    'export_job', v_job_id, v_actor, v_actor
  );
  return v_response;
end;
$$;

revoke execute on function core.wave2_derived_uuid(uuid, integer),
  core.reserve_document_number_impl(uuid, uuid, date, uuid),
  core.register_attachment_impl(uuid, jsonb, uuid),
  core.complete_attachment_impl(uuid, uuid, text, bigint, uuid),
  core.mark_notification_read_impl(uuid, uuid, bigint, uuid),
  core.import_setup_records_impl(uuid, uuid, text, text, text, bigint, jsonb, uuid),
  core.create_export_job_impl(uuid, text, text, jsonb, jsonb, integer, text, bigint, uuid)
  from public, anon, authenticated;
