-- Appended to the existing attendance rollback fixture. Never owner bootstrap.
create function pg_temp.clock_payload(p_id text,p_keys text[],p_shift integer default 0) returns jsonb language plpgsql as $$
declare k text;rows jsonb:='[]';checks text[]:='{}';utc text;checksum text;begin
 utc:=to_char((pg_temp.wdate()::timestamp+interval '3 hours'+make_interval(secs=>p_shift)),
  'YYYY-MM-DD"T"HH24:MI:SS"Z"');
 foreach k in array p_keys loop
  checksum:=encode(extensions.digest(convert_to(concat_ws(chr(10),pg_temp.wid('tenant')::text,
   pg_temp.wid('entity')::text,pg_temp.wid('branch')::text,pg_temp.wid('employee')::text,
   'synthetic-batch',k,utc),'UTF8'),'sha256'),'hex');
  rows:=rows||jsonb_build_array(jsonb_build_object('id',pg_temp.wid(p_id||':'||k),
   'source_key',k,'observed_utc',utc,'checksum',checksum));checks:=array_append(checks,checksum);
 end loop;
 return jsonb_build_object('action','raw_import_batch','id',pg_temp.wid(p_id),
  'employee_id',pg_temp.wid('employee'),'source_system','synthetic-batch','records',rows,
  'manifest_digest',encode(extensions.digest(convert_to(concat_ws(chr(10),'w4-clock-batch-v1',
   pg_temp.wid('tenant')::text,pg_temp.wid('entity')::text,pg_temp.wid('branch')::text,
   pg_temp.wid('employee')::text,'synthetic-batch',array_to_string(checks,chr(10))),'UTF8'),'sha256'),'hex'));
end $$;
create function pg_temp.clock_cmd(p jsonb,k text,v bigint default 0) returns jsonb language sql as $$
 select api.people_attendance_clock_batch(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
  pg_temp.wid(k),pg_temp.wid(k),now(),p,v)
$$;
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class c
 join pg_namespace n on n.oid=c.relnamespace where n.nspname='people'
 and c.relname in('raw_clock_batches','raw_clock_batch_rows')),'AC-401 clock batch forced RLS');
select ok(not has_table_privilege('authenticated','people.raw_clock_batches','SELECT'),
 'AC-401 batch facts API only');
select ok(not has_function_privilege('anon',
 'api.people_attendance_clock_batch(uuid,uuid,uuid,uuid,uuid,timestamptz,jsonb,bigint)','EXECUTE'),
 'AC-401 anonymous batch denied');
select pg_temp.wactor('creator');
set local role authenticated;
insert into attendance_responses values('clock-batch',pg_temp.clock_cmd(
 pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command'));
select is((select response#>>'{entity,imported_count}' from attendance_responses where name='clock-batch'),
 '2','AC-405 bounded batch imports all raw rows');
select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command'),
 (select response from attendance_responses where name='clock-batch'),'AC-401 exact batch replay');
select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-reuse',array['SYN-A','SYN-C']),'clock-reuse-command')#>>'{entity,reused_count}',
 '1','AC-405 exact source reuse preserves original identity');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-conflict',array['SYN-NEW','SYN-A'],60),'clock-conflict-command')$$,
 '55000','CLOCK_SOURCE_CONFLICT','AC-405 changed duplicate rejects entire batch');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-C']),'clock-batch-command')$$,
 '22023','IDEMPOTENCY_MISMATCH','AC-401 reused key rejects changed batch');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-hash',array['SYN-D'])||jsonb_build_object('manifest_digest',repeat('a',64)),
 'clock-hash-command')$$,'22023','CLOCK_MANIFEST_MISMATCH','AC-405 server verifies manifest');
select throws_ok($$select pg_temp.clock_cmd(jsonb_set(pg_temp.clock_payload('clock-row-hash',array['SYN-D']),
 '{records,0,checksum}',to_jsonb(repeat('a',64))),'clock-row-hash-command')$$,
 '22023','CLOCK_CHECKSUM_MISMATCH','AC-405 server verifies row checksum');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-dupe',array['SYN-D','SYN-D']),'clock-dupe-command')$$,
 '22023','CLOCK_BATCH_DUPLICATE','AC-405 repeated file keys denied');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-empty',array[]::text[]),'clock-empty-command')$$,
 '22023','CLOCK_BATCH_INVALID','NFR-405 empty batch denied');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-large',array(select 'SYN-'||x::text from generate_series(1,201)x)),
 'clock-large-command')$$,'22023','CLOCK_BATCH_INVALID','NFR-405 oversize batch denied');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-fields',array['SYN-D'])||jsonb_build_object('salary','100'),
 'clock-fields-command')$$,'22023','CLOCK_BATCH_INVALID','AC-401 unrelated fields denied');
select pg_temp.wactor('creator','aal1');
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command')$$,
 '42501',null,'AC-401 MFA required before batch replay');
reset role;
select pg_temp.wactor('creator');
select is((select count(*)::text from people.raw_clock_events where source_system='synthetic-batch'),
 '3','AC-405 conflict leaves no partial rows');
select is((select count(*)::text from people.raw_clock_batch_rows where batch_id=pg_temp.wid('clock-reuse') and reused),
 '1','AC-405 reuse lineage names original event');
set local role authenticated;
select is(jsonb_array_length(api.people_attendance_clock_batches(pg_temp.wid('tenant'),pg_temp.wid('entity'),
 pg_temp.wid('branch'),pg_temp.wid('employee'))->'items')::text,'2','AC-405 scoped batch history');
select is(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'))#>>'{rows,0,reused}','true','AC-405 immutable original event lineage');
select throws_ok($$select api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch2'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'))$$,'P0002','CLOCK_BATCH_NOT_FOUND','AC-401 cross-branch batch unavailable');
select throws_ok($$select api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-reuse'),201)$$,'22023','CLOCK_CURSOR_INVALID','NFR-405 batch cursor bound');
reset role;
select is((select count(*)::text from people.work_claims where source_kind='attendance'),
 '1','AC-405 raw imports do not create payable time');
select throws_ok($$update people.raw_clock_batches set manifest_digest=repeat('b',64) where id=pg_temp.wid('clock-batch')$$,
 '55000','WORK_HISTORY_IMMUTABLE','AC-405 batch history immutable');
create function pg_temp.clock_fail_late() returns trigger language plpgsql as $$begin
 if new.command_id=pg_temp.wid('clock-late-command') then
  raise exception using errcode='P0001',message='SYNTHETIC_CLOCK_LATE_FAILURE';end if;return new;
end $$;
create trigger synthetic_clock_fail_late before insert on core.outbox_events
 for each row execute function pg_temp.clock_fail_late();
set local role authenticated;
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-late',array['SYN-LATE']),'clock-late-command')$$,
 'P0001','SYNTHETIC_CLOCK_LATE_FAILURE','AC-401 late outbox failure rolls back batch');
reset role;
select ok(not exists(select 1 from people.raw_clock_events where source_key='SYN-LATE')
 and not exists(select 1 from people.raw_clock_batches where id=pg_temp.wid('clock-late')),
 'AC-401 late failure leaves no clock evidence or batch');
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.import';
-- Grant restored only inside this rollback fixture for the declared job boundary.
insert into core.role_permissions(tenant_id,role_id,permission_code)
 values(pg_temp.wid('tenant'),pg_temp.wid('creator.role'),'people.attendance.import');
set local role authenticated;
select is(pg_temp.clock_cmd(pg_temp.clock_payload('clock-max',array(select 'BOUND-'||x::text from generate_series(1,200)x)),
 'clock-max-command')#>>'{entity,imported_count}','200','NFR-405 declared 200-row batch succeeds');
select is(jsonb_array_length(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-max'))->'rows')::text,'50','NFR-405 lineage pages bounded to fifty');
select is(api.people_attendance_clock_batch_detail(pg_temp.wid('tenant'),pg_temp.wid('entity'),pg_temp.wid('branch'),
 pg_temp.wid('employee'),pg_temp.wid('clock-max'),150)->>'next_position',null::text,'NFR-405 final lineage page has no cursor');
reset role;
delete from core.role_permissions where role_id=pg_temp.wid('creator.role') and permission_code='people.attendance.import';
set local role authenticated;
select throws_ok($$select pg_temp.clock_cmd(pg_temp.clock_payload('clock-batch',array['SYN-A','SYN-B']),'clock-batch-command')$$,
 '42501',null,'AC-401 revoked import denied before replay');
reset role;
