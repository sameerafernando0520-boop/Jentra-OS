-- W4-03 candidate: bounded raw clock evidence only, without payable claims.
create table people.raw_clock_batches(
 id uuid primary key,tenant_id uuid not null,legal_entity_id uuid not null,branch_id uuid not null,
 employee_id uuid not null,source_system text not null,
 manifest_digest text not null check(manifest_digest ~ '^[a-f0-9]{64}$'),
 row_count integer not null check(row_count between 1 and 200),
 imported_count integer not null check(imported_count>=0 and imported_count<=row_count),
 imported_by uuid not null references auth.users(id),imported_at timestamptz not null default clock_timestamp(),
 unique(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id) references people.employees(tenant_id,legal_entity_id,id),
 foreign key(tenant_id,legal_entity_id,branch_id) references core.branches(tenant_id,legal_entity_id,id)
);
create index raw_clock_batches_scope_idx on people.raw_clock_batches(tenant_id,legal_entity_id,branch_id,employee_id,id);
create index raw_clock_batches_actor_idx on people.raw_clock_batches(imported_by);
create table people.raw_clock_batch_rows(
 tenant_id uuid not null,legal_entity_id uuid not null,employee_id uuid not null,batch_id uuid not null,
 position integer not null check(position between 1 and 200),event_id uuid not null,reused boolean not null,
 primary key(batch_id,position),unique(batch_id,event_id),
 foreign key(tenant_id,legal_entity_id,employee_id,batch_id) references people.raw_clock_batches(tenant_id,legal_entity_id,employee_id,id),
 foreign key(tenant_id,legal_entity_id,employee_id,event_id) references people.raw_clock_events(tenant_id,legal_entity_id,employee_id,id)
);
create index raw_clock_batch_rows_event_idx on people.raw_clock_batch_rows(event_id);
alter table people.raw_clock_batches enable row level security;
alter table people.raw_clock_batches force row level security;
alter table people.raw_clock_batch_rows enable row level security;
alter table people.raw_clock_batch_rows force row level security;
revoke all on people.raw_clock_batches,people.raw_clock_batch_rows from public,anon,authenticated;
create trigger raw_clock_batch_immutable before update or delete on people.raw_clock_batches
 for each row execute function people.work_history_guard();
create trigger raw_clock_batch_row_immutable before update or delete on people.raw_clock_batch_rows
 for each row execute function people.work_history_guard();

create function api.people_attendance_clock_batch(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_command_id uuid,p_idempotency_key uuid,p_client_timestamp timestamptz,p_payload jsonb,p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_employee uuid;v_system text;v_digest text;v_hash text;v_replay jsonb;
 v_row jsonb;v_event people.raw_clock_events%rowtype;v_instant timestamptz;v_checksum text;
 v_checksums text[]:='{}';v_events jsonb:='[]';v_imported integer:=0;v_position integer:=0;
 v_uuid_pattern text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
 v_after jsonb;v_request uuid:=gen_random_uuid();begin
 if p_command_id is null or p_idempotency_key is null or p_client_timestamp is null
  or p_expected_version is distinct from 0 or coalesce(jsonb_typeof(p_payload),'null')<>'object'
  or p_payload->>'action' is distinct from 'raw_import_batch'
  or coalesce(p_payload->>'id','') !~ v_uuid_pattern
  or coalesce(p_payload->>'employee_id','') !~ v_uuid_pattern
  or exists(select 1 from jsonb_object_keys(p_payload) k where k<>all(array['action','id','employee_id','source_system','records','manifest_digest']))
  or coalesce(jsonb_typeof(p_payload->'records'),'null')<>'array'
  or jsonb_array_length(p_payload->'records') not between 1 and 200 then
  raise exception using errcode='22023',message='CLOCK_BATCH_INVALID';end if;
 v_id:=(p_payload->>'id')::uuid;v_employee:=(p_payload->>'employee_id')::uuid;
 v_system:=p_payload->>'source_system';
 if coalesce(jsonb_typeof(p_payload->'source_system'),'null')<>'string'
  or length(v_system) not between 1 and 80 or v_system<>btrim(v_system)
  or v_system ~ '[[:cntrl:]]' then raise exception using errcode='22023',message='CLOCK_SOURCE_INVALID';end if;
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.import');
 if coalesce(auth.jwt()->>'aal','aal1')<>'aal2' then
  raise exception using errcode='42501',message='ATTENDANCE_MFA_REQUIRED';end if;
 if not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=v_employee) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 v_hash:=core.wave3_request_hash('people.attendance.raw_import_batch',p_command_id,
  p_tenant_id,p_legal_entity_id,p_branch_id,p_payload,p_expected_version);
 v_replay:=core.wave3_replay(p_tenant_id,'people.attendance.raw_import_batch',p_command_id,p_idempotency_key,v_hash);
 if v_replay is not null then return v_replay;end if;
 perform id from people.employees where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and id=v_employee for update;
 if not found then raise exception using errcode='P0002',message='ATTENDANCE_EMPLOYEE_NOT_FOUND';end if;
 for v_row in select value from jsonb_array_elements(p_payload->'records') loop
  if coalesce(jsonb_typeof(v_row),'null')<>'object'
   or exists(select 1 from jsonb_object_keys(v_row) k where k<>all(array['id','source_key','observed_utc','checksum']))
   or coalesce(v_row->>'id','') !~ v_uuid_pattern
   or coalesce(jsonb_typeof(v_row->'source_key'),'null')<>'string'
   or length(v_row->>'source_key') not between 1 and 160 or v_row->>'source_key'<>btrim(v_row->>'source_key')
   or v_row->>'source_key' ~ '[[:cntrl:]]'
   or coalesce(v_row->>'observed_utc','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
   or coalesce(v_row->>'checksum','') !~ '^[a-f0-9]{64}$' then
   raise exception using errcode='22023',message='CLOCK_ROW_INVALID';end if;
  v_instant:=(v_row->>'observed_utc')::timestamptz;
  if to_char(v_instant at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')<>v_row->>'observed_utc' then
   raise exception using errcode='22023',message='CLOCK_INSTANT_INVALID';end if;
  v_checksum:=encode(extensions.digest(convert_to(concat_ws(chr(10),p_tenant_id::text,p_legal_entity_id::text,
   p_branch_id::text,v_employee::text,v_system,v_row->>'source_key',v_row->>'observed_utc'),'UTF8'),'sha256'),'hex');
  if v_checksum<>v_row->>'checksum' then raise exception using errcode='22023',message='CLOCK_CHECKSUM_MISMATCH';end if;
  v_checksums:=array_append(v_checksums,v_checksum);
 end loop;
 if (select count(distinct value->>'source_key') from jsonb_array_elements(p_payload->'records'))<>jsonb_array_length(p_payload->'records')
  or (select count(distinct value->>'id') from jsonb_array_elements(p_payload->'records'))<>jsonb_array_length(p_payload->'records') then
  raise exception using errcode='22023',message='CLOCK_BATCH_DUPLICATE';end if;
 v_digest:=encode(extensions.digest(convert_to(concat_ws(chr(10),'w4-clock-batch-v1',p_tenant_id::text,
  p_legal_entity_id::text,p_branch_id::text,v_employee::text,v_system,array_to_string(v_checksums,chr(10))),'UTF8'),'sha256'),'hex');
 if v_digest is distinct from p_payload->>'manifest_digest' then
  raise exception using errcode='22023',message='CLOCK_MANIFEST_MISMATCH';end if;
 for v_row in select value from jsonb_array_elements(p_payload->'records') order by value->>'source_key' loop
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':clock:'||v_system||':'||(v_row->>'source_key'),0));
 end loop;
 for v_row in select value from jsonb_array_elements(p_payload->'records') loop
  select * into v_event from people.raw_clock_events where tenant_id=p_tenant_id
   and source_system=v_system and source_key=v_row->>'source_key' for update;
  if found then
   if v_event.legal_entity_id<>p_legal_entity_id or v_event.branch_id<>p_branch_id
    or v_event.employee_id<>v_employee or v_event.observed_utc<>(v_row->>'observed_utc')::timestamptz
    or v_event.checksum<>v_row->>'checksum' then
    raise exception using errcode='55000',message='CLOCK_SOURCE_CONFLICT';end if;
   v_events:=v_events||jsonb_build_array(jsonb_build_object('event_id',v_event.id,'reused',true));
  else
   insert into people.raw_clock_events(id,tenant_id,legal_entity_id,branch_id,employee_id,
    source_system,source_key,observed_utc,checksum,imported_by)
   values((v_row->>'id')::uuid,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_system,
    v_row->>'source_key',(v_row->>'observed_utc')::timestamptz,v_row->>'checksum',auth.uid());
   v_imported:=v_imported+1;
   v_events:=v_events||jsonb_build_array(jsonb_build_object('event_id',v_row->>'id','reused',false));
  end if;
 end loop;
 insert into people.raw_clock_batches(id,tenant_id,legal_entity_id,branch_id,employee_id,source_system,
  manifest_digest,row_count,imported_count,imported_by)
 values(v_id,p_tenant_id,p_legal_entity_id,p_branch_id,v_employee,v_system,v_digest,
  jsonb_array_length(v_events),v_imported,auth.uid());
 for v_row in select value from jsonb_array_elements(v_events) loop
  v_position:=v_position+1;
  insert into people.raw_clock_batch_rows(tenant_id,legal_entity_id,employee_id,batch_id,position,event_id,reused)
  values(p_tenant_id,p_legal_entity_id,v_employee,v_id,v_position,(v_row->>'event_id')::uuid,(v_row->>'reused')::boolean);
 end loop;
 v_after:=jsonb_build_object('id',v_id,'tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,
  'branch_id',p_branch_id,'employee_id',v_employee,'version',1,'row_count',jsonb_array_length(v_events),
  'imported_count',v_imported,'reused_count',jsonb_array_length(v_events)-v_imported,'manifest_digest',v_digest);
 return core.wave3_finish_command(p_tenant_id,'people.attendance.raw_import_batch',p_command_id,
  'people.raw_clock_batch',v_id,p_idempotency_key,v_hash,'{}',v_after,p_legal_entity_id,p_branch_id,
  p_source_context=>jsonb_build_object('action','raw_import_batch'),p_request_id=>v_request);
end $$;
revoke all on function api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) from public,anon,authenticated;
grant execute on function api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint) to authenticated;

create function people.clock_batch_payload(p_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',id,'source_system',source_system,'manifest_digest',manifest_digest,
  'row_count',row_count,'imported_count',imported_count,'imported_by',imported_by,'imported_at',imported_at)
 from people.raw_clock_batches where id=p_id
$$;
create function api.people_attendance_clock_batches(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_after uuid default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_employee_id is null or not exists(select 1 from people.employment_assignments where tenant_id=p_tenant_id
  and legal_entity_id=p_legal_entity_id and branch_id=p_branch_id and employee_id=p_employee_id) then
  raise exception using errcode='42501',message='ATTENDANCE_SCOPE_DENIED';end if;
 select coalesce(jsonb_agg(people.clock_batch_payload(q.id) order by q.id),'[]') into items
 from(select id from people.raw_clock_batches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id and(p_after is null or id>p_after) order by id limit 51)q;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'employee_id',p_employee_id,'items',items-50,'next_cursor',case when jsonb_array_length(items)>50 then items->49->>'id' end);
end $$;
create function api.people_attendance_clock_batch_detail(p_tenant_id uuid,p_legal_entity_id uuid,p_branch_id uuid,
 p_employee_id uuid,p_batch_id uuid,p_after integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb;begin
 perform people.require_access(p_tenant_id,p_legal_entity_id,p_branch_id,'people.attendance.view');
 if p_after is null or p_after not between 0 and 200 then
  raise exception using errcode='22023',message='CLOCK_CURSOR_INVALID';end if;
 if not exists(select 1 from people.raw_clock_batches where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and branch_id=p_branch_id and employee_id=p_employee_id and id=p_batch_id) then
  raise exception using errcode='P0002',message='CLOCK_BATCH_NOT_FOUND';end if;
 select coalesce(jsonb_agg(jsonb_build_object('position',q.position,'event_id',q.event_id,'reused',q.reused,
  'source_key',e.source_key,'observed_utc',to_char(e.observed_utc at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
  'checksum',e.checksum) order by q.position),'[]') into items
 from(select * from people.raw_clock_batch_rows where tenant_id=p_tenant_id and legal_entity_id=p_legal_entity_id
  and employee_id=p_employee_id and batch_id=p_batch_id and position>p_after order by position limit 51)q
 join people.raw_clock_events e on e.id=q.event_id;
 return jsonb_build_object('tenant_id',p_tenant_id,'legal_entity_id',p_legal_entity_id,'branch_id',p_branch_id,
  'employee_id',p_employee_id,'batch',people.clock_batch_payload(p_batch_id),'rows',items-50,
  'next_position',case when jsonb_array_length(items)>50 then(items->49->>'position')::integer end);
end $$;
revoke all on function people.clock_batch_payload(uuid),api.people_attendance_clock_batches(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_clock_batch_detail(uuid,uuid,uuid,uuid,uuid,integer) from public,anon,authenticated;
grant execute on function api.people_attendance_clock_batches(uuid,uuid,uuid,uuid,uuid),
 api.people_attendance_clock_batch_detail(uuid,uuid,uuid,uuid,uuid,integer) to authenticated;
