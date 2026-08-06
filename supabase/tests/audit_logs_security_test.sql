begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(7);

-- 1. Verify audit_logs table structure
select has_table('public', 'audit_logs', 'audit_logs table exists');

-- 2. Verify direct mutation privileges on audit_logs are revoked from authenticated
select hasnt_table_privilege('authenticated', 'public.audit_logs', 'insert', 'authenticated cannot insert into audit_logs directly');
select hasnt_table_privilege('authenticated', 'public.audit_logs', 'update', 'authenticated cannot update audit_logs directly');
select hasnt_table_privilege('authenticated', 'public.audit_logs', 'delete', 'authenticated cannot delete from audit_logs directly');

-- 3. Verify SELECT privileges remain intact for authenticated
select has_table_privilege('authenticated', 'public.audit_logs', 'select', 'authenticated can select from audit_logs');

-- 4. Verify private.log_audit_event helper function exists and is private
select has_function('private', 'log_audit_event', ARRAY['uuid', 'uuid', 'text', 'text', 'text', 'jsonb'], 'private.log_audit_event function exists');

select ok(
  not has_function_privilege('anon', 'private.log_audit_event(uuid, uuid, text, text, text, jsonb)', 'execute'),
  'anon cannot execute private.log_audit_event'
);

select * from finish();

rollback;
